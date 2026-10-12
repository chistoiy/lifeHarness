import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/database/schema.dart';
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
}
