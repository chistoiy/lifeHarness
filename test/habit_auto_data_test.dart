import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/features/habit/domain/habit_entry.dart';
import 'package:lifeharness/features/habit/domain/habit_template.dart';
import 'package:lifeharness/shared/linkage/habit_mounts.dart';

/// 习惯批5 · 自动达成/待确认队列/模板库/提醒门控 数据层用例。独立文件。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late HabitRepository repo;

  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HabitRepository(db);
  });
  tearDown(() => db.close());

  Future<Habit> seedBound({
    String name = '晨跑',
    List<String> srcs = const ['待办勾选', '手动打卡'],
  }) => repo.saveHabit(
    Habit(name: name, sourceKinds: srcs, startDate: key(30)),
  );

  group('autoIngest 三分叉（§5-8）', () {
    test('autoMode=0 直接打卡：落流水 origin=auto-todo 且重算 streak', () async {
      final h = await seedBound();
      final msg = await repo.autoIngest(h, src: '待办勾选', at: '08:12');
      expect(msg, isNull);
      final e = (await repo.entriesOf(h.id))[key(0)];
      expect(e, isNotNull);
      expect(e!.checked, true);
      expect(e.origin, HabitEntry.oAutoTodo);
      expect(e.checkAt, '08:12');
      final after = await repo.habitById(h.id);
      expect(after!.streak, 1);
    });

    test('autoChk=false 拦截并给手动打卡文案，不落任何数据', () async {
      final h = await seedBound();
      await repo.setKv('habit.autoChk', 'false');
      final msg = await repo.autoIngest(h, src: '待办勾选');
      expect(msg, '自动打卡已关闭 · 请到习惯页手动打卡');
      expect(await repo.entriesOf(h.id), isEmpty);
      expect(await repo.pends(), isEmpty);
    });

    test('今日已打卡：自动源不重复计入', () async {
      final h = await seedBound();
      await repo.upsertEntry(h.id, day: key(0), checked: true);
      final msg = await repo.autoIngest(h, src: '待办勾选');
      expect(msg, '今天已打卡 · 自动源未重复计入');
    });

    test('autoMode=1 只进队列不落流水；杀进程重建仓储队列仍在', () async {
      final h = await seedBound();
      await repo.setKv('habit.autoMode', '1');
      final msg = await repo.autoIngest(h, src: '待办勾选', value: 3);
      expect(msg, isNull);
      expect(await repo.entriesOf(h.id), isEmpty); // 未确认不落 entries
      // 「重启」= 新仓储实例读同一库
      final after = HabitRepository(db);
      final ps = await after.pends();
      expect(ps.length, 1);
      expect(ps.first['habit_id'], h.id);
      expect(ps.first['src'], '待办勾选');
      expect(ps.first['value'], 3);
    });
  });

  group('待确认队列操作', () {
    test('confirmPend：出队 + 流水 origin 按来源 + check_at 用回报时刻', () async {
      final h = await seedBound();
      await repo.setKv('habit.autoMode', '1');
      await repo.autoIngest(h, src: '阅读计时', value: 30);
      final p = (await repo.pends()).first;
      await repo.confirmPend(p);
      expect(await repo.pends(), isEmpty);
      final e = (await repo.entriesOf(h.id))[key(0)]!;
      expect(e.origin, HabitEntry.oAutoRead);
      expect(e.value, 30);
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(e.checkAt ?? ''), true);
    });

    test('ignorePend：只出队，不产生流水', () async {
      final h = await seedBound();
      await repo.setKv('habit.autoMode', '1');
      await repo.autoIngest(h, src: '番茄完成');
      final p = (await repo.pends()).first;
      await repo.ignorePend(p['id'] as int);
      expect(await repo.pends(), isEmpty);
      expect(await repo.entriesOf(h.id), isEmpty);
    });
  });

  test('habitSyncFromTitle：「打卡：名」+绑定源 才回写（L10 标题约定）', () async {
    final h = await seedBound(name: '晨跑');
    final none = await habitSyncFromTitle(repo, '打卡：游泳');
    expect(none, isNull); // 无此习惯
    expect(await repo.entriesOf(h.id), isEmpty);
    final msg = await habitSyncFromTitle(repo, '打卡：晨跑');
    expect(msg, isNull); // 正常回写
    expect((await repo.entriesOf(h.id))[key(0)]!.origin, HabitEntry.oAutoTodo);
    expect(await habitSyncFromTitle(repo, '买牛奶'), isNull); // 非约定标题
  });

  test('habitLinkedTodoDraft：norm=常规 / pomo=番茄 25 分倒计时', () {
    final norm = habitLinkedTodoDraft('晨跑', form: 'norm');
    expect(norm.title, '打卡：晨跑');
    expect(norm.pomoMode, isNull);
    final pomo = habitLinkedTodoDraft('晨跑', form: 'pomo');
    expect(pomo.pomoMode, 'down');
    expect(pomo.pomoMin, 25);
  });

  group('提醒门控（§6/§7）', () {
    test('habitInDnd：跨零点窗口与关闭档', () {
      expect(habitInDnd(0, '22:30'), false); // 关闭
      expect(habitInDnd(1, '22:30'), true); // 22:00-08:00
      expect(habitInDnd(1, '21:30'), false);
      expect(habitInDnd(1, '07:59'), true);
      expect(habitInDnd(2, '23:30'), true); // 23:00-07:00
      expect(habitInDnd(2, '06:30'), true);
      expect(habitInDnd(2, '07:30'), false);
      expect(habitInDnd(9, '22:30'), false); // 越界档=不拦
    });
    test('nightAt 档表与原型 HB_SET_ITEMS 对齐', () {
      expect(kHabitNightAts, ['18:00', '20:00', '21:30', '22:30']);
    });
  });

  test('模板库资源包：12 套全解析（含周固定日/组/负向额度）', () async {
    final tpls = await loadHabitTemplates();
    expect(tpls.length, 12);
    expect(tpls.first.name, '晨间喝水');
    final run = tpls.firstWhere((t) => t.name == '跑步');
    expect(run.cycle, Habit.kWeek);
    expect(run.weekDays, [1, 3, 5]); // 二/四/六
    final grp = tpls.firstWhere((t) => t.name == '运动组合');
    expect(grp.isGroup, true);
    expect(grp.subs.length, 3);
    expect(grp.remind, '07:00');
    final neg = tpls.firstWhere((t) => t.name == '少喝含糖饮料');
    expect(neg.type, Habit.kNeg);
    expect(neg.target, 3);
    final tidy = tpls.firstWhere((t) => t.name == '整理桌面');
    expect(tidy.remind, isNull); // 空串=无提醒
  });
}
