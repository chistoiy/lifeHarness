import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 物品实物属性批 v53 的 DB 守护：版本/迁移同批、迁移 SQL 正确、
/// 新装库直接带列、老库升级八列就位且已装数据一行不丢。
/// 断言分源码级（DbSchema 常量/语句表）与真库级（sqflite_ffi），
/// 每条都带正档 true 与负档 false。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  const cols = [
    'photos',
    'location_path',
    'attachments',
    'barcode',
    'loan_to',
    'loan_at',
    'loan_due',
    'custom_fields',
  ];

  String alter(String c) => 'ALTER TABLE item_profiles ADD COLUMN $c TEXT';

  test('v53 版本常量 = migrations 最高键 + 1（正档一致 / 负档非 52）', () {
    final maxKey =
        DbSchema.migrations.keys.reduce((a, b) => a > b ? a : b);
    expect(DbSchema.version, 53); // 正档
    expect(DbSchema.version, maxKey + 1); // 正档：漏改 version 就红
    expect(DbSchema.version == 52, isFalse); // 负档
    expect(DbSchema.migrations.containsKey(51), isTrue); // 上一批仍在
  });

  test('migrations[52] 与 createStatements 同批含八条可空 ALTER（正/负档）', () {
    final mig = DbSchema.migrations[52]!;
    expect(mig.length, 8);
    for (final c in cols) {
      expect(mig.contains(alter(c)), isTrue, reason: 'mig 缺列 $c');
      expect(DbSchema.createStatements.contains(alter(c)), isTrue,
          reason: '新装库 createStatements 缺列 $c');
    }
    // 负档：绝不出现破坏性 / 非空 / 默认值（会丢老数据或炸升级）。
    expect(mig.any((s) => s.contains('DROP') || s.contains('DELETE')),
        isFalse);
    expect(mig.any((s) => s.contains('NOT NULL') || s.contains('DEFAULT')),
        isFalse);
    expect(DbSchema.itemsV53AddColumns.length, 8);
  });

  test('真升级：v52 老库跑 migrations[52] 后八列就位且老数据不丢', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // 只用 items 基础 DDL 建 v52 形态（该表尚无 v53 八列）。
    for (final sql in DbSchema.itemSchemaStatements) {
      await db.execute(sql);
    }
    await db.insert('item_profiles', {
      'name': '旧物',
      'buy_date': '2025-01-01',
      'price': 99.0,
      'created_at': 1,
      'updated_at': 1,
    });
    for (final sql in DbSchema.migrations[52]!) {
      await db.execute(sql);
    }
    final rows = await db.query('item_profiles');
    expect(rows.isEmpty, isFalse); // 正档：老行还在
    expect(rows.length, 1);
    expect(rows.first['name'], '旧物');
    expect(rows.first.containsKey('photos_v2'), isFalse); // 负档：无幽灵列
    for (final c in cols) {
      expect(rows.first.containsKey(c), isTrue, reason: '升级后缺列 $c');
      expect(rows.first[c], isNull, reason: '老行 $c 必须 NULL');
    }
    await db.close();
  });

  test('真新装：createStatements 建出的库直接带八列且可空无默认值', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    final info = await db.rawQuery('PRAGMA table_info(item_profiles)');
    final names = info.map((r) => r['name'] as String).toSet();
    for (final c in cols) {
      expect(names.contains(c), isTrue, reason: '新装库缺列 $c');
    }
    for (final r in info) {
      if (cols.contains(r['name'] as String)) {
        expect(r['notnull'], 0, reason: 'v53 列必须可空');
        expect(r['dflt_value'], isNull, reason: 'v53 列不得带 DEFAULT');
      }
    }
    expect(names.contains('brand'), isTrue); // 正档：I03 既有列仍在
    expect(names.contains('nonexistent_v53'), isFalse); // 负档
    await db.close();
  });
}
