import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/goals/domain/goal_calc.dart';
import 'package:lifeharness/features/goals/domain/goal_models.dart';

/// 批3 · 目标 OKR 引擎（周期体系/进度实算，HG-E1 禁写死口径的可执行化）。
void main() {
  final now = DateTime(2026, 9, 19);

  group('GoalPeriod 周期体系', () {
    test('quarter/isQuarter/yearOf/quarterOf/current', () {
      expect(GoalPeriod.quarter(2026, 3), '2026 Q3');
      expect(GoalPeriod.isQuarter('2026 Q3'), isTrue);
      expect(GoalPeriod.isQuarter(GoalPeriod.yearBucket), isFalse);
      expect(GoalPeriod.yearOf('2026 Q3'), 2026);
      expect(GoalPeriod.quarterOf('2026 Q3'), 3);
      expect(GoalPeriod.current(DateTime(2026, 1)), '2026 Q1');
      expect(GoalPeriod.current(now), '2026 Q3');
      expect(GoalPeriod.current(DateTime(2026, 12, 31)), '2026 Q4');
    });

    test('quartersOfYear 四季列表', () {
      expect(GoalPeriod.quartersOfYear(2026),
          ['2026 Q1', '2026 Q2', '2026 Q3', '2026 Q4']);
    });

    test('nextQuarter 跨年 Q4→次年 Q1；prevQuarter 跨年回退', () {
      expect(GoalPeriod.nextQuarter('2026 Q3', now), '2026 Q4');
      expect(GoalPeriod.nextQuarter('2026 Q4', now), '2027 Q1');
      expect(GoalPeriod.nextQuarter(GoalPeriod.yearBucket, now), '2026 Q3');
      expect(GoalPeriod.prevQuarter('2026 Q1'), '2025 Q4');
      expect(GoalPeriod.prevQuarter('2026 Q3'), '2026 Q2');
    });

    test('range 季度窗与年度桶整年窗', () {
      final (qs, qe) = GoalPeriod.range('2026 Q3', now);
      expect(qs, DateTime(2026, 7, 1));
      expect(qe, DateTime(2026, 10, 1)); // 排他末界
      final (ys, ye) = GoalPeriod.range(GoalPeriod.yearBucket, now);
      expect(ys, DateTime(2026, 1, 1));
      expect(ye, DateTime(2027, 1, 1));
    });

    test('stateLabel 三态 + 年度桶 + 已结束未归档', () {
      final archived = {'2026 Q1', '2026 Q2'};
      expect(GoalPeriod.stateLabel('2026 Q1', archived, now), '已归档 · 只读');
      expect(GoalPeriod.stateLabel('2026 Q3', archived, now), '进行中');
      expect(GoalPeriod.stateLabel('2026 Q4', archived, now), '未开始 · 可预建');
      expect(
          GoalPeriod.stateLabel('2026 Q2', {}, now), '已结束 · 请归档');
      expect(GoalPeriod.stateLabel(GoalPeriod.yearBucket, {}, now),
          '年度 · 可编辑');
    });

    test('shouldAggregate：manual 与归档周期不汇聚', () {
      expect(shouldAggregate(KrSource.todo, false), isTrue);
      expect(shouldAggregate(KrSource.todo, true), isFalse);
      expect(shouldAggregate(KrSource.manual, false), isFalse);
    });
  });

  group('进度实算', () {
    GoalKr kr(double cur, double target) =>
        GoalKr(goalId: 1, label: 'K', target: target, cur: cur);

    test('progressPct cur/target 四舍五入、封顶 100、零 target 不炸', () {
      expect(kr(3, 4).progressPct, 75);
      expect(kr(17, 31).progressPct, 55);
      expect(kr(10, 16).progressPct, 63);
      expect(kr(20, 16).progressPct, 100); // 封顶
      expect(kr(5, 0).progressPct, 0); // 零 target
      expect(kr(0, 0).progressPct, 0);
    });

    test('achieved 与 curText/tgtText 整数去尾', () {
      expect(kr(16, 16).achieved, isTrue);
      expect(kr(15.9, 16).achieved, isFalse);
      expect(kr(3, 4).curText, '3');
      expect(kr(3.5, 4).curText, '3.5');
      expect(kr(0, 12).tgtText, '12');
      expect(kr(0, 2.5).tgtText, '2.5');
    });

    test('Goal.pct = KR 进度均值（round）；空 KR 为 0', () {
      final g = Goal(title: 'O1', period: '2026 Q3', krs: [
        kr(4, 5), // 80
        kr(17, 31), // 55
        kr(10, 16), // 63
      ]);
      expect(g.pct, 66);
      expect(const Goal(title: 'O', period: 'x').pct, 0);
    });

    test('GoalsData.inPeriod / isArchived / reviewFor', () {
      const d = GoalsData(
        goals: [
          Goal(title: 'A', period: '2026 Q3'),
          Goal(title: 'B', period: '2026 Q2'),
          Goal(title: 'C', period: '年度目标'),
        ],
        reviews: [GoalReview(period: '2026 Q2', archived: true)],
        archivedPeriods: {'2026 Q2'},
      );
      expect(d.inPeriod('2026 Q3').single.title, 'A');
      expect(d.isArchived('2026 Q2'), isTrue);
      expect(d.isArchived('2026 Q3'), isFalse);
      expect(d.reviewFor('2026 Q2')?.archived, isTrue);
      expect(d.reviewFor('2026 Q3'), isNull);
    });

    test('KrSource.of 未知回落 manual；六源标签', () {
      expect(KrSource.of('habit'), KrSource.habit);
      expect(KrSource.of('unknown'), KrSource.manual);
      expect(KrSource.values.map((s) => s.label).toList(),
          ['手动', '待办完成数', '阅读本数', '日记篇数', '习惯打卡', '记账结余']);
    });
  });
}
