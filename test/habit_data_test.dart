import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/features/habit/domain/habit_entry.dart';

/// 习惯批1a · 数据层与口径函数（习惯计划 §2.1 / §5 / §8）。
/// 独立文件防 isolate 污染（既有踩坑）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late HabitRepository repo;

  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));
  DateTime day(int back) => parseDay(key(back));

  Future<Habit> newHabit({
    String name = '跑步',
    String cycle = Habit.kDay,
    List<int> weekDays = const [],
    String? unit,
    double? goal,
    int backStart = 60,
  }) => repo.saveHabit(
    Habit(
      name: name,
      cycle: cycle,
      weekDays: weekDays,
      unit: unit,
      goal: goal,
      startDate: key(backStart),
    ),
  );

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
    );
    for (final sql in DbSchema.habitSchemaStatements) {
      await db.execute(sql);
    }
    repo = HabitRepository(db);
  });
  tearDown(() => db.close());

  group('1 · v16 建表与幂等', () {
    test('migrations[15] 建五表+字典种子·幂等可重跑', () async {
      for (final sql in DbSchema.migrations[15]!) {
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
          'habits',
          'habit_subs',
          'habit_entries',
          'habit_entry_subs',
          'habit_dict',
        ]),
      );
      final cats = await repo.dictOf('cat');
      expect(cats.map((c) => c.name), ['健康', '学习', '工作', '生活', '成长']);
      expect((await repo.dictOf('unit')).length, 11);
    });

    test('建库段与迁移段同文（共用 habitSchemaStatements）', () {
      expect(DbSchema.migrations[15], equals(DbSchema.habitSchemaStatements));
      expect(DbSchema.version, 16);
    });
  });

  group('2 · 习惯 CRUD 与子项', () {
    test('新建生成 id/时间戳；编辑不换 id；空名子项跳过', () async {
      final h = await repo.saveHabit(
        Habit(
          name: '健身组',
          startDate: key(30),
          groupRule: Habit.kRuleAll,
          subs: const [
            HabitSub(name: '深蹲', unit: '个', goal: 20),
            HabitSub(name: '  ', unit: '个', goal: 5),
            HabitSub(name: '跑步', unit: '分钟', goal: 20),
          ],
        ),
      );
      expect(h.id, isNotEmpty);
      expect(h.subs.length, 2, reason: '空名子项不入库');
      expect(h.subs[0].name, '深蹲');
      final e = await repo.saveHabit(h.copyWith(name: '健身组+'));
      expect(e.id, h.id);
      expect(e.subs.length, 2, reason: '子项整组替换不残留');
    });

    test('软删除：列表消失、流水保留', () async {
      final h = await newHabit();
      await repo.upsertEntry(h.id, day: key(1));
      await repo.deleteHabit(h.id);
      expect(await repo.allHabits(), isEmpty);
      expect((await repo.entriesOf(h.id)).length, 1);
    });

    test('归档/恢复 archived_at 置位与清除', () async {
      final h = await newHabit();
      await repo.setArchived(h.id, true);
      expect((await repo.habitById(h.id))!.isArchived, isTrue);
      await repo.setArchived(h.id, false);
      expect((await repo.habitById(h.id))!.isArchived, isFalse);
    });
  });

  group('3 · 按日流水 UPSERT（§2.1 同日改值）', () {
    test('同 habit+day 二次保存不产生新行、值被改写', () async {
      final h = await newHabit(unit: '分钟', goal: 30);
      await repo.upsertEntry(h.id, day: key(2), value: 20, checkAt: '07:10');
      await repo.upsertEntry(h.id, day: key(2), value: 45, checkAt: '08:30');
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM habit_entries'),
      );
      expect(count, 1);
      final e = (await repo.entriesOf(h.id))[key(2)]!;
      expect(e.value, 45);
      expect(e.checkAt, '08:30');
      expect(e.checked, isTrue, reason: '未传 checked 保留原值');
    });

    test('未来日拒写（时钟防护）', () async {
      final h = await newHabit();
      expect(
        () => repo.upsertEntry(h.id, day: key(-1)),
        throwsArgumentError,
      );
    });

    test('撤销流水：行与子项值同删、streak 回退', () async {
      final h = await newHabit();
      for (final b in [2, 1, 0]) {
        await repo.upsertEntry(h.id, day: key(b));
      }
      expect((await repo.habitById(h.id))!.streak, 3);
      await repo.deleteEntry(h.id, key(0));
      expect((await repo.habitById(h.id))!.streak, 2);
      expect((await repo.entriesOf(h.id)).length, 2);
    });

    test('水位线 habit.maxSeenDay 只进不退', () async {
      final h = await newHabit();
      await repo.upsertEntry(h.id, day: key(3));
      expect(await repo.maxSeenDay(), key(3));
      await repo.upsertEntry(h.id, day: key(10));
      expect(await repo.maxSeenDay(), key(3), reason: '更早日期不回拨水位线');
    });
  });

  group('4 · streak/best 三场景（断签/宽限/非计划日 · §5-6）', () {
    test('连续 3 天打卡 streak=3', () async {
      final h = await newHabit();
      for (final b in [2, 1, 0]) {
        await repo.upsertEntry(h.id, day: key(b));
      }
      expect((await repo.habitById(h.id))!.streak, 3);
      expect((await repo.habitById(h.id))!.best, 3);
    });

    test('断签日未记 → 当前连续断在缺口前', () async {
      final h = await newHabit();
      for (final b in [4, 3]) {
        await repo.upsertEntry(h.id, day: key(b));
      }
      await repo.upsertEntry(h.id, day: key(2));
      await repo.upsertEntry(h.id, day: key(0));
      final r = await repo.habitById(h.id);
      expect(r!.streak, 1);
      expect(r.best, 3, reason: '历史最长取 2/3/4 天那段');
    });

    test('宽限卡日（frozen=1 checked=0）不断连', () async {
      final h = await newHabit();
      await repo.upsertEntry(h.id, day: key(2));
      await repo.upsertEntry(h.id, day: key(1), checked: false, frozen: true);
      await repo.upsertEntry(h.id, day: key(0));
      expect((await repo.habitById(h.id))!.streak, 3);
    });

    test('非计划日不计分母也不断连（周固定日一二）', () async {
      // 以本周一/周三构造计划日，其余日跳过。
      final now = DateTime.now();
      final monday = dayStart(now).subtract(Duration(days: now.weekday - 1));
      final wed = monday.add(const Duration(days: 2));
      final h = await repo.saveHabit(
        Habit(
          name: '周练',
          cycle: Habit.kWeek,
          weekDays: const [0, 2],
          startDate: dayKey(monday.subtract(const Duration(days: 14))),
        ),
      );
      await repo.upsertEntry(h.id, day: dayKey(monday));
      await repo.upsertEntry(h.id, day: dayKey(wed));
      final r = await repo.habitById(h.id);
      expect(r!.streak, 2, reason: '周二/周日等非计划日跳过不计数不断连');
      expect(
        habitRate(
          r,
          entries: await repo.entriesOf(h.id),
          from: monday,
          to: dayStart(now),
        ),
        100,
        reason: '分母=区间计划日数（此处 2），达成率 2/2',
      );
    });

    test('负向：checked=1（未触发）计连，触发日 checked=0 断连', () async {
      final h = await repo.saveHabit(
        Habit(name: '奶茶', type: Habit.kNeg, startDate: key(9)),
      );
      for (final b in [2, 1, 0]) {
        await repo.upsertEntry(h.id, day: key(b), checked: true);
      }
      expect((await repo.habitById(h.id))!.streak, 3);
      await repo.upsertEntry(h.id, day: key(1), checked: false, value: 1);
      expect((await repo.habitById(h.id))!.streak, 1);
    });
  });

  group('5 · 组判定与量（§5-3 禁跨单位求和）', () {
    Future<Habit> groupHabit(String rule) => repo.saveHabit(
      Habit(
        name: '健身组',
        startDate: key(30),
        groupRule: rule,
        subs: const [
          HabitSub(name: '深蹲', unit: '个', goal: 20),
          HabitSub(name: '跑步', unit: '分钟', goal: 20),
          HabitSub(name: '俯卧撑', unit: '个', goal: 30),
        ],
      ),
    );

    test('3 子项填 2 项：half 判达成 / any 判达成 / all 判不达成', () async {
      for (final (rule, expectOk) in [
        (Habit.kRuleHalf, true),
        (Habit.kRuleAny, true),
        (Habit.kRuleAll, false),
      ]) {
        final h = await groupHabit(rule);
        await repo.upsertEntry(
          h.id,
          day: key(0),
          subValues: {h.subs[0].id: 25, h.subs[1].id: 22},
        );
        final e = (await repo.entriesOf(h.id))[key(0)]!;
        expect(habitOkAt(h, e), expectOk, reason: 'rule=$rule');
      }
    });

    test('组总量为 null；子项分别合计', () async {
      final h = await groupHabit(Habit.kRuleAll);
      await repo.upsertEntry(
        h.id,
        day: key(0),
        subValues: {
          h.subs[0].id: 20,
          h.subs[1].id: 30,
        },
      );
      final entries = await repo.entriesOf(h.id);
      expect(habitTotalValue(h, entries, day(5), day(0)), isNull);
      final tot = habitSubTotals(h, entries, day(5), day(0));
      expect(tot[h.subs[0].id], 20);
      expect(tot[h.subs[1].id], 30);
    });
  });

  group('6 · 口径：effDays 截断与达成率', () {
    test('spanFromStart 开=只计开始日后天数；关=全年天数', () async {
      final now = dayStart(DateTime.now());
      final yearStart = DateTime(now.year, 1, 1);
      final h = Habit(name: 'h', startDate: dayKey(now.subtract(const Duration(days: 20))));
      expect(
        habitEffDays(
          h,
          periodDays: 365,
          periodStart: yearStart,
          today: now,
        ),
        21,
      );
      expect(
        habitEffDays(
          h,
          periodDays: 365,
          periodStart: yearStart,
          today: now,
          spanFromStart: false,
        ),
        365,
      );
    });

    test('habitRate=达成/应打卡（先截断）· 关闭截断换分母', () async {
      final h = await newHabit(backStart: 4);
      final entries = <String, HabitEntry>{
        key(4): HabitEntry(habitId: h.id, day: key(4), origin: 'manual'),
        key(3): HabitEntry(habitId: h.id, day: key(3), origin: 'manual'),
      };
      // 6 天窗口（key(5)..key(0)），开始日=key(4) 之后应打卡 5 天，达成 2 → 40%
      expect(
        habitRate(h, entries: entries, from: day(5), to: day(0)),
        40,
      );
      // 关闭截断：分母=窗口应打卡 6 天 → 2/6≈33%
      expect(
        habitRate(
          h,
          entries: entries,
          from: day(5),
          to: day(0),
          spanFromStart: false,
        ),
        33,
      );
    });
  });

  group('7 · 导入自检：重算==缓存列（§2.3）', () {
    test('外部改写缓存列后 recomputeStats 纠正回去', () async {
      final h = await newHabit();
      for (final b in [2, 1, 0]) {
        await repo.upsertEntry(h.id, day: key(b));
      }
      await db.update(
        DbSchema.tHabits,
        {'streak': 99, 'best': 99},
        where: 'id = ?',
        whereArgs: [h.id],
      );
      final got = await repo.recomputeStats(h.id);
      expect(got, (3, 3));
      final r = await repo.habitById(h.id);
      expect(r!.streak, 3);
      expect(r.best, 3);
    });
  });

  group('8 · 设置 KV 与字典', () {
    test('setKv/kvInt/kvBool 默认值与回写', () async {
      expect(await repo.kvBool('habit.spanFromStart', true), isTrue);
      await repo.setKv('habit.spanFromStart', 'false');
      expect(await repo.kvBool('habit.spanFromStart', true), isFalse);
      expect(await repo.kvInt('habit.rateBase', 0), 0);
      await repo.setKv('habit.rateBase', '1');
      expect(await repo.kvInt('habit.rateBase', 0), 1);
    });

    test('addDict 去重（同名不重建）· 空名拒绝', () async {
      expect(await repo.addDict('cat', '健康'), isNotNull);
      final n = Sqflite.firstIntValue(
        await db.rawQuery("SELECT COUNT(*) FROM habit_dict WHERE kind='cat'"),
      );
      expect(n, 5, reason: '种子已有健康，不重复插行');
      expect(await repo.addDict('cat', '  '), isNull);
    });
  });
}
