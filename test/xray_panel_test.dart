import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/data/xray/xray_dao.dart';
import 'package:lifeharness/features/read/data/xray/xray_engine.dart';
import 'package:lifeharness/features/read/data/xray/xray_lexicon.dart';
import 'package:lifeharness/features/read/data/xray/xray_scheduler.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';

import 'helpers.dart';

/// V1.54 批A · X-Ray 面板与跳转（调度器假通道 + 面板 widget，禁真 isolate/真 IO）。
/// 独立文件铁律：全 app widget 用例不与他页同 isolate 混跑。

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

/// 两章小书：`李德` 出现 4 次（per 门槛＝3），`伦敦`（gazetteer）3 次。
EpubDoc _doc() {
  final chs = [
    // 引擎门槛（per=3/loc=3·小书 scale=1）：李德走 说/道/问 语境动词通道 ×4，
    // 伦敦走 gazetteer ×3——低于门槛的样本会被静默丢弃，别拿它测面板。
    EpubChapter(href: 'c1', title: '第一章', paras: [
      _p('李德说今天有雾。'),
      _p('李德道："伦敦起雾了。"'),
      _p('谁也没看见伦敦的雾。'),
      ...List.generate(30, (i) => _p('第一章第$i段。' * 12)),
    ]),
    EpubChapter(href: 'c2', title: '第二章', paras: [
      _p('李德问路，路人摇头。'),
      _p('李德说伦敦的雨来了。'),
      ...List.generate(24, (i) => _p('第二章第$i段。' * 12)),
    ]),
  ];
  return EpubDoc(
    format: 'EPUB2',
    title: '雾都小书',
    author: '甲',
    toc: const [],
    chapters: chs,
    imageCount: 0,
    totalChars: chs.fold(0, (s, c) => s + c.charCount),
  );
}

/// 迷你词库（8 张表都要非空，形态＝一行一词）。
XrayWordBank _bank() => XrayWordBank.parse({
      'func_words.txt': '的\n了\n谁\n也\n没\n看\n见\n在\n路\n雨\n来\n了\n都',
      'common_nouns.txt': '街口\n路人',
      'titles.txt': '先生',
      'surnames.txt': '李',
      'loc_suffix.txt': '市',
      'org_suffix.txt': '公司',
      'stop_en.txt': 'the',
      'gazetteer.txt': '伦敦',
    });

/// 假计算通道：同 isolate 直跑引擎（微任务回执模拟乒乓，FakeAsync 零真线程）。
class _FakeWorker implements XrayWorker {
  _FakeWorker(this._spec, this._ev)
      : engine = XrayEngine(
          bank: _bank(),
          book: XrayUserLayer(added: _spec.added, forbidden: _spec.forbidden),
          totalChars: _spec.totalChars,
          sens: _spec.sens,
        );

  final XrayJobSpec _spec;
  final XrayWorkerEvents _ev;
  final XrayEngine engine;
  final Map<int, List<String>> _stored = {};
  List<XrayEntity>? _keep;

  @override
  void feedCollect(int ci, List<String> paras) {
    _stored[ci] = paras;
    engine.runChapter(XrayChapter(idx: ci, paras: paras));
    scheduleMicrotask(() => _ev.onChapterDone(ci));
  }

  @override
  void feedAnchor(int ci, List<String> paras) {
    engine.anchorPass(XrayChapter(idx: ci, paras: _stored[ci] ?? const []));
    scheduleMicrotask(() => _ev.onChapterDone(ci));
  }

  @override
  void finishCollect() {
    _keep = engine.finish(tocTitles: _spec.tocTitles);
    if (engine.needsAnchorPass) {
      for (final e in _stored.entries) {
        engine.anchorPass(XrayChapter(idx: e.key, paras: e.value));
      }
    }
    scheduleMicrotask(() => _ev.onResult(_payloadOf(_keep!)));
  }

  @override
  void cancel() {}
}

List<Map<String, Object?>> _payloadOf(List<XrayEntity> ents) => [
      for (final e in ents)
        {
          'name': e.name,
          'type': e.type.code,
          'n': e.n,
          'chs': e.chs,
          'score': e.score,
          'ch': e.channels,
          'toc': e.tocFlag ? 1 : 0,
          'al': e.aliases.toList(),
          'm': [
            for (final m in e.mentions) [m.ch, m.para, m.snippet],
          ],
        },
    ];

/// 炸掉的通道（失败弹层用例）。
class _BoomWorker implements XrayWorker {
  _BoomWorker(this._ev);
  final XrayWorkerEvents _ev;
  @override
  void feedCollect(int ci, List<String> paras) {
    scheduleMicrotask(() => _ev.onFail('模拟引擎崩溃'));
  }

