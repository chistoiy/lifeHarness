import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批P5 · 选中态贴点气泡守护（§5 第 7 条 · 产品拍板口径）。
///
/// 口径三条：
/// 1. 底部常驻工具条**整条不在**（不是隐藏、不是透明）；
/// 2. 选中后气泡贴在节点**上沿外侧**（可量几何的关系就不写「有就好」）；
/// 3. 贴顶节点不许压住自己的子级——上方放不下走「右→左→下」三级让位。
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

  /// 泵一张图。`surface` 可压出「贴顶」场景（小视口 ⇒ fit 后节点顶到画布上沿）。
  ///
  /// 注意：只压小视口**不够**——fit 会把整图居中，根节点上下都有留白。贴顶靠
  /// 下面这条「短图 ＋ 往上甩」的路径造（见用例内注释）。
  Future<(MindmapDao, int)> pumpMap(WidgetTester tester,
      {required Future<void> Function(MindmapDao, int) seed,
      Size? surface}) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await seed(dao, mapId);
    if (surface != null) {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(
          home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return (dao, mapId);
  }

  /// 按标题取节点屏幕中心（读屏语义层带真实几何，与画布命中同源）。
  Offset centerOf(WidgetTester tester, String title) {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '') == title);
    expect(f, findsOneWidget, reason: '找不到「$title」的语义块');
    return tester.getCenter(f);
  }

  testWidgets('未选中时气泡不在场，选中后两枚都出现（§5 第 7 条）',
      (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '中心');
    });
    // 负档：刚进场什么都不选 ⇒ 两枚都不该有。
    expect(find.byKey(const ValueKey('mm-bubble-child')), findsNothing);
    expect(find.byKey(const ValueKey('mm-bubble-more')), findsNothing);

    await tapAt(tester, centerOf(tester, '中心'));
    await tester.pump();

    // 正档：同一条用例里断出现（否则「压根没渲染」也会让负档假绿）。
    expect(find.byKey(const ValueKey('mm-bubble-child')), findsOneWidget);
    expect(find.byKey(const ValueKey('mm-bubble-more')), findsOneWidget);
    expect(find.text('加子节点'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    // 触点必须真接上了（key 钉在 Material 上会「找到但点不动」）。
    for (final k in ['mm-bubble-child', 'mm-bubble-more']) {
      final ink = tester.widget<InkWell>(find.byKey(ValueKey(k)));
      expect(ink.onTap, isNotNull, reason: '$k 没接 onTap');
    }
  });

  testWidgets('底部常驻工具条整条不在（不是隐藏）：它的三个 key 全无',
      (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '中心');
    });
    await tapAt(tester, centerOf(tester, '中心'));
    await tester.pump();
    // 选中态是「最想显示工具条」的状态：此刻都没有，别处更不会有。
    expect(find.byKey(const ValueKey('mm-tool-more')), findsNothing);
    expect(find.byKey(const ValueKey('mm-tool-addchild')), findsNothing);
    expect(find.byKey(const ValueKey('mm-tool-bind')), findsNothing);
    // 「挂笔记」唯一入口现在是贴点菜单，底部不许再有同名常驻位。
    expect(find.byKey(const ValueKey('mm-menu-bind')), findsNothing);
  });

  testWidgets('气泡贴节点上沿外侧，且整块水平对齐节点中心（§5 第 7 条）',
      (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '中心');
    });
    await tapAt(tester, centerOf(tester, '中心'));
    await tester.pump();

    final node = tester.getRect(find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '') == '中心'));
    final child = tester.getRect(find.byKey(const ValueKey('mm-bubble-child')));
    final more = tester.getRect(find.byKey(const ValueKey('mm-bubble-more')));
    final row = Rect.fromLTRB(
        child.left, child.top, more.right, more.bottom);

    expect(row.bottom, lessThanOrEqualTo(node.top),
        reason: '气泡整块在节点上沿之外，不压节点字');
    expect(node.top - row.bottom, lessThanOrEqualTo(16),
        reason: '净距过大＝没贴着节点，手指回头还得找');
    expect((row.center.dx - node.center.dx).abs(), lessThanOrEqualTo(2),
        reason: '水平居中对齐节点中心');
  });

  testWidgets('贴顶节点：气泡让到右侧，不压住自己的第一个子级（三级让位）',
      (tester) async {
    // 造一个贴顶的根：一条较长的链把整图撑高（但不能撑太长——链越长 fit 缩得
    // 越小，节点行高与子级净空一起缩到 36dp 以下，气泡怎么收都塞不进，会一路
    // 掉进第三档）。6 级刚好让 fit 缩到 ~0.6，行高 ~24、子级净空 ~70dp。
    await pumpMap(tester, seed: (d, m) async {
      // 根给一段**长备注**逼成多行（行高 > 纵向间距 54dp）——只有多行节点
      // 才会出现「正居中下沿越过子级上沿」：单行 40dp 时居中下沿恒比子级
      // 顶低 16dp，天花板压根用不上（最早那版用例因此假绿）。
      // 用备注而不是长标题：标题一长就被截断/换行，语义标签对不上取不到矩形。
      final root = await d.addNode(mapId: m, parentId: null, title: '根',
          note: '这里放一段足够长的备注文字，把节点撑到两行以上，'
              '好让气泡正居中时会越过下面第一个子级的上沿。');
      await d.addNode(mapId: m, parentId: root.id, title: '子1');
      var p = root.id;
      for (var i = 0; i < 4; i++) {
        final n = await d.addNode(mapId: m, parentId: p, title: '深$i');
        p = n.id;
      }
    });
    final canvas = tester.getRect(find.byKey(const ValueKey('mm-canvas-paint')));
    // 从画布右下空白处往上拽（起点避开节点，否则会变成拖节点）：整图上移、根
    // 被顶到画布上沿，上方放不下 36dp 气泡。
    await tester.dragFrom(
        Offset(canvas.right - 30, canvas.bottom - 40),
        const Offset(0, -110));
    await tester.pumpAndSettle();

    MmBubbleProbe.reset();
    await tapAt(tester, centerOf(tester, '根'));
    await tester.pump();

    // **档位与净空都从委托读**，不从屏幕坐标反推：坐标被视口留白与四边夹取
    // 抹过，反推出来的「贴顶 / 没贴顶」两边可能恒等（本用例首版就这样假绿过）。
    expect(MmBubbleProbe.tier, isNot('top'),
        reason: '读到 top 说明上面压根放得下，用例没逼到让位分支');
    final room = MmBubbleProbe.ceiling;
    expect(room, isNotNull, reason: '根本没取到子级上沿，天花板形同虚设');
    expect(MmBubbleProbe.tier, 'right',
        reason: '上方放不下、右侧放得下 ⇒ 第二档');

    final child = tester.getRect(find.byKey(const ValueKey('mm-bubble-child')));
    final more = tester.getRect(find.byKey(const ValueKey('mm-bubble-more')));
    final row = Rect.fromLTRB(child.left, child.top, more.right, more.bottom);
    final firstChild = tester.getRect(find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '') == '子1'));
    // 这条用例守的是**行为**：让位到侧面后不许把子级压掉。
    // 注意「天花板」在纵向树里其实用不上——行高 40 + 间距 14 = 54，气泡高 36、
    // 正居中下沿在上沿 +38，天生比子级顶低 16dp，除非节点被撑成两行以上。
    // 天花板规则本身由 `mindmap_bubble_ceiling_test.dart` 直接喂多行节点断，
    // 不靠这条 widget 用例的几何偶然成立。
    expect(row.overlaps(firstChild), isFalse,
        reason: '侧面让位后不许压住自己的第一个子级');
    expect(canvas.contains(row.topLeft) && canvas.contains(row.bottomRight),
        isTrue,
        reason: '让位后仍须整块夹在画布内');
  });

  testWidgets('点「加子节点」进弹层（不是只留个气痕）', (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '中心');
    });
    await tapAt(tester, centerOf(tester, '中心'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-bubble-child')));
    await tester.pumpAndSettle();
    // 断「进流程」要看弹层自身的文案——只断气泡还在的话不点也过。
    expect(find.byKey(const ValueKey('mm-node-sheet')), findsOneWidget);
    expect(find.text('添加子节点'), findsOneWidget);
    expect(find.byKey(const ValueKey('mm-node-save')), findsOneWidget);
    // 连录提示在场＝走的是「加点子节点」这条路，不是别的弹层。
    expect(find.byKey(const ValueKey('mm-node-quick-hint')), findsOneWidget);
  });

  testWidgets('点「更多」开出贴点菜单（菜单项可见可点）', (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '中心');
    });
    await tapAt(tester, centerOf(tester, '中心'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
    await tester.pumpAndSettle();
    // 气泡自身也在「更多」外面：全局点外关闭必须豁免气泡（原型踩过这一刀）。
    expect(find.byKey(const ValueKey('mm-menu-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('mm-menu-del')), findsOneWidget);
    expect(find.byKey(const ValueKey('mm-bubble-more')), findsOneWidget,
        reason: '点「更多」不该把气泡本身关掉');
  });

  testWidgets('连接态不给操作气泡（此时点节点是「选目标」不是「改这一枝」）',
      (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      // 根给一段**长备注**逼成多行（行高 > 纵向间距 54dp）——只有多行节点
      // 才会出现「正居中下沿越过子级上沿」：单行 40dp 时居中下沿恒比子级
      // 顶低 16dp，天花板压根用不上（最早那版用例因此假绿）。
      // 用备注而不是长标题：标题一长就被截断/换行，语义标签对不上取不到矩形。
      final root = await d.addNode(mapId: m, parentId: null, title: '根',
          note: '这里放一段足够长的备注文字，把节点撑到两行以上，'
              '好让气泡正居中时会越过下面第一个子级的上沿。');
      await d.addNode(mapId: m, parentId: root.id, title: '甲');
    });
    await tapAt(tester, centerOf(tester, '根'));
    await tester.pump();
    expect(find.byKey(const ValueKey('mm-bubble-child')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
    await tester.pumpAndSettle();
    final connect = find.byKey(const ValueKey('mm-menu-connect'));
    await tester.ensureVisible(connect);
    await tester.pumpAndSettle();
    await tester.tap(connect);
    // **不能用 pumpAndSettle**：连接态呼吸是 `repeat(reverse: true)` 无限动画，
    // settle 必然超时（见批P 实证）。固定帧推过去即可。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byKey(const ValueKey('mm-connect-bar')), findsOneWidget,
        reason: '没进连接态，这条用例就没意义');
    expect(find.byKey(const ValueKey('mm-bubble-child')), findsNothing);
    expect(find.byKey(const ValueKey('mm-bubble-more')), findsNothing);
  });
}
