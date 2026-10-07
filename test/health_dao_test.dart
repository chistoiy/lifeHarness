import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/health.dart' as h;
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';

/// 批0/批1 · 健康仓储：档案隔离、同日覆盖、归档保留流水、级联删除、目标 upsert。
/// 独立文件防 isolate 污染（AGENTS 门禁段）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late HealthRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
  });

  tearDown(() => db.close());

  Future<int> countOf(String table, {String? where, List<Object?>? args}) =>
      db.rawQuery('SELECT COUNT(*) c FROM $table'
          '${where == null ? '' : ' WHERE $where'}', args)
          .then((r) => r.first['c'] as int);

  test('「本人」档案随建表种子在位且 id 钉死 1', () async {
    final ps = await repo.profiles();
    expect(ps.map((p) => p.id), contains(h.selfProfileId));
    expect(ps.firstWhere((p) => p.id == h.selfProfileId).rel, '本人');
  });

  test('喝水就地累加与撤销，下限 0（撤销不弹确认、不出现负数）', () async {
    expect(await repo.bumpCups(1, '2026-01-05', 1), 1);
    expect(await repo.bumpCups(1, '2026-01-05', 1), 2);
    expect(await repo.bumpCups(1, '2026-01-05', -1), 1);
    expect(await repo.bumpCups(1, '2026-01-05', -9), 0);
    expect(await repo.cupsOf(1, '2026-01-05'), 0);
    expect(await countOf(h.tHealthWater, where: "date='2026-01-05'"), 1,
        reason: '一天一行，靠 replace 覆盖而不是插多行');
  });

  test('跨档案不聚合：另一档案的杯数不进「本人」的读数', () async {
    final other = await repo.saveProfile(
        const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    await repo.bumpCups(1, '2026-01-05', 3);
    await repo.bumpCups(other, '2026-01-05', 7);
    expect(await repo.cupsOf(1, '2026-01-05'), 3);
    expect(await repo.cupsOf(other, '2026-01-05'), 7);
    final w = await repo.waterRange(other, '2026-01-01', '2026-01-31');
    expect(w.single.cups, 7);
  });

  test('睡眠：时长在写入侧算一次（跨天 +1440），读取侧直接用', () async {
    await repo.saveSleep(const SleepRecord(
        profileId: 1, date: '2026-01-06', bedTime: '23:00', wakeTime: '07:00', durationMin: 0));
    final rows = await repo.sleepRange(1, '2026-01-01', '2026-01-31');
    expect(rows.single.durationMin, 480);
    expect(rows.single.hasStages, isFalse);
    final n = await repo.lastNight(1, '2026-01-06');
    expect(n?.date, '2026-01-06');
    expect(await repo.lastNight(1, '2026-01-05'), isNull,
        reason: '归属日＝醒来日，早于它的查询不该捞到这条');
  });

  test('身体数据同日重记＝覆盖（唯一索引），历史不留第二行', () async {
    await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-01-05', kg: 70, heightCm: 175));
    await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-01-05', kg: 69.5));
    final rows = await repo.bodyRange(1, '2026-01-01', '2026-01-31');
    expect(rows.length, 1);
    expect(rows.single.kg, 69.5);
    expect(rows.single.heightCm, isNull,
        reason: '覆盖＝整行替换，不合并旧值（身高这次没填就是没填）');
    expect((await repo.latestBody(1, '2026-01-31'))?.kg, 69.5);
  });

  test('运动：kcal/配速留空按口径补算，用户填了以填的为准', () async {
    await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-01-05', type: '跑步', distanceKm: 5, durationMin: 30));
    await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-01-06', type: '力量', durationMin: 40, kcal: 999));
    final rs = await repo.exerciseRange(1, '2026-01-01', '2026-01-31');
    final run = rs.firstWhere((e) => e.type == '跑步');
    expect(run.paceSec, 360);
    expect(run.kcal, 315);
    final strength = rs.firstWhere((e) => e.type == '力量');
    expect(strength.kcal, 999, reason: '用户填的值不被 MET 覆盖');
    expect(strength.paceSec, isNull, reason: '无距离类算不出配速，留空不编造');
    expect(strength.countsAsSession, isTrue);
  });

  test('用药：归档只停用在读，打卡流水与历史档案都还在', () async {
    final id = await repo.saveDrug(const DrugPlan(
        profileId: 1, name: '维生素D', times: ['08:00', '20:00'], remind: true));
    await repo.logDrug(DrugLog(
        profileId: 1, drugId: id, date: '2026-01-05', time: '08:00', state: 'taken'));
    await repo.archiveDrug(id);

    expect(await repo.drugs(1), isEmpty, reason: '在册列表不再出现');
    final all = await repo.drugs(1, includeArchived: true);
    expect(all.single.archived, isTrue);
    expect(await repo.drugLogs(1, '2026-01-05'), {id: {'08:00': 'taken'}},
        reason: '删除档案≠删除历史（§五.8 与回收站同口径）');

    await repo.logDrug(DrugLog(
        profileId: 1, drugId: id, date: '2026-01-05', time: '08:00', state: 'skipped'));
    expect((await repo.drugLogs(1, '2026-01-05'))[id]!['08:00'], 'skipped',
        reason: '同刻重复打卡＝覆盖状态，不插第二行');
    await repo.undoDrugLog(id, '2026-01-05', '08:00');
    expect(await repo.drugLogs(1, '2026-01-05'), isEmpty);
  });

  test('目标：同键重复设置只留一行（改目标不动历史记录）', () async {
    await repo.setGoal(1, GoalKeys.water, 8);
    await repo.setGoal(1, GoalKeys.water, 10);
    await repo.setGoal(1, GoalKeys.sleep, 7.5);
    final g = await repo.goals(1);
    expect(g[GoalKeys.water], 10);
    expect(g[GoalKeys.sleep], 7.5);
    expect(await countOf(h.tHealthGoal), 2);
  });

  test('档案删除＝级联清全部健康数据；「本人」不可删', () async {
    final id = await repo.saveProfile(const HealthProfile(id: 0, name: '爸爸', rel: '父'));
    await repo.bumpCups(id, '2026-01-05', 4);
    await repo.saveBody(BodyRecord(profileId: id, date: '2026-01-05', kg: 80));
    final drugId = await repo.saveDrug(DrugPlan(profileId: id, name: '降压药', times: ['08:00']));
    await repo.logDrug(DrugLog(
        profileId: id, drugId: drugId, date: '2026-01-05', time: '08:00', state: 'taken'));

    await repo.deleteProfile(id);
    expect(await countOf(h.tHealthProfile, where: 'id=$id'), 0);
    expect(await countOf(h.tHealthWater, where: 'profile_id=$id'), 0);
    expect(await countOf(h.tHealthBody, where: 'profile_id=$id'), 0);
    expect(await countOf(h.tHealthDrug, where: 'profile_id=$id'), 0);
    expect(await countOf(h.tHealthDrugLog, where: 'profile_id=$id'), 0,
        reason: '级联：子流水靠父档案反查清掉');
    // 「本人」的数据一行都不许被牵连
    expect(await countOf(h.tHealthProfile, where: 'id=1'), 1);

    await expectLater(repo.deleteProfile(h.selfProfileId), throwsStateError);
  });

  test('工作台快照一次取齐五类（避免各卡各读出现错位）', () async {
    await repo.bumpCups(1, '2026-01-05', 3);
    await repo.saveSleep(const SleepRecord(
        profileId: 1, date: '2026-01-05', bedTime: '23:10', wakeTime: '06:40', durationMin: 0));
    await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-01-05', type: '步行', durationMin: 25));
    await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-01-05', kg: 68));
    final drugId = await repo.saveDrug(const DrugPlan(profileId: 1, name: '钙片', times: ['21:00']));
    await repo.logDrug(DrugLog(
        profileId: 1, drugId: drugId, date: '2026-01-05', time: '21:00', state: 'taken'));

    final t = await repo.today(1, '2026-01-05');
    expect(t.cups, 3);
    expect(t.sleepMin, 450);
    expect(t.exerciseMin, 25);
    expect(t.exerciseCount, 1);
    expect(t.kg, 68);
    expect(t.plannedSlots, 1);
    expect(t.takenSlots, 1);
    expect(t.score(waterGoalCups: 8, sleepGoalHours: 8), 73,
        reason: '喝水 3/8×40=15 ＋ 睡眠 450/480×35=32.8125 ＋ 运动满 25 ＝ 72.8125 → 四舍五入 73');
  });
}
