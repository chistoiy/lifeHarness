import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批P2 · **同级速录 ＋ 弹层回车提交**守护（§5 第 2、3 条）。
///
/// 口径：回车＝存一个、清空、接着录（弹层不关），点「保存」＝只存这一份收手，
/// 「取消」＝收手（已录的保留，不撤）。备注框仍是多行，回车留给换行。
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
      {required Future<void> Function(MindmapDao, int) seed}) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await seed(dao, mapId);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return (dao, mapId);
  }

  Rect rectOf(WidgetTester tester, String title) {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '') == title);
    expect(f, findsOneWidget, reason: '找不到「$title」的语义块');
    return tester.getRect(f);
  }

  Future<void> settleFrames(WidgetTester tester, {int frames = 24}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
  }

  Future<void> pickMenu(WidgetTester tester, String key) async {
    await openMenu(tester);
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// 在标题框里敲字并回车（`testTextInput.receiveAction`＝软键盘 done 键）。
  Future<void> typeAndEnter(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('mm-node-title')), text);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('加同级：回车连录三个 → 弹层不关，结果挂在同一父下', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '父');
      await d.addNode(mapId: m, parentId: a.id, title: '长子');
    });
    await tapAt(tester, rectOf(tester, '长子').center);
    await tester.pump();
    await pickMenu(tester, 'mm-menu-sibling');
    await typeAndEnter(tester, '次子');
    // 已录第一个：弹层还在（这是「速录」的全部意义）。
    expect(find.byKey(const ValueKey('mm-node-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('mm-node-quick-hint')), findsOneWidget);
    // 清空后接着录第二个。
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('mm-node-title')))
            .controller!
            .text,
        isEmpty);
    await typeAndEnter(tester, '三子');
    expect(find.byKey(const ValueKey('mm-node-sheet')), findsOneWidget);
    // 点「取消」收手：已录的两个都留着。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final nodes = await dao.nodesOf(mapId);
    final parent = nodes.firstWhere((n) => n.title == '父');
    final kids = nodes.where((n) => n.parentId == parent.id).map((n) => n.title)
        .toList();
    expect(kids, containsAll(<String>['长子', '次子', '三子']),
        reason: '连录的两个都挂在同一个父下');
  });

  testWidgets('加同级：回车后点保存＝只存这一份并收手', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '父');
      await d.addNode(mapId: m, parentId: a.id, title: '长子');
    });
    await tapAt(tester, rectOf(tester, '长子').center);
    await tester.pump();
    await pickMenu(tester, 'mm-menu-sibling');
    await typeAndEnter(tester, '次子');
    await tester.enterText(
        find.byKey(const ValueKey('mm-node-title')), '待存的第四个');
    await tester.pump();
    // 弹层底部在 600 高的测试视口里被键盘位/滚动挤到折叠线外：先滚进可视区
    // （与长菜单末项同款打法），否则 tap 会落在渲染树外。
    await tester.ensureVisible(find.byKey(const ValueKey('mm-node-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-node-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mm-node-sheet')), findsNothing,
        reason: '点保存＝本份存完就关层');
    final nodes = await dao.nodesOf(mapId);
    expect(nodes.where((n) => n.title == '待存的第四个'), hasLength(1));
  });

  testWidgets('连录到上限（5 个）自动收手，不会无限刷节点', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      final a = await d.addNode(mapId: m, parentId: null, title: '父');
      await d.addNode(mapId: m, parentId: a.id, title: '长子');
    });
    await tapAt(tester, rectOf(tester, '长子').center);
    await tester.pump();
    await pickMenu(tester, 'mm-menu-sibling');
    // 上限＝一轮速录最多 5 份：前 4 份回车后弹层都在（接着录），第 5 份录完
    // 便到此为止。注意第 5 份的「关层」不靠断在途帧——退场动画要下一帧才推进，
    // 而软键盘动作不驱动帧；这里只断**落库结果**（录满 5 个就停），
    // 关层动作已由上一用例（点保存）覆盖。
    for (var i = 1; i < 5; i++) {
      await typeAndEnter(tester, '快录$i');
      expect(find.byKey(const ValueKey('mm-node-sheet')), findsOneWidget,
          reason: '第 $i 个录完还在层内（上限是 5）');
    }
    await typeAndEnter(tester, '快录5');
    // 退场收尾：软键盘动作不驱动帧时，退场动画不会被推进——这里补固定帧把
    // 退场跑完再断「已关层」（真机上视图会因键盘收起刷新，测试视口不会）。
    await settleFrames(tester, frames: 30);
    final nodes = await dao.nodesOf(mapId);
    expect(nodes.where((n) => n.title.toString().startsWith('快录')),
        hasLength(5), reason: '录满 5 个就停（第 5 个已落库）');
    // 每个都各算一步撤销（速录不是「合并成一步」，逐个可退）。
    expect(nodes.where((n) => n.parentId == nodes.firstWhere((x) => x.title == '父').id),
        hasLength(6), reason: '长子＋5 个快录');
  });

  testWidgets('编辑节点：回车即存（不再需要找保存钮）', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '甲');
    });
    await tapAt(tester, rectOf(tester, '甲').center);
    await tester.pump();
    await pickMenu(tester, 'mm-menu-edit');
    expect(find.byKey(const ValueKey('mm-node-quick-hint')), findsNothing,
        reason: '编辑不连录，不给速录提示');
    await tester.enterText(
        find.byKey(const ValueKey('mm-node-title')), '甲改名');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mm-node-sheet')), findsNothing);
    final nodes = await dao.nodesOf(mapId);
    expect(nodes.map((n) => n.title), contains('甲改名'));
  });

  testWidgets('备注框回车＝换行，不提交（多行备注保留）', (tester) async {
    final (dao, mapId) = await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '甲');
    });
    await tapAt(tester, rectOf(tester, '甲').center);
    await tester.pump();
    await pickMenu(tester, 'mm-menu-edit');
    await tester.enterText(find.byKey(const ValueKey('mm-node-note')), '第一行');
    await tester.pump();
    // 备注框是 maxLines>1 且无 onSubmitted：动作进不来，弹层必须还在。
    expect(find.byKey(const ValueKey('mm-node-sheet')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final nodes = await dao.nodesOf(mapId);
    expect(nodes.first.title, '甲', reason: '取消不落任何改动');
  });
}
