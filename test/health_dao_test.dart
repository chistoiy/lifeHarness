import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/health.dart' as h;
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_vital.dart';

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
  test('运动：就地改＝按 id 覆盖同一行（同日可多条，改一条不长成两条）', () async {
    final id = await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-01-05', type: '骑行', distanceKm: 10, durationMin: 40, note: '通勤'));
    expect(await repo.updateExercise(ExerciseRecord(id: id, profileId: 1, date: '2026-01-05',
        type: '骑行', distanceKm: 12.5, durationMin: 50, note: '通勤·改')), 1);
    final rows = await repo.exerciseRange(1, '2026-01-01', '2026-01-31');
    expect(rows.length, 1, reason: '运动不按日期唯一，所以改是 update 而不是再插一行');
    expect(rows.single.id, id, reason: '就地改：id 不变，流水那一行不会被替换成新行');
    expect(rows.single.distanceKm, 12.5);
    expect(rows.single.durationMin, 50);
    expect(rows.single.note, '通勤·改');
    // 空列回落与 addExercise 同式：这次没填配速/kcal，按 距离÷时长 与 MET 现算（两处不会算出两个数）。
    expect(rows.single.paceSec, 240);
    expect(rows.single.kcal, 375);
  });

  test('运动删除带档案归属：跨档案删不到别人的行（与体征/身体数据同一道闸）', () async {
    final other = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    final mine = await repo.addExercise(const ExerciseRecord(
        profileId: 1, date: '2026-01-05', type: '跑步', distanceKm: 5, durationMin: 30));
    final theirs = await repo.addExercise(ExerciseRecord(
        profileId: other, date: '2026-01-05', type: '跑步', distanceKm: 8, durationMin: 60));
    expect(await repo.deleteExercise(other, mine), 0, reason: 'profile_id 条件一摘就删掉了别人的行（刀3 靶）');
    expect(await repo.deleteExercise(1, theirs), 0, reason: '反向同样拦：别人的行不在我的归属里');
    expect(
        await repo.updateExercise(ExerciseRecord(
            id: mine, profileId: other, date: '2026-01-05', type: '跑步', distanceKm: 5, durationMin: 99)),
        0,
        reason: '改别人的行同样被归属条件挡住（刀3 的另一半）');
    expect((await repo.exerciseRange(1, '2026-01-01', '2026-01-31')).single.durationMin, 30,
        reason: '两条写路径吃同一道闸，不会一处拦一处放行');
    expect((await repo.exerciseRange(1, '2026-01-01', '2026-01-31')).length, 1);
    expect((await repo.exerciseRange(other, '2026-01-01', '2026-01-31')).length, 1);
    expect(await repo.deleteExercise(1, mine), 1);
    expect(await repo.exerciseRange(1, '2026-01-01', '2026-01-31'), isEmpty);
  });


  test('用药：归档只停用在读，打卡流水与历史档案都还在', () async {
    final id = await repo.addDrug(const DrugPlan(
        profileId: 1, name: '维生素D', times: ['08:00', '20:00'], remind: true));
    await repo.logDrug(DrugLog(
        profileId: 1, drugId: id, date: '2026-01-05', time: '08:00', state: 'taken'));
    expect(await repo.archiveDrug(1, id), 1);

    expect(await repo.drugs(1), isEmpty, reason: '在册列表不再出现');
    final all = await repo.drugs(1, includeArchived: true);
    expect(all.single.archived, isTrue);
    expect(await repo.drugLogs(1, '2026-01-05'), {id: {'08:00': 'taken'}},
        reason: '删除档案≠删除历史（§五.8 与回收站同口径）');

    await repo.logDrug(DrugLog(
        profileId: 1, drugId: id, date: '2026-01-05', time: '08:00', state: 'skipped'));
    expect((await repo.drugLogs(1, '2026-01-05'))[id]!['08:00'], 'skipped',
        reason: '同刻重复打卡＝覆盖状态，不插第二行');
    expect(await countOf(h.tHealthDrugLog), 1, reason: '唯一槽位索引真的在拦第二行');
    expect(await repo.undoDrugLog(1, id, '2026-01-05', '08:00'), 1);
    expect(await repo.drugLogs(1, '2026-01-05'), isEmpty);
  });

  test('用药：改档与归档都带档案归属（刀3 靶＝摘掉 profile_id 就改到别人的药）', () async {
    final other = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    final mine = await repo.addDrug(const DrugPlan(
        profileId: 1, name: '钙片', times: ['08:00'], dose: 1));
    final theirs = await repo.addDrug(DrugPlan(
        profileId: other, name: '降压药', times: const ['21:00'], dose: 2));

    expect(
        await repo.updateDrug(DrugPlan(
            id: mine, profileId: other, name: '改名尝试', times: const ['09:00'])),
        0,
        reason: '用别人的 profile_id 发起改档＝归属条件挡住');
    expect(
        await repo.updateDrug(DrugPlan(
            id: theirs, profileId: 1, name: '覆盖尝试', times: const ['07:00'])),
        0,
        reason: '反向同理：我的档案改不到别人的行');
    expect(await repo.archiveDrug(other, mine), 0, reason: '跨档案停不掉别人的药（刀3）');
    expect(await repo.archiveDrug(1, theirs), 0, reason: '反向同理');
    expect((await repo.drugs(1)).single.name, '钙片', reason: '两条写路径吃同一道闸');
    expect((await repo.drugs(other)).single.archived, isFalse);

    // 本档案内改档成功，且就地改同一行（不插第二份档案）。
    expect(
        await repo.updateDrug(DrugPlan(
            id: mine, profileId: 1, name: '钙片', spec: '600mg', times: const ['08:00', '20:00'])),
        1);
    final rows = await repo.drugs(1);
    expect(rows.length, 1);
    expect(rows.single.spec, '600mg');
    expect(rows.single.times, ['08:00', '20:00']);
  });

  test('用药：总开关只覆写非归档行，单药开关带归属', () async {
    final other = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    final a = await repo.addDrug(const DrugPlan(profileId: 1, name: 'A', times: ['08:00'], remind: true));
    await repo.addDrug(const DrugPlan(profileId: 1, name: 'B', times: ['20:00'], remind: true));
    final c = await repo.addDrug(const DrugPlan(profileId: 1, name: 'C', times: ['12:00'], remind: true));
    await repo.archiveDrug(1, c);

    expect(await repo.setAllDrugRemind(1, false), 2, reason: '覆写行数＝非归档两行（偏离⑤＝全量覆写不记得原状态）');
    final m = {for (final d in await repo.drugs(1, includeArchived: true)) d.name: d.remind};
    expect(m['A'], isFalse);
    expect(m['B'], isFalse);
    expect(m['C'], isTrue, reason: '归档档案不参与总开关（它已不在卡列表里）');

    expect(await repo.setDrugRemind(1, a, true), 1);
    expect((await repo.drugs(1)).firstWhere((d) => d.id == a).remind, isTrue);
    expect(await repo.setDrugRemind(other, a, false), 0, reason: '跨档案改不到别人的提醒位');
    expect(await repo.setAllDrugRemind(other, true), 0, reason: '总开关按档案作用域，不越界覆写');
  });

  test('用药：近 7 天流水一次取数按「日期→药→时刻」分层，跨档案不串味', () async {
    final id = await repo.addDrug(const DrugPlan(profileId: 1, name: '钙片', times: ['08:00', '20:00']));
    await repo.logDrug(DrugLog(profileId: 1, drugId: id, date: '2026-01-01', time: '08:00', state: 'taken'));
    await repo.logDrug(DrugLog(profileId: 1, drugId: id, date: '2026-01-03', time: '20:00', state: 'taken'));
    // 归档之后历史仍要在区间里（热力与批6 趋势都读它）
    final old = await repo.addDrug(const DrugPlan(profileId: 1, name: '旧药', times: ['09:00']));
    await repo.logDrug(DrugLog(profileId: 1, drugId: old, date: '2026-01-02', time: '09:00', state: 'taken'));
    await repo.archiveDrug(1, old);
    // 别的档案 / 区间外的日子都不该出现
    final other = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    final theirs = await repo.addDrug(DrugPlan(profileId: other, name: '降压药', times: const ['21:00']));
    await repo.logDrug(DrugLog(profileId: other, drugId: theirs, date: '2026-01-02', time: '21:00', state: 'taken'));
    await repo.logDrug(DrugLog(profileId: 1, drugId: id, date: '2026-02-01', time: '08:00', state: 'taken'));

    final r = await repo.drugLogRange(1, '2026-01-01', '2026-01-07');
    expect(r.keys.toList()..sort(), ['2026-01-01', '2026-01-02', '2026-01-03'],
        reason: '区间外的日期与别的档案都不出现（热力七格吃这一份）');
    expect(r['2026-01-01'], {id: {'08:00': 'taken'}});
    expect(r['2026-01-02'], {old: {'09:00': 'taken'}}, reason: '归档药的历史不过滤（软删父行藏子记录是本仓踩过的坑）');
    expect(r['2026-01-03']![id]!['20:00'], 'taken');
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
    final drugId = await repo.addDrug(DrugPlan(profileId: id, name: '降压药', times: ['08:00']));
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
    final drugId = await repo.addDrug(const DrugPlan(profileId: 1, name: '钙片', times: ['21:00']));
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

  // ==================== 体征五类（批2.5） ====================

  test('体征跨档案不聚合：读口的 profile_id 一摘就串味（刀1 靶）', () async {
    final other = await repo.saveProfile(
        const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-01-05', time: '07:00', kind: 'bp', sys: 118, dia: 76));
    await repo.saveVital(HealthVital(
        profileId: other, date: '2026-01-05', time: '07:00', kind: 'bp', sys: 145, dia: 92));

    final mine = await repo.vitals(1, '2026-01-01', '2026-01-31');
    expect(mine.single.sys, 118);
    final theirs = await repo.vitals(other, '2026-01-01', '2026-01-31');
    expect(theirs.single.sys, 145);
    // 快照口同口径：按档案各取各的最近一条。
    expect((await repo.latestVitals(1, '2026-01-31'))['bp']?.sys, 118);
    expect((await repo.latestVitals(other, '2026-01-31'))['bp']?.sys, 145);
  });

  test('体征：新增给 id，改是就地改同一行，删除只删这一行', () async {
    final id = await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-01-05', time: '07:00', kind: 'bp', sys: 118, dia: 76, hr: 62));
    expect(await countOf(h.tHealthVital), 1);

    final edited = await repo.vitals(1, '2026-01-01', '2026-01-31');
    await repo.saveVital(HealthVital(
        id: id, profileId: 1, date: '2026-01-05', time: '07:00', kind: 'bp',
        sys: 132, dia: 88, hr: 62, slot: edited.single.slot, note: '复测'));
    final rows = await repo.vitals(1, '2026-01-01', '2026-01-31');
    expect(rows.length, 1, reason: '流水点行就地改：不许插第二行');
    expect(rows.single.sys, 132);
    expect(rows.single.dia, 88, reason: '血压两值都要落库，只回显收缩压会漏掉舒张压');
    expect(rows.single.note, '复测');

    await repo.deleteVital(id);
    expect(await repo.vitals(1, '2026-01-01', '2026-01-31'), isEmpty);
  });

  test('体征窗口＋按类过滤：窗口外的读数进不来', () async {
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-01-05', time: '08:00', kind: 'hr', val: 64));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-01-20', time: '08:00', kind: 'hr', val: 70));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-01-06', time: '08:00', kind: 'temp', val: 36.5));

    final window = await repo.vitals(1, '2026-01-01', '2026-01-10');
    expect(window.map((v) => v.kind), containsAll(['hr', 'temp']));
    expect(window.any((v) => v.val == 70), isFalse, reason: '20 日那条在窗口外');
    final hrOnly = await repo.vitals(1, '2026-01-01', '2026-01-31', kind: 'hr');
    expect(hrOnly.map((v) => v.val), [64.0, 70.0], reason: 'date,time 升序＝曲线自左向右的序');
    expect(hrOnly.every((v) => v.kind == 'hr'), isTrue);
  });

  test('latestVitals：五类齐出定长 map，没记的类留 null，同类取同日最晚一条', () async {
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-01-05', time: '07:00', kind: 'bp', sys: 116, dia: 74));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-01-05', time: '20:30', kind: 'bp', sys: 128, dia: 82));
    await repo.saveVital(const HealthVital(
        profileId: 1, date: '2026-01-03', time: '09:00', kind: 'spo2', val: 98));

    final m = await repo.latestVitals(1, '2026-01-06');
    expect(m.keys.toList(), vitalOrder, reason: '工作台体征条按五类定序，缺类也要占位');
    expect(m['bp']?.sys, 128, reason: '同日多条取最晚那次（晚间值才是「当前」）');
    expect(m['spo2']?.val, 98);
    expect(m['hr'], isNull);
    expect(m['glu'], isNull);
    expect(m['temp'], isNull);
    // 晚于查询日上界的记录不许提前露面
    expect((await repo.latestVitals(1, '2026-01-02'))['bp'], isNull);
  });

  // ==================== 身体数据与目标（批3） ====================

  test('身体数据同日覆盖＝整行替换：这次没填的围度清空，合并在弹层回填（刀2 口径的另一半）', () async {
    await repo.saveBody(const BodyRecord(
        profileId: 1, date: '2026-01-05', kg: 70, heightCm: 175,
        fatPct: 18, waistCm: 76, hipCm: 93, neckCm: 36));
    await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-01-05', kg: 69.5));

    expect(await countOf(h.tHealthBody), 1,
        reason: '唯一索引 (profile_id,date)：同日只可能一行');
    final r = (await repo.bodyRange(1, '2026-01-01', '2026-01-31')).single;
    expect(r.kg, 69.5);
    for (final v in [r.heightCm, r.fatPct, r.waistCm, r.hipCm, r.neckCm]) {
      expect(v, isNull, reason: '仓储层不合并旧值：留空＝留空，「—」回填是弹层的职责');
    }
  });

  test('删除一条测量带 profile 归属：跨档案删不到别人的行（与体征同一道闸）', () async {
    final other = await repo.saveProfile(
        const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-01-05', kg: 70));
    await repo.saveBody(BodyRecord(profileId: other, date: '2026-01-05', kg: 55));
    final mine = (await repo.bodyRange(1, '2026-01-01', '2026-01-31')).single.id!;
    final theirs = (await repo.bodyRange(other, '2026-01-01', '2026-01-31')).single.id!;

    await repo.deleteBody(1, theirs);
    expect(await countOf(h.tHealthBody, where: 'id=$theirs'), 1,
        reason: '只给 id 删不动：where 里的 profile_id 是第二道闸');
    await repo.deleteBody(other, theirs);
    expect(await countOf(h.tHealthBody, where: 'id=$theirs'), 0);
    expect(await countOf(h.tHealthBody, where: 'id=$mine'), 1,
        reason: '删另一档案的行也不许顺手带走本档案的行');
  });

  test('身体数据与目标跨档案不聚合：读数、身高、目标各归各', () async {
    final other = await repo.saveProfile(
        const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-01-05', kg: 70, heightCm: 175));
    await repo.saveBody(BodyRecord(profileId: other, date: '2026-01-05', kg: 55, heightCm: 160));
    await repo.setGoal(other, GoalKeys.weightGoal, 50);

    final mine = await repo.bodyRange(1, '2026-01-01', '2026-01-31');
    expect(mine.single.kg, 70);
    expect(mine.single.heightCm, 175, reason: 'BMI 回落链只看本档案身高，不串到 160');
    expect((await repo.latestBody(1, '2026-01-31'))?.kg, 70);
    expect(await repo.goals(1), isEmpty, reason: '另一档案设的目标体重不进本档案');
    expect((await repo.goals(other))[GoalKeys.weightGoal], 50);
  });

  // ==================== 症状（批3.5a） ====================

  test('症状同日可多条：表无唯一索引，两次 INSERT 长两行（同日覆盖会把下午与夜里并成一条）', () async {
    await repo.addSymptom(const SymptomRecord(
        profileId: 1, date: '2026-01-05', time: '14:00', name: '头痛', level: 3));
    await repo.addSymptom(const SymptomRecord(
        profileId: 1, date: '2026-01-05', time: '21:00', name: '头痛', level: 6));
    final rows = await repo.symptoms(1);
    expect(rows.length, 2);
    expect(rows.map((r) => r.time), ['14:00', '21:00'],
        reason: '取数按 date/id 升序，「最新在上」是 UI 侧 symListDesc 的事');
  });

  test('症状多部位与照片往返：库里逗号连接＋JSON，读回不丢第二枚；脏值吞成空而不是炸', () async {
    final id = await repo.addSymptom(const SymptomRecord(profileId: 1,
        date: '2026-01-05', name: '腹痛', parts: ['头部', '四肢'], photos: ['a.jpg', 'b.jpg']));
    final r = (await repo.symptoms(1)).single;
    expect(r.id, id);
    expect(r.parts, ['头部', '四肢'], reason: '原型只取第一枚，本实现全量存');
    expect(r.photos, ['a.jpg', 'b.jpg']);

    await db.update(h.tHealthSymptom, {'parts': '头部,,', 'photos': '{bad json'});
    final dirty = (await repo.symptoms(1)).single;
    expect(dirty.parts, ['头部'], reason: '多余的逗号只丢空段，不炸整张流水');
    expect(dirty.photos, isEmpty, reason: '坏 photos 按「无图」处理（catch-ok 只在这一处）');
  });

  test('症状就地改与删除都带档案归属：别人的 profile_id 拿去动我的行，一道闸就挡住', () async {
    final other = await repo.saveProfile(const HealthProfile(id: 0, name: '小明', rel: '子'));
    final id = await repo.addSymptom(const SymptomRecord(
        profileId: 1, date: '2026-01-05', name: '头痛', level: 4, durationMin: 30, ongoing: true));
    expect(
        await repo.updateSymptom(SymptomRecord(
            id: id, profileId: other, date: '2026-01-05', name: '冒充', level: 9)),
        0);
    expect(await repo.deleteSymptom(other, id), 0);
    final r = (await repo.symptoms(1)).single;
    expect(r.name, '头痛');
    expect(r.level, 4);
    expect(await repo.deleteSymptom(1, id), 1);
    expect(await repo.symptoms(1), isEmpty);
  });

  test('标记结束＝ongoing 落下且时长 +15 一次写完；建档时间不被编辑冲成现在', () async {
    final id = await repo.addSymptom(const SymptomRecord(
        profileId: 1, date: '2026-01-05', name: '胸闷', level: 5, durationMin: 45, ongoing: true));
    final loaded = (await repo.symptoms(1)).single;
    await repo.endSymptom(loaded);
    final row = await db.query(h.tHealthSymptom, where: 'id=?', whereArgs: [id]);
    expect(row.single['ongoing'], 0);
    expect(row.single['duration_min'], 60);
    expect(row.single['created_at'], loaded.createdAt, reason: 'update 写回模型原值，不是 now');
  });

  test('档案删除级联清掉症状行：healthTables 少登记一张就留孤儿', () async {
    final id = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    await repo.addSymptom(SymptomRecord(profileId: id, date: '2026-01-05', name: '头痛', level: 2));
    await repo.deleteProfile(id);
    expect(await countOf(h.tHealthSymptom, where: 'profile_id=$id'), 0);
  });

  // ==================== 检查报告与检验项（批3.5b） ====================

  test('报告拼包一次到位：父行按档案隔离、子项挂在各自父行下', () async {
    final mine = await repo.addReport(const HealthReport(
        profileId: 1, date: '2026-01-05', name: '血常规', files: ['a.pdf'], kind: 'pdf'));
    await repo.addMetric(ReportMetric(
        reportId: mine, name: '血红蛋白', value: 100, unit: 'g/L', refLo: 115, refHi: 150));
    final theirs = await repo.addReport(const HealthReport(
        profileId: 2, date: '2026-01-06', name: '别人的报告', files: ['x.pdf'], kind: 'pdf'));
    await repo.addMetric(ReportMetric(reportId: theirs, name: '尿蛋白', value: 1));

    final bs = await repo.reportBundles(1);
    expect(bs, hasLength(1), reason: '别人的父行不该混进我的读数');
    expect(bs.single.report.name, '血常规');
    // files 与 kind 走 JSON 往返：库里一列文本，读回还是列表。
    expect(bs.single.report.files, ['a.pdf']);
    expect(bs.single.report.kind, 'pdf');
    expect(bs.single.metrics.map((e) => e.name).toList(), ['血红蛋白']);
    expect(bs.single.abnormalCount, 1, reason: '100 落在 115~150 之外＝偏低');

    // 没有检验项的报告也要成包（卡片要出「尚未录入检验项」，而不是整张报告消失）。
    final bare = await repo.addReport(const HealthReport(
        profileId: 1, date: '2026-01-07', name: '体检', files: []));
    final bs2 = await repo.reportBundles(1);
    expect(bs2.map((b) => b.report.id).toList(), contains(bare));
    expect(bs2.firstWhere((b) => b.report.id == bare).metrics, isEmpty);
    expect(await repo.reportBundles(3), isEmpty, reason: '空档案出空列表，不出 null');
  });

  test('检验项位次＝现有 MAX+1：追加在尾、删中间不回填空洞', () async {
    final rid = await repo.addReport(const HealthReport(
        profileId: 1, date: '2026-01-05', name: '血常规'));
    final a = await repo.addMetric(ReportMetric(reportId: rid, name: '甲', value: 1));
    await repo.addMetric(ReportMetric(reportId: rid, name: '乙', value: 2));
    await repo.addMetric(ReportMetric(reportId: rid, name: '丙', value: 3));
    expect((await repo.metrics(rid)).map((e) => e.sort).toList(), [0, 1, 2],
        reason: '原型 r.ms.push＝新项永远排最后；回读按 sort ASC 才不会把「刚录的」插进中间');

    await repo.deleteMetric(rid, a);
    final d = await repo.addMetric(ReportMetric(reportId: rid, name: '丁', value: 4));
    expect((await repo.metrics(rid)).map((e) => e.sort).toList(), [1, 2, 3],
        reason: 'MAX+1 不回收空洞：位次只表示录入先后，不是行号');
    expect((await repo.metrics(rid)).map((e) => e.id).toList(), contains(d));
  });

  test('删报告＝归属双闸＋连带清检验项；跨档案的 id 动不了我的行', () async {
    final rid = await repo.addReport(const HealthReport(
        profileId: 1, date: '2026-01-05', name: '血常规'));
    await repo.addMetric(ReportMetric(reportId: rid, name: '血红蛋白', value: 100));
    await repo.addMetric(ReportMetric(reportId: rid, name: '白细胞', value: 6.5));

    expect(await repo.deleteReport(2, rid), 0, reason: 'profile_id 不匹配就删不到');
    expect(await countOf(h.tHealthReportMetric, where: 'report_id=$rid'), 2,
        reason: '父行没删动，子行一枚都不该被连带清掉');

    expect(await repo.deleteReport(1, rid), 1);
    expect(await countOf(h.tHealthReport, where: 'id=$rid'), 0);
    expect(await countOf(h.tHealthReportMetric, where: 'report_id=$rid'), 0,
        reason: '不留「报告没了、检验项还在表里」的孤儿行');
  });

  test('检验项删除带归属闸：拿别人的 report_id 动我的行，一道闸就挡住', () async {
    final mine = await repo.addReport(const HealthReport(
        profileId: 1, date: '2026-01-05', name: '我的'));
    final other = await repo.addReport(const HealthReport(
        profileId: 1, date: '2026-01-06', name: '另一份'));
    final mid = await repo.addMetric(ReportMetric(reportId: mine, name: '血红蛋白', value: 100));
    expect(await repo.deleteMetric(other, mid), 0, reason: 'id 对但归属错＝删不动');
    expect(await countOf(h.tHealthReportMetric, where: 'id=$mid'), 1);
    expect(await repo.deleteMetric(mine, mid), 1);
  });

  test('坏 files 列按「无附件」读，不炸整张报告列表', () async {
    final rid = await repo.addReport(const HealthReport(
        profileId: 1, date: '2026-01-05', name: '血常规', files: ['a.pdf']));
    await db.update(h.tHealthReport, {'files': '{bad json'}, where: 'id=?', whereArgs: [rid]);
    final r = (await repo.reports(1)).single;
    expect(r.files, isEmpty, reason: '一条脏数据不该把归档轴与统计一起带崩');
    expect(r.name, '血常规');
  });

  test('档案删除级联清掉报告与检验项两张表：healthTables 少登记一张就留孤儿', () async {
    final pid = await repo.saveProfile(const HealthProfile(id: 0, name: '妈妈', rel: '母'));
    final rid = await repo.addReport(HealthReport(profileId: pid, date: '2026-01-05', name: '血常规'));
    await repo.addMetric(ReportMetric(reportId: rid, name: '血红蛋白', value: 100));
    await repo.deleteProfile(pid);
    expect(await countOf(h.tHealthReport, where: 'profile_id=$pid'), 0);
    expect(await countOf(h.tHealthReportMetric, where: 'report_id=$rid'), 0,
        reason: '检验项只挂 report_id，删档案时必须先按父表反查清掉，否则永远查不到也删不掉');
  });

  // ==================== 批6a · trendDays 区间一次取数 ====================

  group('trendDays 逐日出格（批6a）', () {
    test('区间内一天一格：空日出 null 格、运动同日求和、睡眠同日取最后一条、配速收集', () async {
      await repo.bumpCups(1, '2026-01-02', 3);
      await repo.saveSleep(const SleepRecord(
          profileId: 1, date: '2026-01-02', bedTime: '23:00', wakeTime: '07:00', durationMin: 0));
      await repo.addExercise(const ExerciseRecord(
          profileId: 1, date: '2026-01-02', type: '跑步', distanceKm: 5, durationMin: 30));
      await repo.addExercise(const ExerciseRecord(
          profileId: 1, date: '2026-01-02', type: '骑行', distanceKm: 10, durationMin: 40));
      await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-01-04', kg: 70));

      final days = await repo.trendDays(1, '2026-01-01', '2026-01-05');
      expect(days.map((d) => d.date),
          ['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04', '2026-01-05'],
          reason: '旧→新逐日出格，缺记录日也占一格（热力才数得出空格）');

      final empty = days.first;
      expect([empty.cups, empty.sleepMin, empty.exMin, empty.kg, empty.medPlanned, empty.medTaken],
          [null, null, null, null, null, null]);
      expect(empty.recorded, isFalse, reason: '整日缺席＝null 格，不补 0 假点');

      final d2 = days[1];
      expect(d2.cups, 3);
      expect(d2.sleepMin, 480);
      expect(d2.exMin, 70, reason: '同日两条运动求和（六指标共用一条流水，不再按 chip 各开查询）');
      expect(d2.paces, [360, 240], reason: '跑步 5k/30min→360″、骑行 10k/40min→240″（周报取均值）');
      expect(d2.kg, isNull);
      expect(d2.medPlanned, isNull);

      expect(days[3].kg, 70);
      expect(days[3].exMin, isNull);
    });

    test('同日多条睡眠取最后写入（与原型「一条为准」同形）', () async {
      await repo.saveSleep(const SleepRecord(
          profileId: 1, date: '2026-01-06', bedTime: '23:00', wakeTime: '06:00', durationMin: 0));
      await repo.saveSleep(const SleepRecord(
          profileId: 1, date: '2026-01-06', bedTime: '23:30', wakeTime: '07:30', durationMin: 0));
      final d = (await repo.trendDays(1, '2026-01-06', '2026-01-06')).single;
      expect(d.sleepMin, 480, reason: '按 date ASC 覆盖读数，最后一条为准');
    });

    test('归档药只在当日有流水时计进依从分母（批5 §2 偏离②的前置兑现）', () async {
      final active = await repo.addDrug(
          const DrugPlan(profileId: 1, name: '钙片', times: ['08:00', '20:00']));
      final old = await repo.addDrug(
          const DrugPlan(profileId: 1, name: '旧药', times: ['09:00']));
      await repo.logDrug(DrugLog(
          profileId: 1, drugId: active, date: '2026-01-02', time: '08:00', state: 'taken'));
      await repo.logDrug(DrugLog(
          profileId: 1, drugId: old, date: '2026-01-02', time: '09:00', state: 'taken'));
      await repo.logDrug(DrugLog(
          profileId: 1, drugId: active, date: '2026-01-04', time: '20:00', state: 'taken'));
      expect(await repo.archiveDrug(1, old), 1);

      final days = await repo.trendDays(1, '2026-01-01', '2026-01-04');
      // 01-01：整日无任何流水 → 依从缺席（null），曲线不画假点；在册药不当分母
      expect(days.first.medPlanned, isNull);
      expect(days.first.medTaken, isNull);
      expect(days.first.medRate, isNull);
      // 01-02：归档药有当日流水 → 计进分母，历史依从不被多年前停用的药拖着失真
      expect(days[1].medPlanned, 3, reason: '在册 2 时刻＋归档当日在场 1 时刻');
      expect(days[1].medTaken, 2);
      expect(days[1].medRate, 67);
      // 01-03：无任何流水，即便在册钙片天天有计划也不出格（口径＝有交代的日子才参与依从轴）
      expect(days[2].medPlanned, isNull, reason: '分母只在当日有该药流水时计——无流水日整格缺席');
      // 01-04：只有在册药有流水 → 分母＝2（归档药那日无流水不计）
      expect(days[3].medPlanned, 2);
      expect(days[3].medTaken, 1);
    });

    test('跨档案不串：另一档案的杯数与药都读进不来', () async {
      final other = await repo.saveProfile(
          const HealthProfile(id: 0, name: '妈妈', rel: '母'));
      await repo.bumpCups(1, '2026-01-02', 3);
      await repo.bumpCups(other, '2026-01-02', 9);
      final theirDrug = await repo.addDrug(
          DrugPlan(profileId: other, name: '降压药', times: const ['21:00']));
      await repo.logDrug(DrugLog(
          profileId: other, drugId: theirDrug, date: '2026-01-02', time: '21:00', state: 'taken'));

      final mine = await repo.trendDays(1, '2026-01-02', '2026-01-02');
      expect(mine.single.cups, 3);
      expect(mine.single.medPlanned, isNull, reason: '别人的药不给我的依从率当分母');
      final theirs = await repo.trendDays(other, '2026-01-02', '2026-01-02');
      expect(theirs.single.cups, 9);
      expect(theirs.single.medPlanned, 1);
      expect(theirs.single.medTaken, 1);
    });
  });

  group('导出取数（批6b）', () {
    test('五类一次取齐并按日期升序、同日按固定内序（喝水·睡眠·运动·身体·用药）', () async {
      await repo.bumpCups(1, '2026-01-05', 3);
      await repo.saveSleep(const SleepRecord(
          profileId: 1, date: '2026-01-05', bedTime: '23:00', wakeTime: '07:00', durationMin: 0));
      await repo.addExercise(const ExerciseRecord(
          profileId: 1, date: '2026-01-05', type: '跑步', distanceKm: 5, durationMin: 30));
      await repo.saveBody(const BodyRecord(profileId: 1, date: '2026-01-05', kg: 70, heightCm: 175));
      final drugId = await repo.addDrug(
          DrugPlan(profileId: 1, name: '阿司匹林', times: const ['08:00']));
      await repo.logDrug(DrugLog(
          profileId: 1, drugId: drugId, date: '2026-01-05', time: '08:00', state: 'taken'));
      await repo.bumpCups(1, '2026-01-04', 2);

      final rows = await repo.exportRows(1, '2026-01-01', '2026-01-31');
      expect(rows.map((e) => e.date).toList(),
          ['2026-01-04', '2026-01-05', '2026-01-05', '2026-01-05', '2026-01-05', '2026-01-05'],
          reason: '日期升序；缺记录日不占位（01-02/03 整日缺席）');
      expect(rows.skip(1).map((e) => e.kind).toList(),
          ['喝水', '睡眠', '运动', '身体', '用药']);
      final sleep = rows.firstWhere((e) => e.kind == '睡眠');
      expect(sleep.value, '480 分钟', reason: '时长用写入侧算好的值，跨天不重算');
      expect(sleep.detail, '入睡 23:00 · 醒 07:00');
      final ex = rows.firstWhere((e) => e.kind == '运动');
      expect(ex.detail, contains('跑步'));
      expect(ex.detail, contains('5.0 km'));
      expect(ex.detail, contains('6′00″'), reason: '配速按存储的公制秒算出展示串');
      expect(rows.firstWhere((e) => e.kind == '用药').detail, '阿司匹林');
    });

    test('导出恒公制：屏上单位切换不进文件（同一列不许两种单位）', () async {
      await repo.addExercise(const ExerciseRecord(
          profileId: 1, date: '2026-01-05', type: '骑行', distanceKm: 10, durationMin: 40));
      final rows = await repo.exportRows(1, '2026-01-01', '2026-01-31');
      expect(rows.single.detail, contains('km'), reason: '不是 mile');
    });

    test('归档用药的历史打卡照样进流水（删除档案保留历史＝需求口径）', () async {
      final drugId = await repo.addDrug(
          DrugPlan(profileId: 1, name: '旧药', times: const ['21:00']));
      await repo.logDrug(DrugLog(
          profileId: 1, drugId: drugId, date: '2026-01-02', time: '21:00', state: 'skipped'));
      await repo.archiveDrug(1, drugId);

      final rows = await repo.exportRows(1, '2026-01-01', '2026-01-31');
      expect(rows, hasLength(1));
      expect(rows.single.value, '跳过');
      expect(rows.single.detail, '旧药', reason: '归档只停父行，流水读侧不过滤');
    });

    test('跨档案不串：别人的流水不出现在我的导出里', () async {
      final other = await repo.saveProfile(
          const HealthProfile(id: 0, name: '妈妈', rel: '母'));
      await repo.bumpCups(1, '2026-01-05', 3);
      await repo.bumpCups(other, '2026-01-05', 9);
      final mine = await repo.exportRows(1, '2026-01-01', '2026-01-31');
      expect(mine, hasLength(1));
      expect(mine.single.value, '3 杯');
      final theirs = await repo.exportRows(other, '2026-01-01', '2026-01-31');
      expect(theirs.single.value, '9 杯');
    });

    test('区间边界闭开：to 之外的日子不捞', () async {
      await repo.bumpCups(1, '2026-01-05', 1);
      await repo.bumpCups(1, '2026-02-01', 1);
      final rows = await repo.exportRows(1, '2026-01-01', '2026-01-31');
      expect(rows, hasLength(1));
      expect(rows.single.date, '2026-01-05');
    });
  });
}
