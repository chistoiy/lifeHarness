import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/reader_cfg.dart';
import 'package:lifeharness/features/read/domain/s2t_map.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';

// R3-6 批3 · 一键简繁（仅正文显示层）。独立文件防 isolate 污染；
// 真表读盘走 File.readAsStringSync（FakeAsync 下 rootBundle 资产不可靠）。

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

/// 上屏文本合集（正文走 Text.rich，find.text 只认 Text.data，故自取 span）。
String _shown(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
    .join('\n');

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------- A · 转换器纯逻辑（手搓小表，零资产 IO） ----------
  group('R3-6 转换器 · 逐字兜底与短语择字', () {
    const toTrad = S2tTable(
      chars: {'头': '頭', '发': '發', '干': '幹'},
      phrases: {'头发': '頭髮', '乾隆': '乾隆'},
      maxPhrase: 2,
    );
    const toSimp = S2tTable(
      // 髮（頭髮）与 發（發憤）是两个不同的繁体字，都归到简体 发——
      // 一繁对多简的归并在简体侧本来就是单值。
      chars: {'頭': '头', '發': '发', '髮': '发', '幹': '干'},
      phrases: {},
      maxPhrase: 0,
    );

    setUp(() => S2t.installTables(toTrad: toTrad, toSimp: toSimp));
    tearDown(S2t.resetForTest);

    test('短语优先于逐字（一简对多繁的择字就在这一步）', () {
      expect(S2t.convert('我的头发', kS2TTrad), '我的頭髮');
      // 落单字才走逐字兜底。
      expect(S2t.convert('发', kS2TTrad), '發');
      expect(S2t.convert('干', kS2TTrad), '幹');
    });

    test('逐字等长：标点/数字/拉丁原样，偏移不位移', () {
      const s = '头发（第3章）· 2026 · Book ABC';
      final out = S2t.convert(s, kS2TTrad);
      expect(out.length, s.length);
      expect(out, '頭髮（第3章）· 2026 · Book ABC');
      // 第 i 位仍对应原文第 i 位：切片语义不变。
      expect(out.substring(0, 2), '頭髮');
    });

    test('段长小于最长词组时仍必须命中词组（越界判断写进循环条件的回归）', () {
      // 表里有一条 4 字词组，段只有 2 字：曾经的写法是
      // `for (len = maxPhrase; len > 1 && i + len <= n; len--)`，
      // 起始就因 4 > 2 直接退出 → 全书词组择字静默失效。
      S2t.installTables(
        toTrad: const S2tTable(
          chars: {'头': '頭', '发': '發', '眉': '睂'},
          phrases: {'头发': '頭髮', '眉头深锁': '睂頭深鎖'},
          maxPhrase: 4,
        ),
        toSimp: S2tTable.empty,
      );
      expect(S2t.convert('头发', kS2TTrad), '頭髮');
      expect(S2t.convert('她的头发', kS2TTrad), '她的頭髮');
      // 长词组优先于短词组与逐字（贪心最长匹配）。
      expect(S2t.convert('眉头深锁', kS2TTrad), '睂頭深鎖');
    });

    test('orig 档与未知档一律原文；繁→简走另一张表', () {
      expect(S2t.convert('頭髮', kS2TOrig), '頭髮');
      expect(S2t.convert('頭髮', 'nope'), '頭髮');
      expect(S2t.convert('頭髮', kS2TSimp), '头发');
    });

    test('表未装载时回落原文（阅读不能因词表失败而白屏或崩）', () {
      S2t.resetForTest();
      expect(S2t.ready, isFalse);
      expect(S2t.convert('头发', kS2TTrad), '头发');
    });

    test('结果缓存有上限（整本预载段落数以万计，不做无限增长的 Map）', () {
      for (var i = 0; i < 6000; i++) {
        S2t.convert('第$i段头发', kS2TTrad);
      }
      expect(S2t.cacheSize, lessThanOrEqualTo(4100));
    });

    test('变长词组在装表期即被丢弃（偏移红线的第二道闸）', () {
      final t = S2tTable.fromJson(const {
        'chars': 'AB',
        'to': 'ａｂ',
        'phr': ['好|壞壞', '乾|乾', '头发|頭髮'],
      });
      expect(t.phrases.keys, ['头发']);
      expect(t.maxPhrase, 2);
    });
  });

  // ---------- B · 真表（assets/read_s2t/s2t.json 读盘） ----------
  group('R3-6 真表 · 生成产物体检', () {
    late Map<String, dynamic> raw;

    setUpAll(() {
      raw = jsonDecode(
        File('assets/read_s2t/s2t.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      S2t.installFromJson(jsonEncode(raw));
    });
    tearDownAll(S2t.resetForTest);

    test('规模下限：表被生成器跑空/截断要立刻红', () {
      // 上限侧不卡：非 BMP 目标（占 2 码元＝会挪下标）在生成期就被剔除，
      // 所以 t2s 比原始数据少约 800 条是**预期**，不是丢数据。
      expect((raw['s2t']['chars'] as String).length, greaterThan(2500));
      expect((raw['t2s']['chars'] as String).length, greaterThan(3000));
      expect((raw['s2t']['phr'] as List).length, greaterThan(3000));
      expect((raw['t2s']['phr'] as List).length, greaterThan(400));
    });

    test('表内所有目标字符都在 BMP（1 码元）——偏移红线的根', () {
      for (final k in ['s2t', 't2s']) {
        for (final ru in (raw[k]['to'] as String).runes) {
          expect(ru, lessThan(0x10000), reason: '$k 逐字表含非 BMP 目标');
        }
        for (final e in raw[k]['phr'] as List) {
          final s = '$e', bar = s.indexOf('|');
          expect(
            s.substring(bar + 1).runes.every((r) => r < 0x10000),
            isTrue,
            reason: '$k 词组目标含非 BMP：$s',
          );
        }
      }
    });

    test('逐字平行表两侧等长 · 全部词组等长（偏移红线的生成期承诺）', () {
      for (final k in ['s2t', 't2s']) {
        final m = raw[k] as Map<String, dynamic>;
        expect((m['chars'] as String).length, (m['to'] as String).length);
        for (final e in m['phr'] as List) {
          final s = '$e', bar = s.indexOf('|');
          expect(bar, greaterThan(0), reason: '词组条目缺分隔符：$s');
          expect(
            bar,
            s.length - bar - 1,
            reason: '词组变长，会让划线/书摘偏移错位：$s',
          );
        }
      }
    });

    test('择字正确：头发→頭髮 而 乾隆 不被误伤为 干隆', () {
      // 期望值全部按码点写死（终端是 GBK，打中文看不出来红在哪）。
      // 頭=U+982D 髮=U+9AE6（頭髮）；發=U+767C；乾=U+4E7E；幹=U+5E79；鑑=U+9451。
      String hex(String s) => s.runes.map((r) => r.toRadixString(16)).join('-');
      expect(hex(S2t.convert('头发', kS2TTrad)), '982d-9aee');
      expect(hex(S2t.convert('发愤图强', kS2TTrad)), '767c-61a4-5716-5f37');
      expect(hex(S2t.convert('乾隆', kS2TTrad)), '4e7e-9686'); // 乾不被并成幹
      expect(S2t.convert('資治通鑑', kS2TSimp), '资治通鉴');
      expect(hex(S2t.convert('资治通鉴', kS2TTrad)), '8cc7-6cbb-901a-9451');
    });

    test('古文混排双向转换均等长', () {
      const corpus =
          '（甲子）初命晉大夫魏斯、趙籍、韓虔為諸侯。周天子，前 256 年滅於秦。';
      for (final mode in [kS2TTrad, kS2TSimp]) {
        final out = S2t.convert(corpus, mode);
        expect(out.length, corpus.length, reason: '模式 $mode 改变了长度');
      }
      final t = S2t.convert('魏斯、趙籍', kS2TSimp);
      expect(t, '魏斯、赵籍');
    });
  });

  // ---------- C · 显示通道与分页指纹 ----------
  group('R3-6 显示通道 · 单点与指纹', () {
    setUp(() => S2t.installTables(
      toTrad: const S2tTable(
        chars: {'测': '測', '试': '試', '发': '發'},
        phrases: {},
        maxPhrase: 0,
      ),
      toSimp: S2tTable.empty,
    ));
    tearDown(S2t.resetForTest);

    test('paraBody 是唯一上屏通道；paraDisplayText = 缩进前缀 + paraBody', () {
      final p = _p('测试段');
      expect(paraBody(p, kS2TTrad), '測試段');
      expect(paraDisplayText(p, indMode: '2', s2t: kS2TTrad), '\u3000\u3000測試段');
      // 等长 ⇒ 缩进偏移差值仍只反映前缀（批2 的 display.length - text.length 口径不破）。
      expect(
        paraDisplayText(p, indMode: '2', s2t: kS2TTrad).length - p.text.length,
        2,
      );
      expect(p.text, '测试段', reason: '转换器不得写脏模型');
    });

    test('ReaderLayout.of 带上 s2t · 指纹随三档变化（漏进指纹＝切了不重排）', () {
      ReaderLayout l(String mode) => ReaderLayout.of(
        ReaderCfg(s2t: mode),
        width: 400,
        height: 800,
      );
      final f = {for (final m in [kS2TOrig, kS2TSimp, kS2TTrad]) m: l(m)};
      expect(f[kS2TOrig]!.s2t, kS2TOrig);
      expect(
        PagStore.fingerprint(l(kS2TTrad)),
        isNot(PagStore.fingerprint(l(kS2TSimp))),
      );
      expect(
        PagStore.fingerprint(l(kS2TTrad)),
        isNot(PagStore.fingerprint(l(kS2TOrig))),
      );
    });
  });

  // ---------- D · 主屏端到端（外观弹层选繁体 → 正文变、原文不变） ----------
  group('R3-6 主屏 · 切繁体即时重排', () {
    late Database db;
    late ReadRepository repo;
    late SharedPreferences prefs;
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      // 必须用 NoIsolate 工厂：widget 测试跑在 FakeAsync 里，带 isolate 的 sqflite
      // 查询永不返回（reader_b4 同口径），表现就是整组用例挂死。
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = ReadRepository(db);
      tmp = Directory.systemTemp.createTempSync('lh_s2t');
      S2t.installTables(
        toTrad: const S2tTable(
          chars: {'这': '這', '个': '個', '测': '測', '试': '試', '发': '發'},
          phrases: {'头发': '頭髮'},
          maxPhrase: 2,
        ),
        toSimp: S2tTable.empty,
      );
    });
    tearDown(() async {
      S2t.resetForTest();
      await db.close();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    List<Override> overrides() => [
      readRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
      epubDocLoaderProvider.overrideWithValue((_) async => EpubDoc(
        format: 'EPUB3',
        title: '简繁书',
        author: '甲',
        toc: const [],
        chapters: [
          EpubChapter(
            href: 'c1',
            title: '第一章',
            paras: [
              const EpubPara(
                kind: EpubParaKind.heading,
                text: '第一章',
                headingLevel: 1,
              ),
              _p('这是一个测试段落，头发在镜前。'),
              _p('第二段，测试这一个人。'),
            ],
          ),
        ],
        imageCount: 0,
        totalChars: 30,
        images: const {},
      )),
      epubPreloadProvider.overrideWith((_) => EpubPreloadService(repo)),
    ];

    Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await t.pump(Duration(milliseconds: ms));
      }
    }

    Future<void> openReader(WidgetTester t, String id) async {
      await useSurface(t, const Size(420, 780));
      await repo.addBook(
        Book(
          id: id,
          title: '简繁书$id',
          local: true,
          epub: EpubRef(
            fmt: 'EPUB3',
            size: 10,
            path: '${tmp.path}/copy_$id.epub',
            srcPath: '${tmp.path}/src_$id.epub',
            srcName: 'src_$id.epub',
          ),
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(home: ReaderPage(bookId: id)),
        ),
      );
      await step(t, times: 4);
    }

    testWidgets('默认跟随原书＝正文按原文渲染', (t) async {
      await openReader(t, 's1');
      await t.tapAt(const Offset(210, 645)); // 中区唤起 chrome
      await step(t);
      expect(_shown(t), contains('这是一个测试段落'));
    });

    testWidgets('外观弹层选繁体并保存 → 标题与正文同换上屏，原文不受影响', (t) async {
      await openReader(t, 's2');
      await t.tapAt(const Offset(210, 645));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brBtnLook')));
      await step(t, times: 3);
      await t.tap(find.byKey(const ValueKey('brApSubBtn-s2t')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApS2T-t')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApSubDone')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brApSave')));
      await step(t, times: 3);
      await step(t, ms: 600, times: 2); // 指纹变了要重排一轮

      final shown = _shown(t);
      expect(shown, contains('這是一個測試段落'), reason: '正文未切繁体：\n$shown');
      expect(shown, contains('頭髮'), reason: '词组择字未生效');
      expect(shown, isNot(contains('这是一个测试段落')));
      // 逐书补丁落库＝配置面（不是把繁体写回文档）。
      final patch =
          jsonDecode((await repo.kv('reader.cfg.s2'))!) as Map<String, dynamic>;
      expect(patch['s2t'], kS2TTrad);
    });
  });
}
