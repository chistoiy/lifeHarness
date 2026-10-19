import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';
import 'journal_layout_kit.dart';

/// 日记改版批1a · 月历图墙（7 列格，只为「哪天写过」服务）。
///
/// 三态次序**不可对调**（工单 §2 硬口径 3）：无日记＝虚线空环 ＞ 有日记无图＝心情色实心 ＞ 有日记有图＝实心＋右上角标。
/// 图墙**不做图片浏览、不做点击进图**——点格只做一件事：看当天（当天多篇给选择弹层）。
class JournalWall extends StatelessWidget {
  const JournalWall({
    super.key,
    required this.month,
    required this.byDayFirst,
    required this.onTapDay,
    this.moodColorOf,
  });

  /// 展示的月份（本批固定当月；翻月属 1c）。
  final DateTime month;

  /// 当日首篇（同日多篇取最新一篇来判「有没有图」，与列表卡头同源）。
  final Map<int, JournalEntry> byDayFirst;
  final void Function(int day) onTapDay;
  final Color? Function(JournalEntry e)? moodColorOf;

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