  @override
  void feedAnchor(int ci, List<String> paras) {}
  @override
  void finishCollect() {}
  @override
  void cancel() {}
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late XrayDao dao;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    dao = XrayDao(db);
  });
  tearDown(() => db.close());

  Future<Book> addBook(String id) async {
    return repo.addBook(Book(
      id: id,
      title: '雾都小书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB2', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ));
  }

  XrayScheduler makeScheduler({bool boom = false}) => XrayScheduler(
        dao: dao,
        loadDoc: (_) async => _doc(),
        md5Hook: (_) async => 'M',
        workerFactory: (spec, ev) async =>
            boom ? _BoomWorker(ev) : _FakeWorker(spec, ev),
      );

  /// 假通道全链路只踩微任务（sqflite ffiNoIsolate 同线程），无需推钟。
  Future<XrayTaskRow?> waitTask(XrayScheduler s, String md5) async {
    for (var i = 0; i < 2000; i++) {
      final t = await dao.task(md5);
      if (t != null &&
          (t.status == 'success' ||
              t.status == 'failed' ||
              t.status == 'canceled')) {
        return t;
      }
      await Future<void>.microtask(() {});
    }
    return dao.task(md5);
  }

  group('批A-S · 调度器（假通道）', () {
    test('ensureMd5 懒补算：无指纹→算→落 books.md5（经 DAO）', () async {
      final b = await addBook('s1');
      final s = makeScheduler();
      expect(await dao.bookMd5('s1'), isNull);
      expect(await s.ensureMd5(b), 'M');
      expect(await dao.bookMd5('s1'), 'M');
      s.dispose();
    });

    test('全书跑：逐章进度 → 词条+锚点落库 → 任务态 success', () async {
      final b = await addBook('s2');
      final s = makeScheduler();
      await s.start(book: b, md5: 'M', from: 0, to: 1);
      final t = await waitTask(s, 'M');
      expect(t?.status, 'success', reason: '假通道必须推到终态');
      final ents = await dao.allEntities('M');
      final lide = ents.where((e) => e.name == '李德').toList();
      expect(lide, hasLength(1));
      expect(lide.first.n, greaterThanOrEqualTo(4));
      // 批A 引擎补齐：锚点全量（此前截到 6），迷你分布条/出场列表都要全。
      final anchors = await dao.anchorsOf('M', lide.first.id);
      expect(anchors.length, lide.first.n);
      // snippet 只许前 6 条带文（§6 体积口径）。
      final withSnip = anchors.where((a) => a.snippet != null).length;
      expect(withSnip, lessThanOrEqualTo(6));
      s.dispose();
    });

    test('失败通道：任务态 failed + live.error 可见', () async {
      final b = await addBook('s3');
      final s = makeScheduler(boom: true);
      await s.start(book: b, md5: 'M', from: 0, to: 1);
      final t = await waitTask(s, 'M');
      expect(t?.status, 'failed');
      expect(s.live('s3')?.error, contains('模拟引擎崩溃'));
      s.dispose();
    });

    test('重置：三层数据清空、用户词典保留', () async {
      final b = await addBook('s4');
      final s = makeScheduler();
      await dao.putUserWord(scope: 'M', word: '自定义词', action: 'add');
      await s.start(book: b, md5: 'M', from: 0, to: 1);
      await waitTask(s, 'M');
      expect(await dao.allEntities('M'), isNotEmpty);
      await s.reset('s4', 'M');
      expect(await dao.allEntities('M'), isEmpty);
      expect(await dao.task('M'), isNull);
      expect((await dao.userLayer('M')).added, contains('自定义词'));
      s.dispose();
    });
  });

  group('批A-P · 面板与跳转（widget）', () {
    Future<XrayScheduler> openReader(
      WidgetTester t,
      String id, {
      bool boom = false,
      List<Override>? extra,
    }) async {
      final sched = makeScheduler(boom: boom);
      // 半屏弹层里的开始/菜单行在 780 高视口放不下（真机同样要能点）：垫高再测。
      await useSurface(t, const Size(420, 1600));
      await addBook(id);
      await dao.setBookMd5(id, 'M');
      await t.pumpWidget(ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
          xraySchedulerProvider.overrideWith((_) => sched),
          ...extra ?? const [],
        ],
        child: MaterialApp(home: ReaderPage(bookId: id)),
      ));
      // 阅读页有周期计时 Timer，禁 pumpAndSettle（reader_ui 同法小步推帧）。
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      // 默认收起 chrome：中区空白点开顶/底栏（reader_ui 同法坐标）。
      await t.tapAt(const Offset(210, 645));
      await t.pump(const Duration(milliseconds: 200));
      return sched;
    }

    Future<void> toXrTab(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('brBtnToc')));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('xrSegXr')));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('未解析空态 → 生成入口 → 范围弹层 → 跑完出词条', (t) async {
      final sched = await openReader(t, 'p1');
      await toXrTab(t);
      expect(find.byKey(const ValueKey('xrGen')), findsOne);
      await t.tap(find.byKey(const ValueKey('xrGen')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('sheetXrScope')), findsOne);
      // 半屏弹层入场动画走完之前几何还在屏幕下方——先落帧再取点。
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      await t.ensureVisible(find.byKey(const ValueKey('xrScopeGo')));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byKey(const ValueKey('xrScopeGo')));
      await waitTask(sched, 'M');
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.textContaining('已解析'), findsOne);
      expect(find.textContaining('李德'), findsWidgets);
      await t.pump(const Duration(milliseconds: 400));
    });

    testWidgets('先解析再开面板：词条行+类型段+详情+剧透保护', (t) async {
      final sched = await openReader(t, 'p2');
      final b = await repo.bookById('p2');
      await sched.start(book: b!, md5: 'M', from: 0, to: 1);
      await waitTask(sched, 'M');
      expect(await dao.bookMd5('p2'), 'M', reason: '前置：指纹已在库');
      expect((await dao.allEntities('M')).map((e) => e.name).toList(), isNotEmpty,
          reason: '前置：词条已落库');
      await toXrTab(t);
      // 类型段：人名/地点非空必现。
      expect(find.byKey(const ValueKey('xr-tp-per')), findsOne);
      expect(find.byKey(const ValueKey('xr-tp-loc')), findsOne);
      // 「在当前页」分组：第一章第一段有李德，当前停在章0页0。
      expect(find.textContaining('在当前页'), findsOne);
      // 点第一个词条行进详情。
      final rows = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xrRow-'));
      expect(rows, findsWidgets);
      await t.tap(rows.first);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('xr-back')), findsOne);
      expect(find.byKey(const ValueKey('xr-cites')), findsOne);
      // F12 默认保护：橙线之前的引用可见、隐藏行按数据出现。
      // 点一条出场 → 关面板跳阅读位。
      final clips = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xr-clip-'));
      expect(clips, findsWidgets);
      await t.scrollUntilVisible(clips.first, 300,
          scrollable: find.descendant(
              of: find.byKey(const ValueKey('xrDetail')),
              matching: find.byType(Scrollable)));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(clips.first);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('brDrPanel')), findsNothing);
      await t.pump(const Duration(seconds: 2)); // 闪烁环 1.6s 自摘
      await t.pump(const Duration(milliseconds: 400));
    });

    testWidgets('范围段切换：当前页 ⊂ 本章 ⊂ 全书', (t) async {
      final sched = await openReader(t, 'p3');
      final b = await repo.bookById('p3');
      await sched.start(book: b!, md5: 'M', from: 0, to: 1);
      await waitTask(sched, 'M');
      await toXrTab(t);
      int rowCount() => find
          .byWidgetPredicate((w) =>
              w is GestureDetector &&
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('xrRow-'))
          .evaluate()
          .length;
      // 原型默认段态＝全书；逐级收到「当前页」再逐级放宽回来。
      await t.tap(find.byKey(const ValueKey('xr-scope-page')));
      await t.pump(const Duration(milliseconds: 100));
      final page = rowCount();
      await t.tap(find.byKey(const ValueKey('xr-scope-chapter')));
      await t.pump(const Duration(milliseconds: 200));
      final chap = rowCount();
      await t.tap(find.byKey(const ValueKey('xr-scope-book')));
      await t.pump(const Duration(milliseconds: 200));
      final book = rowCount();
      expect(page, lessThanOrEqualTo(chap));
      expect(chap, lessThanOrEqualTo(book));
      expect(book, greaterThan(0));
      await t.pump(const Duration(milliseconds: 400));
    });

    testWidgets('失败态：面板打开自动挂中断弹层，可关闭', (t) async {
      final sched = await openReader(t, 'p4', boom: true);
      final b = await repo.bookById('p4');
      await sched.start(book: b!, md5: 'M', from: 0, to: 1);
      await waitTask(sched, 'M');
      await toXrTab(t);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('sheetXrFail')), findsOne);
      await t.ensureVisible(find.byKey(const ValueKey('xrFailClose')));
      await t.tap(find.byKey(const ValueKey('xrFailClose'))); // 关闭钮退弹层
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('sheetXrFail')), findsNothing);
      await t.pump(const Duration(milliseconds: 400));
    });

    testWidgets('⋯菜单行入口：打开面板即停 X-Ray 段', (t) async {
      final sched = await openReader(t, 'p5');
      await t.tap(find.byKey(const ValueKey('brBtnMore')));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('brMoreXr')), findsOne);
      await t.ensureVisible(find.byKey(const ValueKey('brMoreXr')));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byKey(const ValueKey('brMoreXr')));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('brDrPanel')), findsOne);
      expect(find.byKey(const ValueKey('xrGen')), findsOne);
      await t.pump(const Duration(milliseconds: 400));
    });

    testWidgets('搜词条：独占态过滤词条行（段感知）', (t) async {
      final sched = await openReader(t, 'p6');
      final b = await repo.bookById('p6');
      await sched.start(book: b!, md5: 'M', from: 0, to: 1);
      await waitTask(sched, 'M');
      await toXrTab(t);
      await t.tap(find.byKey(const ValueKey('xrSearchPill')));
      await t.pump(const Duration(milliseconds: 200));
      await t.enterText(find.byKey(const ValueKey('brDrQ')), '李德');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('xrSearchPill')), findsNothing); // pill 让位输入行
      expect(find.byKey(const ValueKey('xrHdrClr')), findsOne);
      await t.tap(find.byKey(const ValueKey('xrHdrCancel')));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('xrSearchPill')), findsOne);
      await t.pump(const Duration(milliseconds: 400));
    });
  });
}
