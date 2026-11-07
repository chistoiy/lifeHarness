import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_entry.dart';
import 'habit_backfill_sheet.dart';
import 'habit_providers.dart';
import 'widgets/habit_kit.dart';

/// 习惯弹层集合（原型 sheetHabitLog / sheetHabitDay / sheetHabitEdit）。
/// 批1 三张；记触发/补卡/操作/待确认/字典/模板/分享随批2/3/5 落。

void habitToast(BuildContext context, String msg) =>
    messengerToast(ScaffoldMessenger.of(context), msg);

/// 先取 messenger 再 pop 弹层后仍可用（弹层 context 失效场景）。
void messengerToast(ScaffoldMessengerState m, String msg) => m
  ..hideCurrentSnackBar()
  ..showSnackBar(
    SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 1600),
    ),
  );

/// 底部弹层骨架公开入口（供 habit_aux_sheets 等复用）。
Future<T?> hBottomSheet<T>(
  BuildContext context,
  Widget Function(BuildContext) build,
) => _hSheet<T>(context, build);

/// 底部弹层骨架（真机验收轮2 同款：constraints 限高=屏高-状态栏-24，
/// 作为 sheet 约束参与布局；builder 内 viewInsets 取弹层自身 context）。
Future<T?> _hSheet<T>(BuildContext context, Widget Function(BuildContext) build) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            24,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: SafeArea(child: Builder(builder: build)),
      ),
    );





// =====================================================================
// 记量弹层（sheetHabitLog · LH-S16）
// =====================================================================

/// 记量步进档位 —— **实现已迁 domain**（[habitStepOf]）。
///
/// 留这个名字是因为本文件里两处加减按钮都按 `hStepOf(goal)` 读，语义上就是
/// 「本弹层的步进」；**禁在本文件另写一套阶梯**（桌面小组件的 `+N` 用的是
/// 同一个 domain 函数）。
double hStepOf(double goal) => habitStepOf(goal);

/// 快捷量 chips（原型 hbQuick：半目标/1.5x/目标/2x/3x 去重升序取 6）。
List<double> hQuick(double goal) {
  final g = goal <= 0 ? 10.0 : goal;
  final set = <double>{
    (g / 2).round().clamp(1, 1000000).toDouble(),
    (g * 1.5).round().toDouble(),
    g,
    g * 2,
    g * 3,
  };
  final l = set.where((v) => v > 0).toList()..sort();
  return l.length > 6 ? l.sublist(0, 6) : l;
}

/// 记量/记录编辑弹层（2026-10-18 批E 扩成**按日记录编辑**）。
///
/// 原来只服务「今日记量」（`habits_page` 点卡片进来）；产品真机反馈
/// 「缺少修改打卡记录，删除或修改（打卡时间、数值这一类的）」——故：
///  · 新增 [day]：传了就编辑**那一天**的记录（习惯详情「打卡流水」每行点进来）；
///  · 新增**打卡时间**可改（`showTimePicker`，原来只有「首次打卡时刻」自动落）；
///  · 保存时**保留原来源/补记标记**（改一条历史补记不该把它洗成手动记录）。
Future<void> showHabitLogSheet(
  BuildContext context,
  WidgetRef ref,
  Habit h, {
  String? day,
}) async {
  await _hSheet<void>(
    context,
    (ctx) => _HabitLogSheet(habit: h, ref: ref, day: day),
  );
}

class _HabitLogSheet extends ConsumerStatefulWidget {
  const _HabitLogSheet({required this.habit, required this.ref, this.day});
  final Habit habit;
  final WidgetRef ref;

  /// 要编辑的日键（`null`＝今天）。历史日从「打卡流水」进来。
  final String? day;

  @override
  ConsumerState<_HabitLogSheet> createState() => _HabitLogSheetState();
}

class _HabitLogSheetState extends ConsumerState<_HabitLogSheet> {
  late final List<double> _v;
  late final TextEditingController _note;
  Habit get h => widget.habit;
  String get todayK => dayKey(DateTime.now());

  /// 本次编辑的目标日（`null` 传参＝今天）。
  String get k => widget.day ?? todayK;

  /// 是否在编辑今天（决定「补记」标记与文案口径）。
  bool get isToday => k == todayK;

  /// 打卡时刻（`HH:MM`）：取原记录，没有就取此刻；**可在弹层里改**。
  late String _at = () {
    final e = widget.ref.read(habitDataProvider).valueOrNull?.of(h.id)[k];
    final at = e?.checkAt;
    return (at != null && at.isNotEmpty) ? at : hhmmNow();
  }();

