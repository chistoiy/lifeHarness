import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_clipboard.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';

import 'mindmap_test_harness.dart';

/// 批P3 · 同级换序 ＋ 剪贴板三枚入口（复制/剪切/粘贴两档）。
///
/// 两段：**纯函数**（树序整理、粘贴重映射）与**画布接线**（菜单点下去真落库）。
/// 纯函数那几条不是凑数——`nodesOfIds` 走 IN 查询、行序由 SQLite 决定，
/// 「根行是不是第一行」直接决定粘贴挂到谁身上，用界面测很难稳定复现乱序。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CloseableDb db;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openMmDb();
    // 剪贴板是会话级静态态：跨用例必须清，否则「上一条用例复制的东西」
    // 会让这一条凭空多出一个可粘贴项。
    MmClipboard.clear();
  });
  tearDown(() async {
    await db.close();
  });

  // ==================== 纯函数 ====================

  group('mmOrderSubtree', () {
    MindmapNode row(int id, int? parent, String title, {int sort = 0}) =>
        MindmapNode(
          id: id,
          mapId: 1,
          parentId: parent,
          title: title,
          sort: sort,
          createdAt: 0,
          updatedAt: 0,
        );

    test('乱序行集 → 根在前、父先子后、同层按 sort', () {
      // 故意把子行排到根前面：这正是 `WHERE id IN (...)` 可能给出的样子。
      // 孙挂在长子下 ⇒ 期望里它紧跟长子（DFS 父先子后），而不是排在两个叔伯之间。
      final rows = [
        row(3, 4, '孙', sort: 0),
        row(2, 1, '次子', sort: 1),
        row(1, null, '根', sort: 0),
        row(4, 1, '长子', sort: 0),
      ];
      final out = mmOrderSubtree(rows, 1);
      expect(out.map((n) => n.title).toList(), ['根', '长子', '孙', '次子']);
      expect(out.first.id, 1, reason: '首行必须是根（pasteRemap 靠它认 root）');
    });

    test('孤儿行（父不在集内）不丢：追加在末尾', () {
      final rows = [row(2, 9, '孤儿'), row(1, null, '根')];
      final out = mmOrderSubtree(rows, 1);
      expect(out.length, 2);
      expect(out.first.id, 1);
      expect(out.last.id, 2, reason: '父不在行集里＝数据异常，宁可多带一行也不吞');
    });
  });

  group('pasteRemap', () {
    // `isTask` 必须一起给：模型的 copyWith 有一条不变量「非任务不得带完成态」，
    // 只给 taskDone 会被强制掰回 false（那不是 bug，是 `if(!n.task) taskDone=false`）。
    MindmapNode row(int id, int? parent,
            {int sort = 0, bool done = false, bool folded = false}) =>
        MindmapNode(
          id: id,
          mapId: 1,
          parentId: parent,
          title: 'n$id',
          sort: sort,
          folded: folded,
          isTask: done,
          taskDone: done,
          createdAt: 0,
          updatedAt: 0,
        );

    test('换新 id、父子按映射重挂、拖拽偏移清零、勾选/折叠态跟走', () async {
      final rows = [row(1, null, done: true), row(2, 1, folded: true)];
      var seq = 100;
      final (root, out) = await pasteRemap(
        rows: rows,
        targetMapId: 7,
        newRootParent: 55,
        nextId: () => ++seq,
        now: 1234,
      );
      expect(out.length, 2);
      expect(root.id, 101);
      expect(out.map((n) => n.mapId).toSet(), {7});
      expect(out.first.parentId, 55, reason: '根挂到粘贴落点');
      expect(out.last.parentId, 101, reason: '子跟着新根走，不是老 id');
      expect(out.first.taskDone, isTrue, reason: '粘贴一份已勾选的清单，勾选态不能丢');
      expect(out.last.folded, isTrue);
      expect(out.every((n) => n.dx == 0 && n.dy == 0), isTrue);
      expect(out.first.createdAt, 1234);
    });
  });

  // ==================== 画布接线 ====================

  /// 按标题取节点屏幕中心（读屏语义层带真实几何，与画布命中同源）。
  Offset centerOf(WidgetTester tester, String title) {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '') == title);
    expect(f, findsOneWidget, reason: '找不到「$title」的语义块');
    return tester.getCenter(f);
  }

  /// 让 toast 让路（连续 show 后自动退场计时会失效，故直接摘掉）。
  Future<void> letToastPass(WidgetTester tester) async {
    if (find.byType(SnackBar).evaluate().isEmpty) return;
    final ctx = tester.element(find.byType(Scaffold).first);
    ScaffoldMessenger.of(ctx).removeCurrentSnackBar();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// 选中节点 → 打开节点菜单 → 点某一项。
  ///
  /// 不用 `pumpAndSettle` 收尾：菜单是浮层（140ms 淡入），settle 本身没问题，
  /// 但节点选中态会带出「聚焦降噪」的重绘，用定长帧更稳。
  Future<void> pickMenu(WidgetTester tester, String title, String key) async {
    await letToastPass(tester);
    await tapAt(tester, centerOf(tester, title));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
    final target = find.byKey(ValueKey('mm-menu-$key'));
    expect(target, findsOneWidget, reason: '菜单里没有 $key');
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<MindmapDao> pumpCanvas(WidgetTester tester) async {
    final dao = mindmapDaoOf(db);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(home: MindmapCanvasPage(mapId: 1, dao: dao, db: db)),
    ));
    return dao;
  }

  testWidgets('上移改同级序 → 落库；撤销一步复原', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '根');
    final a = await dao.addNode(mapId: mapId, parentId: root.id, title: '甲');
    final b = await dao.addNode(mapId: mapId, parentId: root.id, title: '乙');
    await pumpCanvas(tester);
    await tester.pumpAndSettle();

    // 甲乙同父：乙的 sort 比甲大，上移后应排到甲前面。
    expect((await dao.nodeById(b.id!))!.sort,
        greaterThan((await dao.nodeById(a.id!))!.sort));

    await pickMenu(tester, '乙', 'up');

    final a2 = (await dao.nodeById(a.id!))!;
    final b2 = (await dao.nodeById(b.id!))!;
    expect(b2.sort, lessThan(a2.sort), reason: '上移＝乙排到甲前面');

    // 一步撤销：两行同时回原位（不是退半组）。
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    final a3 = (await dao.nodeById(a.id!))!;
    final b3 = (await dao.nodeById(b.id!))!;
    expect(b3.sort, greaterThan(a3.sort), reason: '撤销一次即整组复原');
  });

  testWidgets('同级第一位再上移＝只提示、不写库不动历史', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '根');
    final a = await dao.addNode(mapId: mapId, parentId: root.id, title: '甲');
    await pumpCanvas(tester);
    await tester.pumpAndSettle();

    await letToastPass(tester);
    await tapAt(tester, centerOf(tester, '甲'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
    // 已是第一位 ⇒ 上移置灰（点不动），这是菜单层面的正确表达。
    final up =
        tester.widget<OutlinedButton>(find.byKey(const ValueKey('mm-menu-up')));
    expect(up.enabled, isFalse);
    expect(up.onPressed, isNull);
    final before = (await dao.nodeById(a.id!))!;
    expect(before.sort, 0, reason: '取消/置灰都不该动数据');
  });

  testWidgets('复制 → 粘贴同级：落在选中节点的**父**下（不是变成它的子级）',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '根');
    final a = await dao.addNode(mapId: mapId, parentId: root.id, title: '甲');
    final b = await dao.addNode(mapId: mapId, parentId: root.id, title: '乙');
    await pumpCanvas(tester);
    await tester.pumpAndSettle();

    await pickMenu(tester, '甲', 'copy');
    expect(MmClipboard.hasContent, isTrue);
    expect(MmClipboard.isCut, isFalse);
    expect(MmClipboard.previewTitle, '甲');

    // 选中乙，粘贴同级 ⇒ 新枝挂在根的下面（与甲、乙同级）。
    await pickMenu(tester, '乙', 'pasteSib');
    final all = await dao.nodesOf(mapId);
    expect(all.length, 4, reason: '复制只带自己＝+1 行');
    final fresh = all.where((n) => n.id != root.id && n.id != a.id && n.id != b.id);
    expect(fresh.length, 1);
    expect(fresh.first.title, '甲');
    expect(fresh.first.parentId, root.id, reason: '粘贴同级＝挂到选中节点的父下');
    expect(MmClipboard.hasContent, isTrue, reason: '复制语义：读而不清');
  });

  testWidgets('复制整枝 → 粘贴子级：子级跟着一起来', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '根');
    final a = await dao.addNode(mapId: mapId, parentId: root.id, title: '甲');
    final aChild = await dao.addNode(mapId: mapId, parentId: a.id, title: '甲子');
    final b = await dao.addNode(mapId: mapId, parentId: root.id, title: '乙');
    await pumpCanvas(tester);
    await tester.pumpAndSettle();

    await pickMenu(tester, '甲', 'copy');
    expect(MmClipboard.descendantCount, 1, reason: '含子级＝2 行、后代 1 个');

    await pickMenu(tester, '乙', 'pasteChild');
    final all = await dao.nodesOf(mapId);
    expect(all.length, 6, reason: '4 行原图 + 2 行粘贴');
    final fresh = all.where((n) => n.title == '甲' && n.id != a.id).toList();
    expect(fresh.length, 1);
    expect(fresh.first.parentId, b.id, reason: '粘贴子级＝挂进选中节点');
    final child = all.where((n) => n.title == '甲子' && n.id != aChild.id);
    expect(child.length, 1, reason: '粘贴出来的子级是**另一行**，不是把原行改挂');
    expect(child.first.parentId, fresh.first.id, reason: '子级跟着新根，不是老 id');
  });

  testWidgets('剪切：整枝离场＋进剪贴板；粘贴回来是新 id；撤销剪切还原原 id',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final root = await dao.addNode(mapId: mapId, title: '根');
    final a = await dao.addNode(mapId: mapId, parentId: root.id, title: '甲');
    final aChild = await dao.addNode(mapId: mapId, parentId: a.id, title: '甲子');
    // 留一个兄弟当粘贴落点：选中**根**时「粘贴同级」＝贴成新根（原型
    // `parentOf(sel)` 为 null 的同一语义），那是另一条分支；这里要测的是
    // 「贴着兄弟落回同一层」。
    await dao.addNode(mapId: mapId, parentId: root.id, title: '乙');
    await pumpCanvas(tester);
    await tester.pumpAndSettle();

    await pickMenu(tester, '甲', 'cut');
    expect(await dao.nodesOf(mapId), hasLength(2), reason: '整枝离场（连带子级）');
    expect(MmClipboard.isCut, isTrue);
    expect(MmClipboard.previewTitle, '甲');

    // 粘贴回来：贴在「乙」这一层（乙的父＝根）。
    await pickMenu(tester, '乙', 'pasteSib');
    final all = await dao.nodesOf(mapId);
    expect(all.length, 4);
    // 不拿「新 id ≠ 旧 id」当判据：剪切刚把行删掉，表内 max 回落，粘贴**可能
    // 复用**同一批 id——那是数据库正常行为，不是粘贴成了「恢复」。这里断的是
    // 结构：一父一子、父子挂对。
    final back = all.firstWhere((n) => n.title == '甲');
    final backChild = all.firstWhere((n) => n.title == '甲子');
    expect(back.parentId, root.id);
    expect(backChild.parentId, back.id);
    expect(MmClipboard.hasContent, isFalse, reason: '剪切语义：粘贴后清空');

    // 撤销粘贴 → 撤销剪切：原 id 整行复原。
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    final restored = await dao.nodesOf(mapId);
    expect(restored.map((n) => n.id), containsAll([a.id, aChild.id]));
    expect(restored.firstWhere((n) => n.id == aChild.id).parentId, a.id);
    expect(restored.map((n) => n.title), containsAll(['根', '乙']),
        reason: '旁枝不受牵连');
  });

  testWidgets('剪贴板空时两枚粘贴置灰（不给人点了才知道）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await dao.addNode(mapId: mapId, title: '根');
    await pumpCanvas(tester);
    await tester.pumpAndSettle();
    MmClipboard.clear();

    await letToastPass(tester);
    await tapAt(tester, centerOf(tester, '根'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-tool-more')));
    await tester.pumpAndSettle();
    for (final k in ['mm-menu-pasteSib', 'mm-menu-pasteChild']) {
      final b = tester.widget<OutlinedButton>(find.byKey(ValueKey(k)));
      expect(b.onPressed, isNull, reason: '$k 在剪贴板空时应当置灰');
    }
  });
}
