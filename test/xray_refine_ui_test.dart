import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/data/xray/xray_dao.dart';
import 'package:lifeharness/features/read/data/xray/xray_engine.dart'
    show XrayMention;
import 'package:lifeharness/features/read/data/xray/xray_refine.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_xray_refine.dart';

import 'helpers.dart';

/// V1.54.1 批4 · 精化 UI 面（面板内进度卡 + 汇总审阅弹层）。
///
/// 门控与真请求（`AiService.gate/request`）由 ai_* 套件与真机走查覆盖；这里只钉两件事：
/// ① 卡片是否把 runner 的状态如实画出来（含暂停↔继续、失败提示、中止收场）；
/// ② 审阅是否**按勾选**落库（默认全勾、取消的不写、写入后清持有位并刷面板）。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const md5 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  late Database db;
  late ReadRepository repo;
  late XrayDao dao;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    dao = XrayDao(db);
    await db.insert(DbSchema.tBooks, {
      'id': 'bkB',
      'title': '书B',
      'md5': md5,
      'created_at': 1,
      'updated_at': 1,
    });
    await dao.writeRunResult(md5: md5, rows: [
      XrayWriteEntity(
          name: '概念',
          type: 'term',
          n: 20,
          chs: 3,
          score: 2.0,
          channels: 1,
          tocFlag: false,
          aliases: const [],
          anchors: const [XrayMention(0, 1, '概念先行')]),
      XrayWriteEntity(
          name: '罗马',
          type: 'term',
          n: 9,
          chs: 2,
          score: 1.2,
          channels: 1,
          tocFlag: false,
          aliases: const [],
          anchors: const [XrayMention(1, 4, '罗马城中')]),
    ]);
    container = ProviderContainer(overrides: [
      readRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
  });

  tearDown(() async => db.close());

  void setHolder(XrRefineRunner? r) =>
      container.read(xrRefineHolderProvider.notifier).state = r;

  XrRefineRunner baseRunner() =>
      XrRefineRunner(budgetChars: 40, caller: (_) async => null);

  Future<void> pumpHost(WidgetTester t, Widget Function(BuildContext, WidgetRef) body) =>
      t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(body: Consumer(builder: (c, ref, _) => body(c, ref)))),
      ));

  testWidgets('进度卡：状态如实渲染 · 暂停↔继续就地切换', (t) async {
    final r = baseRunner()
      ..totalBatches = 4
      ..doneBatches = 1
      ..lastFailedBatch = 2
      ..stage = XrRefineStage.running;
    setHolder(r);
    await pumpHost(t,
        (c, ref) => XrRefineCard(runner: r, md5: md5));

    expect(find.byKey(const ValueKey('xrAiBar')), findsOne);
    expect(find.text('AI 精化 · 第 1/4 批'), findsOne);
    expect(find.byKey(const ValueKey('xrAiErr')), findsOne,
        reason: '有失败批就明写，不静默跳过');
    expect(find.byKey(const ValueKey('xrAiPause')), findsOne);

    await t.tap(find.byKey(const ValueKey('xrAiPause')));
    await t.pump();
    expect(r.stage, XrRefineStage.paused);
    expect(find.byKey(const ValueKey('xrAiResume')), findsOne);

    await t.tap(find.byKey(const ValueKey('xrAiResume')));
    await t.pump();
    expect(r.stage, XrRefineStage.running);
    expect(find.byKey(const ValueKey('xrAiPause')), findsOne);
    await settleLogTimer(t);
  });

  testWidgets('中止且零建议：出「清除」钮，点了就摘掉持有位', (t) async {
    final r = baseRunner()
      ..totalBatches = 3
      ..doneBatches = 1
      ..failedBatches = 2
      ..stage = XrRefineStage.cancelled;
    setHolder(r);
    await pumpHost(t,
        (c, ref) => XrRefineCard(runner: r, md5: md5));

    expect(find.byKey(const ValueKey('xrAiAborted')), findsOne);
    expect(find.byKey(const ValueKey('xrAiShowRev')), findsNothing);
    await t.tap(find.byKey(const ValueKey('xrAiClear')));
    await t.pump();
    expect(container.read(xrRefineHolderProvider), isNull);
    await settleLogTimer(t);
  });

  testWidgets('跑完→查看汇总：默认全勾 · 取消勾选的不写 · 升级全局写 GLOBAL', (t) async {
    final r = baseRunner()
      ..suggestions.addAll(const [
        XrRefineSuggestion(kind: XrRefineKind.remove, word: '概念'),
        XrRefineSuggestion(kind: XrRefineKind.retype, word: '罗马', type: 'loc'),
        XrRefineSuggestion(kind: XrRefineKind.add, word: '波洛', type: 'per'),
      ])
      ..totalBatches = 2
      ..doneBatches = 2
      ..stage = XrRefineStage.done;
    setHolder(r);
    await pumpHost(t, (c, ref) => Column(children: [
          XrRefineCard(runner: r, md5: md5),
          TextButton(
              key: const ValueKey('probe'),
              onPressed: () => showXrRefineReview(c, ref, md5: md5),
              child: const Text('probe')),
        ]));

    expect(find.text('2 批跑完 · 建议 3 条'), findsOne);
    await t.tap(find.byKey(const ValueKey('xrAiShowRev')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('xrAiRevBody')), findsOne);
    expect(find.text('建议删除 · 1'), findsOne);
    expect(find.text('建议改类 · 1'), findsOne);
    expect(find.text('建议补词 · 1'), findsOne);
    expect(find.text('确认写入 3 条'), findsOne, reason: '默认全勾（与原型一致）');

    await t.tap(find.byKey(const ValueKey('xrAiR-remove/概念')));
    await t.pump();
    expect(find.text('确认写入 2 条'), findsOne);

    await t.tap(find.byKey(const ValueKey('xrAiSc-global')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('xrAiApplyGo')));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.textContaining('已写入 2 条'), findsOne);
    final g = await dao.listGlobalDict();
    expect(g.map((e) => '${e.word}/${e.action}'),
        containsAll(<String>['罗马/add', '波洛/add']));
    expect(g.any((e) => e.word == '概念'), isFalse, reason: '取消勾选的不写');
    expect((await dao.entityByName(md5, '罗马'))!.type, 'loc',
        reason: '勾了的改类要真改实体行');
    expect((await dao.entityByName(md5, '概念'))!.status, 'active',
        reason: '勾掉的删除建议一条都没落');
    expect(container.read(xrRefineHolderProvider), isNull,
        reason: '写完即收场，进度卡不永挂');
    await drainLogTimer(t);
  });

  testWidgets('持有位为空时点「查看汇总」＝不开层不崩', (t) async {
    setHolder(null);
    await pumpHost(t, (c, ref) => TextButton(
          key: const ValueKey('probe'),
          onPressed: () => showXrRefineReview(c, ref, md5: md5),
          child: const Text('probe'),
        ));
    await t.tap(find.byKey(const ValueKey('probe')));
    await t.pump();
    expect(find.byKey(const ValueKey('xrAiRevBody')), findsNothing);
  });
}
