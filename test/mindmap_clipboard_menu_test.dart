import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_clipboard.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';

import 'mindmap_test_harness.dart';

/// 批P3 · 节点菜单余项（工单 §5 第 5/10 条）：贴点浮层、同级换序、剪贴板三枚入口。
///
/// 本文件只泵画布页（全 app widget 测试一文件一页口径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openMmDb();
    MmClipboard.clear(); // 剪贴板是会话级静态态，用例之间必须隔离
  });
  tearDown(() async {
    await (db as CloseableDb).close();
    MmClipboard.clear();
  });

  Future<MindmapDao> pumpCanvas(WidgetTester tester, int mapId) async {
    final dao = mindmapDaoOf(db);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return dao;
  }

  /// 点节点本体（用读屏语义层定位：它和节点盒同位置同尺寸，命中会穿透到画布）。
  Future<void> tapNode(WidgetTester tester, String title) async {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == title);
    expect(f, findsOneWidget, reason: '画布语义层应能找到节点「$title」');
    await tapAt(tester, tester.getCenter(f));
  }

  /// 让 toast 让路：SnackBar 浮动在底部、工具条也在底部，上一步留下的
  /// toast 会正好盖住「更多」按钮（tap 落在 SnackBar 的 Material 上）。
  /// 连续 show 后自动退场计时会失效，`pump(3s)` 也等不掉 ⇒ 直接摘掉。
  Future<void> letToastPass(WidgetTester tester) async {
    if (find.byType(SnackBar).evaluate().isEmpty) return;
    final ctx = tester.element(find.byType(Scaffold).first);
    ScaffoldMessenger.of(ctx).removeCurrentSnackBar();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> openMenu(WidgetTester tester) async {
    await letToastPass(tester);
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
  }

  /// 菜单项可能落在浮层折叠线外（视口 600 高装不下 17 项）⇒ 先滚到它。
  Future<void> pickMenuItem(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey('mm-menu-$key'));
    expect(f, findsOneWidget, reason: '菜单里应有「$key」');
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('节点菜单是贴点浮层：宽度按 236 收口，不再是全宽底部弹层', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '中心主题');
    await pumpCanvas(tester, mapId);

    await tapNode(tester, '中心主题');
    await openMenu(tester);

    final panel = find.byKey(const ValueKey('mm-node-menu'));
    expect(panel, findsOneWidget, reason: '浮层容器');
    final size = tester.getSize(panel);
    expect(size.width, 236, reason: '贴点浮层按内容收口，不铺满屏宽');
    // 浮层必须完整落在屏内（不越过上下沿）。
    final rect = tester.getRect(panel);
    expect(rect.top, greaterThanOrEqualTo(10));
    expect(rect.bottom, lessThanOrEqualTo(600 - 10 + .01));
    // 收场：点外部关掉浮层（留着会让下一个用例的 pumpWidget 踩到悬空路由）。
    await tester.tapAt(const Offset(10, 590));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  testWidgets('复制（含子级）→ 粘贴子级：新枝挂进选中节点，原枝不动', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '中心主题');
    await dao.addNode(mapId: mapId, parentId: root.id, title: '子一');
    await pumpCanvas(tester, mapId);

    await tapNode(tester, '中心主题');
    await openMenu(tester);
    await pickMenuItem(tester, 'copy');
    expect(MmClipboard.hasContent, isTrue, reason: '复制后剪贴板有内容');
    expect(MmClipboard.descendantCount, 1, reason: '含子级：根之外还带 1 个子节点');
    expect(MmClipboard.isCut, isFalse);

    await tapNode(tester, '中心主题');
    await openMenu(tester);
    await pickMenuItem(tester, 'pasteChild');

    final rows = await dao.nodesOf(mapId);
    expect(rows.length, 4, reason: '原 2 行 + 粘贴 2 行');
    // 新枝的根挂在「中心主题」下，且是新 id。
    final pasted = rows.where((n) => n.title == '中心主题' && n.id != root.id).toList();
    expect(pasted.length, 1);
    expect(pasted.first.parentId, root.id, reason: '粘贴子级＝挂进选中节点');
    expect(rows.where((n) => n.title == '子一').length, 2, reason: '子级跟着搬过来');
    expect(MmClipboard.hasContent, isTrue, reason: '复制语义读而不清，可继续粘');
  });

  testWidgets('粘贴同级：落到选中节点的父下（选中是根＝贴成新根）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '中心主题');
    await pumpCanvas(tester, mapId);

    await tapNode(tester, '中心主题');
    await openMenu(tester);
    await pickMenuItem(tester, 'copy');

    await tapNode(tester, '中心主题');
    await openMenu(tester);
    await pickMenuItem(tester, 'pasteSib');

    final rows = await dao.nodesOf(mapId);
    expect(rows.length, 2);
    final pasted = rows.firstWhere((n) => n.id != root.id);
    expect(pasted.parentId, isNull, reason: '根节点的同级＝新根，不是子级');
    expect(pasted.title, '中心主题');
  });

  testWidgets('剪切：原枝退场、剪贴板转剪切语义，粘回后位置复原', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '中心主题');
    final branch = await dao.addNode(mapId: mapId, title: '要剪的');
    await dao.addNode(mapId: mapId, parentId: branch.id, title: '枝内子级');
    await pumpCanvas(tester, mapId);

    await tapNode(tester, '要剪的');
    await openMenu(tester);
    await pickMenuItem(tester, 'cut');

    expect(MmClipboard.isCut, isTrue, reason: '剪切语义');
    expect(MmClipboard.descendantCount, 1);
    expect((await dao.nodesOf(mapId)).length, 1, reason: '整枝（含子级）已退场');
    expect((await dao.nodesOf(mapId)).first.id, root.id, reason: '别的枝不受连坐');

    // 粘回：选中中心主题 → 粘贴同级 ⇒ 新根（原枝是根级节点）。
    await tapNode(tester, '中心主题');
    await openMenu(tester);
    await pickMenuItem(tester, 'pasteSib');

    final back = await dao.nodesOf(mapId);
    expect(back.length, 3, reason: '粘回整枝两行');
    expect(MmClipboard.hasContent, isFalse, reason: '剪切取走即清');
  });

  testWidgets('上移/下移：只动同级先后，一步撤销整组复原', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '甲');
    await dao.addNode(mapId: mapId, title: '乙');
    await dao.addNode(mapId: mapId, title: '丙');
    await pumpCanvas(tester, mapId);

    Future<List<String>> order() async =>
        (await dao.nodesOf(mapId)).map((n) => n.title).toList();

    expect(await order(), ['甲', '乙', '丙']);

    await tapNode(tester, '乙');
    await openMenu(tester);
    await pickMenuItem(tester, 'up');
    expect(await order(), ['乙', '甲', '丙'], reason: '上移＝与前一兄弟换位');

    // 撤销一次即整组复原（不是退半组）。
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    expect(await order(), ['甲', '乙', '丙'], reason: '一步撤销复原整组顺序');

    // 重做回到换序后，再验下移。
    await tapNode(tester, '乙');
    await openMenu(tester);
    await pickMenuItem(tester, 'down');
    expect(await order(), ['甲', '丙', '乙'], reason: '下移＝与后一兄弟换位');
  });

  testWidgets('第一个不能再上移（同级首项置灰）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '甲');
    await dao.addNode(mapId: mapId, title: '乙');
    await pumpCanvas(tester, mapId);

    await tapNode(tester, '甲');
    await openMenu(tester);
    final up = find.byKey(const ValueKey('mm-menu-up'));
    expect(up, findsOneWidget);
    // 上移/下移在原型里是并排一行（`.nm-row`）⇒ 实现是 OutlinedButton。
    expect(tester.widget<OutlinedButton>(up).onPressed, isNull, reason: '首个不可上移');
  });

  testWidgets('最后一个不能再下移（同级末项置灰）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '甲');
    await dao.addNode(mapId: mapId, title: '乙');
    await pumpCanvas(tester, mapId);

    // 一个用例一个场景：同一页面里「关菜单再选另一枚」会让断言落在
    // 上一次的选中态上（关层与选中是两条独立状态），拆开才断得准。
    await tapNode(tester, '乙');
    await openMenu(tester);
    final down = find.byKey(const ValueKey('mm-menu-down'));
    expect(down, findsOneWidget);
    expect(tester.widget<OutlinedButton>(down).onPressed, isNull,
        reason: '末个不可下移');
  });
}
