import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';

/// X-Ray 全书索引 · 批1a 数据层守护（需求 V1.54·设计书 §6/§11 批1）
///
/// 钉三件事：
/// 1. **新装库**（`createStatements`）就把四表与 `books.md5` 建全；
/// 2. **存量库**（v30 形态）跑 `migrations[30]` 升到 v31，只多出这四张表、别的一张不塌；
/// 3. **迁移键全局唯一**——中枢用 `...域.mig` 展开，同键会被后者静默覆盖，
///    跨域撞号是这套 schema 组织方式最阴的一种坏法，必须源码级拦死。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const xrayTables = ['xray_task', 'xray_entity', 'xray_mention', 'xray_userdict'];

  Future<Database> openFresh() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: DbSchema.version),
    );
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    return db;
  }

  Future<Set<String>> tablesOf(Database db) async => (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      ))
      .map((r) => r['name'] as String)
      .toSet();

  Future<Set<String>> columnsOf(Database db, String table) async => (await db
          .rawQuery('PRAGMA table_info($table)'))
      .map((r) => r['name'] as String)
      .toSet();

  test('v31：新装库直接建全 X-Ray 四表与 books.md5', () async {
    final db = await openFresh();
    addTearDown(db.close);
    final tables = await tablesOf(db);
    for (final t in xrayTables) {
      expect(tables, contains(t), reason: '$t 应随 createStatements 建出（新装库不跑迁移）');
    }
    expect(await columnsOf(db, 'books'), contains('md5'));
    expect(DbSchema.version, 31, reason: '加表加列是 schema 变更，必须升版本');
    // 四表在新装库里必须可用（写入探针·顺带钉住 NOT NULL 默认形态）
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('xray_task', {
      'book_md5': 'M', 'total_ch': 3, 'status': 'pending', 'update_time': now,
    });
    final id = await db.insert('xray_entity', {
      'book_md5': 'M', 'name': '波洛', 'type': 'per', 'n': 12, 'chs': 5, 'score': 0.8,
    });
    await db.insert('xray_mention', {
      'entity_id': id, 'book_md5': 'M', 'ch': 1, 'para': 7, 'snippet': '…',
    });
    await db.insert('xray_userdict', {
      'scope': 'M', 'word': '探长', 'action': 'forbid', 'create_time': now,
    });
    expect(await db.query('xray_entity'), hasLength(1));
  });

  test('v30→v31 迁移：只增四表与 md5 列，不波及他表', () async {
    final db = await openFresh();
    addTearDown(db.close);
    // 造 v30 形态：摘掉 X-Ray 四表，并把 books 的 md5 列去掉重建（索引随 DROP 一起消失）。
    for (final t in xrayTables) {
      await db.execute('DROP TABLE IF EXISTS $t');
    }
    final fresh = DbSchema.createStatements
        .firstWhere((s) => s.contains('CREATE TABLE IF NOT EXISTS books'));
    final v30 = fresh.replaceAll(RegExp(r'\n\s*md5 TEXT,'), '');
    expect(v30, isNot(contains('md5')), reason: '前置态没构造成功：md5 列没摘掉');
    await db.execute('DROP TABLE IF EXISTS books');
    await db.execute(v30);
    await db.execute(
      "INSERT INTO books(id,title,created_at,updated_at) VALUES('b1','人类简史',1,1)",
    );
    expect(await columnsOf(db, 'books'), isNot(contains('md5')),
        reason: '前置态必须是「还没有 md5 列」的 v30 形态，否则本用例什么都没验');

    expect(DbSchema.migrations.containsKey(30), isTrue,
        reason: 'v30→v31 迁移条目必须由 xray 域认领');
    final before = await tablesOf(db);
    for (final sql in DbSchema.migrations[30]!) {
      await db.execute(sql);
    }
    final after = await tablesOf(db);

    expect(after.difference(before), xrayTables.toSet());
    expect(before.difference(after), isEmpty, reason: '迁移不许删任何既有表');
    expect(await columnsOf(db, 'books'), contains('md5'));
    final rows = await db.query('books', where: 'id=?', whereArgs: ['b1']);
    expect(rows, hasLength(1), reason: '加列不得动存量行');
    expect(rows.first['md5'], isNull, reason: 'md5 懒补算：升级瞬间应为空，由导入/补算链路回填');
  });

  test('守护自证：迁移版本号跨域唯一（中枢展开会静默覆盖同键）', () {
    final dir = Directory('lib/core/database/schema');
    final owner = <int, String>{};
    final dup = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final name = f.uri.pathSegments.last;
      final src = f.readAsStringSync();
      // 只认 mig 映射里的键行：形如「  28: [」或「    25: [...」
      for (final m in RegExp(r'^\s{2,}(\d+):\s*\[', multiLine: true).allMatches(src)) {
        final v = int.parse(m.group(1)!);
        // read.dart 里也有 createStatements 之外的键行，统一按「域内 mig」处理：
        // 中枢的内联键（29）不在本目录，故这里只需查跨文件重复。
        if (owner.containsKey(v) && owner[v] != name) {
          dup.add('v$v 同时被 ${owner[v]} 与 $name 认领');
        }
        owner[v] = name;
      }
    }
    expect(dup, isEmpty,
        reason: 'DbSchema.migrations 用 ...域.mig 展开，同键后者静默覆盖前者 → 迁移会静默丢失');
    expect(owner.containsKey(30), isTrue, reason: 'v31 迁移应存在（xray 域）');
    expect(owner.containsKey(29), isNot(isTrue),
        reason: 'v29→v30 条目挂在中枢内联（kit DROP），不在域文件里——若哪天搬进域文件，记得同步本断言');
  });

  test('books.md5 不做唯一约束（F9：重复条目共享同一份索引）', () async {
    final db = await openFresh();
    addTearDown(db.close);
    final idx = await db.rawQuery('PRAGMA index_list(books)');
    final md5Idx = idx.where((r) => (r['name'] as String).contains('md5')).toList();
    expect(md5Idx, hasLength(1), reason: 'books.md5 要有查询索引');
    expect(md5Idx.first['unique'], 0,
        reason: '同一 MD5 允许多条书架条目（重复导入共享索引），唯一约束会把 F9 变成报错');
  });
}
