import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/domain/mindmap_layout.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_style.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_painter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批3 · 样式层**交互面 + painter 重画**守护（工单 §4d.4 ⑥⑦ 的一半
/// ＋变异刀3 钉位）。与 `mindmap_style_test.dart` 分文件＝一文件一波。
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

  Future<int> pumpCanvas(WidgetTester tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '中心主题');
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return mapId;
  }

  MindmapNode nodeOf(int id, {int? parent}) => MindmapNode(
        id: id,
        mapId: 1,
        parentId: parent,
        title: '节点$id',
        createdAt: 1,
        updatedAt: 1,
      );

  // 共享 fixture：**必须同一批实例**——painter 的 shouldRepaint 用
  // `identical(nodes/titles/dxs/dys)` 比，工厂每次新建会让「样式未变」也判重画，
  // 用例就成了假红（knife3 的对照基线也必须是同一批实例）。
  final fixtureNodes = [nodeOf(1), nodeOf(2, parent: 1)];
  final fixtureLayout = TreeLayoutEngine().layout(fixtureNodes);

  MmCanvasPainter painterOf(MmPaintStyle style, {int? selectedId}) {
    return MmCanvasPainter(
      nodes: fixtureNodes,
      layout: fixtureLayout,
      scale: 1,
      pan: Offset.zero,
      selectedId: selectedId,
      nodeTitles: {1: '一', 2: '二'},
      mountedIds: const {},
      dxs: const {},
      dys: const {},
      style: style,
    );
  }

  testWidgets('样式弹层：六段齐全＋改档即时写 prefs 并可恢复默认', (tester) async {
    final mapId = await pumpCanvas(tester);
    // 入口在右下缩放条旁（原型 mmZoomBar 同款：样式是画布高频项）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mm-style-sheet')), findsOneWidget);
    for (final k in [
      'mm-style-text-accent',
      'mm-style-size-md',
      'mm-style-bg-soft',
      'mm-style-line-accent',
      'mm-style-linew-dec',
      'mm-style-linew-inc',
      'mm-style-canvas-dots',
      'mm-style-reset',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: '缺 $k');
    }

    // 改两档（文字色 → 主题；线粗 +）→ 关弹层 → prefs 已落。
    await tester.tap(find.byKey(const ValueKey('mm-style-text-accent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-style-linew-inc')));
    await tester.pumpAndSettle();
    expect(find.text('2.0 px'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mm-style-close')));
    await tester.pumpAndSettle();

    final stored = MmStyleStore(mmPrefs).load(mapId);
    expect(stored?.text, MmStyle.kTextAccent);
    expect(stored?.lineW, 2.0);

    // 重开：读回刚才那档（冷启往返的 UI 面证据）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-style-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-style-close')));
    await tester.pumpAndSettle();
    expect(MmStyleStore(mmPrefs).load(mapId), MmStyle.defaults);
  });

  testWidgets('改样式可撤销：撤销后档位退回（原型 mmPushHistory 同款语义）',
      (tester) async {
    final mapId = await pumpCanvas(tester);
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-style-text-warn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-style-close')));
    await tester.pumpAndSettle();
    expect(MmStyleStore(mmPrefs).load(mapId)?.text, MmStyle.kTextWarn);

    // 撤销钮此时应可用（改样式入了栈）。
    final undoBtn = find.byKey(const ValueKey('mm-undo-btn'));
    expect(tester.widget<IconButton>(undoBtn).onPressed, isNotNull);
    await tester.tap(undoBtn);
    await tester.pumpAndSettle();
    expect(MmStyleStore(mmPrefs).load(mapId), isNull,
        reason: '撤销「调整样式」⇒ 回到未设样式（该图本无档）');
  });

  test('⑥ 改样式画布重画（变异刀3 钉位）：shouldRepaint 比样式', () {
    final cs = ThemeData.light().colorScheme;
    final before = painterOf(MmPaintStyle.of(null, cs));
    final sameStyleNewInstance = painterOf(MmPaintStyle.of(null, cs));
    expect(before.shouldRepaint(sameStyleNewInstance), isFalse,
        reason: '样式未变不重画');

    final changed = painterOf(MmPaintStyle.of(
        MmStyle.defaults.copyWith(text: MmStyle.kTextWarn), cs));
    expect(before.shouldRepaint(changed), isTrue,
        reason: '换档必须重画（漏比＝改样式画布不刷新）');

    final widthChanged = painterOf(MmPaintStyle.of(
        MmStyle.defaults.copyWith(lineW: 3.2), cs));
    expect(before.shouldRepaint(widthChanged), isTrue,
        reason: '线粗变也要重画');
  });

  testWidgets('字号档改后节点盒宽随之重算（度量与 painter 同源，不溢出）',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '很长很长的一个节点标题用于验证盒宽重算');
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 切 lg 档后画布不得抛（度量缓存键含字号⇒盒宽已重算）。
    await MmStyleStore(mmPrefs).save(mapId,
        MmStyle.defaults.copyWith(size: MmStyle.kSizeLg));
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(key: const ValueKey('v2'), mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(MmStyleStore(mmPrefs).load(mapId)?.size, MmStyle.kSizeLg);
  });
}