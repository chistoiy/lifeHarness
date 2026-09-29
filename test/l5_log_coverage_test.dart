/// L5 日志批验收钉桩（docs/日志覆盖工单-20260929.md §三·L5）：
/// 日子派生、目标自动汇聚与上限、物品财务动作四条路必须留痕，
/// 且**来源归类**正确（日志页按「日子 / 目标 / 物品」筛得出来）。
/// 口径同 L1~L4：只加日志零行为改动，本文件只钉「有没有留痕」。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/features/days/data/days_repository.dart';
import 'package:lifeharness/features/goals/data/goals_repository.dart';
import 'package:lifeharness/features/goals/domain/goal_models.dart';
import 'package:lifeharness/features/items/data/items_repository.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool logged(String contains, {String? level, bool key = false}) =>
    AppLog.lines.any((l) =>
        l.text.contains(contains) &&
        (level == null || l.level.name == level) &&
        (!key || l.key));

void srcOf(String contains, String want) {
  for (final l in AppLog.lines.where((x) => x.text.contains(contains))) {
    expect(l.src, want, reason: '${l.text} 归到了 ${l.src}，应为 $want');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Database db;

  setUp(() async {
    AppLog.reset();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
  });
  tearDown(() async {
    await db.close();
    AppLog.reset();
  });

  group('日子（features/days）· 跨模块派生', () {
    test('派生刷新落汇总；源表读不到时两处 warn 且不炸页面', () async {
      final repo = DaysRepository(db);
      await repo.syncDerived();
      expect(logged('日子派生刷新：订阅 0 项 · 保修表已同步', key: true), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      // 把两张外模块表摘掉：派生条目会静默缺失，必须各留一行归因。
      await db.execute('DROP TABLE ${DbSchema.tLedgerRecur}');
      // 保修侧保留空表只抽走 warranty 列——syncDerived 先查 sqlite_master 再 SELECT，
      // 整表消失会直接跳过（另一条分支在下面断言），列缺失才会走到读取失败。
      await db.execute(
          'ALTER TABLE ${DbSchema.tItemProfiles} DROP COLUMN warranty');
      await repo.syncDerived();
      expect(logged('日子派生：记账订阅表读取失败（订阅提醒会缺项）', level: 'warn'),
          isTrue, reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect(logged('日子派生：物品保修表读取失败（保修提醒会缺项）', level: 'warn'),
          isTrue, reason: AppLog.lines.map((l) => l.text).join(' | '));
      // 整表不在＝跳过分支（不报错，但汇总行要写明是跳过而非同步到 0 项）
      await db.execute('DROP TABLE ${DbSchema.tItemProfiles}');
      await repo.syncDerived();
      expect(logged('保修表不存在（跳过）', key: true), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('日子派生', '日子');
    });
  });

  group('目标（features/goals）· 汇聚与上限', () {
    test('建目标 / KR 回填 / 整组复制各落一条；超上限拒绝留 warn', () async {
      final repo = GoalsRepository(db);
      final id = await repo.addGoal(Goal(
          title: 'O1 把身体养回来',
          period: '2026 Q3',
          krs: [
            const GoalKr(
                goalId: 0, label: '锻炼次数', target: 30, source: KrSource.todo)
          ]));
      expect(id, isNotNull);
      for (var i = 2; i <= 5; i++) {
        expect(await repo.addGoal(Goal(title: 'O$i', period: '2026 Q3')), isNotNull);
      }
      // 每期上限 5：第六个建不出来，UI 只 toast，日志要写清是哪一期。
      expect(await repo.addGoal(Goal(title: 'O6', period: '2026 Q3')), isNull);
      expect(logged('目标新建被拒：2026 Q3 已有 5 个 O', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));

      final data = await repo.loadAll(now: DateTime(2026, 8, 10));
      final kr = data.goals.first.krs.first;
      await repo.bumpKr(kr.id!, 12, note: '实练 12 次');
      expect(logged('目标 KR 回填：#${kr.id} → 12.0（实练 12 次）', key: true), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));

      expect(await repo.copyGoals('2026 Q3', '2026 Q4'), 5);
      expect(logged('目标整组复制：2026 Q3 → 2026 Q4 · 5/5 个', key: true), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('目标', '目标');
    });

    test('自动汇聚源表异常 → error 归因后照常抛出（控制流未动）', () async {
      final repo = GoalsRepository(db);
      await db.execute('DROP TABLE ${DbSchema.tTodos}');
      await expectLater(
          repo.aggregate(KrSource.todo, '锻炼次数', '2026 Q3', DateTime(2026, 8, 10)),
          throwsA(anything));
      expect(logged('目标自动汇聚失败（源', level: 'error'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect(logged('KR「锻炼次数」'), isTrue, reason: '归因要带是哪个 KR');
      srcOf('目标自动汇聚', '目标');
    });
  });

  group('物品（features/items）· 财务动作', () {
    test('建档 / 二次付费 / 回收 / 报废各落一条 key 行', () async {
      final repo = ItemsRepository(db);
      final shoe = await repo.addItem(ItemProfile(
          name: 'Nike 跑鞋', buyDate: '2026-09-01', price: 899, expectedYears: 2));
      expect(logged('物品建档：#$shoe Nike 跑鞋 · 价 899.0 · 2026-09-01 · 计费=true',
          key: true), isTrue, reason: AppLog.lines.map((l) => l.text).join(' | '));
      await repo.addExtraPay(shoe, 120, '换底', date: '2026-09-10');
      expect(logged('物品二次付费：#$shoe +120.0 · 换底', key: true), isTrue);
      await repo.recycle(shoe, 200, keep: false, date: '2026-09-11');
      expect(
          logged('物品回收：#$shoe 残值 200.0 · 转出·停计费并冻结决算', key: true),
          isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      final ear = await repo.addItem(
          ItemProfile(name: '耳机', buyDate: '2026-09-01', price: 399));
      await repo.scrap(ear, '进水', date: '2026-09-12');
      expect(
          logged('物品报废：#$ear · 原因「进水」 · 2026-09-12 · 停计费并冻结决算',
              key: true),
          isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      // 停计费要真落到库里（加日志没改行为）
      final data = await repo.loadAll();
      expect(
          data.items.firstWhere((x) => x.id == shoe).billing, isFalse,
          reason: '回收转出后 billing 必须为 false');
      expect(data.active.map((x) => x.id), isNot(contains(shoe)));
      srcOf('物品', '物品');
    });
  });
}
