import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/health.dart' as h;

/// v36→v37 健康建表闸 + 两条结构红线（跨档案隔离 / 派生不落库）。
/// 独立文件：全 app 点火类用例混跑会 isolate 污染。
void main() {
  sqfliteFfiInit();

  late Database db;
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  Future<Set<String>> tables() async => (await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
      .map((r) => r['name'] as String)
      .toSet();

  Future<Set<String>> cols(String table) async => (await db.rawQuery('PRAGMA table_info($table)'))
      .map((r) => r['name'] as String)
      .toSet();

  test('版本号已到 37，且 36→37 段就是健康建表', () {
    expect(DbSchema.version, 37);
    expect(DbSchema.migrations.containsKey(36), isTrue,
        reason: '缺这段＝老库升级时不会建健康表（新装库有、老库没有＝最坏的一种不一致）');
  });

  test('老库跑 mig[36]：14 张表齐、既有表与数据不动、「本人」档案落种子', () async {
    await db.execute('CREATE TABLE todos (id INTEGER PRIMARY KEY, title TEXT)');
    await db.execute("INSERT INTO todos(title) VALUES('旧库里的一条待办')");

    for (final sql in DbSchema.migrations[36]!) {
      await db.execute(sql);
    }

    final t = await tables();
    for (final name in h.healthTables) {
      expect(t, contains(name), reason: '$name 未随 v37 建出');
    }
    expect(h.healthTables, hasLength(14));
    final old = await db.query('todos');
    expect(old.single['title'], '旧库里的一条待办', reason: '迁移绝不碰别的模块');
    final self = await db.query(h.tHealthProfile, where: 'id=${h.selfProfileId}');
    expect(self.single['rel'], '本人');
    // 种子幂等：重复跑不该插出第二个「本人」
    for (final sql in DbSchema.migrations[36]!) {
      await db.execute(sql);
    }
    expect(await db.query(h.tHealthProfile, where: 'id=${h.selfProfileId}'), hasLength(1));
  });

  test('结构红线①：每张记录表都带 profile_id（跨档案不聚合的前提）', () async {
    for (final sql in h.healthSchemaStatements) {
      await db.execute(sql);
    }
    // 两处例外：档案表自己（它就是主体）、报告子表（靠 report_id 反查，且随档案级联删）。
    final noProfile = {h.tHealthProfile, h.tHealthReportMetric};
    for (final name in h.healthTables) {
      if (noProfile.contains(name)) continue;
      expect(await cols(name), contains('profile_id'),
          reason: '$name 缺 profile_id＝档案切换后会串数据');
    }
  });

  test('结构红线②：派生量不落库（毫升/达标度/分期占比都不许建列）', () async {
    for (final sql in h.healthSchemaStatements) {
      await db.execute(sql);
    }
    expect(await cols(h.tHealthWater), {'profile_id', 'date', 'cups', 'updated_at'},
        reason: '喝水只存杯数，毫升由 cupMl 在展示层换算（§2.2）');
    final body = await cols(h.tHealthBody);
    for (final banned in ['bmi', 'score', 'delta']) {
      expect(body.any((c) => c.contains(banned)), isFalse, reason: '$banned 属派生值，不落库');
    }
    // 唯一例外：配速与 kcal 保存时算一次（用户可改），睡眠时长写入侧算一次。
    final ex = await cols(h.tHealthExercise);
    expect(ex, containsAll(['pace_sec', 'kcal']));
    expect(await cols(h.tHealthSleep), contains('duration_min'));
  });

  test('列名避开 SQL 关键词（trigger/desc 已改 trig/desc_txt）', () async {
    for (final sql in h.healthSchemaStatements) {
      await db.execute(sql);
    }
    final sym = await cols(h.tHealthSymptom);
    expect(sym, containsAll(['trig', 'desc_txt']));
    expect(sym.intersection({'trigger', 'desc'}), isEmpty);
  });
}
