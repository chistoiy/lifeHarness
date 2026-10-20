import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/shared/linkage/mindmap_mounts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mindmap_test_harness.dart';

/// 批2 F4-3/F4-4 · 文件夹数据层＋搜索第三源＋卡片预览出口（工单 §4c.3 ③④）。
/// 纯 DB 层（内存库），UI 接线回归由 note_search 既有件与面5 卡片件担。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MindmapDao dao;
  late int mapId;

  setUp(() async {
    db = await openMmDb();
    dao = mindmapDaoOf(db);
    mapId = await dao.createMap('主图');
    await dao.addNode(mapId: mapId, parentId: null, title: '根一');
    await dao.addNode(mapId: mapId, parentId: null, title: '根二');
  });

  tearDown(() async => db.close());

  group('F4-4 文件夹数据层', () {
    test('新建/重命名/列表', () async {
      final id = await dao.createFolder('工作');
      expect((await dao.listFolders()).single.title, '工作');
      await dao.renameFolder(id, '工作·改');
      expect((await dao.listFolders()).single.title, '工作·改');
    });

    test('归入/移出：folder_id 落列与置空', () async {
      final fid = await dao.createFolder('箱');
      await dao.setMapFolder(mapId, fid);
      expect((await dao.mapById(mapId))!.folderId, fid);
      await dao.setMapFolder(mapId, null);
      expect((await dao.mapById(mapId))!.folderId, isNull);
    });

    test('删文件夹只置空引用不删图（守护口径钉点）', () async {
      final fid = await dao.createFolder('待删');
      await dao.setMapFolder(mapId, fid);
      final mapB = await dao.createMap('旁图');
      await dao.setMapFolder(mapB, fid);

      await dao.deleteFolder(fid);

      expect(await dao.listFolders(), isEmpty, reason: '文件夹行删了');
      expect((await dao.mapById(mapId))!.folderId, isNull,
          reason: '引用置空');
      expect((await dao.mapById(mapB))!.folderId, isNull);
      expect((await dao.mapById(mapId))!.title, '主图',
          reason: '图本身完好');
      expect((await dao.nodesOf(mapId)).length, 2, reason: '节点不受牵连');
    });
  });

  group('F4-3 搜索第三源（mmSearchMountedNodes）', () {
    test('空查询＝零命中；节点自身标题命中', () async {
      expect(await mmSearchMountedNodes('  ', db), isEmpty);
      final n = await dao.addNode(mapId: mapId, parentId: null, title: '年度规划');
      final hits = await mmSearchMountedNodes('规划', db);
      expect(hits.single.nodeId, n.id);
      expect(hits.single.mapTitle, '主图');
      expect(hits.single.noteTitle, isNull, reason: '命中的是节点标题，无来源标注');
    });

    test('挂载笔记标题命中（实时 join）＋笔记删除后不再谎报', () async {
      // 直插一条笔记（内存库全量 DDL 含 notes 表）
      final noteId = await db.insert('notes',
          {'title': '读书摘录集', 'content': '', 'archived': 0, 'created_at': 1, 'updated_at': 1});
      final n = await dao.addNode(
          mapId: mapId, parentId: null, title: '不相关标题', noteId: noteId);

      final hits = await mmSearchMountedNodes('摘录', db);
      expect(hits.single.nodeId, n.id);
      expect(hits.single.noteTitle, '读书摘录集');

      // 笔记删除（软删口径与生产一致：deleted_at 非空即出列）
      await db.update('notes', {'deleted_at': 2},
          where: 'id = ?', whereArgs: [noteId]);
      expect(await mmSearchMountedNodes('摘录', db), isEmpty,
          reason: '笔记删除＝join 不出行，失效标题不进搜索');
    });

    test('回收站里的图不进搜索', () async {
      await dao.addNode(mapId: mapId, parentId: null, title: '秘密节点');
      await dao.trashMap(mapId);
      expect(await mmSearchMountedNodes('秘密', db), isEmpty);
    });
  });

  group('连接点② 卡片预览出口（mmCardPreview）', () {
    test('图在册＝(图名, 根标题集 ≤5)；根超 5 截断', () async {
      final r = await mmCardPreview(mapId, db);
      expect(r, isNotNull);
      expect(r!.$1, '主图');
      expect(r.$2, ['根一', '根二']);
      // 第 6 枚根不进预览
      for (var i = 0; i < 4; i++) {
        await dao.addNode(mapId: mapId, parentId: null, title: '根$i');
      }
      final r2 = await mmCardPreview(mapId, db);
      expect(r2!.$2.length, 5);
    });

    test('图删除（软删）后＝null（卡片占位依据）', () async {
      await dao.trashMap(mapId);
      expect(await mmCardPreview(mapId, db), isNull);
    });
  });
}
