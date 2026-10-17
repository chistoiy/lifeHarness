import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/block_ops.dart';
import '../../domain/time_block.dart';

/// V1.57 C 批 · 时间账本分类明细下钻半屏（原型 index.html sheetTsCat/tsCatSegs 同构）。
///
/// 谓词与汇总行同源（time_stats_page `_aggregate`）：**明细段数与合计必然等于
/// 汇总行「(N 次)」与时长**（ts8check 三处同源断言的 Flutter 版）。现行 DAO 把
/// 结束分钟钳到 1440，跨零点拆分仅作口径兜底保留（拆出两段并标「跨零点」）。

/// 一个明细段（日 · 起止分钟 · 时长 · 展示行名 · 跨零点标注）。
class TsCatSeg {
  const TsCatSeg({
    required this.day,
    required this.s,
    required this.e,
    required this.mins,
    required this.label,
    this.cross = false,
  });

  final DateTime day;
  final int s;
  final int e;
  final int mins;
  final String label;
  final bool cross;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 钟面文本；1440 显 24:00（不回绕成 00:00）。
String tsClock(int m) => m >= 1440 ? '24:00' : fmtMin(m);

/// 与汇总同源地抽该分类明细段（日升序 · 起始分钟升序）。
List<TsCatSeg> tsCatSegs(
  List<TimeBlock> blocks,
  String cat,
  DateTime from,
  DateTime to,
  DateTime now,
) {
  final out = <TsCatSeg>[];
  for (final b in blocks) {
    if (b.catName != cat) continue;
    final e = b.effEnd(now);
    final parts = e > 1440
        ? [(0, 1440), (1, e - 1440)]
        : <(int, int)>[(0, e)];
    for (final (shift, end) in parts) {
      final d = DateTime(b.day.year, b.day.month, b.day.day)
          .add(Duration(days: shift));
      final start = shift == 0 ? b.startMin : 0;
      final mins = math.max(0, end - start);
      if (mins <= 0) continue;
      if (d.isBefore(from) || d.isAfter(to)) continue;
      final note = (b.note ?? '').trim();
      out.add(TsCatSeg(
        day: d,
        s: start,
        e: end,
        mins: mins,
        label: note.isEmpty ? b.catName : note,
        cross: shift == 1 || end > 1440,
      ));
    }
  }
  out.sort((x, y) => !x.day.isSameDay(y.day)
      ? x.day.compareTo(y.day)
      : x.s.compareTo(y.s));
  return out;
}

extension on DateTime {
  bool isSameDay(DateTime o) =>
      year == o.year && month == o.month && day == o.day;
}

/// 打开「$cat 明细」半屏。periodText＝档期标签（如「本周 · 9.13-9.19」）。
Future<void> showTsCatSheet(
  BuildContext context, {
  required List<TimeBlock> blocks,
  required String cat,
  required DateTime from,
  required DateTime to,
  required int spanDays,
  required String periodText,
  required Color color,
}) {
  final segs = tsCatSegs(blocks, cat, from, to, DateTime.now());
  final sum = segs.fold<int>(0, (t, x) => t + x.mins);
  final mx = segs.isEmpty ? 1 : segs.map((x) => x.mins).reduce(math.max);
  final tokens = context.tokens;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) {
      final cs = Theme.of(bc).colorScheme;
      return SafeArea(
        child: Padding(
          key: const ValueKey('ts-cat-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                  Text(periodText,
                      style: TextStyle(
                          fontSize: 10.5, color: cs.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 12),
              // 三格：段数 / 合计 / 日均（=合计÷档期天数，原型 tscStat 同构）。
              Row(
                children: [
                  _tile(bc, '${segs.length}', '段数'),
                  _tile(bc, fmtDur(sum), '合计'),
                  _tile(bc, fmtDur((sum / math.max(1, spanDays)).round()), '日均'),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: segs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          '该时段没有此分类的时间块',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: segs.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: cs.outlineVariant),
                        itemBuilder: (_, i) =>
                            _row(cs, color, segs[i], mx),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(bc).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('收起',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('ts-cat-goto'),
                      onPressed: () {
                        Navigator.of(bc).pop();
                        // 时间页＝底部导航壳内 tab（/calendar），go 合规。
                        context.go('/calendar');
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: tokens.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('去时间页',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _tile(BuildContext bc, String v, String lab) {
  final cs = Theme.of(bc).colorScheme;
  return Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(v,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(lab,
              style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
        ],
      ),
    ),
  );
}

Widget _row(ColorScheme cs, Color color, TsCatSeg x, int mx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: Text('${x.day.month}-${_two(x.day.day)}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(x.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                Text(
                  '${tsClock(x.s)}–${tsClock(x.e)}'
                  '${x.cross ? ' · 跨零点' : ''}',
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                // 占最长段比例条（原型 width=mins/max*100%）。
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: (x.mins / math.max(1, mx)).clamp(0.0, 1.0),
                    color: color,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(fmtDur(x.mins),
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
