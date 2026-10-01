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
import 'package:lifeharness/features/read/data/xray/xray_scheduler.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';

import 'helpers.dart';

/// 批1 修（20261002）· 选区迷你卡「查看全部位置」→ 面板直达详情的接力链路。
/// 独立文件铁律：全 app widget 用例不与他页同 isolate 混跑。
///
/// 修的两个哑火根因：
/// ① 只传词、面板全等匹配——选中文本与词条名不一致直接落空；
/// ② 一次性接力标志在面板首帧被消耗，而快照 provider 是异步加载的，
///    首帧 `snap.entities` 往往还是空 → 匹配必败且永不重试＝还得手动再搜。
///
/// 解析链不进本文件：词条用 `dao.writeRunResult` 直插（接力只依赖快照数据），
/// 调度器只做 provider 依赖填充、从不 start。

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

EpubDoc _doc() {
  final chs = [
    EpubChapter(href: 'c1', title: '第一章', paras: [
      _p('李德说今天有雾。'),
      ...List.generate(12, (i) => _p('第一章第$i段。' * 12)),
    ]),
    EpubChapter(href: 'c2', title: '第二章', paras: [
      _p('李德问路，路人摇头。'),
      ...List.generate(10, (i) => _p('第二章第$i段。' * 12)),
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

  /// 直插两词条：李德（章0/1 各一条锚点）+ 伦敦。返回 (李德id, 伦敦id)。
  Future<(int, int)> seedEntities() async {
    await dao.writeRunResult(md5: 'M', rows: [
      XrayWriteEntity(
          name: '李德',
          type: 'per',
          n: 2,
          chs: 2,
          score: 3.0,
          channels: 1,
          tocFlag: false,
          aliases: const [],
          anchors: const [XrayMention(0, 1, '李德说今天有雾'), XrayMention(1, 0)]),
      XrayWriteEntity(
          name: '伦敦',
          type: 'loc',
          n: 1,
          chs: 1,
          score: 1.5,
          channels: 4,
          tocFlag: false,
          aliases: const [],
          anchors: const [XrayMention(0, 2)]),
    ]);
    return (
      (await dao.entityByName('M', '李德'))!.id,
      (await dao.entityByName('M', '伦敦'))!.id,
    );
  }

  Future<void> openReader(
    WidgetTester t,
    String id, {
    List<Override> extra = const [],
  }) async {
    final sched = XrayScheduler(
      dao: dao,
      loadDoc: (_) async => _doc(),
      md5Hook: (_) async => 'M',
      // 接力测试永不 start 解析；真被调到即断言失败。
      workerFactory: (spec, ev) async => throw StateError('接力测试不应起解析'),
    );
    await useSurface(t, const Size(420, 1600));
    await repo.addBook(Book(
      id: id,
      title: '雾都小书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB2', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ));
    await dao.setBookMd5(id, 'M');
    await t.pumpWidget(ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
        xraySchedulerProvider.overrideWith((_) => sched),
        ...extra,
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
  }

  ProviderContainer containerOf(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(ReaderPage)));

  /// 开抽屉并切到 X-Ray 段（xray_panel_test toXrTab 同法）。
  Future<void> toXrTab(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('brBtnToc')));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('xrSegXr')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('快照竞态回归：闸住快照时直达不烧标志，放行后落详情', (t) async {
    final (lideId, _) = await seedEntities();
    final gate = Completer<XrayPanelData>();
    await openReader(t, 'r1', extra: [
      xraySnapProvider.overrideWith((ref, md5) => gate.future),
    ]);
    containerOf(t).read(readerXrFocusIdProvider.notifier).state = lideId;
    await toXrTab(t);
    // 快照未放行＝首帧空快照：老代码在这里已经把一次性标志烧掉、
    // 全等匹配打在空列表上，之后永远落在默认列表。
    expect(find.byKey(const ValueKey('xrDetail')), findsNothing);
    gate.complete(await dao.panelData('M'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('xrDetail')), findsOne,
        reason: '快照可用后接力必须补跑（老逻辑此处红灯）');
    expect(find.byKey(const ValueKey('xr-back')), findsOne);
    // 消费即清：旗标不残留，下次开面板不被旧 id 劫持。
    expect(containerOf(t).read(readerXrFocusIdProvider), isNull);
    expect(containerOf(t).read(readerXrFocusWordProvider), isNull);
  });

  testWidgets('id 失效回退词全等：重解析换行后仍落详情', (t) async {
    await seedEntities();
    await openReader(t, 'r2');
    containerOf(t).read(readerXrFocusIdProvider.notifier).state = 987654;
    containerOf(t).read(readerXrFocusWordProvider.notifier).state = '李德';
    await toXrTab(t);
    expect(find.byKey(const ValueKey('xrDetail')), findsOne);
    expect(find.text('李德'), findsWidgets);
    expect(containerOf(t).read(readerXrFocusIdProvider), isNull);
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('词互含回退：选中文本与词条名互含也能落到详情', (t) async {
    await seedEntities();
    await openReader(t, 'r3');
    // 只传词不传 id（老包升级中间态防御）：「李德先」与「李德」互含。
    containerOf(t).read(readerXrFocusWordProvider.notifier).state = '李德先';
    await toXrTab(t);
    expect(find.byKey(const ValueKey('xrDetail')), findsOne);
    expect(find.text('李德'), findsWidgets);
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('未命中＝面板带入搜索+空态加词入口（批2修③，不再自动弹加词）', (t) async {
    await seedEntities();
    await openReader(t, 'r4');
    containerOf(t).read(readerXrKwProvider.notifier).state = '巧克力';
    await toXrTab(t);
    // 搜索横幅 + 空态提示 + 加词入口（不自动弹层、不前置屏蔽）。
    expect(find.byKey(const ValueKey('xrKwBar')), findsOne);
    expect(find.text('搜索「巧克力」'), findsOne);
    expect(find.text('没有找到「巧克力」'), findsOne);
    expect(find.byKey(const ValueKey('xrKwAdd')), findsOne);
    expect(find.byKey(const ValueKey('sheetXrAdd')), findsNothing);
    expect(containerOf(t).read(readerXrKwProvider), isNull,
        reason: '接力旗标即清');
    // 空态加词 → 预填弹层。
    await t.tap(find.byKey(const ValueKey('xrKwAdd')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(find.byKey(const ValueKey('sheetXrAdd')), findsOne);
    expect(
      t.widget<TextField>(find.byKey(const ValueKey('xrAddWordIn')))
          .controller!
          .text,
      '巧克力',
    );
    // 清除搜索回全量列表。
    await clearToasts(t);
    await t.tapAt(const Offset(20, 20)); // 遮罩收加词弹层
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byKey(const ValueKey('xrKwClr')));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('xrKwBar')), findsNothing);
    final rows = find.byWidgetPredicate((w) =>
        w is GestureDetector &&
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('xrRow-'));
    expect(rows, findsWidgets, reason: '清除后应回到全量词条列表');
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('养词库开关：关＝纯预置视角（隐我的词条、恢复被屏蔽词）', (t) async {
    final (lideId, ldId) = await seedEntities();
    await dao.registerUserWord(md5: 'M', word: '自定义词', type: 'term');
    await dao.markDeleted('M', [ldId]); // 屏蔽引擎原始行「伦敦」
    await openReader(t, 'r6');
    await toXrTab(t);
    Future<void> expandLow() async {
      if (find.byKey(const ValueKey('xr-lowmore')).evaluate().isNotEmpty) {
        await t.tap(find.byKey(const ValueKey('xr-lowmore')));
        await t.pump(const Duration(milliseconds: 150));
      }
    }

    await expandLow();
    // 默认开：我的词条在列、被屏蔽的伦敦不出现。
    expect(find.text('自定义词'), findsOne);
    expect(find.text('伦敦'), findsNothing);
    // 关＝纯预置视角：user_added 隐掉、deleted 恢复。
    await t.tap(find.byKey(const ValueKey('xrUserDictBtn')));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('养词库 关'), findsOne);
    // 低置信折叠区保持展开（首次 expandLow 后 _lowOpen 常驻，快照重取不清）。
    expect(find.text('自定义词'), findsNothing,
        reason: '纯预置视角不显示 user_added');
    expect(find.text('伦敦'), findsOne, reason: '纯预置视角恢复被屏蔽的原始行');
    expect(containerOf(t).read(readerXrFocusIdProvider), isNull);
    expect(lideId, greaterThan(0));
    await clearToasts(t);
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('全落空不炸：id/词都无命中时停在默认列表', (t) async {
    await seedEntities();
    await openReader(t, 'r5');
    containerOf(t).read(readerXrFocusIdProvider.notifier).state = 876543;
    containerOf(t).read(readerXrFocusWordProvider.notifier).state = '不存在的实体';
    await toXrTab(t);
    expect(find.byKey(const ValueKey('xrDetail')), findsNothing);
    expect(find.byKey(const ValueKey('xrList')), findsOne);
    expect(containerOf(t).read(readerXrFocusIdProvider), isNull);
    expect(containerOf(t).read(readerXrFocusWordProvider), isNull);
    await t.pump(const Duration(milliseconds: 400));
  });
}
