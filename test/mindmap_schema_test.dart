import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/mindmap.dart'
    show mindmapMig45Statements;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 思维导图批1 · schema 层守护（工单 §4b.3 ①＋§6.2 双写 DDL）。
///
/// 6109 实锤的铁律：迁移批必跑 S6（version=migrations 最高键+1）＋
/// S7（真升级路径，禁只测 onCreate——测试库走 onCreate 全量 DDL，
/// 升级路径平时零覆盖）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('思维导图 v44→v45（批1 数据层）', () {
    // ---- S6：版本常量与 migrations 最高键同批同步（journal_test 同款守护）----
    test('S6 version 常量 = migrations 最高键 + 1（漏改 version＝升级静默失效）',
        () {
      final maxKey =
          DbSchema.migrations.keys.reduce((a, b) => a > b ? a : b);
      expect(DbSchema.version, maxKey + 1,
          reason: 'migrations 已定义到 $maxKey → ${maxKey + 1}，'
              '但 version=${DbSchema.version} 没跟上——真机 user_version 已到 '
              '${maxKey + 1} 以上时该迁移永不执行（6109 日记全断同源）');
    });

    // ---- S7：真升级路径 v44→v45（禁只测 onCreate）----
    test('S7 真升级 v44 库 → v45：两表与索引齐全、side/sort/dx/dy/folded 五列在',
        () async {
      const name = 'mmtest_upgrade_v44to45.db';
      await databaseFactory.deleteDatabase(name);
      // 1) 手工搭 v44 时代库（随便一张既有表占位）并钉 user_version=44
      final old = await databaseFactory.openDatabase(name);
      await old.execute('CREATE TABLE journal_entries (id INTEGER PRIMARY KEY)');
      await old.execute('PRAGMA user_version = 44');
      await old.close();
      // 2) 按生产口径重开，version 触发 onUpgrade 逐级迁移
      final upgraded = await databaseFactory.openDatabase(name,
          options: OpenDatabaseOptions(
            version: DbSchema.version,
            onUpgrade: (d, from, to) async {
              for (var v = from; v < to; v++) {
                for (final sql in DbSchema.migrations[v] ?? const <String>[]) {
                  await d.execute(sql);
                }
              }
            },
          ));
      // 3) 两表存在
      final tables = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      final tnames = tables.map((r) => r['name'] as String).toSet();
      expect(tnames, containsAll(DbSchema.mindmapTables));
      // 4) 节点表五列在（side/sort/dx/dy/folded ＝ 批1 布局与折叠持久化的落点）
      final cols = await upgraded
          .rawQuery('PRAGMA table_info(${DbSchema.tMindmapNodes})');
      expect(cols.map((c) => c['name']),
          containsAll(['side', 'sort', 'dx', 'dy', 'folded']));
      // 5) 复合索引在（数据层三条之一）
      final idx = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index'");
      expect(idx.map((r) => r['name']),
          contains('idx_mmnode_map_parent'));
      await upgraded.close();
    });

    // ---- onCreate 路径（双写 DDL 的另一路：新装库全量 DDL 也带两表）----
    test('onCreate 全量 DDL 同样建出两表（双写 DDL 闸）', () async {
      final db =
          await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      final tnames = tables.map((r) => r['name'] as String).toSet();
      expect(tnames, containsAll(DbSchema.mindmapTables));
      await db.close();
    });

    // ---- 备份口径：两新表默认进备份包、不进可再生排除名单（工单 §4b.3 ⑧）----
    test('mindmaps/mindmap_nodes 不在备份排除名单（防「同步后丢图」）', () {
      expect(kRegenerableExcluded, isNot(contains(DbSchema.tMindmaps)));
      expect(kRegenerableExcluded, isNot(contains(DbSchema.tMindmapNodes)));
    });
  });

  group('思维导图 v45→v46（批2 F4-4 文件夹数据层）', () {
    // ---- S7b：真升级路径 v45→v46（禁只测 onCreate；批2 迁移批必跑）----
    test('S7b 真升级 v45 库 → v46：folders 表在、mindmaps.folder_id 列在、索引在',
        () async {
      const name = 'mmtest_upgrade_v45to46.db';
      await databaseFactory.deleteDatabase(name);
      // 1) 手工搭 v45 时代库：mindmaps **不带 folder_id**（v45 口径）＋钉 user_version=45
      final old = await databaseFactory.openDatabase(name);
      await old.execute('''
        CREATE TABLE mindmaps (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER
        )
      ''');
      await old.execute('''
        CREATE TABLE mindmap_nodes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          map_id INTEGER NOT NULL,
          parent_id INTEGER,
          note_id INTEGER,
          title TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          side TEXT,
          sort INTEGER NOT NULL DEFAULT 0,
          dx REAL NOT NULL DEFAULT 0,
          dy REAL NOT NULL DEFAULT 0,
          folded INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await old.execute(
          "INSERT INTO mindmaps (title, created_at, updated_at) VALUES ('老图', 1, 1)");
      await old.execute('PRAGMA user_version = 45');
      await old.close();
      // 2) 按生产口径重开，触发 mig[45]（45→46：建 folders＋ALTER 加列）
      final upgraded = await databaseFactory.openDatabase(name,
          options: OpenDatabaseOptions(
            version: DbSchema.version,
            onUpgrade: (d, from, to) async {
              for (var v = from; v < to; v++) {
                for (final sql in DbSchema.migrations[v] ?? const <String>[]) {
                  await d.execute(sql);
                }
              }
            },
          ));
      // 3) 三表齐全（mindmapTables 含批2 的 mindmap_folders）
      final tables = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      expect(tables.map((r) => r['name'] as String).toSet(),
          containsAll(DbSchema.mindmapTables));
      // 4) folder_id 列在且可写（ALTER 真生效；老行值 null）
      final cols = await upgraded
          .rawQuery('PRAGMA table_info(${DbSchema.tMindmaps})');
      expect(cols.map((c) => c['name']), contains('folder_id'));
      await upgraded.execute(
          'UPDATE ${DbSchema.tMindmaps} SET folder_id = 7 WHERE title = ?', ['老图']);
      final row = (await upgraded
              .query(DbSchema.tMindmaps, where: 'title = ?', whereArgs: ['老图']))
          .single;
      expect(row['folder_id'], 7);
      // 5) folder 索引在
      final idx = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index'");
      expect(idx.map((r) => r['name']), contains('idx_mmaps_folder'));
      await upgraded.close();
    });

    // ---- 44→46 直升链：批1 的 v45 口径建表（无 folder_id）后接 mig[45] ALTER 不撞列 ----
    test('44→46 直升：v45 口径建表 + ALTER folder_id 零撞列（拆两份口径闸）',
        () async {
      const name = 'mmtest_upgrade_v44to46.db';
      await databaseFactory.deleteDatabase(name);
      final old = await databaseFactory.openDatabase(name);
      await old.execute('CREATE TABLE journal_entries (id INTEGER PRIMARY KEY)');
      await old.execute('PRAGMA user_version = 44');
      await old.close();
      final upgraded = await databaseFactory.openDatabase(name,
          options: OpenDatabaseOptions(
            version: DbSchema.version,
            onUpgrade: (d, from, to) async {
              for (var v = from; v < to; v++) {
                for (final sql in DbSchema.migrations[v] ?? const <String>[]) {
                  await d.execute(sql);
                }
              }
            },
          ));
      // 走完 44→45→46 全链：ALTER 已执行过一次、mindmaps 带 folder_id
      final cols =
          await upgraded.rawQuery('PRAGMA table_info(${DbSchema.tMindmaps})');
      expect(cols.map((c) => c['name']), contains('folder_id'));
      await upgraded.close();
    });

    // ---- onCreate 路径（v46 全量口径：mindmaps 自带 folder_id）----
    test('onCreate 全量 DDL：mindmaps 自带 folder_id＋folders 表在', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      final cols =
          await db.rawQuery('PRAGMA table_info(${DbSchema.tMindmaps})');
      expect(cols.map((c) => c['name']), contains('folder_id'));
      final tables =
          await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      expect(tables.map((r) => r['name']),
          contains(DbSchema.tMindmapFolders));
      await db.close();
    });

    // ---- 备份口径：folders 表默认进包（工单 §4c.1）----
    test('mindmap_folders 不在备份排除名单', () {
      expect(kRegenerableExcluded, isNot(contains(DbSchema.tMindmapFolders)));
    });
  });

  group('思维导图 v46→v47（批5 F4-9 节点增强数据层）', () {
    /// 四列在基础 DDL 与 mig[46] 两处都在，且**只在**这两处
    /// （老口径 v45 语句表里多写一次就会让 44→47 直升撞 duplicate column）。
    test('S7c 四列在基础 DDL 与 mig[46] 各一次、老口径零出现', () {
      const four = ['tags', 'is_task', 'task_done', 'image_path'];
      final base = DbSchema.createStatements.join('\n');
      final mig46 = (DbSchema.migrations[46] ?? const <String>[]).join('\n');
      final old45 = mindmapMig45Statements.join('\n');
      for (final c in four) {
        expect(base, contains(c), reason: '$c 缺失则新装库无批5 三段');
        expect(
            mig46,
            contains('ALTER TABLE ${DbSchema.tMindmapNodes} ADD COLUMN $c'),
            reason: '$c 迁移语句缺失则老库升级不触发');
        expect(old45, isNot(contains(c)),
            reason: '$c 出现在 v45 老口径里会让 44→47 直升 duplicate column');
      }
    });

    test('S7d 真升级 v46 库 → v47：四列在、老行取默认、批5 写入读回走通',
        () async {
      const name = 'mmtest_upgrade_v46to47.db';
      await databaseFactory.deleteDatabase(name);
      final old = await databaseFactory.openDatabase(name);
      await old.execute('CREATE TABLE mindmaps ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'title TEXT NOT NULL, folder_id INTEGER, '
          'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
          'deleted_at INTEGER)');
      await old.execute('CREATE TABLE mindmap_nodes ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'map_id INTEGER NOT NULL, parent_id INTEGER, note_id INTEGER, '
          'title TEXT NOT NULL, note TEXT NOT NULL DEFAULT "", '
          'side TEXT, sort INTEGER NOT NULL DEFAULT 0, '
          'dx REAL NOT NULL DEFAULT 0, dy REAL NOT NULL DEFAULT 0, '
          'folded INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
      await old.insert('mindmaps',
          {'title': '升级前的图', 'created_at': 1, 'updated_at': 1});
      await old.insert('mindmap_nodes', {
        'map_id': 1,
        'title': '升级前的节点',
        'created_at': 1,
        'updated_at': 1,
      });
      await old.execute('PRAGMA user_version = 46');
      await old.close();

      final upgraded = await databaseFactory.openDatabase(name,
          options: OpenDatabaseOptions(
            version: DbSchema.version,
            onUpgrade: (d, from, to) async {
              for (var v = from; v < to; v++) {
                for (final sql in DbSchema.migrations[v] ?? const <String>[]) {
                  await d.execute(sql);
                }
              }
            },
          ));

      final cols = await upgraded
          .rawQuery('PRAGMA table_info(${DbSchema.tMindmapNodes})');
      expect(cols.map((c) => c['name']),
          containsAll(['tags', 'is_task', 'task_done', 'image_path']));

      final dao = MindmapDao(upgraded);
      final nodes = await dao.nodesOf(1);
      expect(nodes.length, 1);
      expect(nodes.first.title, '升级前的节点');
      expect(nodes.first.tags, isEmpty);
      expect(nodes.first.isTask, isFalse);
      expect(nodes.first.taskDone, isFalse);
      expect(nodes.first.hasImage, isFalse);

      await dao.updateNode(nodes.first.copyWith(
        tags: const ['方法论', '复盘'],
        isTask: true,
        taskDone: true,
        imagePath: '/tmp/x.jpg',
      ));
      final back = (await dao.nodesOf(1)).first;
      expect(back.tags, ['方法论', '复盘']);
      expect(back.isTask, isTrue);
      expect(back.taskDone, isTrue);
      expect(back.imagePath, '/tmp/x.jpg');
      await upgraded.close();
    });

    test('S7e 撤销重做与复制图路径（insertNodeFull/copyMap）四列不走失',
        () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      final dao = MindmapDao(db);
      final mapId = await dao.createMap('四列图');
      var src = await dao.addNode(
        mapId: mapId,
        title: '带三段的节点',
        tags: const ['a', 'b'],
        isTask: true,
        imagePath: '/tmp/y.jpg',
      );
      src = src.copyWith(taskDone: true);
      await dao.updateNode(src);
      // 整行删→整行重插＝撤销「删」的恢复侧（四列必须跟着回来）
      await dao.deleteNodeRows({src.id!});
      expect(await dao.nodesOf(mapId), isEmpty);
      await dao.insertNodeFull(src);
      final restored = (await dao.nodesOf(mapId)).first;
      expect(restored.tags, ['a', 'b']);
      expect(restored.taskDone, isTrue);
      // 复制图也带三段
      final copyId = await dao.copyMap(mapId);
      final copied = (await dao.nodesOf(copyId)).first;
      expect(copied.tags, ['a', 'b'], reason: '复制图必须带标签（漏列即丢三段）');
      expect(copied.isTask, isTrue);
      expect(copied.taskDone, isTrue);
      expect(copied.imagePath, '/tmp/y.jpg');
      await db.close();
    });

    test('S7f 取消任务属性即清完成态（原型 if(!n.task) n.taskDone=false）', () {
      final n = MindmapNode(
        mapId: 1,
        title: 'x',
        isTask: true,
        taskDone: true,
        createdAt: 1,
        updatedAt: 1,
      );
      expect(n.copyWith(isTask: false).taskDone, isFalse);
      expect(n.copyWith(taskDone: false).taskDone, isFalse);
      expect(n.copyWith(isTask: true, taskDone: true).taskDone, isTrue);
    });

    test('S7g 备份排除名单不含节点表（四列随包走）', () {
      expect(kRegenerableExcluded, isNot(contains(DbSchema.tMindmapNodes)));
    });
  });
}
