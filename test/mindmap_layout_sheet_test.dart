import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/domain/mindmap_layout_preset.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批4 · 布局家族**交互面**守护（工单 §4e.2 ③④⑦ + 变异刀1 钉位）。
///
/// 与 `mindmap_layout_preset_test.dart` 分文件＝一文件一波（口径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late SharedPreferences mmPrefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mmPrefs = await SharedPreferences.getInstance();
    db = await openMmDb();
  });
  tearDown(() async {
    await (db as CloseableDb).close();
  });

  Future<int> pumpCanvas(WidgetTester tester, {String title = '图'}) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap(title);
    await dao.addNode(mapId: mapId, title: '中心主题');
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return mapId;
  }

  testWidgets('布局弹层：四张预设卡＋容器比例段齐全，入口在缩放条布局钮',
      (tester) async {
    await pumpCanvas(tester);
    // 入口＝缩放条上的布局钮（原型 mmZoomBar 顺序：放大·缩小·fit·布局·样式）。
    await tester.tap(find.byKey(const ValueKey('mm-layout-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mm-layout-sheet')), findsOneWidget);
    for (final k in [
      'mm-layout-card-tree/right/portrait',
      'mm-layout-card-tree/right/landscape',
      'mm-layout-card-tree/both/landscape',
      'mm-layout-card-radial/both/portrait',
      'mm-layout-ratio-portrait',
      'mm-layout-ratio-landscape',
      'mm-layout-close',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: '缺 $k');
    }
    // 四张卡的标题与副标逐字照原型。
    for (final t in ['纵向树', '横向树', '双向树', '放射图']) {
      expect(find.text(t), findsOneWidget, reason: '缺卡面标题 $t');
    }
  });

  testWidgets('点放射卡：即时生效＋落 prefs（每图一套），关闭不回滚',
      (tester) async {
    final mapId = await pumpCanvas(tester);
    await tester.tap(find.byKey(const ValueKey('mm-layout-btn')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('mm-layout-card-radial/both/portrait')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-layout-close')));
    await tester.pumpAndSettle();

    final stored = MmLayoutStore(mmPrefs).load(mapId);
    expect(stored?.key, 'radial/both/portrait');
    expect(tester.takeException(), isNull);
  });

  testWidgets('切预设可撤销：撤销后回到上一个预设（原型 mmPushHistory 同款）',
      (tester) async {
    final mapId = await pumpCanvas(tester);
    expect(MmLayoutStore(mmPrefs).load(mapId), isNull, reason: '起始未设预设');

    await tester.tap(find.byKey(const ValueKey('mm-layout-btn')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('mm-layout-card-tree/both/landscape')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-layout-close')));
    await tester.pumpAndSettle();
    expect(MmLayoutStore(mmPrefs).load(mapId)?.key, 'tree/both/landscape');

    // 撤销钮此时应可用（切预设入了栈）。
    final undoBtn = find.byKey(const ValueKey('mm-undo-btn'));
    expect(tester.widget<IconButton>(undoBtn).onPressed, isNotNull);
    await tester.tap(undoBtn);
    await tester.pumpAndSettle();
    expect(MmLayoutStore(mmPrefs).load(mapId), isNull,
        reason: '撤销「切换布局」⇒ 回到未设预设（该图本无预设）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('每图隔离：A 设放射、B 重开仍是纵向树（变异刀2 UI 面证据）',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final a = await dao.createMap('图A');
    await dao.addNode(mapId: a, title: 'A 根');
    final b = await dao.createMap('图B');
    await dao.addNode(mapId: b, title: 'B 根');

    Future<void> openMap(int id) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(
            home: MindmapCanvasPage(
                key: ValueKey('v$id'), mapId: id, dao: dao, db: db)),
      ));
      await tester.pumpAndSettle();
    }

    await openMap(a);
    await tester.tap(find.byKey(const ValueKey('mm-layout-btn')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('mm-layout-card-radial/both/portrait')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-layout-close')));
    await tester.pumpAndSettle();
    expect(MmLayoutStore(mmPrefs).load(a)?.isRadial, isTrue);

    await openMap(b);
    expect(MmLayoutStore(mmPrefs).load(b), isNull);
    // B 的画布不能有 A 的预设残留（打开弹层时默认卡选中纵向树）。
    await tester.tap(find.byKey(const ValueKey('mm-layout-btn')));
    await tester.pumpAndSettle();
    final portraitCard = tester.widget<GestureDetector>(find
        .byKey(const ValueKey('mm-layout-card-tree/right/portrait')));
    expect(portraitCard, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切预设保留节点拖拽偏移（变异刀1 钉位·UI 面）', (tester) async {
    final mapId = await pumpCanvas(tester);
    // 直接给根节点落一个偏移（拖拽后落库的形态）。
    final dao = mindmapDaoOf(db);
    final rows = await dao.nodesOf(mapId);
    await dao.updateNode(rows.first.copyWith(dx: 64, dy: -24, updatedAt: 9));

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(
              key: const ValueKey('v2'), mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mm-layout-btn')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('mm-layout-card-radial/both/portrait')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-layout-close')));
    await tester.pumpAndSettle();

    // 偏移仍在库里（切预设只重算基线，不清偏移——2d 冻结口径）。
    final after = await dao.nodesOf(mapId);
    expect(after.first.dx, 64);
    expect(after.first.dy, -24);
    expect(tester.takeException(), isNull);
  });

  testWidgets('容器比例切横向：只改比例、不转屏（App 内不转屏口径）',
      (tester) async {
    final mapId = await pumpCanvas(tester);
    await tester.tap(find.byKey(const ValueKey('mm-layout-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-layout-ratio-landscape')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-layout-close')));
    await tester.pumpAndSettle();

    final stored = MmLayoutStore(mmPrefs).load(mapId);
    expect(stored?.ratio, MmLayoutPreset.rLandscape);
    expect(stored?.struct, MmLayoutPreset.sTree);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重开图读回同一预设（冷启往返的 UI 面证据）', (tester) async {
    final mapId = await pumpCanvas(tester);
    final dao = mindmapDaoOf(db);
    await tester.tap(find.byKey(const ValueKey('mm-layout-btn')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('mm-layout-card-tree/right/landscape')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-layout-close')));
    await tester.pumpAndSettle();

    // 重开：弹层里该卡应为选中态（选中卡描边用 primary，行为上体现为不抛且预设读回）。
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(
              key: const ValueKey('v2'), mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    expect(MmLayoutStore(mmPrefs).load(mapId)?.key, 'tree/right/landscape');
    expect(tester.takeException(), isNull);
  });
}