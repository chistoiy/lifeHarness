import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';
import 'journal_layout_kit.dart';

/// 日记改版批1a · 月历图墙（7 列格，只为「哪天写过」服务）；批1c 起支持**翻月**。
///
/// 三态次序**不可对调**（工单 §2 硬口径 3）：无日记＝虚线空环 ＞ 有日记无图＝心情色实心 ＞ 有日记有图＝实心＋右上角标。
/// 图墙**不做图片浏览、不做点击进图**——点格只做一件事：看当天（当天多篇给选择弹层）。
///
/// 翻月口径（原型 `dwMonthStep`）：只往**过去**翻，范围 `[本月-24, 本月]`；不给未来月——
/// 未来的日子不可能有日记，翻过去只会看到一整屏空格，白费一次点击。
class JournalWall extends StatelessWidget {
  const JournalWall({
    super.key,
    required this.month,
    required this.byDayFirst,
    required this.onTapDay,
    this.moodColorOf,
    this.onMonthStep,
    this.minMonthOffset = -kWallMaxMonthBack,
  });

  /// 展示的月份。
  final DateTime month;

  /// 当日首篇（同日多篇取最新一篇来判「有没有图」，与列表卡头同源）。
  final Map<int, JournalEntry> byDayFirst;
  final void Function(int day) onTapDay;
  final Color? Function(JournalEntry e)? moodColorOf;

  /// 翻月回调：`-1` 上一月、`+1` 下一月。为 null 时不显示翻月钮（1a 旧调用点保持原样）。
  final void Function(int delta)? onMonthStep;

  /// 允许往前翻的最多个月数（负数）。默认 −24 与原型一致。
  final int minMonthOffset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month, 1).weekday - 1;
    final total = wallCellCount(month);
    return Column(
      key: const ValueKey('diary-wall'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 月份标题 + 翻月钮（批1c）。原型 `dwRenderWall` 同构：标题吃满左边、两枚钮在右。
        // 「下一月」在当月置灰：不能翻到未来（见类注释）。
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${month.year}年${month.month}月',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              if (onMonthStep != null) ...[
                _WallNavBtn(
                  key: const ValueKey('wall-prev'),
                  icon: Icons.chevron_left,
                  label: '上一月',
                  onTap: () => onMonthStep!(-1),
                ),
                _WallNavBtn(
                  key: const ValueKey('wall-next'),
                  icon: Icons.chevron_right,
                  label: '下一月',
                  // 只在「还没到本月」时可点：未来月份不可能有日记，翻过去只会看到一屏空格。
                  enabled: !_isThisMonth(month),
                  onTap: () => onMonthStep!(1),
                ),
              ],
            ],
          ),
        ),
        // 星期表头（周一开头，与日期块「周一」同源）
        Row(
          children: [
            for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < total ~/ 7; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: () {
                      final idx = r * 7 + c;
                      final day = idx - lead + 1;
                      if (idx < lead || day > daysInMonth) {
                        return const SizedBox(height: 34);
                      }
                      final e = byDayFirst[day];
                      final state = wallCellStateOf(e);
                      final color = e == null ? null : (moodColorOf?.call(e));
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _WallCell(
                          key: ValueKey('wall-day-$day'),
                          day: day,
                          state: state,
                          fill: state == WallCellState.empty
                              ? null
                              : (color ?? tokens.accent),
                          onTap: () => onTapDay(day),
                        ),
                      );
                    }(),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 2),
        Text(
          '实心＝当天写过 · 右上角标＝当天有图',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _WallCell extends StatelessWidget {
  const _WallCell({
    super.key,
    required this.day,
    required this.state,
    required this.onTap,
    this.fill,
  });

  final int day;
  final WallCellState state;
  final VoidCallback onTap;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final written = state != WallCellState.empty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: written ? fill?.withValues(alpha: .85) : null,
          border: written
              ? null
              : Border.all(
                  color: scheme.onSurfaceVariant.withValues(alpha: .28),
                  width: 1,
                  style: BorderStyle.solid,
                ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: written ? FontWeight.w700 : FontWeight.w500,
                  color: written
                      ? Colors.white
                      : scheme.onSurfaceVariant.withValues(alpha: .75),
                ),
              ),
            ),
            if (state == WallCellState.writtenWithImage)
              const Positioned(
                top: 2,
                right: 2,
                child: Icon(Icons.image_outlined, size: 9, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

/// 当前是否为「本月」（决定「下一月」是否可点）。
bool _isThisMonth(DateTime m) {
  final now = DateTime.now();
  return m.year == now.year && m.month == now.month;
}

/// 图墙最多往前翻几个月（原型 `dwMonthStep` 的 `-24` 下界）。
const int kWallMaxMonthBack = 24;

/// 翻月钮：24×24 触摸面，图标 18（48dp 触控是列表级规范，图墙标题行放不下）。
class _WallNavBtn extends StatelessWidget {
  const _WallNavBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 18,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 18,
            color: scheme.onSurfaceVariant.withValues(alpha: enabled ? .9 : .3),
          ),
        ),
      ),
    );
  }
}
