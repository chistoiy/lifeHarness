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
  XrayWordScan? _scan;

  @override
  void feedCollect(int ci, List<String> paras) {
    _stored[ci] = paras;
    if (_spec.word != null) {
      _scan ??= XrayWordScan(
          word: _spec.word!, type: _spec.wordType ?? 'term', bank: _bank());
      _scan!.addChapter(ci, paras);
    } else {
      engine.runChapter(XrayChapter(idx: ci, paras: paras));
    }
    scheduleMicrotask(() => _ev.onChapterDone(ci));
  }

  @override
  void feedAnchor(int ci, List<String> paras) {
    engine.anchorPass(XrayChapter(idx: ci, paras: _stored[ci] ?? paras));
    // 与真 isolate `_entry` 同形：锚点遍**只回 'w' 不回 'd'**，越界才投递 result。
    // （旧夹具在 finishCollect 里自己把锚点遍跑完，等于绕过了握手，
    //  把 `_onWantAnchor` 掩盖成死代码 → 真机第一章后死锁。）
    scheduleMicrotask(() {
      if (ci + 1 >= _spec.totalCh) {
        _ev.onResult(_payloadOf(_keep!));
      } else {
        _ev.onWantAnchor(ci + 1);
      }
    });
  }

  @override
  void finishCollect() {
    if (_scan != null) {
      final payload = _scan!.payload();
      scheduleMicrotask(() => _ev.onResult([payload]));
      return;
    }
    _keep = engine.finish(tocTitles: _spec.tocTitles);
    if (engine.needsAnchorPass) {
      scheduleMicrotask(() => _ev.onWantAnchor(0));
      return;
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

/// 只收不回话的通道：喂完章不推进，用来验「暂停/恢复」这条状态机分支
/// （假通道跑得太快，暂停态根本停不出来）。
class _SilentWorker implements XrayWorker {
  _SilentWorker(XrayWorkerEvents ev);
  @override
  void feedCollect(int ci, List<String> paras) {}
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

  XrayScheduler makeScheduler({bool boom = false, bool silent = false}) =>
      XrayScheduler(
        dao: dao,
        loadDoc: (_) async => _doc(),
        md5Hook: (_) async => 'M',
        workerFactory: (spec, ev) async => boom
            ? _BoomWorker(ev)
            : silent
                ? _SilentWorker(ev)
                : _FakeWorker(spec, ev),
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

    test('退后台暂停：running 标记必须落回，回前台给原地续喂（真机死状态回归）',
        () async {
      // 2026-10-01 15:49 真机：Home 后回来面板头仍「解析中 25%」，只剩「重置」——
      // pause() 只停喂章、没清 live.running，于是标签和钮双双骗人。
      final b = await addBook('s7');
      final s = makeScheduler(silent: true);
      await s.start(book: b, md5: 'M', from: 0, to: 1);
      var up = false;
      for (var i = 0; i < 500 && !up; i++) {
        await dao.task('M'); // 真 DB 往返：让 _drive 的 await 链推进
        up = s.live('s7')?.running ?? false;
      }
      expect(up, isTrue, reason: '静默通道下任务应停在「在跑」');
      s.pauseBook('s7');
      expect(s.live('s7')!.running, isFalse,
          reason: '暂停后仍报在跑 → 面板永远「解析中」且「继续生成」不出现');
      var paused = false;
      XrayTaskRow? t;
      for (var i = 0; i < 500 && !paused; i++) {
        t = await dao.task('M');
        paused = t?.status == 'pause';
      }
      expect(paused, isTrue, reason: '断点必须落库（进程被杀也接得回）');
      await s.resume(b, 'M');
      expect(s.live('s7')!.running, isTrue,
          reason: 'worker 还活着＝原地续喂，不该整本重来');
      s.dispose();
    });

    test('冷启动收尸：库里残留 running 转 pause（否则谎报已解析/解析中）', () async {
      await dao.upsertTask(
          md5: 'M',
          totalCh: 2,
          rangeStart: 0,
          rangeEnd: 1,
          status: 'running',
          processedCh: 1);
      final s = makeScheduler();
      await s.reconcileStale();
      expect((await dao.task('M'))!.status, 'pause',
          reason: '单进程 app 里 running 只可能是上个进程的死任务');
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
      await openReader(t, 'p5');
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

  group('批B-L · 自学习（假通道）', () {
    test('加词补扫：出场回填 + 称谓形态建议产出', () async {
      final b = await addBook('l1');
      await dao.setBookMd5('l1', 'M');
      final s = makeScheduler();
      await s.dao.registerUserWord(md5: 'M', word: '李德', type: 'per');
      await s.scanWord(book: b, md5: 'M', word: '李德', type: 'per');
      // 假通道纯微任务：轮询到词条计数回填为止。
      var ent = await dao.entityByName('M', '李德');
      for (var i = 0; i < 2000 && (ent == null || ent.n == 0); i++) {
        await Future<void>.microtask(() {});
        ent = await dao.entityByName('M', '李德');
      }
      expect(ent, isNotNull);
      expect(ent!.userAdded, isTrue, reason: '加词行必须标 my-vocab 来源');
      expect(ent.n, greaterThanOrEqualTo(4));
      final anchors = await dao.anchorsOf('M', ent.id);
      expect(anchors.length, ent.n, reason: '补扫锚点全量');
      // 语料里「李德说/李德道/李德问」后跟的是动词不是称谓 → 不产建议；
      // 称谓形态在下一例专门验。
      expect(s.suggestion('l1'), isNull);
      s.dispose();
    });

    test('称谓形态 ≥30% → 建议卡 + 采纳落 GLOBAL', () async {
      final b = await addBook('l2');
      await dao.setBookMd5('l2', 'M');
      final s2 = XrayScheduler(
        dao: dao,
        loadDoc: (_) async => EpubDoc(
          format: 'EPUB2',
          title: '称谓书',
          author: '甲',
          toc: const [],
          chapters: [
            EpubChapter(href: 'c1', title: '第一章', paras: [
              _p('李德先生说。'),
              _p('李德先生道。'),
              _p('李德先生问。'),
              _p('有人喊了李德。'),
            ]),
          ],
          imageCount: 0,
          totalChars: 40,
        ),
        md5Hook: (_) async => 'M',
        workerFactory: (spec, ev) async => _FakeWorker(spec, ev),
      );
      await s2.dao.registerUserWord(md5: 'M', word: '李德', type: 'per');
      await s2.scanWord(book: b, md5: 'M', word: '李德', type: 'per');
      for (var i = 0; i < 2000 && s2.suggestion('l2') == null; i++) {
        await Future<void>.microtask(() {});
      }
      final sug2 = s2.suggestion('l2');
      expect(sug2, isNotNull, reason: '75% 出场后跟「先生」必须挂出建议');
      expect(sug2!.title, '先生');
      await s2.dao.promoteWordToGlobal('M', '李德', patternHint: '先生');
      final layer = await s2.dao.userLayer('M');
      expect(layer.added, contains('李德'));
      s2.dismissSuggestion('l2');
      expect(s2.suggestion('l2'), isNull);
      s2.dispose();
    });

    test('合并写时物化：mention 迁移 + aliases + n/chs 重算 + 死行标记', () async {
      await addBook('l3');
      await dao.setBookMd5('l3', 'M');
      final s = makeScheduler();
      // 造两条词条：李德（章0/1 各一条锚点）与 李德先生（章1 两条）。
      await s.dao.writeRunResult(md5: 'M', rows: [
        XrayWriteEntity(
            name: '李德',
            type: 'per',
            n: 2,
            chs: 2,
            score: 3.0,
            channels: 1,
            tocFlag: false,
            aliases: const [],
            anchors: const [XrayMention(0, 3), XrayMention(1, 1)]),
        XrayWriteEntity(
            name: '李德先生',
            type: 'per',
            n: 2,
            chs: 1,
            score: 2.0,
            channels: 1,
            tocFlag: false,
            aliases: const [],
            anchors: const [XrayMention(1, 5, '李德先生道'), XrayMention(1, 9)]),
      ]);
      final a = (await dao.entityByName('M', '李德'))!;
      final c = (await dao.entityByName('M', '李德先生'))!;
      await dao.mergeInto('M', intoId: a.id, fromIds: [c.id]);
      final into = (await dao.entityByName('M', '李德'))!;
      expect(into.aliases, contains('李德先生'));
      expect(into.n, 4, reason: '写时物化：n 当场重算，不靠读侧再并');
      final anchors = await dao.anchorsOf('M', into.id);
      expect(anchors, hasLength(4));
      expect((await dao.anchorsOf('M', c.id)), isEmpty,
          reason: '出场已整体迁到规范词条');
      final dead = await dao.entityById('M', c.id);
      expect(dead, isNull, reason: 'merged_into 行不再出现在读侧');
      s.dispose();
    });

    test('移除=状态位：读侧消失且重解析不洗白；全局升级入黑名单', () async {
      final b = await addBook('l4');
      await dao.setBookMd5('l4', 'M');
      final s = makeScheduler();
      await s.start(book: b, md5: 'M', from: 0, to: 1);
      await waitTask(s, 'M');
      final lide = (await dao.entityByName('M', '李德'))!;
      await dao.markDeleted('M', [lide.id], toGlobal: true);
      // entityByName 是加词幂等点查（不带状态过滤）；读侧口径看 allEntities。
      expect(
          (await dao.allEntities('M')).where((e) => e.name == '李德'), isEmpty);
      final layer = await dao.userLayer('M');
      expect(layer.forbidden, contains('李德'));
      // 重跑解析（洗白攻击面）：被屏蔽的词不得回到读侧。
      // 注意不能复用 waitTask——库里仍是上一轮的 success，轮询会立刻假绿放行；
      // 改等终态修订号前进（写入链真正完成之后才 bump）。
      final rev0 = s.revision;
      await s.start(book: b, md5: 'M', from: 0, to: 1);
      for (var i = 0; i < 4000 && s.revision == rev0; i++) {
        await Future<void>.microtask(() {});
      }
      expect((await dao.allEntities('M')).where((e) => e.name == '李德'),
          isEmpty);
      s.dispose();
    });
  });

  group('批B-W · 面板自学习面（widget）', () {
    Future<XrayScheduler> openReaderB(
      WidgetTester t,
      String id, {
      Size surface = const Size(420, 1600),
    }) async {
      final sched = makeScheduler();
      await useSurface(t, surface);
      await addBook(id);
      await dao.setBookMd5(id, 'M');
      await t.pumpWidget(ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
          xraySchedulerProvider.overrideWith((_) => sched),
        ],
        child: MaterialApp(home: ReaderPage(bookId: id)),
      ));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      await t.tapAt(const Offset(210, 645));
      await t.pump(const Duration(milliseconds: 200));
      return sched;
    }

    Future<void> toXrTabB(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('brBtnToc')));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('xrSegXr')));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('＋加词 → 弹层登记 → 整理模式勾选→移除弹层', (t) async {
      final sched = await openReaderB(t, 'w1');
      final b = await repo.bookById('w1');
      await sched.start(book: b!, md5: 'M', from: 0, to: 1);
      await waitTask(sched, 'M');
      await toXrTabB(t);
      // 加词弹层
      await t.tap(find.byKey(const ValueKey('xrAddBtn')));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const ValueKey('sheetXrAdd')), findsOne);
      await t.enterText(find.byKey(const ValueKey('xrAddWordIn')), '巧克力');
      await t.pump(const Duration(milliseconds: 100));
      await t.ensureVisible(find.byKey(const ValueKey('xrAddGo')));
      await t.tap(find.byKey(const ValueKey('xrAddGo')));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final ent = await dao.entityByName('M', '巧克力');
      expect(ent, isNotNull, reason: '加词行必须登记（默认语料无出场也建行）');
      expect(ent!.userAdded, isTrue);
      // 整理模式：勾选榜首 → 底栏出现 → 移除弹层确认 → 该行从列表消失。
      // 加词提示条盖在底栏上（真机同理），先退场再点整理钮。
      await clearToasts(t);
      await t.tap(find.byKey(const ValueKey('xrOrgBtn')));
      await t.pump(const Duration(milliseconds: 100));
      final rows = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xrRow-'));
      expect(rows, findsWidgets);
      final firstKey =
          (rows.evaluate().first.widget as GestureDetector).key as ValueKey<String>;
      await t.tap(rows.first);
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('xrOrgBar')), findsOne);
      await t.tap(find.byKey(const ValueKey('xrOrgDel')));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const ValueKey('sheetXrDel')), findsOne);
      await t.ensureVisible(find.byKey(const ValueKey('xrDelGo')));
      await t.tap(find.byKey(const ValueKey('xrDelGo')));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(firstKey), findsNothing,
          reason: '移除＝读侧立刻消失（状态位口径）');
    });

    testWidgets('详情自学习三件套在位（候选卡随数据出现）', (t) async {
      // 详情整段放进视口：scrollUntilVisible 对 List-delegate ListView 会触发
      // sliver 断言（本批实测），垫高视口比与框架打架划算。
      final sched = await openReaderB(t, 'w2', surface: const Size(420, 2600));
      final b = await repo.bookById('w2');
      await sched.start(book: b!, md5: 'M', from: 0, to: 1);
      await waitTask(sched, 'M');
      // 造一条与「李德」互含的词条触发候选卡。
      await dao.writeRunResult(md5: 'M', rows: [
        XrayWriteEntity(
            name: '李德先生',
            type: 'per',
            n: 1,
            chs: 1,
            score: 0.5,
            channels: 1,
            tocFlag: false,
            aliases: const [],
            anchors: const [XrayMention(1, 0, '李德先生道')]),
      ]);
      sched.notifyDataChanged();
      await toXrTabB(t);
      final rows = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xrRow-'));
      expect(rows, findsWidgets);
      // 榜首是高频术语（几百条出场会把自学习区顶出视口）——直点低频的「李德」；
      // 它的分值低于「本书最高分×0.7」，先在低置信折叠区展开。
      if (find.text('李德').evaluate().isEmpty) {
        await t.tap(find.byKey(const ValueKey('xr-lowmore')));
        await t.pump(const Duration(milliseconds: 100));
      }
      final rowPred = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xrRow-'));
      await t.tap(find.ancestor(of: find.text('李德'), matching: rowPred).first);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const ValueKey('xr-merge-into')), findsOne);
      expect(find.byKey(const ValueKey('xr-ban')), findsOne);
      expect(find.byKey(const ValueKey('xr-aihold')), findsOne);
      final cand = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xr-cand-'));
      expect(cand, findsOne, reason: '「李德先生」互含必出候选卡');
    });
  });
}
