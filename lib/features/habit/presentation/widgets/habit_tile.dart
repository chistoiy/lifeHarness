import 'package:flutter/material.dart';

import '../../domain/habit.dart';
import '../../domain/habit_calc.dart';
import 'habit_kit.dart';
import 'habit_card.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';

/// 方块卡（原型 hbTile · LH-C08：完成度环 + 7 日点阵 + 待打卡时刻 +
/// 补记角标；不放大号打卡钮，点卡进详情/未达成即打卡；点合格格就地打卡）。
class HabitTile extends StatelessWidget {
  const HabitTile({
    super.key,
    required this.habit,
    required this.info,
    required this.today,
    required this.enabled,
    required this.actions,
  });

  final Habit habit;
  final HabitRowInfo info;
  final DateTime today;

  /// 今天（非回看）且未归档。
  final bool enabled;
  final HabitActions actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = info.dayOk;
    final rate = info.rate;
    final ringColor = habit.isPos ? HK.brand : HK.teal400;
    return GestureDetector(
      onTap: () {
        // 原型 hbTileTap：正向未达成→打卡；其余进详情。
        if (habit.isPos && !ok && enabled) {
          actions.tap(habit);
        } else {
          actions.open(habit);
        }
      },
      child: Container(
        decoration: hCardDeco(context).copyWith(
          border: Border.all(
            color: ok ? scheme.outlineVariant : HK.brand.withValues(alpha: .25),
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HabitIconTile(
                      iconKey: habit.icon,
                      neg: habit.isNeg,
                      size: 24,
                      radius: 8,
                      iconSize: 13,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        habit.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (ok)
                      Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: HK.ok500,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 9,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$rate%',
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            habit.isPos ? '本周达成' : '本周守住',
                            style: TextStyle(
                              fontSize: 8.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    RingProgress(
                      value: rate / 100,
                      size: 36,
                      stroke: 3.4,
                      color: ringColor,
                      bg: scheme.onSurface.withValues(alpha: .08),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 7 日条：合格格可点就地打卡/撤销（§3.2）
                Row(
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        child: GestureDetector(
                          onTap:
                              enabled && _day(i).isBefore(dayStart(today))
                                  ? () => actions.dotTap(habit, _day(i))
                                  : null,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color:
                                  info.flags[i]
                                      ? (habit.isPos ? HK.ok400 : HK.teal400)
                                      : scheme.onSurface.withValues(
                                          alpha: .08,
                                        ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        habit.hasVal
                            ? (info.dayShortVal.isNotEmpty
                                  ? '量 ${info.dayShortVal}'
                                  : '今日未记量')
                            : '${habit.streak} 天连击',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      ok
                          ? (info.dayEntry?.checkAt?.isNotEmpty ?? false)
                                ? info.dayEntry!.checkAt!
                                : '已打卡'
                          : '待打卡',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: ok ? HK.ok500 : HK.brand,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (info.bfCount > 0)
              Positioned(
                right: 0,
                top: 26,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: HK.amber500.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '补${info.bfCount}',
                    style: const TextStyle(
                      fontSize: 8,
                      color: HK.amber600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  DateTime _day(int idx) =>
      dayStart(today).subtract(Duration(days: 6 - idx));
}
