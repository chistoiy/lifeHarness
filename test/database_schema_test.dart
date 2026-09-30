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
    // V1.57 E 批：软删列随建表就位，在册条目恒为 NULL（0＝在册是错的，NULL 才是）。
    expect(after.containsKey('deleted_at'), isTrue);
    expect(after['deleted_at'], isNull);
    await db.close();
  });

  test('v28→v29 迁移：todos 增 deleted_at 列且既有行数据不动', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // 手工构造 v28 结构（todos 无 deleted_at）+ 在册/已完成两条数据。
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
        tag TEXT,
        time_mode TEXT,
        start_min INTEGER,
        end_min INTEGER,
        pomo_mode TEXT,
        pomo_min INTEGER,
        dropped INTEGER NOT NULL DEFAULT 0,
        color INTEGER,
        grp TEXT,
        habit_id INTEGER,
        link_cat INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    final now = DateTime.now().millisecondsSinceEpoch;
    final keepId = await db.insert(DbSchema.tTodos, {
      'title': '在册旧任务',
      'quadrant': 2,
      'due_at': now,
      'done': 1,
      'created_at': now,
      'updated_at': now,
    });
    final doneId = await db.insert(DbSchema.tTodos, {
      'title': '已完成旧任务',
      'created_at': now,
      'updated_at': now,
    });

    for (final sql in DbSchema.migrations[28]!) {
      await db.execute(sql);
    }
    final rows = await db.query(DbSchema.tTodos, orderBy: 'id');
    expect(rows.length, 2);
    for (final r in rows) {
      expect(r.containsKey('deleted_at'), isTrue, reason: '迁移后应有软删列');
      expect(r['deleted_at'], isNull, reason: '迁移绝不把既有行标成已删除');
    }
    expect(rows.first['title'], '在册旧任务');
    expect(rows.first['quadrant'], 2);
    expect(rows.first['done'], 1);
    expect(rows.last['id'], doneId);
    expect(rows.first['id'], keepId);
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

  // V1.58 小工具整模块下架（产品负责人 2026-09-30 拍板「模块价值太低」）。
  test('v29→v30 迁移：kit_* 四表删除，其余表与数据一律不动', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // 手工构造 v29 现场：kit 四表（带数据）+ 一张无关表（带数据）。
    await db.execute('CREATE TABLE kit_usage (id INTEGER PRIMARY KEY AUTOINCREMENT,'
        ' tool TEXT NOT NULL, kind TEXT NOT NULL DEFAULT \'builtin\', ts INTEGER NOT NULL)');
    await db.execute('CREATE INDEX idx_kit_usage_ts ON kit_usage(ts)');
    await db.execute('CREATE TABLE kit_layout (key TEXT PRIMARY KEY,'
        ' value TEXT NOT NULL, updated_at INTEGER NOT NULL)');
    await db.execute('CREATE TABLE kit_tool_data (tool TEXT PRIMARY KEY,'
        ' data TEXT NOT NULL, updated_at INTEGER NOT NULL)');
    await db.execute('CREATE TABLE kit_plugin (id INTEGER PRIMARY KEY AUTOINCREMENT,'
        ' name TEXT NOT NULL, src TEXT, enabled INTEGER NOT NULL DEFAULT 1)');
    await db.execute('CREATE TABLE leftovers (id INTEGER PRIMARY KEY AUTOINCREMENT,'
        ' title TEXT NOT NULL)');
    await db.insert('kit_usage', {'tool': 'ruler', 'kind': 'builtin', 'ts': 1});
    await db.insert('kit_layout', {'key': 'order', 'value': '[]', 'updated_at': 1});
    await db.insert('kit_tool_data', {'tool': 'tele', 'data': '{}', 'updated_at': 1});
    await db.insert('kit_plugin', {'name': 'morse', 'src': 'local', 'enabled': 1});
    await db.insert('leftovers', {'title': '留下来的行'});

    expect(DbSchema.version, greaterThanOrEqualTo(30),
        reason: '删表是 schema 变更，v30 起只许更高（X-Ray 批1 已把版本推到 v31）');
    // 新库不再建这四张表（否则删完又被 onCreate 建回来）。
    expect(DbSchema.createStatements.join(), isNot(contains('kit_usage')));
    expect(DbSchema.migrations[29], hasLength(4));

    for (final sql in DbSchema.migrations[29]!) {
      await db.execute(sql);
    }
    final tables = (await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'] as String)
        .toSet();
    for (final t in ['kit_usage', 'kit_layout', 'kit_tool_data', 'kit_plugin']) {
      expect(tables, isNot(contains(t)), reason: '$t 应随 v30 迁移删除');
    }
    // 索引随表消失：残留会在「以后重建同名表」时撞名。
    final idx = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_kit%'"));
    expect(idx, isEmpty, reason: 'kit 索引未随表删除');
    expect(tables, contains('leftovers'), reason: '删表不得波及其他模块');
    expect((await db.query('leftovers')).single['title'], '留下来的行');
    await db.close();
  });

  test('v30 迁移幂等：从未建过 kit 表的新库重跑不报错', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final round in [0, 1]) {
      for (final sql in DbSchema.migrations[29]!) {
        await db.execute(sql);
      }
      expect(round, lessThan(2));
    }
    await db.close();
  });
}
