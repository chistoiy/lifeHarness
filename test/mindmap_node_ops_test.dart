import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/shared/trash/trash_models.dart';
import 'package:lifeharness/shared/trash/trash_specs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批1 · 节点操作闭环守护（工单 §4b.3 ⑥）＋ 图管理/回收站第九类
/// 级联（部分 DAO 层断言放本文件；全 app widget 独立文件口径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late dynamic db;
  setUp(() async {
    db = await openMmDb();
  });
  tearDown(() async {
    await (db as CloseableDb).close();
  });

  group('DAO 节点操作（编辑读回/加根/同级/折叠持久化）', () {
    test('编辑节点＝updateNode 读回改写标题＋备注（H2：写得进也读得回）',
        () async {
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('图');
      final root = await dao.addNode(mapId: mapId, title: '旧标题', note: '旧备注');
      final u = root.copyWith(title: '新标题', note: '新备注', updatedAt: 2);
      await dao.updateNode(u);
      final back = await dao.nodeById(root.id!);
      expect(back!.title, '新标题');
      expect(back.note, '新备注');
    });

    test('加根节点各生一枚（F1-4 多根）；根上加同级＝新增根（C7/F1-6）', () async {
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('图');
      final r1 = await dao.addNode(mapId: mapId, parentId: null, title: '根一');
      // 「加同级」在根节点上＝parentId 保持 null ＝ 新根。
      final siblingOfRoot = await dao.addNode(
          mapId: mapId, parentId: r1.parentId, title: '根二');
      expect(siblingOfRoot.parentId, isNull);
      // 选中子节点加同级＝同父新兄弟。
      final child = await dao.addNode(mapId: mapId, parentId: r1.id, title: '子');
      final sibling = await dao.addNode(
          mapId: mapId, parentId: child.parentId, title: '兄弟');
      expect(sibling.parentId, r1.id);
      // 兄弟序递增（F1-5：sort 排在末尾）。
      expect(sibling.sort, greaterThan(child.sort));
      final nodes = await dao.nodesOf(mapId);
      expect(nodes.where((n) => n.parentId == null), hasLength(2));
    });

    test('折叠态持久化（C10）：folded 落库，重开读回', () async {
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('图');
      final root = await dao.addNode(mapId: mapId, title: '根');
      await dao.addNode(mapId: mapId, parentId: root.id, title: '子');
      await dao.updateNode(root.copyWith(folded: true, updatedAt: 2));
      // 模拟「重开图」：全新 DAO 实例重读。
      final fresh = mindmapDaoOf(db);
      final again = await fresh.nodeById(root.id!);
      expect(again!.folded, isTrue);
    });

    test('descendantIdsOf/deleteNodeCascade：后代全收、连带数正确', () async {
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('图');
      final root = await dao.addNode(mapId: mapId, title: '根');
      final c1 = await dao.addNode(mapId: mapId, parentId: root.id, title: '子1');
      await dao.addNode(mapId: mapId, parentId: c1.id, title: '孙');
      final ids = await dao.descendantIdsOf(root.id!);
      expect(ids, hasLength(3));
      final removed = await dao.deleteNodeCascade(root.id!);
      expect(removed, 2, reason: '连带子级数＝2（确认文案读数）');
      expect(await dao.nodesOf(mapId), isEmpty);
    });

    test('空标题节点禁止保存（B8）由弹层守门：DAO 直接存空串不越界（画布拦截）',
        () async {
      // B8 拦截点在弹层（mm-node-sheet 空标题禁保存钮）；DAO 不重复做业务校验，
      // 但「禁保存」的读数口径＝标题 trim 空。这里钉 DAO 行为不变（回归哨兵）。
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('图');
      final n = await dao.addNode(mapId: mapId, title: ' ', note: '');
      expect(n.title, ' ');
    });
  });

  group('图管理（F2-1~F2-4）与回收站第九类级联', () {
    test('复制图：标题「原名 副本」、节点与挂载引用复制、父子关系不乱（F2-3）',
        () async {
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('原图');
      final root = await dao.addNode(mapId: mapId, title: '根');
      final child =
          await dao.addNode(mapId: mapId, parentId: root.id, title: '子');
      await dao.updateNode(child.copyWith(noteId: 77, updatedAt: 2));
      final copyId = await dao.copyMap(mapId);
      final (copy, cnt) = (await dao.listLive()).firstWhere((e) => e.$1.id == copyId);
      expect(copy.title, '原图 副本');
      expect(cnt, 2);
      final nodes = await dao.nodesOf(copyId);
      final newRoot = nodes.firstWhere((n) => n.parentId == null);
      final newChild = nodes.singleWhere((n) => n.parentId == newRoot.id);
      expect(newChild.title, '子');
      expect(newChild.noteId, 77, reason: '挂载引用随图复制');
      // 原图不受影响。
      expect((await dao.nodesOf(mapId)).length, 2);
    });

    test('删图进第九类：软删图行、节点行不动；恢复带全节点回原位（B7）',
        () async {
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('要删的图');
      await dao.addNode(mapId: mapId, title: '根');
      await dao.addNode(mapId: mapId, title: '根二');
      await dao.trashMap(mapId);
      // trash_spec 读源：行在第九类（登记式接口真调用）。
      final rows = await trashSpecOf(TrashKind.mindmap).rows(db);
      final it = rows.singleWhere((e) => e.rawId == mapId);
      expect(it.kind, TrashKind.mindmap);
      expect(it.subs.single, '2 个节点');
      // 节点行仍在（软删不动子表）——恢复＝只清标记即带全节点回原位。
      expect(await dao.nodesOf(mapId), hasLength(2));
      await dao.restoreMap(mapId);
      final back = await dao.mapById(mapId);
      expect(back!.isDeleted, isFalse);
      expect(await dao.nodesOf(mapId), hasLength(2));
    });

    test('第九类到期清理经 spec 出口真调用（purgeExpired 级联节点）', () async {
      final dao = mindmapDaoOf(db);
      final now = DateTime.now().millisecondsSinceEpoch;
      final m2 = await dao.createMap('删很久了');
      await dao.addNode(mapId: m2, title: '根');
      await db.update(DbSchema.tMindmaps, {'deleted_at': now - 40 * 86400000},
          where: 'id = ?', whereArgs: [m2]);
      final perKind = await trashSpecOf(TrashKind.mindmap)
          .purgeExpired(db, 30);
      expect(perKind, 1);
      expect(await dao.mapById(m2), isNull);
      expect(await dao.nodesOf(m2), isEmpty, reason: '到期清理同样级联');
    });

    test('彻底删除 purgeMap：图行＋全部节点行级联真 DELETE（B7 删除侧）',
        () async {
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('图');
      await dao.addNode(mapId: mapId, title: '根');
      final n = await dao.purgeMap(mapId);
      expect(n, 1);
      expect(await dao.nodesOf(mapId), isEmpty);
      expect(await dao.mapById(mapId), isNull);
    });

    test('到期清理 purgeExpired：只清过期的，未到期保留', () async {
      final dao = mindmapDaoOf(db);
      final now = DateTime.now().millisecondsSinceEpoch;
      final m1 = await dao.createMap('刚删');
      await dao.addNode(mapId: m1, title: '根');
      await db.update(DbSchema.tMindmaps, {'deleted_at': now},
          where: 'id = ?', whereArgs: [m1]);
      final m2 = await dao.createMap('删很久了');
      await dao.addNode(mapId: m2, title: '根');
      await db.update(DbSchema.tMindmaps,
          {'deleted_at': now - 40 * 86400000},
          where: 'id = ?', whereArgs: [m2]);
      final removed = await dao.purgeExpired(30);
      expect(removed, 1);
      expect(await dao.mapById(m1), isNotNull);
      expect(await dao.mapById(m2), isNull);
      expect(await dao.nodesOf(m2), isEmpty, reason: '到期清理同样级联');
    });
  });
}
