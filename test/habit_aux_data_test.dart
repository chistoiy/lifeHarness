import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/features/habit/domain/habit_dict.dart';
import 'package:lifeharness/features/habit/domain/habit_entry.dart';

/// 习惯批2 · 触发/宽限/字典迁移/目标历史（习惯计划 §2.1 九表 / §4 批2 验收）。
/// 独立文件防 isolate 污染（既有踩坑）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late HabitRepository repo;

  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

  Future<Habit> newHabit({
    String name = '跑步',
    String type = Habit.kPos,
    String? unit,
    double? goal,
    int negLimit = 0,
    String? groupRule,
    List<HabitSub> subs = const [],
    String cat = '健康',
    int backStart = 60,
  }) => repo.saveHabit(
    Habit(
      name: name,
      type: type,
      unit: unit,
      goal: goal,
      negLimit: negLimit,
      groupRule: groupRule,
      subs: subs,
      cat: cat,
      startDate: key(backStart),
    ),
  );

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
    );
    for (final sql in [...DbSchema.habitSchemaStatements, ...DbSchema.habitAuxSchemaStatements]) {
      await db.execute(sql);
    }
    repo = HabitRepository(db);
  });
  tearDown(() => db.close());

  group('1 · v17 辅四表', () {
    test('migrations[16] 建 slips/freezes/goal_hist/pend·幂等可重跑', () async {
      for (final sql in DbSchema.migrations[16]!) {
        await db.execute(sql);
      }
      final names = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'habit%'",
          ))
          .map((r) => r['name'] as String)
          .toList();
      expect(
        names,
        containsAll([
          'habit_slips',
          'habit_freezes',
          'habit_goal_hist',
          'habit_pend',
        ]),
      );
    });
  });

  group('2 · 组规则 half 联调（§4 批2 验收）', () {
    test('3 子项填 2 项：half 判达成、all 判不达成', () async {
      final subs = [
        const HabitSub(name: '深蹲', unit: '个', goal: 20),
        const HabitSub(name: '跑步', unit: '分钟', goal: 20),
        const HabitSub(name: '俯卧撑', unit: '个', goal: 30),
      ];
      final half = await newHabit(name: '健身A', groupRule: Habit.kRuleHalf, subs: subs);
      final all = await newHabit(name: '健身B', groupRule: Habit.kRuleAll, subs: subs);
      // 重新取回带 id 的子项
      final halfSaved = (await repo.habitById(half.id))!;
      final allSaved = (await repo.habitById(all.id))!;
      final vHalf = {
        halfSaved.subs[0].id: 25.0,
        halfSaved.subs[1].id: 22.0,
        halfSaved.subs[2].id: 0.0,
      };
      final vAll = {
        allSaved.subs[0].id: 25.0,
        allSaved.subs[1].id: 22.0,
        allSaved.subs[2].id: 0.0,
      };
      await repo.upsertEntry(half.id, day: key(0), checked: true, subValues: vHalf);
      await repo.upsertEntry(all.id, day: key(0), checked: true, subValues: vAll);
      expect(
        habitOkAt(halfSaved, (await repo.entriesOf(half.id))[key(0)]),
        isTrue,
      );
      expect(
        habitOkAt(allSaved, (await repo.entriesOf(all.id))[key(0)]),
        isFalse,
      );
    });
  });

  group('3 · 字典改名迁移与删除守卫（§2.1 habit_dict）', () {
    test('分类改名同步 habits.cat；引用>0 禁删；迁移并删除成功', () async {
      final h = await newHabit(name: '晨跑', cat: '健康');
      final cats = await repo.dictOf(HabitDict.kCat);
      final health = cats.firstWhere((c) => c.name == '健康');
      final ok = await repo.renameDict(HabitDict.kCat, health.id, '体能');
      expect(ok, isTrue);
      expect((await repo.habitById(h.id))!.cat, '体能');
      expect(await repo.dictRefCount(HabitDict.kCat, '体能'), 1);
      // 仍被引用 → 守卫拦截（UI 依据 refCount 拒绝直接删）
      final tizhi = (await repo.dictOf(HabitDict.kCat)).firstWhere((c) => c.name == '体能');
      expect(await repo.dictRefCount(HabitDict.kCat, '体能') > 0, isTrue);
      // 迁移到「生活」后引用清零并可删除
      final n = await repo.mergeDict(HabitDict.kCat, '体能', '生活');
      expect(n, 1);
      expect((await repo.habitById(h.id))!.cat, '生活');
      expect(await repo.dictOf(HabitDict.kCat), isNot(contains(tizhi.name)));
      expect(await repo.dictRefCount(HabitDict.kCat, '生活'), 1);
    });

    test('单位改名同步 habits.unit 与 habit_subs.unit；同名拒绝', () async {
      final h = await newHabit(
        name: '健身组',
        unit: '分钟',
        groupRule: Habit.kRuleAny,
        subs: [const HabitSub(name: '深蹲', unit: '分钟', goal: 10)],
      );
      final saved = (await repo.habitById(h.id))!;
      final units = await repo.dictOf(HabitDict.kUnit);
      final min = units.firstWhere((u) => u.name == '分钟');
      expect(await repo.renameDict(HabitDict.kUnit, min.id, '分钟'), isFalse);
      expect(await repo.renameDict(HabitDict.kUnit, min.id, '个'), isFalse); // 与既有单位同名
      expect(await repo.renameDict(HabitDict.kUnit, min.id, 'mins'), isTrue);
      final after = (await repo.habitById(h.id))!;
      expect(after.unit, 'mins');
      expect(after.subs.first.unit, 'mins');
      expect(await repo.dictRefCount(HabitDict.kUnit, 'mins'), 2);
      expect(saved.unit, '分钟');
    });

    test('排序上移/下移与相邻交换', () async {
      final units = await repo.dictOf(HabitDict.kUnit);
      final a = units[0], b = units[1];
      await repo.moveDict(HabitDict.kUnit, b.id, -1);
      final after = await repo.dictOf(HabitDict.kUnit);
      expect(after[0].name, b.name);
      expect(after[1].name, a.name);
      await repo.moveDict(HabitDict.kUnit, after[0].id, -1); // 越界不动
      expect((await repo.dictOf(HabitDict.kUnit))[0].name, b.name);
    });
  });

  group('4 · 宽限卡（§5-6 · 余额按月已用推导）', () {
    test('每月配额扣已用；用一张抵今日断签：frozen=1 保连不算达成', () async {
      final h = await newHabit(name: '跑步');
      for (final back in [3, 2, 1]) {
        await repo.upsertEntry(h.id, day: key(back), checked: true);
      }
      expect(await repo.graceLeft(h), 1); // 默认 habit.grace=1
      await repo.useFreeze(h, day: key(0));
      final e = (await repo.entriesOf(h.id))[key(0)]!;
      expect(e.frozen, isTrue);
      expect(e.checked, isFalse);
      expect(habitOkAt((await repo.habitById(h.id))!, e), isFalse); // 不算达成
      expect((await repo.habitById(h.id))!.streak, 4); // 保连续且宽限日计入（§5-6）
      expect(await repo.graceLeft(h), 0);
    });

    test('配额 0（不用）恒 0 张', () async {
      await repo.setKv('habit.grace', '0');
      final h = await newHabit(name: '冥想');
      expect(await repo.graceLeft(h), 0);
    });
  });

  group('5 · 负向触发（§5-10 一等数据）', () {
    test('recordTrigger：流水 checked=0、量累加、slip 落表、连续归零', () async {
      final h = await newHabit(name: '奶茶', type: Habit.kNeg, unit: '杯', goal: 1, negLimit: 2);
      await repo.upsertEntry(h.id, day: key(1), checked: true); // 昨天守住
      expect((await repo.habitById(h.id))!.streak, 1);
      await repo.recordTrigger(h.id, day: key(0), amount: 2, amountText: '2 杯', reasons: ['应酬', '情绪'], note: '下午茶');
      final e = (await repo.entriesOf(h.id))[key(0)]!;
      expect(e.checked, isFalse);
      expect(e.value, 2);
      expect((await repo.habitById(h.id))!.streak, 0);
      final slips = await repo.slipsOf(h.id);
      expect(slips, hasLength(1));
      expect(slips.first.reasons, ['应酬', '情绪']);
      expect(slips.first.note, '下午茶');
      expect(await repo.slipCountIn(h.id, key(6), key(0)), 1);
      // 同日再触发一次：量累加、slip 追加
      await repo.recordTrigger(h.id, day: key(0), amount: 1);
      expect((await repo.entriesOf(h.id))[key(0)]!.value, 3);
      expect(await repo.slipsOf(h.id), hasLength(2));
    });
  });

  group('6 · 目标生效历史（goal_hist · 不追改历史）', () {
    test('新建不登记；改目标/单位登记一条', () async {
      final h = await newHabit(name: '喝水', unit: '杯', goal: 8);
      expect(await repo.goalHistOf(h.id), isEmpty);
      await repo.saveHabit((await repo.habitById(h.id))!.copyWith(goal: 10));
      final hist = await repo.goalHistOf(h.id);
      expect(hist, hasLength(1));
      expect(hist.first['goal'], 10.0);
      expect(hist.first['effective_from'], dayKey(DateTime.now()));
      // 只改名字不再登记
      await repo.saveHabit((await repo.habitById(h.id))!.copyWith(name: '喝水2'));
      expect(await repo.goalHistOf(h.id), hasLength(1));
    });
  });
}
