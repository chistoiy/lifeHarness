import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批P · 连接态交互守护（工单 §7 P1 交互面 + §5 第 1 条抬升）。
/// 全 app widget 独立文件口径：本文件只泵画布页。
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

  Future<(MindmapDao, int)> pumpMap(WidgetTester tester,
      {required Future<void> Function(MindmapDao, int) seed,
      EdgeInsets viewPadding = EdgeInsets.zero}) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await seed(dao, mapId);
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(padding: viewPadding),
      child: ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(
            home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
      ),
    ));
    await tester.pumpAndSettle();
    return (dao, mapId);
  }

  /// 按标题取节点的屏幕坐标（读屏语义层带真实几何，与画布命中同源）。
  /// **精确匹配**：用 startsWith 时「甲」会同时命中「甲子」（前缀歧义）。
  Offset centerOf(WidgetTester tester, String title) {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '') == title);
    expect(f, findsOneWidget, reason: '找不到「$title」的语义块');
    return tester.getCenter(f);
  }

  /// 让 toast 让路。
  ///
  /// SnackBar 浮动在底部、工具条也在底部：上一步留下的 toast 会正好把按钮盖住
  /// （实测 tap 落在 SnackBar 的 Material 上）。这里的坑是**等它自己走完不可靠**——
  /// 连续两次 `hideCurrentSnackBar + showSnackBar` 后自动退场计时不再触发，
  /// `pumpAndSettle` 也等不掉它。故直接 `removeCurrentSnackBar`，再走固定帧
  /// （不用 pumpAndSettle：连接态呼吸是无限动画，settle 会挂）。
  Future<void> letToastPass(WidgetTester tester) async {
    if (find.byType(SnackBar).evaluate().isEmpty) return;
    final ctx = tester.element(find.byType(Scaffold).first);
    ScaffoldMessenger.of(ctx).removeCurrentSnackBar();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// toast 读数：只 pump 400ms（别 pumpAndSettle，SnackBar 时长 1.6s 会被退到底）。
  Future<void> toastOf(WidgetTester tester, String text) async {
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(text), findsOneWidget);
  }

  /// 动作后的固定帧推进。
  ///
  /// 为什么不用 `pumpAndSettle`：连接态呼吸控制器是 `repeat(reverse: true)`
  /// 的无限动画，期间 pumpAndSettle 永不 settle（不是偶发挂死，是必然）。
  /// 落位/取消成功后会停掉脉冲，届时再 settle 收尾才安全。
  Future<void> settleAfterAct(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  /// 选中 → 更多 → 菜单项。
  ///
  /// 进连接态时呼吸控制器 `repeat(reverse: true)`——**无限动画让
  /// pumpAndSettle 永不 settle**，所以菜单这一步固定改用定长 pump（轮次
  /// 内同理）。这不是给测试开后门：无限动画本来就不该出现在 pumpAndSettle 路径上。
  Future<void> openMenu(WidgetTester tester) async {
    await letToastPass(tester);
    await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
    await tester.pumpAndSettle();
  }

  Future<void> pickMenu(WidgetTester tester, String menuKey) async {
    await openMenu(tester);
    // 节点菜单 12 项＋底部并排一行，在 600 高的测试视口里「收起整枝/展开全部」
    // 会被折到可视区外（弹层本就包了滚动——真机横屏同理，不是缺陷）。
    final target = find.byKey(ValueKey(menuKey));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('菜单进连接态 → 点目标即挂接（一次一步、可撤销）', (tester) async {
    // 甲是根、乙是甲的子级：拿**非根的乙**当起点，文案走「连接到…」。
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: a.id, title: '乙');
      await d.addNode(mapId: m, parentId: null, title: '丙');
    });
    await tapAt(tester, centerOf(tester, '乙'));
    await tester.pump();
    await pickMenu(tester, 'mm-menu-connect');
    // 提示条在场（顶部），提示语提到「挂到它下面」。
    expect(find.byKey(const ValueKey('mm-connect-bar')), findsOneWidget);
    expect(find.textContaining('挂到它下面'), findsOneWidget);
    // 点目标「丙」⇒ 落库。
    await tapAt(tester, centerOf(tester, '丙'));
    await settleAfterAct(tester);
    final b = (await dao.nodesOf(mapId)).firstWhere((n) => n.title == '乙');
    final c = (await dao.nodesOf(mapId)).firstWhere((n) => n.title == '丙');
    expect(b.parentId, c.id, reason: '乙挂到丙下（跨根合并）');
    expect(find.byKey(const ValueKey('mm-connect-bar')), findsNothing,
        reason: '落位即退出连接态');
    await toastOf(tester, '已把「乙」连接到「丙」');
    // 撤销一步回到连接前（乙仍挂在甲下）。
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    final b2 = (await dao.nodesOf(mapId)).firstWhere((n) => n.title == '乙');
    expect(b2.parentId, isNotNull, reason: '撤销回到「挂在甲下」，不是回根');
  });

  testWidgets('连接态点空白＝取消（不落任何库）', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: null, title: '乙');
    });
    await tapAt(tester, centerOf(tester, '甲'));
    await tester.pump();
    await pickMenu(tester, 'mm-menu-connect');
    // 提示条实测占 y=68..134（视口 800×600）：点它下方的空白（200）才算空白，
    // 点 120 会落在提示条上——那是「条自己的区域」，不是画布。
    final bar = tester.getRect(find.byKey(const ValueKey('mm-connect-bar')));
    await tapAt(tester, Offset(24, bar.bottom + 40));
    await settleAfterAct(tester);
    expect(find.byKey(const ValueKey('mm-connect-bar')), findsNothing);
    await toastOf(tester, '已取消连接');
    final nodes = await dao.nodesOf(mapId);
    expect(nodes.where((n) => n.parentId == null), hasLength(2),
        reason: '什么都没动');
  });

  testWidgets('成环目标点了也只给理由，不改树、不踢出连接态', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: null, title: '乙');
    });
    await tapAt(tester, centerOf(tester, '甲'));
    await tester.pump();
    await pickMenu(tester, 'mm-menu-connect');
    await tapAt(tester, centerOf(tester, '乙'));
    await settleAfterAct(tester);
    // 反向：给乙开连接，点甲 ⇒ 成环 ⇒ 拒绝（此时甲是乙的子级）。
    await tapAt(tester, centerOf(tester, '乙'));
    await tester.pump();
    await pickMenu(tester, 'mm-menu-connect');
    await tapAt(tester, centerOf(tester, '甲'));
    await tester.pump();
    await toastOf(tester, '不能挂到自己的子节点下（会成环）');
    final nodes = await dao.nodesOf(mapId);
    final a = nodes.firstWhere((n) => n.title == '甲');
    final b = nodes.firstWhere((n) => n.title == '乙');
    expect(a.parentId, b.id, reason: '树没被这次打扰');
    expect(b.parentId, isNull);
    expect(find.byKey(const ValueKey('mm-connect-bar')), findsOneWidget,
        reason: '给了理由不踢出，用户可换目标');
  });

  testWidgets('根节点进连接态＝「并入」语义，落位用并入文案', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '中心');
      await d.addNode(mapId: m, parentId: null, title: '旁支');
    });
    await tapAt(tester, centerOf(tester, '中心'));
    await tester.pump();
    await openMenu(tester);
    expect(find.text('并入到…'), findsOneWidget,
        reason: '根没有父可挂，动作语义＝成为别人的子级');
    await tester.ensureVisible(find.byKey(const ValueKey('mm-menu-connect')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-connect')));
    await settleAfterAct(tester);    expect(find.textContaining('整枝并入它下面'), findsOneWidget);
    await tapAt(tester, centerOf(tester, '旁支'));
    await settleAfterAct(tester);
    final c = (await dao.nodesOf(mapId)).firstWhere((n) => n.title == '中心');
    expect(c.parentId, isNotNull);
    await toastOf(tester, '已把「中心」整枝并入「旁支」');
  });

  testWidgets('断开并移到根层级：只在有父时可用', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: a.id, title: '乙');
    });
    await tapAt(tester, centerOf(tester, '乙'));
    await tester.pump();
    await openMenu(tester);
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('mm-menu-detach')))
            .enabled,
        isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('mm-menu-detach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-detach')));
    await tester.pumpAndSettle();
    final b = (await dao.nodesOf(mapId)).firstWhere((n) => n.title == '乙');
    expect(b.parentId, isNull);
    await toastOf(tester, '已断开「乙」· 现为根层级');
    // 已经是根 ⇒ 菜单项置灰（没有父可断）。toast 会盖住工具条 ⇒ 先等它走。
    await letToastPass(tester);
    await openMenu(tester);
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('mm-menu-detach')))
            .enabled,
        isFalse);
  });

  testWidgets('收起整枝/展开全部是纯视图态，不入命令栈', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '甲');
      await d.addNode(mapId: m, parentId: a.id, title: '甲子');
      final c = await d.addNode(mapId: m, parentId: null, title: '丙');
      await d.addNode(mapId: m, parentId: c.id, title: '丙子');
    });
    await tapAt(tester, centerOf(tester, '甲'));
    await tester.pump();
    await pickMenu(tester, 'mm-menu-collapse');
    var nodes = await dao.nodesOf(mapId);
    expect(nodes.firstWhere((n) => n.title == '甲子').folded, isFalse);
    expect(nodes.firstWhere((n) => n.title == '丙').folded, isTrue,
        reason: '同层旁支折掉（它有子级）');
    expect(nodes.firstWhere((n) => n.title == '丙子').folded, isFalse,
        reason: '叶子没有可折的枝——折它等于折父级（父已折，子自然不可见）');
    expect(nodes.firstWhere((n) => n.title == '甲').folded, isFalse,
        reason: '祖先链必须留展开（根一折＝整屏空）');
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('mm-undo-btn')))
            .onPressed,
        isNull,
        reason: '折叠不进命令栈（F4-1：只有增删改移折叠各一步，视图态不算）');
    // 展开全部。
    await pickMenu(tester, 'mm-menu-expand');
    nodes = await dao.nodesOf(mapId);
    expect(nodes.every((n) => !n.folded), isTrue);
  });

  testWidgets('提示条让位：进场后最顶节点不被压住（§5 第 1 条）', (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '中心');
    });
    await tapAt(tester, centerOf(tester, '中心'));
    await tester.pump();
    await pickMenu(tester, 'mm-menu-connect');
    final bar = tester.getRect(find.byKey(const ValueKey('mm-connect-bar')));
    final after = centerOf(tester, '中心');
    expect(after.dy, greaterThanOrEqualTo(bar.bottom),
        reason: '节点被下移让开提示条，否则合法目标被遮');
  });

  testWidgets('贴点气泡落在画布内（§5 第 1 条新口径：底部不再有常驻条，'
      '安全区自然不相干）', (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '中心');
    });
    await tapAt(tester, centerOf(tester, '中心'));
    await tester.pump();
    final child = tester.getRect(find.byKey(const ValueKey('mm-bubble-child')));
    final more = tester.getRect(find.byKey(const ValueKey('mm-bubble-more')));
    final canvas = tester.getRect(find.byKey(const ValueKey('mm-canvas-paint')));
    expect(canvas.contains(child.topLeft) && canvas.contains(more.bottomRight),
        isTrue, reason: '气泡四边都夹在画布内，不会被系统手势条压到');
    expect(child.right, lessThanOrEqualTo(more.left),
        reason: '主操作在左、次操作在右（原型同序）');
    expect(more.height, greaterThanOrEqualTo(30), reason: '命中区没被裁');
    // 旧口径「底部条退出手势热区」随底部条一并作废：这里断言它真的不在了。
    expect(find.byKey(const ValueKey('mm-tool-more')), findsNothing);
  });
}
