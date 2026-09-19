import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('v1 DDL 可执行：核心表 + 预留表 + settings 全部建出', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DbSchema.version,
        onCreate: (d, v) async {
          final batch = d.batch();
          for (final sql in DbSchema.createStatements) {
            batch.execute(sql);
          }
          await batch.commit(noResult: true);
        },
      ),
    );

    final tables = (await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'] as String)
        .toSet();

    for (final t in [
      DbSchema.tTodos,
      DbSchema.tEvents,
      DbSchema.tJournal,
      DbSchema.tNotes,
      DbSchema.tInbox,
      DbSchema.tSettings,
      DbSchema.tHealth,
      DbSchema.tFinance,
      DbSchema.tItems,
    ]) {
      expect(tables, contains(t), reason: '缺表 $t');
    }
    await db.close();
  });

  test('todos 基本 CRUD 与四象限默认值', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert(DbSchema.tTodos, {
      'title': '写测试',
      'created_at': now,
      'updated_at': now,
    });
    final row = (await db
            .query(DbSchema.tTodos, where: 'id = ?', whereArgs: [id]))
        .single;
    expect(row['quadrant'], 4); // 默认第四象限
    expect(row['done'], 0);

    await db.update(DbSchema.tTodos, {'done': 1}, where: 'id = ?', whereArgs: [id]);
    final after = (await db
            .query(DbSchema.tTodos, where: 'id = ?', whereArgs: [id]))
        .single;
    expect(after['done'], 1);
    await db.close();
  });

  test('plugin_* 命名规范常量存在，宿主表不加前缀', () {
    expect(DbSchema.pluginPrefix, 'plugin_');
    for (final t in [DbSchema.tTodos, DbSchema.tSettings]) {
      expect(t.startsWith(DbSchema.pluginPrefix), isFalse);
    }
  });
}
