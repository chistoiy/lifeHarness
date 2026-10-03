import 'dart:convert' show jsonEncode;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_css.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/reader_cfg.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_appearance_sheet.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

// 批三实现批·刀4「开关与不支持项提示行」上屏回归（工单 §3D 刀4 段＋路线说明 §五.2）。
// 钉四件事：① 开（默认）＝分层色/小字真上屏；② 关＝span 里没有原书色（逐字节回到止血口径）；
// ③ 夜间主题下原书深色被调亮后才上屏；④ 外观弹层的「跟随原书样式」开关与
// **不支持项提示行**（按 key 去重、描边框画不成框也不许静默）＋一条记录落盘一行式日志。
// 独立文件防 isolate 污染；doc 直接手搓（同 reader_r32_test 的 loader override 路子）。

const _navy = Color(0xFF000080); // 通鉴 .brp-cmt 史评（CSS navy）
const _green = Color(0xFF006400); // .brp-note 注（DarkGreen）
const _nightBg = Color(0xFF101317);

double _lum(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

/// 竖排声明＋两条边线（border-left 与 border 归同一个判定键 border）。
const _uns = [
  EpubUnsupported(
      kind: EpubUnsupportedKind.cssStructural,
      property: 'writing-mode',
      value: 'vertical-rl',
      count: 306),
  EpubUnsupported(
      kind: EpubUnsupportedKind.cssFlattened,
      property: 'border-left',
      value: '.12em solid',
      count: 812),
  EpubUnsupported(
      kind: EpubUnsupportedKind.cssFlattened,
      property: 'border',
      value: '.1em solid',
      count: 96),
];

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  group('刀4 上屏 · 跟随原书样式开关', () {
    late Database db;
    late ReadRepository repo;
    late SharedPreferences prefs;

    setUp(() async {
      AppLog.reset();
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = ReadRepository(db);
    });
    tearDown(() => db.close());

    final doc = EpubDoc(
      format: 'EPUB3',
      title: '古籍书',
      author: '司馬光',
      toc: const [],
      chapters: [
        EpubChapter(href: 'c1', title: '卷一', paras: [
          const EpubPara(kind: EpubParaKind.text, text: '普通正文段。'),
          const EpubPara(
            kind: EpubParaKind.text,
            text: '史评段：臣光曰。',
            style: EpubStyle(color: _navy),
          ),
          const EpubPara(
            kind: EpubParaKind.text,
            text: '胡三省注：作，謂能創制。',
            annotation: true,
            ownIndent: true,
            runs: [
              EpubStyleRun(
                  start: 0,
                  end: 5,
                  style: EpubStyle(color: _green, fontRatio: .75)),
            ],
          ),
        ]),
      ],
      imageCount: 0,
      totalChars: 40,
      unsupported: _uns,
    );

    Future<void> open(WidgetTester t, String id, {Map<String, Object?> cfg = const {}}) async {
      await useSurface(t, const Size(420, 780));
      await repo.addBook(
        Book(
          id: id,
          title: '古籍书',
          local: true,
          epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      if (cfg.isNotEmpty) {
        await repo.setKv(
            'reader.cfg', jsonEncode({...ReaderCfg.defaults.toMap(), ...cfg}));
      }
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            readRepositoryProvider.overrideWithValue(repo),
            sharedPreferencesProvider.overrideWithValue(prefs),
            epubDocLoaderProvider.overrideWithValue((_) async => doc),
          ],
          child: MaterialApp(home: ReaderPage(bookId: id)),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    }

    List<InlineSpan> spans(WidgetTester t, int pi) =>
        (t.widget<Text>(
          find
              .descendant(
                  of: find.byKey(ValueKey('brp-0-$pi')), matching: find.byType(Text))
              .first,
        ).textSpan as TextSpan)
            .children!;

    testWidgets('开（默认）＝段级分层色与段内小字绿上屏，未声明段仍是主题色', (t) async {
      await open(t, 'o1');
      final fg = ReaderCfg.defaults.textColor;
      expect(ReaderCfg.defaults.orig, isTrue, reason: '默认开＝§5.4 拍板③');
      // 段级原书蓝（日间底对比达标＝原色照上）。
      expect((spans(t, 1).last as TextSpan).style!.color, _navy);
      // 段内区间：绿＋0.75×；区间之外仍是止血注释体（正文色压暗）。
      final note = spans(t, 2);
      expect((note.first as TextSpan).style!.color, _green);
      expect((note.first as TextSpan).style!.fontSize, closeTo(19 * .75, .001));
      expect((note.last as TextSpan).style!.color,
          fg.withValues(alpha: kAnnotationAlpha));
      // 没声明的普通段：主题正文色，一点没变。
      expect((spans(t, 0).last as TextSpan).style!.color, fg);
      await settle5(t);
    });

    testWidgets('关＝span 里没有任何原书色（逐字节回到止血口径）', (t) async {
      await open(t, 'o2', cfg: {'orig': false});
      for (final pi in [0, 1, 2]) {
        for (final s in spans(t, pi)) {
          final c = (s as TextSpan).style?.color;
          expect(c, isNot(_navy), reason: 'pi=$pi 关态漏了原书蓝');
          expect(c, isNot(_green), reason: 'pi=$pi 关态漏了原书绿');
        }
      }
      // 关态注释体仍是小一号正文色（止血口径没被动过）。
      expect((spans(t, 2).last as TextSpan).style!.fontSize,
          19 * kAnnotationFsFactor);
      await settle5(t);
    });

    testWidgets('夜间主题：原书深蓝被调亮后才上屏（禁直接压黑底原色）', (t) async {
      await open(t, 'o3', cfg: {'theme': 'night'});
      final c = (spans(t, 1).last as TextSpan).style!.color!;
      expect(c, isNot(_navy));
      expect(_contrast(c, _nightBg), greaterThanOrEqualTo(kOrigContrastMin));
      await settle5(t);
    });
  });

  group('刀4 外观弹层 · 开关行与不支持项提示行', () {
    ReaderCfg? saved;

    Future<void> openSheet(
      WidgetTester t, {
      ReaderCfg? cur,
      List<EpubUnsupported> uns = _uns,
    }) async {
      await useSurface(t, const Size(420, 780));
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showReaderAppearance(
                  c,
                  current: cur ?? ReaderCfg.defaults,
                  unsupported: uns,
                  onSave: (d, book, img) => saved = d,
                ),
                child: const Text('openAp'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('openAp'));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    setUp(() {
      AppLog.reset();
      saved = null;
    });

    testWidgets('开关行「跟随原书样式」在·默认开·切换生效', (t) async {
      await openSheet(t);
      final sw = find.byKey(const ValueKey('brApOrig'));
      expect(sw, findsOneWidget);
      await t.dragUntilVisible(
          sw, find.byType(SingleChildScrollView), const Offset(0, -60));
      expect(t.widget<SwitchListTile>(sw).value, isTrue);
      await t.tap(
          find.descendant(of: sw, matching: find.byType(Switch)).first);
      await t.pump(); // setState 后要落一帧，否则读到的是切换前的树
      expect(t.widget<SwitchListTile>(sw).value, isFalse);
      expect(saved, isNull, reason: '草稿制：切换只进草稿，未「保存应用」不落库');
      await settle5(t);
    });

    testWidgets('提示行逐条 describe 且按 key 去重（border-left 与 border 只印一遍）', (t) async {
      await openSheet(t);
      final line = find.byKey(const ValueKey('brApOrigWarn'));
      expect(line, findsOneWidget);
      final data = t.widget<Text>(line).data!;
      expect(data, contains('竖排直排'));
      expect(data, contains('框线描边（当前按文字上下的线显示，画不出整框）'));
      // 去重必须按**出现次数**判：整个提示是一行 Text，两条边线声明若各印一遍，
      // find.textContaining 仍只命中一个 widget——那样这条断言就是空闸。
      expect(RegExp('框线描边').allMatches(data).length, 1,
          reason: '.name 的 border-left 与 .name1 的 border 归同一个判定键');
      expect(RegExp('竖排直排').allMatches(data).length, 1);
      await settle5(t);
    });

    testWidgets('提示行同时落一条日志（一条记录＝落盘一行）', (t) async {
      await openSheet(t);
      final hits = AppLog.lines.where((l) => l.text.contains('竖排直排')).toList();
      expect(hits, hasLength(1));
      expect(hits.single.text, isNot(contains('\n')),
          reason: '一条记录＝落盘一行，多行必须压平');
      await drainLogTimer(t);
    });

    testWidgets('没有不支持声明的书＝不显提示行、不落日志（开关照在）', (t) async {
      await openSheet(t, uns: const []);
      expect(find.byKey(const ValueKey('brApOrigWarn')), findsNothing);
      expect(find.byKey(const ValueKey('brApOrig')), findsOneWidget);
      expect(AppLog.lines.where((l) => l.text.contains('排版')), isEmpty);
      await settle5(t);
    });
  });
}
