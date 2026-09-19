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

  test('v1→v2 迁移：todos 增 tag 列且数据保留', () async {
    // 手工构造 v1 结构（无 tag 列）+ 一条数据。
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE ${DbSchema.tTodos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        note TEXT,
        quadrant INTEGER NOT NULL DEFAULT 4,
        due_at INTEGER,
        remind_at INTEGER,
        done INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(DbSchema.tTodos, {'title': '旧任务', 'created_at': now, 'updated_at': now});

    for (final sql in DbSchema.migrations[1]!) {
      await db.execute(sql);
    }
    final row = (await db.query(DbSchema.tTodos)).single;
    expect(row['title'], '旧任务');
    expect(row.containsKey('tag'), isTrue);
    expect(row['tag'], isNull);
    await db.close();
  });
}