  @override
  void initState() {
    super.initState();
    final e = widget.ref.read(habitDataProvider).valueOrNull?.of(h.id)[k];
    _v = h.isGroup
        ? (e != null && e.subValues.values.any((v) => v > 0)
              ? [for (final s in h.subs) e.subValues[s.id] ?? 0]
              : [for (final s in h.subs) s.goal])
        : [e?.value != null && e!.value! > 0 ? e.value! : (h.goal ?? 0)];
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _checked {
    final e = widget.ref.read(habitDataProvider).valueOrNull?.of(h.id)[k];
    return e != null && habitOkAt(h, e);
  }

  int get _met => [
    for (final (i, s) in h.subs.indexed)
      if (s.goal > 0 && _v[i] >= s.goal) 1,
  ].length;

  bool get _ruleOk => h.isGroup
      ? switch (h.groupRule) {
          Habit.kRuleAny => _met >= 1,
          Habit.kRuleHalf => _met >= (h.subs.length / 2).ceil(),
          _ => _met == h.subs.length,
        }
      : true;

  Future<void> _save() async {
    final repo = widget.ref.read(habitRepositoryProvider);
    if (h.isGroup && !_ruleOk) {
      habitToast(
        context,
        '未达组内达成条件（$_met/${h.subs.length} 项达标）· 可改为「任一即达成」',
      );
      return;
    }
    final e = widget.ref.read(habitDataProvider).valueOrNull?.of(h.id)[k];
    await repo.upsertEntry(
      h.id,
      day: k,
      checked: true,
      value: h.isGroup ? null : _v[0],
      subValues: h.isGroup
          ? {
              for (final (i, s) in h.subs.indexed) s.id: _v[i],
            }
          : null,
      // ⚠ **保留原来源**：改一条补记/自动源记录，不该把它洗成「手动」。
      //   （旧实现一律写 oManual ⇒ 改一次值，历史来源就丢了。）
      origin: e?.origin ?? HabitEntry.oManual,
      // 打卡时刻＝弹层里可改的那个值（不再「沿用旧值/取此刻」二选一）。
      checkAt: _at,
      // 补记标记同理保留；历史日首次建记录按补记算。
      backfilled: e?.backfilled ?? !isToday,
      frozen: e?.frozen,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    final after = await repo.habitById(h.id);
    widget.ref.read(habitTickProvider.notifier).state++;
    if (!mounted) return;
    // toast 文案不依赖 provider 重载时序：量取本次刚写入的值，streak 取重算回写后的缓存列
    final valText = habitValText(
      h,
      HabitEntry(
        habitId: h.id,
        day: k,
        checked: true,
        value: h.isGroup ? null : _v[0],
        subValues: h.isGroup
            ? {
                for (final (i, s) in h.subs.indexed) s.id: _v[i],
              }
            : const {},
        origin: HabitEntry.oManual,
      ),
    );
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messengerToast(
      messenger,
      isToday
          ? '已记录 · ${h.name} 今日 $valText · 连续 ${after?.streak ?? h.streak} 天'
          : '已修改 · ${h.name} ${_md(k)} $valText · 时刻 $_at',
    );
  }

  Future<void> _undo() async {
    final repo = widget.ref.read(habitRepositoryProvider);
    await repo.deleteEntry(h.id, k);
    widget.ref.read(habitTickProvider.notifier).state++;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messengerToast(
      messenger,
      isToday ? '已撤销今日打卡与记录量' : '已删除 ${_md(k)} 的记录',
    );
  }

  /// 日键 → `M月d日`（弹层副文案用；不引新工具函数，保持本文件自足）。
  String _md(String day) {
    final p = day.split('-');
    if (p.length != 3) return day;
    return '${int.tryParse(p[1]) ?? p[1]}月${int.tryParse(p[2]) ?? p[2]}日';
  }

  /// 改打卡时刻（任意分钟，不限整点）：`showTimePicker` 24 小时制。
  Future<void> _pickAt() async {
    final p = _at.split(':');
    final init = TimeOfDay(
      hour: int.tryParse(p.first) ?? 8,
      minute: p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: init,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _at = '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = widget.ref.watch(habitDataProvider).valueOrNull?.of(h.id)[k];
    final rows = h.isGroup
        ? [for (final (i, s) in h.subs.indexed) (i, s.name, s.unit, s.goal)]
        : [(0, h.name, h.unit ?? '次', h.goal ?? 0)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${isToday ? '打卡记量' : '记录'} · ${h.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              GestureDetector(
                key: const ValueKey('btn-hlog-clear'),
                onTap: () => setState(() {
                  for (var i = 0; i < _v.length; i++) {
                    _v[i] = 0;
                  }
                }),
                child: Text(
                  '清零',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            (h.isGroup
                    ? '组内 ${h.subs.length} 项 · ${HabitSubChips.ruleText(h)}'
                    : '目标 ${HabitSubChips.n(h.goal ?? 0)} ${h.unit ?? '次'} · 可直接改') +
                (isToday ? '' : ' · ${_md(k)}${e?.backfilled ?? false ? ' · 补记' : ''}'),
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          // ── 打卡时刻（批E：可改）────────────────────────────────
          // 原来只有「首次打卡时刻」自动落，用户想改早上补记成 07:30 没有入口；
          // 这里给一个整行可点的时刻位，点开系统时间选择器（24 小时制）。
          GestureDetector(
            key: const ValueKey('hlog-at'),
            onTap: _pickAt,
            child: Container(
              decoration: hCardDeco(context),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '打卡时间',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _at,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 布尔型习惯没有「量」，整块数值区不出现（批E：本弹层已是通用记录编辑）。
                  if (h.hasVal)
                    for (final (i, name, unit, goal) in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: hCardDeco(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '目标 ${HabitSubChips.n(goal)} $unit',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                HSmallBtn(
                                  icon: Icons.remove,
                                  size: 32,
                                  onTap: () => setState(
                                    () => _v[i] =
                                        (_v[i] - hStepOf(goal)).clamp(0, 1e9),
                                  ),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: TextField(
                                    key: ValueKey('hlog-val-$i'),
                                    controller: TextEditingController(
                                      text: HabitSubChips.n(_v[i]),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    onSubmitted: (s) => setState(
                                      () => _v[i] =
                                          (double.tryParse(s) ?? 0).clamp(
                                            0,
                                            1e9,
                                          ),
                                    ),
                                  ),
                                ),
                                HSmallBtn(
                                  icon: Icons.add,
                                  size: 32,
                                  onTap: () => setState(
                                    () => _v[i] = _v[i] + hStepOf(goal),
                                  ),
                                ),
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    unit,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                for (final q in hQuick(goal))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: PillChip(
                                      label: HabitSubChips.n(q),
                                      selected: _v[i] == q,
                                      onTap: () =>
                                          setState(() => _v[i] = q),
                                    ),
                                  ),
                                PillChip(
                                  label: '清零',
                                  selected: false,
                                  onTap: () => setState(() => _v[i] = 0),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (h.isGroup)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '已达标 $_met/${h.subs.length} 项'
                        '${h.groupRule == Habit.kRuleAll && !_ruleOk ? ' · 还差 ${h.subs.length - _met} 项' : _ruleOk ? ' · 满足达成条件' : ''}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: _ruleOk ? FontWeight.w700 : null,
                          color: _ruleOk ? HK.ok500 : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Text(
                        '备注',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _note,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: isToday ? '可选 · 今天的情况' : '可选 · 当天的情况',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                key: const ValueKey('btn-hlog-undo'),
                onTap: _checked ? _undo : () => Navigator.pop(context),
                child: Container(
                  width: 80,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: HK.rose500.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isToday ? '撤销' : '删除',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: HK.rose500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 80,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('btn-hlog-save'),
                  onTap: _save,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: context.tokens.gradient,
                    ),
                    child: Text(
                      _checked ? '保存修改' : '保存并打卡',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String hhmmNow() {
  final n = DateTime.now();
  return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
}

// =====================================================================
// 日期速览弹层（sheetHabitDay · LH-S18 · 三处共用月历 LH-C09 之「速览」侧）
// =====================================================================

/// 打开日期速览。[back] 初始回看天数；[onPick] 选日内联回主页切日。
Future<void> showHabitDaySheet(
  BuildContext context,
  WidgetRef ref,
  int back, {
  required void Function(int back) onPick,
}) {
  return _hSheet<void>(
    context,
    (ctx) => _HabitDaySheet(back: back, onPick: onPick),
  );
}

class _HabitDaySheet extends ConsumerStatefulWidget {
  const _HabitDaySheet({required this.back, required this.onPick});
  final int back;
  final void Function(int back) onPick;

  @override
  ConsumerState<_HabitDaySheet> createState() => _HabitDaySheetState();
}

class _HabitDaySheetState extends ConsumerState<_HabitDaySheet> {
  late int _back = widget.back;
  late int _monthOff = () {
    final d = DateTime.now().subtract(Duration(days: widget.back));
    final t0 = DateTime.now();
    return ((d.year * 12 + d.month) - (t0.year * 12 + t0.month)).clamp(-11, 0);
  }();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final dAsync = ref.watch(habitDataProvider);
    if (!dAsync.hasValue) return const SizedBox(height: 300);
    final d = dAsync.requireValue;
    final t0 = dayStart(DateTime.now());
    final book = d.book;
    final viewDay = t0.subtract(Duration(days: _back));
    final viewDayK = dayKey(viewDay);

    (int, int) okCount(String k) {
      var ok = 0;
      for (final h in book) {
        if (h.startDate.compareTo(k) > 0) continue;
        if (habitOkAt(h, d.of(h.id)[k])) ok++;
      }
      return (ok, book.length);
    }

    final anchor = DateTime(
      t0.year,
      t0.month + _monthOff,
    );
    final monthLabel = '${anchor.year} 年 ${anchor.month} 月';
    final first = DateTime(anchor.year, anchor.month, 1);
    final lastDay = DateTime(anchor.year, anchor.month + 1, 0).day;
    final lead = d.weekStart == 1
        ? first.weekday % 7
        : first.weekday - 1;
    final heads = d.weekStart == 1
        ? const ['日', '一', '二', '三', '四', '五', '六']
        : const ['一', '二', '三', '四', '五', '六', '日'];
    final rows = [
      for (final h in book) (h, d.of(h.id)[viewDayK]),
    ];
    final okN = rows.where((r) => habitOkAt(r.$1, r.$2)).length;
    final bfN = rows
        .where((r) => habitOkAt(r.$1, r.$2) && (r.$2?.backfilled ?? false))
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HSmallBtn(
                icon: Icons.chevron_left,
                size: 28,
                onTap: () =>
                    setState(() => _monthOff = (_monthOff - 1).clamp(-11, 0)),
              ),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              HSmallBtn(
                icon: Icons.chevron_right,
                size: 28,
                disabled: _monthOff >= 0,
                onTap: () =>
                    setState(() => _monthOff = (_monthOff + 1).clamp(-11, 0)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final w in heads)
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
          _monthGrid(
            cells: [
              for (var i = 0; i < lead; i++) null,
              for (var day = 1; day <= lastDay; day++)
                () {
                  final k = dayKey(DateTime(anchor.year, anchor.month, day));
                  return k.compareTo(dayKey(t0)) <= 0 ? k : null;
                }(),
            ],
            t0: t0,
            okCount: okCount,
            viewDayK: viewDayK,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '格内数字为当天达成习惯数 · 点日期切换 · 点下方条目可直接打卡',
              style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_back == 0 ? '今天' : _back == 1 ? '昨天' : '$_back 天前'} · ${viewDayK.substring(5)} 周${'一二三四五六日'[viewDay.weekday - 1]}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$okN / ${rows.length} 达成${bfN > 0 ? ' · 含补记 $bfN' : ''}',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (h, e) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _rowTap(h),
                      child: Container(
                        decoration: hCardDeco(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            HabitIconTile(
                              iconKey: h.icon,
                              neg: h.isNeg,
                              size: 24,
                              radius: 8,
                              iconSize: 13,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                h.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              (e?.checkAt?.isNotEmpty ?? false)
                                  ? e!.checkAt!
                                  : '—',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 84,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _rowStateText(h, e),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: habitOkAt(h, e)
                                        ? tokens.accent
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            _rowBadge(h, e),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      '还没有习惯 · 先去新建一个',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: hCardDeco(context),
                    child: Text(
                      '关闭',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('btn-hday-backfill'),
                  onTap: () async {
                    // 原型 hbDayToBackfill：开补卡并预选当前日 → 关闭速览
                    final m = ScaffoldMessenger.of(context);
                    final dayK = dayKey(
                      dayStart(DateTime.now())
                          .subtract(Duration(days: _back)),
                    );
                    await showHabitBackfillSheet(
                      context,
                      ref,
                      preselectDay: dayK,
                    );
                    messengerToast(
                      m,
                      '已选中 ${dayK.substring(5)} · 选习惯后确认补记',
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: tokens.gradient,
                    ),
                    child: const Text(
                      '去补卡 / 补量',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _rowStateText(Habit h, HabitEntry? e) {
    if (!habitOkAt(h, e)) {
      return h.isNeg && e != null && !e.checked ? '触发' : '未打卡';
    }
    if (!h.hasVal || e == null) return '已打卡';
    if (h.isGroup) {
      final n = e.subValues.values.where((v) => v > 0).length;
      return n > 0 ? '量 $n 项' : '已打卡';
    }
    return e.value != null ? '量 ${HabitSubChips.n(e.value!)} ${h.unit}' : '已打卡';
  }

  Widget _rowBadge(Habit h, HabitEntry? e) {
    final scheme = Theme.of(context).colorScheme;
    if (habitOkAt(h, e) && (e?.backfilled ?? false)) {
      return _badge('补', HK.amber600, HK.amber500);
    }
    if (habitOkAt(h, e) && h.sourceKinds.any((s) => s != '手动打卡')) {
      return _badge('自动', scheme.onSurfaceVariant, scheme.onSurface);
    }
    return const SizedBox(width: 26);
  }

  Widget _badge(String t, Color fg, Color tint) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 8.5, color: fg, fontWeight: FontWeight.w700),
    ),
  );

  Future<void> _rowTap(Habit h) async {
    if (_back != 0) {
      // 原型 hbDayRowTap：历史日 → 进详情 + 指引补卡
      final m = ScaffoldMessenger.of(context);
      context.push('/habit/${h.id}');
      Navigator.pop(context);
      messengerToast(m, '查看 / 修改历史日期请用「去补卡 · 补量」');
      return;
    }
    final d = ref.read(habitDataProvider).requireValue;
    final k = dayKey(dayStart(DateTime.now()));
    final e = d.of(h.id)[k];
    final okNow = habitOkAt(h, e);
    if (h.isPos && h.hasVal && !okNow) {
      await showHabitLogSheet(context, ref, h);
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
    if (!h.isPos && okNow) {
      return; // 今天已计入未触发
    }
    final repo = ref.read(habitRepositoryProvider);
    if (okNow) {
      await repo.deleteEntry(h.id, k);
    } else {
      await repo.upsertEntry(
        h.id,
        day: k,
        checked: true,
        origin: HabitEntry.oManual,
        checkAt: hhmmNow(),
      );
    }
    ref.read(habitTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.pop(context);
  }

  Widget _monthGrid({
    required List<String?> cells,
    required DateTime t0,
    required (int, int) Function(String) okCount,
    required String viewDayK,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final rowsW = <Widget>[];
    for (var r = 0; r * 7 < cells.length; r++) {
      final cells7 = <Widget>[];
      for (var c = 0; c < 7; c++) {
        final idx = r * 7 + c;
        final k = idx < cells.length ? cells[idx] : null;
        cells7.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 2, left: 2),
              child: k == null
                  ? const SizedBox(height: 38)
                  : () {
                      final (ok, tot) = okCount(k);
                      final lv = ok == 0
                          ? 0
                          : ok <= tot * .25
                          ? 1
                          : ok <= tot * .5
                          ? 2
                          : ok <= tot * .75
                          ? 3
                          : 4;
                      final bg = [
                        scheme.onSurface.withValues(alpha: .06),
                        HK.ok500.withValues(alpha: .10),
                        HK.ok500.withValues(alpha: .20),
                        HK.ok500.withValues(alpha: .30),
                        HK.ok500.withValues(alpha: .45),
                      ][lv];
                      final isToday = k == dayKey(t0);
                      final dnum = int.parse(k.substring(8));
                      return GestureDetector(
                        onTap: () {
                          final back = t0.difference(parseDay(k)).inDays;
                          final dd = parseDay(k);
                          setState(() {
                            _back = back;
                            _monthOff =
                                ((dd.year * 12 + dd.month) -
                                        (t0.year * 12 + t0.month))
                                    .clamp(-11, 0);
                          });
                          if (back <= 6) widget.onPick(back);
                        },
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(10),
                            border: k == viewDayK
                                ? Border.all(color: tokens.accent, width: 2)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$dnum',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                  color: isToday
                                      ? tokens.accent
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                ok > 0 ? '$ok/$tot' : '—',
                                style: TextStyle(
                                  fontSize: 8,
                                  height: 1,
                                  color: ok > 0
                                      ? HK.ok700.withValues(alpha: .9)
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }(),
            ),
          ),
        );
      }
      rowsW.add(Row(children: cells7));
    }
    return Column(children: rowsW);
  }
}
