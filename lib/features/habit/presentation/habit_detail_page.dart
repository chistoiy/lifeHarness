import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_entry.dart';
import '../domain/habit_slip.dart';
import 'habit_aux_sheets.dart';
import 'habit_auto_sheets.dart';
import 'habit_backfill_sheet.dart';
import 'habit_edit_sheet.dart';
import 'habit_providers.dart';
import 'habit_sheets.dart';
import 'widgets/habit_kit.dart';

/// 习惯详情页（原型 p-habitDetail · 计划 §3 `/habit/:id`）。
/// 顶栏承担编辑/更多（底部不重复放按钮）；FAB 不在本页。

String _md(DateTime d) =>
    '${(d.month).toString().padLeft(2, '0')}-${(d.day).toString().padLeft(2, '0')}';

class HabitDetailPage extends ConsumerStatefulWidget {
  const HabitDetailPage({super.key, required this.habitId});

  final String habitId;

  @override
  ConsumerState<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends ConsumerState<HabitDetailPage> {
  static const kMilestones = [7, 21, 66, 100, 365];
  String _dim = 'w';
  int _dcMonth = 0;

  Future<void> _ops(Habit h) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        Widget row(String key, String label, IconData icon, VoidCallback onTap) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                key: ValueKey('ho-$key'),
                onTap: () {
                  Navigator.pop(ctx);
                  onTap();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: hCardDeco(ctx),
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                row('edit', '编辑习惯', Icons.edit_outlined,
                    () => showHabitEditSheet(context, ref, h)),
                row('set', '打卡设置', Icons.settings_outlined,
                    () => context.push('/habit-set')),
                row(
                  'copy',
                  '复制到新分类',
                  Icons.add_circle_outline,
                  () async {
                    final repo = ref.read(habitRepositoryProvider);
                    await repo.saveHabit(
                      h.copyWith(
                        id: '',
                        createdAt: 0,
                        streak: 0,
                        clearArchived: true,
                        subs: [
                          for (final s in h.subs)
                            HabitSub(name: s.name, unit: s.unit, goal: s.goal, sort: s.sort),
                        ],
                      ),
                    );
                    ref.read(habitTickProvider.notifier).state++;
                    if (!mounted) return;
                    habitToast(context, '已复制一份用于新分类');
                  },
                ),
                row(
                  'arch',
                  h.isArchived ? '恢复跟踪' : '归档 · 不再跟踪',
                  Icons.inventory_2_outlined,
                  () async {
                    final repo = ref.read(habitRepositoryProvider);
                    await repo.setArchived(h.id, !h.isArchived);
                    ref.read(habitTickProvider.notifier).state++;
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          h.isArchived
                              ? '已恢复跟踪'
                              : '已归档 · 纪录保留在详情与纪录墙',
                        ),
                        duration: const Duration(milliseconds: 1600),
                      ),
                    );
                  },
                ),
                row('export', '导出该习惯数据', Icons.description_outlined,
                    () => habitToast(
                        context, '已导出 ${h.name}.json（打卡序列 + 触发记录 · 模拟）')),
                row(
                  'del',
                  '删除习惯',
                  Icons.delete_outline,
                  () async {
                    final repo = ref.read(habitRepositoryProvider);
                    await repo.deleteHabit(h.id);
                    ref.read(habitTickProvider.notifier).state++;
                    if (!mounted) return;
                    final m = ScaffoldMessenger.of(context);
                    m.showSnackBar(
                      const SnackBar(
                        content: Text('已删除习惯 · 历史流水保留在时间账本'),
                        duration: Duration(milliseconds: 1600),
                      ),
                    );
                    if (context.mounted) context.go('/habits');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final d = ref.watch(habitDataProvider).valueOrNull;
    final h = d?.habits.where((x) => x.id == widget.habitId).firstOrNull;
    if (d == null || h == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final entries = d.of(h.id);
    final today = dayStart(DateTime.now());
    final (from, to) = switch (_dim) {
      'w' => (today.subtract(const Duration(days: 6)), today),
      'm' => (DateTime(today.year, today.month, 1), today),
      'a' => (DateTime(today.year, 1, 1), today),
      _ => (parseDay(h.startDate), today),
    };
    final cnt = habitCountOkInRange(h, entries, from, to);
    final total = habitTotalValue(h, entries, from, to);
    final rate = habitRate(
      h,
      entries: entries,
      from: from,
      to: to,
      spanFromStart: d.spanFromStart,
      rateByTotalDays: d.rateByTotalDays,
    );
    final subs = habitSubTotals(h, entries, from, to);
    final negWeekOk = [
      for (var i = 0; i < 7; i++)
        if (habitOkAt(
          h,
          entries[dayKey(today.subtract(Duration(days: 6 - i)))],
        ))
          1,
    ].length;
    // 柱状数据（原型 hbBars）
    final bars = <(String, double)>[
      if (_dim == 'w')
        for (var i = 0; i < 7; i++)
          (
            '一二三四五六日'[
              today.subtract(Duration(days: 6 - i)).weekday - 1
            ],
            entries[dayKey(today.subtract(Duration(days: 6 - i)))]?.value ?? 0,
          )
      else if (_dim == 'a')
        for (var m = 1; m <= today.month; m++)
          (
            '$m',
            habitTotalValue(
                  h,
                  entries,
                  DateTime(today.year, m, 1),
                  DateTime(today.year, m) == DateTime(today.year, m, 0)
                      ? today
                      : DateTime(today.year, m + 1, 0).isAfter(today)
                          ? today
                          : DateTime(today.year, m + 1, 0),
                ) ??
                0,
          )
      else
        for (var i = 29; i >= 0; i--)
          (
            i % 10 == 0 ? '${30 - i}' : '',
            entries[dayKey(today.subtract(Duration(days: i)))]?.value ?? 0,
          ),
    ];
    final bmax = bars.map((b) => b.$2).fold<double>(1, (a, b) => b > a ? b : a);

    // 流水近 14 天（最多 8 行）
    final flow = <(DateTime, HabitEntry)>[];
    for (var back = 0; back < 14 && flow.length < 8; back++) {
      final k = dayKey(today.subtract(Duration(days: back)));
      final e = entries[k];
      if (e == null) continue;
      if (h.isPos && !habitOkAt(h, e)) continue;
      flow.add((parseDay(k), e));
    }

    final slipsF = ref.watch(habitSlipsProvider(h.id));
    final slips = slipsF.valueOrNull ?? const <HabitSlip>[];
    final avgPer = cnt > 0 ? (total ?? 0) / cnt : 0.0;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            const Text('习惯详情', style: TextStyle(fontSize: 16)),
            Text(
              '连续 · 里程碑 · 触发记录',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('hd-edit'),
            tooltip: '编辑习惯',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => showHabitEditSheet(context, ref, h),
          ),
          IconButton(
            key: const ValueKey('hd-more'),
            tooltip: '更多操作',
            icon: const Icon(Icons.more_horiz, size: 20),
            onPressed: () => _ops(h),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 头部卡
          Container(
            decoration: hCardDeco(context),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                HabitIconTile(
                  iconKey: h.icon,
                  neg: h.isNeg,
                  size: 48,
                  radius: 16,
                  iconSize: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              h.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (h.isGroup)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.accent.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '组 · ${h.subs.length} 项',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: HK.brand,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${h.isPos ? '正向 · 坚持' : '负向 · 控制'} · ${h.dueText} · '
                        '${h.cat ?? '未分类'}'
                        '${h.remindAt != null ? ' · 提醒 ${h.remindAt}' : ' · 无提醒'}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: h.isArchived
                        ? scheme.onSurface.withValues(alpha: .06)
                        : HK.teal400.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    h.isArchived ? '已归档' : '跟踪中',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: h.isArchived
                          ? scheme.onSurfaceVariant
                          : HK.teal600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 维度切换
          Row(
            children: [
              for (final (k, lab) in const [
                ('w', '周'),
                ('m', '月'),
                ('a', '年'),
                ('all', '全部'),
              ]) ...[
                if (k != 'w') const SizedBox(width: 8),
                GestureDetector(
                  key: ValueKey('hd-dim-$k'),
                  onTap: () => setState(() => _dim = k),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _dim == k
                          ? tokens.accent
                          : scheme.onSurface.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      lab,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _dim == k ? Colors.white : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // 四指标卡
          Row(
            children: [
              _metric(
                context,
                h.isPos
                    ? '$cnt'
                    : '${_dim == 'w' ? slips.length : (slips.length * 4.3).round()}',
                h.isPos ? '打卡次数' : (_dim == 'w' ? '本周触发' : '触发次数'),
              ),
              const SizedBox(width: 8),
              _metric(
                context,
                h.isGroup
                    ? '${h.subs.length} 项'
                    : (h.hasVal ? HabitSubChips.n(total ?? 0) : '—'),
                h.isGroup ? '子项分别统计' : (h.hasVal ? '总${h.unit ?? '次'}' : '未记量'),
                color: HK.brand,
              ),
              const SizedBox(width: 8),
              _metric(context, '${h.streak}', '当前连续', color: HK.amber500),
              const SizedBox(width: 8),
              _metric(
                context,
                '$rate%',
                _dim == 'w' ? '本周达成' : '近30天达成',
                color: HK.rateText(rate),
              ),
            ],
          ),
          // 记录量
          if (h.hasVal)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                decoration: hCardDeco(context),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _HdTitle('记录量'),
                        Expanded(
                          child: Text(
                            textAlign: TextAlign.right,
                            '${_dimLabel(_dim)} · $cnt 次 · 每次均 '
                            '${HabitSubChips.n(avgPer)}${h.unit ?? ''}',
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 78,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final (lab, v) in bars)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: .5,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        v > 0 ? HabitSubChips.n(v) : '',
                                        style: const TextStyle(fontSize: 7),
                                      ),
                                      Container(
                                        height: v > 0
                                            ? (v / bmax * 52).clamp(4.0, 52.0)
                                            : 3,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(2),
                                              ),
                                          gradient:
                                              v > 0 ? tokens.gradient : null,
                                          color: v > 0
                                              ? null
                                              : scheme.onSurface.withValues(
                                                alpha: .08,
                                              ),
                                        ),
                                      ),
                                      SizedBox(
                                        height: 9,
                                        child: Text(
                                          lab,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (h.isGroup)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          children: [
                            for (final s in h.subs)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      child: Text(
                                        s.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        child: LinearProgressIndicator(
                                          minHeight: 6,
                                          value: (subs[s.id] ?? 0) /
                                              (s.goal <= 0 ? 1 : s.goal),
                                          backgroundColor:
                                              scheme.onSurface.withValues(
                                                alpha: .07,
                                              ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        textAlign: TextAlign.right,
                                        '${HabitSubChips.n(subs[s.id] ?? 0)} ${s.unit}',
                                        style: const TextStyle(fontSize: 10.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: HMiniBtn(
                            entries[dayKey(today)] != null &&
                                    habitOkAt(h, entries[dayKey(today)])
                                ? '修改今日记录量'
                                : '打卡并记量',
                            onTap: () => showHabitLogSheet(context, ref, h),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: HMiniBtn(
                            '补卡 / 补量',
                            onTap: () =>
                                showHabitBackfillSheet(context, ref, habitId: h.id),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          // 打卡日历
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              decoration: hCardDeco(context),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _HdTitle('打卡日历'),
                      Expanded(
                        child: Text(
                          textAlign: TextAlign.right,
                          h.isPos ? '绿点=已打卡' : '绿点=未触发 · 红点=触发',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _navBtn(context, Icons.chevron_left, 'hd-dc-prev',
                          () => setState(() => _dcMonth = max(-11, _dcMonth - 1))),
                      Expanded(
                        child: Center(
                          child: Text(
                            () {
                              final a = DateTime(
                                today.year,
                                today.month + _dcMonth,
                                1,
                              );
                              return '${a.year} 年 ${a.month} 月'
                                  '${_dcMonth == 0 ? ' · 本月' : ''}';
                            }(),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: _dcMonth >= 0 ? .3 : 1,
                        child: _navBtn(context, Icons.chevron_right,
                            'hd-dc-next',
                            () => setState(() => _dcMonth = min(0, _dcMonth + 1))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final w in (d.weekStart == 1
                          ? const ['日', '一', '二', '三', '四', '五', '六']
                          : const ['一', '二', '三', '四', '五', '六', '日']))
                        Expanded(
                          child: Text(
                            w,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ..._calRows(h, entries, d.weekStart),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _legend(HK.ok500, '有打卡'),
                      _legend(tokens.accent, '有数值'),
                    ],
                  ),
                  Text(
                    textAlign: TextAlign.right,
                    '点日期可补记 · 今天可直接打卡',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _HdTitle('打卡流水 · 近 14 天'),
                  const SizedBox(height: 4),
                  if (flow.isEmpty)
                    Text(
                      '还没有流水',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final (i, fdt) in flow.indexed)
                      () {
                        final fd = fdt.$1;
                        final fe = fdt.$2;
                        return Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: i == 0
                            ? null
                            : BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: scheme.outlineVariant
                                        .withValues(alpha: .5),
                                  ),
                                ),
                              ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 46,
                              child: Text(
                                _md(fd),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: dayKey(fd) == dayKey(today)
                                      ? tokens.accent
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '周${'一二三四五六日'[fd.weekday - 1]}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                fe.checkAt ?? '—',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _flowText(h, fe),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: h.isNeg
                                      ? (habitOkAt(h, fe)
                                            ? HK.teal600
                                            : HK.rose500)
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (fe.backfilled)
                              const HBadge('补记', HK.amber600, HK.amber500),
                            if (fe.origin != HabitEntry.oManual &&
                                fe.origin != HabitEntry.oBackfill)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: HBadge(
                                  '自动',
                                  scheme.onSurfaceVariant,
                                  scheme.onSurface,
                                ),
                              ),
                          ],
                        ),
                      );
                    }(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: HMiniBtn(
                          '自动达成源',
                          onTap: () => showHabitSrcSheet(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: HMiniBtn(
                          '全局统计',
                          onTap: () => context.push('/habit-stat'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 里程碑
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              decoration: hCardDeco(context),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HdTitle('里程碑'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 66,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final m in kMilestones) ...[
                          if (m != kMilestones.first) const SizedBox(width: 8),
                          Container(
                            width: 74,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: h.best >= m
                                ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: tokens.gradient,
                                  )
                                : BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$m',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: h.best >= m
                                        ? Colors.white
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  h.best >= m ? '已达成' : '天 · 还差 ${m - h.best}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: h.best >= m
                                        ? Colors.white
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 负向：触发统计
          if (h.isNeg)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                decoration: hCardDeco(context),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _HdTitle('触发统计'),
                        Expanded(
                          child: Text(
                            textAlign: TextAlign.right,
                            '额度 ${slips.length}/${h.negLimit} · 未触发 $negWeekOk/7 天',
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _metric(context, '${slips.length}', '本周触发',
                            color: HK.rose500),
                        const SizedBox(width: 8),
                        _metric(context, '${slips.length}', '累计记录'),
                        const SizedBox(width: 8),
                        _metric(context, '$negWeekOk', '未触发天数',
                            color: HK.ok500),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '情境分布',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._reasonBars(slips),
                    if (slips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '触发明细',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      for (final s in slips)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: HDot(HK.rose400),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${s.day.substring(5)}'
                                      '${s.checkAt != null ? ' ${s.checkAt}' : ''}'
                                      ' · ${s.reasons.isEmpty ? '未填情境' : s.reasons.join('、')}'
                                      '${s.amountText != null ? ' · ${s.amountText}' : ''}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (s.note?.isNotEmpty ?? false)
                                      Text(
                                        s.note!,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                key: ValueKey('hd-slip-del-${s.id}'),
                                onTap: () async {
                                  final m = ScaffoldMessenger.of(context);
                                  await ref
                                      .read(habitRepositoryProvider)
                                      .deleteSlip(s.id);
                                  ref
                                      .read(habitTickProvider.notifier)
                                      .state++;
                                  messengerToast(m, '已删除该条触发记录');
                                },
                                child: Text(
                                  '删除',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => showHabitTriggerSheet(context, h),
                      child: Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: HK.rose500.withValues(alpha: .08),
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
                  ],
                ),
              ),
            ),
          // 组内子项
          if (h.isGroup)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                decoration: hCardDeco(context),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _HdTitle('组内子项'),
                        const Spacer(),
                        HMiniBtn(
                          '编辑子项',
                          onTap: () => showHabitEditSheet(context, ref, h),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final (i, s) in h.subs.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                s.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '目标 ${HabitSubChips.n(s.goal)} ${s.unit}',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.onSurface.withValues(alpha: .06),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '本周 ${HabitSubChips.n(subs[s.id] ?? 0)}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      '达成规则：'
                      '${h.groupRule == Habit.kRuleAll ? '全部子项达标' : h.groupRule == Habit.kRuleAny ? '任一子项达标' : '过半子项达标'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 规则与绑定
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              decoration: hCardDeco(context),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HdTitle('规则与绑定'),
                  const SizedBox(height: 6),
                  _kv(context, '频率', h.dueText),
                  _kv(
                    context,
                    '记录量',
                    h.isGroup
                        ? '组内 ${h.subs.length} 项'
                        : h.hasVal
                        ? '${HabitSubChips.n(h.goal ?? 0)} ${h.unit}'
                        : '不记录',
                  ),
                  _kv(context, '提醒', h.remindAt ?? '未设置'),
                  _kv(
                    context,
                    '自动达成源',
                    h.sourceKinds.join(' / '),
                  ),
                  _kv(
                    context,
                    '开始跟踪',
                    '${h.startDate} · 已跟踪 ${today.difference(parseDay(h.startDate)).inDays + 1} 天',
                  ),
                  _kv(
                    context,
                    '宽限卡',
                    h.isPos
                        ? '${d.graceOf[h.id] ?? 0} 张可用 · 本月已用 '
                              '${(d.grace - (d.graceOf[h.id] ?? 0)).clamp(0, 99)} 张'
                        : '不适用',
                  ),
                  FutureBuilder<List<Map<String, Object?>>>(
                    future: ref
                        .read(habitRepositoryProvider)
                        .goalHistOf(h.id),
                    builder: (context, snap) {
                      final g = snap.data ?? const [];
                      if (g.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '目标变更：${g.map((x) => '${x['effective_from']} 起 ${x['goal'] ?? 0}${x['unit'] ?? ''}').join(' · ')}',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int await0(int v) => v;

  Iterable<Widget> _reasonBars(List<HabitSlip> slips) {
    const reasons = ['熬夜', '应酬', '情绪', '赶时间', '忘记', '他人带动'];
    final rows = [
      for (final r in reasons)
        (r, slips.where((s) => s.reasons.contains(r)).length),
    ].where((x) => x.$2 > 0).toList();
    if (rows.isEmpty) {
      return [
        Text(
          '还没有触发记录',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }
    return [
      for (final (r, n) in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  r,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: n / slips.length.clamp(1, 99),
                    color: HK.rose400,
                    backgroundColor:
                        Theme.of(context).colorScheme.onSurface.withValues(
                          alpha: .07,
                        ),
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                child: Text(
                  '$n',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _calRows(Habit h, Map<String, HabitEntry> entries, int weekStart) {
    final today = dayStart(DateTime.now());
    final anchor = DateTime(today.year, today.month + _dcMonth, 1);
    final lastDay = DateTime(anchor.year, anchor.month + 1, 0).day;
    final lead =
        (DateTime(anchor.year, anchor.month, 1).weekday +
            (weekStart == 1 ? 0 : 6)) %
        7;
    final start = parseDay(h.startDate);
    final out = <Widget>[];
    for (var r = 0; r * 7 < lead + lastDay; r++) {
      out.add(
        Row(
          children: [
            for (var c = 0; c < 7; c++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 1, right: 1),
                  child: () {
                    final idx = r * 7 + c - lead;
                    if (idx < 0 || idx >= lastDay) {
                      return const SizedBox(height: 38);
                    }
                    final dt = dayStart(DateTime(anchor.year, anchor.month, idx + 1));
                    if (dt.isAfter(today) || dt.isBefore(start)) {
                      return const SizedBox(height: 38);
                    }
                    final k = dayKey(dt);
                    final e = entries[k];
                    final ok = e != null && habitOkAt(h, e);
                    final trig = h.isNeg && e != null && !e.checked;
                    final hasV =
                        (e?.value ?? 0) > 0 ||
                        (e != null && e.subValues.values.any((v) => v > 0));
                    return GestureDetector(
                      key: ValueKey('hd-cal-$k'),
                      onTap: () {
                        if (k == dayKey(today)) {
                          habitToast(context, '今天请在卡片上打卡或记量');
                          return;
                        }
                        showHabitBackfillSheet(
                          context,
                          ref,
                          habitId: h.id,
                          preselectDay: k,
                        );
                      },
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: ok
                              ? (h.isPos
                                    ? HK.ok500.withValues(alpha: .10)
                                    : HK.teal400.withValues(alpha: .12))
                              : trig
                              ? HK.rose400.withValues(alpha: .12)
                              : schemeOfCtx().onSurface.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${dt.day}',
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                color: k == dayKey(today)
                                    ? tokensOfCtx().accent
                                    : ok
                                ? (h.isPos ? HK.ok700 : HK.teal600)
                                : trig
                                ? HK.rose500
                                : schemeOfCtx().onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (ok) HDot(h.isPos ? HK.ok500 : HK.teal500),
                                if (hasV) HDot(trig ? HK.rose500 : HK.brand),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }(),
                ),
              ),
          ],
        ),
      );
    }
    return out;
  }

  ColorScheme schemeOfCtx() => Theme.of(context).colorScheme;
  ThemeTokens tokensOfCtx() => context.tokens;

  Widget _navBtn(
    BuildContext context,
    IconData icon,
    String key,
    VoidCallback onTap,
  ) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16),
    ),
  );

  Widget _legend(Color c, String t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      HDot(c),
      const SizedBox(width: 3),
      Text(
        t,
        style: TextStyle(
          fontSize: 9.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _metric(
    BuildContext context,
    String v,
    String lab, {
    Color? color,
  }) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: hCardDeco(context),
      child: Column(
        children: [
          Text(
            v,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            lab,
            style: TextStyle(
              fontSize: 9.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _kv(BuildContext context, String k, String v) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

HabitEntry? e0(Map<String, HabitEntry> m, DateTime d) => m[dayKey(d)];

String _dimLabel(String dim) => switch (dim) {
  'w' => '本周',
  'm' => '本月',
  'a' => '今年',
  _ => '全部',
};

String _flowText(Habit h, HabitEntry e) {
  final ok = habitOkAt(h, e);
  final v = e.value ?? 0;
  if (h.isNeg) {
    if (ok) return '未触发';
    return v > 0 ? '触发 · ${HabitSubChips.n(v)} ${h.unit ?? '次'}' : '触发';
  }
  final note = e.note != null && e.note!.isNotEmpty ? ' · ${e.note}' : '';
  if (h.isGroup) {
    // 原型组流水＝按「项次」合计（达成判定仍按子项规则，禁跨单位仅约束汇总展示）
    final sum = e.subValues.values.fold<double>(0, (a, b) => a + b);
    return sum > 0 ? '${HabitSubChips.n(sum)} 项次$note' : '已打卡$note';
  }
  return v > 0 ? '${HabitSubChips.n(v)} ${h.unit ?? '次'}$note' : '已打卡$note';
}

class _HdTitle extends StatelessWidget {
  const _HdTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
  );
}

class HDot extends StatelessWidget {
  const HDot(this.c, {super.key});

  final Color c;

  @override
  Widget build(BuildContext context) => Container(
    width: 5,
    height: 5,
    margin: const EdgeInsets.symmetric(horizontal: .5),
    decoration: BoxDecoration(shape: BoxShape.circle, color: c),
  );
}

class HBadge extends StatelessWidget {
  const HBadge(this.t, this.fg, this.bg, {super.key});

  final String t;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 8.5,
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// 触发记录随 tick 重载（详情页负向卡消费）。
final habitSlipsProvider = FutureProvider.autoDispose
    .family<List<HabitSlip>, String>((ref, id) async {
      ref.watch(habitTickProvider);
      return ref.watch(habitRepositoryProvider).slipsOf(id);
    });
