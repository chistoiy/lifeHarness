import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/habit.dart';
import 'habit_card.dart';
import 'habit_kit.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';

/// 紧凑行（原型 hbCardMini · LH-L09：图标+名+迷你 7 日点阵+完成度+打卡小钮，
/// 高 ≤46，无记录量摘要——信息密度优先给完成度）。
class HabitTileRow extends StatelessWidget {
  const HabitTileRow({
    super.key,
    required this.habit,
    required this.info,
    required this.enabled,
    required this.actions,
  });

  final Habit habit;
  final HabitRowInfo info;

  /// 今天且未归档可打卡；回看/归档只读。
  final bool enabled;
  final HabitActions actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final ok = info.dayOk;
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: hCardDeco(context),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: InkWell(
        onTap: () => actions.open(habit),
        child: Row(
          children: [
            HabitIconTile(
              iconKey: habit.icon,
              neg: habit.isNeg,
              size: 28,
              radius: 8,
              iconSize: 14,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    habit.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      for (var i = 0; i < 7; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                info.flags[i]
                                    ? (habit.isPos ? HK.ok400 : HK.teal400)
                                    : scheme.onSurface.withValues(alpha: .12),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Text(
                        '${info.rate}%'
                        '${info.dayValText.isNotEmpty ? ' · ${info.dayValText}' : ''}',
                        style: TextStyle(
                          fontSize: 9,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (enabled)
              GestureDetector(
                // 原型 hbCardMini：负向按钮 ok 态也走 hbAvoid（页面层 toast 守卫）
                onTap: () =>
                    habit.isPos ? actions.tap(habit) : actions.avoid(habit),
                child: habit.isPos
                    ? Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: ok ? null : tokens.gradient,
                        color:
                            ok
                                ? scheme.onSurface.withValues(alpha: .06)
                                : null,
                      ),
                      child: Icon(
                        ok ? HIcons.resolve('check') : HIcons.resolve('plus'),
                        size: 15,
                        color: ok ? scheme.onSurfaceVariant : Colors.white,
                      ),
                    )
                    : Container(
                      height: 32,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color:
                            ok
                                ? scheme.onSurface.withValues(alpha: .06)
                                : HK.teal500,
                      ),
                      child: Text(
                        ok ? '守住' : '记触发',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: ok ? scheme.onSurfaceVariant : Colors.white,
                        ),
                      ),
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
