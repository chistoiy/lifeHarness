import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';

/// 呵护批0 · v18→v19 迁移与建表种子（交接 §3 数据模型）。
/// 独立文件防 isolate 污染（既有踩坑）。
void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
    for (final sql in DbSchema.migrations[18]!) {
      await db.execute(sql);
    }
  });

  tearDown(() => db.close());

  Future<List<String>> tablesLike(String like) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE ?",
      [like],
    );
    return rows.map((r) => r['name'] as String).toList()..sort();
  }

  group('1 · v19 建表与幂等', () {
    test('migrations[18] 建齐呵护全部表', () async {
      final names = await tablesLike('care_%');
      expect(
        names,
        containsAll(<String>[
          DbSchema.tCareBabies,
          DbSchema.tCareCarers,
          DbSchema.tCareLogs,
          DbSchema.tCareCycleDays,
          DbSchema.tCareCyclePred,
          DbSchema.tCareMeasures,
          DbSchema.tCareVaccines,
          DbSchema.tCareMilestones,
          DbSchema.tCareAllergies,
          DbSchema.tCareCustomEvents,
          DbSchema.tCareEventOrder,
        ]),
      );
    });

    test('重复执行迁移幂等（IF NOT EXISTS / INSERT OR IGNORE）', () async {
      for (final sql in DbSchema.migrations[18]!) {
        await db.execute(sql);
      }
      final carers =
          await db.rawQuery('SELECT COUNT(*) c FROM ${DbSchema.tCareCarers}');
      expect(carers.first['c'], 4);
      final order =
          await db.rawQuery('SELECT COUNT(*) c FROM ${DbSchema.tCareEventOrder}');
      expect(order.first['c'], 13); // 内置 13 类种子序
    });

    test('速记顺序种子=EV_BASE 同序（nurse 首位 custom 末位）', () async {
      final rows = await db
          .query(DbSchema.tCareEventOrder, orderBy: 'sort ASC');
      final keys = rows.map((r) => r['key'] as String).toList();
      expect(keys.first, 'nurse');
      expect(keys.last, 'custom');
      expect(keys.length, 13);
    });
  });

  group('2 · 关键约束', () {
    test('记录人重名被唯一索引拦截', () async {
      await db.insert(DbSchema.tCareCarers, {'name': '外婆', 'sort': 5});
      expect(
        () => db.insert(DbSchema.tCareCarers, {'name': '外婆', 'sort': 6}),
        throwsA(anything),
      );
    });

    test('过敏史按宝宝分档：同宝宝同食物唯一，跨宝宝可重复', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(
          DbSchema.tCareAllergies, {'baby_id': 1, 'food': '鸡蛋', 'created_at': now});
      expect(
        () => db.insert(
            DbSchema.tCareAllergies, {'baby_id': 1, 'food': '鸡蛋', 'created_at': now}),
        throwsA(anything),
      );
      await db.insert(
          DbSchema.tCareAllergies, {'baby_id': 2, 'food': '鸡蛋', 'created_at': now});
      final n = await db
          .rawQuery('SELECT COUNT(*) c FROM ${DbSchema.tCareAllergies}');
      expect(n.first['c'], 2);
    });

    test('周期日 day 主键：同日二次保存为改值不新增', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 2; i++) {
        await db.insert(DbSchema.tCareCycleDays,
            {'day': '2026-09-19', 'state': i == 0 ? '' : 'p1', 'updated_at': now},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final row = (await db.query(DbSchema.tCareCycleDays,
              where: "day = '2026-09-19'"))
          .single;
      expect(row['state'], 'p1');
    });
  });
}
