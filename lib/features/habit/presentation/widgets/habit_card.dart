import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/habit.dart';
import 'habit_kit.dart';
import 'package:lifeharness/features/habit/presentation/habit_providers.dart';

/// 主页三视图对单条习惯的共享回调（§3.2 点击语义集中入口，禁私自增删入口）。
class HabitActions {
  const HabitActions({
    required this.open,
    required this.tap,
    required this.avoid,
    required this.trigger,
    required this.freeze,
    required this.archiveToggle,
    required this.openLog,
    required this.dotTap,
  });

  /// 点卡片本体 → 详情。
  final void Function(Habit h) open;

  /// 打卡/撤销（无量正向）或打开记量（有量正向）。
  final void Function(Habit h) tap;

  /// 负向「今天没做」。
  final void Function(Habit h) avoid;

  /// 负向「记一次触发」。
  final void Function(Habit h) trigger;

  /// 宽限卡使用（批5 前占位）。
  final void Function(Habit h) freeze;
  final void Function(Habit h) archiveToggle;

  /// 打开记量弹层（记录量摘要 / 组子项 chips 点按）。
  final void Function(Habit h) openLog;

  /// 方块视图 7 日格就地打卡/撤销该日（§3.2）。
  final void Function(Habit h, DateTime day) dotTap;
}

/// 卡片通用描边底（原型 .card）见 habit_kit.hCardDeco。

/// 列表卡（原型 hbCard：头行 + 组子项 chips + 七日点阵 + 统计脚注 +
/// 补记注行 + 进度条 + 动作区）。
class HabitCardView extends StatelessWidget {
  const HabitCardView({
    super.key,
    required this.habit,
    required this.info,
    required this.dayOff,
    required this.actions,
    required this.grace,
  });

  final Habit habit;
  final HabitRowInfo info;

  /// 0=今天；<0 回看模式（动作区替换为提示行）。
  final int dayOff;
  final HabitActions actions;
  final int grace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final ok = info.dayOk;
    final rate = info.rate;
    final hasVal = habit.hasVal;

    return Container(
      decoration: hCardDeco(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => actions.open(habit),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HabitIconTile(iconKey: habit.icon, neg: habit.isNeg),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              habit.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (habit.isGroup) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: HK.brand.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '组 · ${habit.subs.length} 项',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: HK.brand,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${habit.dueText}'
                        '${(habit.remindAt?.isNotEmpty ?? false) ? ' · 提醒 ${habit.remindAt}' : ''}'
                        ' · ${habit.sourceKinds.join('/')}',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        habit.isPos
                            ? HK.teal400.withValues(alpha: .15)
                            : HK.rose500.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    habit.isPos ? '坚持' : '控制',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: habit.isPos ? HK.teal600 : HK.rose500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (habit.isGroup) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: dayOff == 0 ? () => actions.openLog(habit) : null,
              child: HabitSubChips(habit: habit, values: info.daySubs),
            ),
          ],
          const SizedBox(height: 8),
          HabitWeekDots(
            habit: habit,
            flags: info.flags,
            frozens: info.frozens,
            todayIdx: info.todayIdx,
            valTips: info.tips,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _statsText(),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              Text(
                '$rate%',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: HK.rateText(rate),
                ),
              ),
            ],
          ),
          if (info.bfCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '本周含补记 ${info.bfCount} 天',
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: rate / 100,
              minHeight: 6,
              backgroundColor: scheme.onSurface.withValues(alpha: .06),
              valueColor: AlwaysStoppedAnimation(
                habit.isPos ? tokens.accent : HK.ok400,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _actions(context, ok, hasVal),
        ],
      ),
    );
  }

  /// 脚注统计串（原型条件段：正向 连续/本周/量·达标数；负向 已用额度/未触发）。
  String _statsText() {
    if (habit.isPos) {
      final parts = ['连续 ${habit.streak} 天', '本周 ${info.weekOk}/7'];
      if (habit.hasVal) {
        if (habit.isGroup) {
          final met = habit.subs.where((s) {
            final v = info.daySubs[s.id] ?? 0;
            return s.goal > 0 && v >= s.goal;
          }).length;
          parts.add('子项 $met/${habit.subs.length} 达标');
        } else {
          parts.add('量 ${info.dayValText.isEmpty ? '—' : info.dayValText}');
        }
      }
      return parts.join(' · ');
    }
    return '本周已用 ${info.negUsed}/${habit.negLimit} · 未触发 ${info.weekOk}/7 天';
  }

  Widget _actions(BuildContext context, bool ok, bool hasVal) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    if (habit.isArchived) {
      return Row(
        children: [
          Expanded(
            child: HMiniBtn(
              '已归档 · 恢复跟踪',
              onTap: () => actions.archiveToggle(habit),
            ),
          ),
          const SizedBox(width: 8),
          HMiniBtn('看纪录', onTap: () => actions.open(habit)),
        ],
      );
    }
    if (dayOff != 0) {
      return Text(
        '回看模式 · 修改这天请用「补卡」',
        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      );
    }
    if (habit.isPos) {
      final label = !ok
          ? (hasVal ? '打卡并记量' : '打卡')
          : hasVal
          ? '今日 ${info.dayShortVal.isEmpty ? '未记量' : info.dayShortVal} · 点击修改'
          : '已打卡 · 点击撤销';
      return Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => actions.tap(habit),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: ok ? null : tokens.gradient,
                  color: ok ? scheme.onSurface.withValues(alpha: .06) : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: ok ? scheme.onSurfaceVariant : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (!ok && grace > 0 && habit.streak > 0) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => actions.freeze(habit),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: HK.sky400.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '宽限 $grace',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: HK.sky600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => actions.open(habit),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(
                HIcons.resolve('chart'),
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => actions.avoid(habit),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: ok ? scheme.onSurface.withValues(alpha: .06) : HK.teal500,
              ),
              child: Text(
                ok ? '今天没做 ✓' : '今天没做',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ok ? scheme.onSurfaceVariant : Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => actions.trigger(habit),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HK.rose500.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '记一次触发',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: HK.rose500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
