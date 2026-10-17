import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_entry.dart';
import 'habit_providers.dart';
import 'habit_sheets.dart';
import 'widgets/habit_kit.dart';

/// 补卡弹层（原型 sheetHabitBackfill · LH-S19）。
/// 先选习惯 → 月历多选（可跨月）→ 补记时刻/数值 → 确认；补卡记录可撤销。

/// 补记时刻档（原型 HB_ATS）。
const kHabitAtChips = [
  ('清早', '06:30'),
  ('早上', '08:00'),
  ('中午', '12:30'),
  ('下午', '16:00'),
  ('晚上', '20:30'),
  ('睡前', '22:30'),
  ('不填', ''),
];

class _BackfillSheet extends ConsumerStatefulWidget {
  const _BackfillSheet({this.initHabitId, this.initDay});

  final String? initHabitId;

  /// 'YYYY-MM-DD'：从日期速览/方块格带入预选。
  final String? initDay;

  @override
  ConsumerState<_BackfillSheet> createState() => _BackfillSheetState();
}

class _BackfillSheetState extends ConsumerState<_BackfillSheet> {
  late String? _hid = widget.initHabitId;
  final Set<String> _sel = {};
  int _monthOff = 0; // 0=当前月，负=往前
  String _at = '08:00';
  bool _countStreak = true;
  List<TextEditingController> _valC = [];
  String? _valKey; // 数值初始化对应的习惯

  @override
  void initState() {
    super.initState();
    final k = widget.initDay;
    if (k != null && k.compareTo(dayKey(DateTime.now())) < 0) _sel.add(k);
  }

  Future<void> _pickHabit(String id) async {
    setState(() {
      _hid = id;
      _sel.clear();
      _monthOff = 0;
      _valKey = null;
    });
  }

  void _ensureVal(Habit h) {
    if (_valKey == h.id) return;
    for (final c in _valC) {
      c.dispose();
    }
    _valC = h.isGroup
        ? [for (final s in h.subs) TextEditingController(text: '${s.goal.toInt()}')]
        : [TextEditingController(text: '${(h.goal ?? 0).toInt()}')];
    _valKey = h.id;
  }

  Future<void> _save() async {
    final h = _habit;
    if (h == null) return;
    final m = ScaffoldMessenger.of(context);
    if (_sel.isEmpty) {
      habitToast(context, '先选要补记的日期');
      return;
    }
    final repo = ref.read(habitRepositoryProvider);
    final days = _sel.toList()..sort();
    final useVal = h.isPos && h.hasVal;
    final vals = [
      for (final c in _valC) (double.tryParse(c.text.trim()) ?? 0).clamp(0, 1e6).toDouble(),
    ];
    for (final k in days) {
      await repo.upsertEntry(
        h.id,
        day: k,
        checked: true,
        value: useVal && !h.isGroup ? vals.first : null,
        subValues: useVal && h.isGroup
            ? {
                for (final (i, s) in h.subs.indexed) s.id: vals[i],
              }
            : null,
        origin: HabitEntry.oBackfill,
        checkAt: _at.isEmpty ? null : _at,
        backfilled: true,
      );
    }
    await repo.setKv('habit.bfCountStreak', '$_countStreak');
    ref.read(habitTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.pop(context);
    final vTxt = useVal
        ? (h.isGroup ? ' · 子项 ${vals.map((v) => v % 1 == 0 ? v.toInt() : v).join('/')}' : ' · 数值 ${vals.first % 1 == 0 ? vals.first.toInt() : vals.first}')
        : '';
    messengerToast(
      m,
      '已为「${h.name}」补记 ${days.length} 天'
      '${_at.isEmpty ? '' : ' · 时刻 $_at'}$vTxt'
      '${_countStreak ? ' · 已计入连续' : ' · 未计入连续'}',
    );
  }

  Future<void> _undoDay(String k) async {
    final h = _habit;
    if (h == null) return;
    final repo = ref.read(habitRepositoryProvider);
    await repo.deleteEntry(h.id, k);
    setState(() => _sel.remove(k));
    ref.read(habitTickProvider.notifier).state++;
    if (!mounted) return;
    messengerToast(
      ScaffoldMessenger.of(context),
      '已撤销 ${k.substring(5).replaceFirst('-', '-')} 的补卡',
    );
  }

  Habit? get _habit {
    final d = ref.watch(habitDataProvider).valueOrNull;
    final list = d?.habits ?? const <Habit>[];    if (_hid != null) {
      for (final h in list) {
        if (h.id == _hid) return h;
      }
    }
    return list.where((h) => !h.isArchived).firstOrNull;
  }

  @override
  void dispose() {
    for (final c in _valC) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dAsync = ref.watch(habitDataProvider);
    final d = dAsync.valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final h = _habit;
    if (d == null || h == null) {
      return const SizedBox(height: 300);
    }
    _ensureVal(h);
    final book = d.habits.where((x) => !x.isArchived).toList();
    final entries = d.of(h.id);
    final today = dayStart(DateTime.now());
    final start = parseDay(h.startDate);
    final weekStart = d.weekStart;
    // 当前月格子
    final anchor = DateTime(today.year, today.month + _monthOff, 1);
    final lastDay = DateTime(anchor.year, anchor.month + 1, 0).day;
    final lead = (DateTime(anchor.year, anchor.month, 1).weekday + (weekStart == 1 ? 0 : 6)) % 7;
    final useVal = h.isPos && h.hasVal;
    final bfDays = entries.entries
        .where((e) => e.value.backfilled)
        .map((e) => e.key)
        .toList()
      ..sort();

    // 固定头部：标题/习惯选择/翻月/月历/图例（bottom sheet 按固有高度
    // 布局，滚动区必须给有界高度，中段与按钮钉在外面才能保证可见可点）
    final head = <Widget>[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '补卡 · ${h.name}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '已选 ${_sel.length} 天',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '先选习惯 · 再点日期，可跨月补记',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final x in book) ...[
                    if (x.id != book.first.id) const SizedBox(width: 6),
                    GestureDetector(
                      key: ValueKey('hbf-h-${x.name}'),
                      onTap: () => _pickHabit(x.id),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: x.id == h.id
                              ? tokens.accent
                              : scheme.onSurface.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          x.name,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: x.id == h.id
                                ? Colors.white
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 翻月行
            Row(
              children: [
                _navBtn(context, Icons.chevron_left, 'btn-hbf-prev',
                    () => setState(() => _monthOff = max(-11, _monthOff - 1))),
                Expanded(
                  child: Center(
                    key: const ValueKey('hbf-month'),
                    child: Text(
                      '${anchor.year} 年 ${anchor.month} 月'
                      '${_monthOff == 0 ? ' · 今天所在月' : ''}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: _monthOff >= 0 ? .3 : 1,
                  child: _navBtn(context, Icons.chevron_right, 'btn-hbf-next',
                      () => setState(() => _monthOff = min(0, _monthOff + 1))),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  key: const ValueKey('btn-hbf-clear'),
                  onTap: () {
                    if (_sel.isEmpty) {
                      habitToast(context, '当前没有选中日期');
                      return;
                    }
                    setState(_sel.clear);
                  },
                  child: Text(
                    '清空选择',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 星期头
            Row(
              children: [
                for (final w in (weekStart == 1
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
            // 月历格
            for (var r = 0; r * 7 < lead + lastDay; r++)
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
                          final dt = dayStart(
                            DateTime(anchor.year, anchor.month, idx + 1),
                          );
                          if (dt.isAfter(today) || dt.isBefore(start)) {
                            return const SizedBox(height: 38);
                          }
                          final k = dayKey(dt);
                          final e = entries[k];
                          final ok = e != null && habitOkAt(h, e);
                          final trig =
                              h.isNeg && e != null && !e.checked;
                          final hasV = (e?.value ?? 0) > 0 ||
                              (e != null &&
                                  e.subValues.values.any((v) => v > 0));
                          final on = _sel.contains(k);
                          final bg = on
                              ? tokens.accent.withValues(alpha: .10)
                              : ok
                                  ? (h.isPos
                                      ? HK.ok500.withValues(alpha: .10)
                                      : HK.teal400.withValues(alpha: .12))
                                  : trig
                                      ? HK.rose400.withValues(alpha: .12)
                                      : scheme.onSurface.withValues(
                                          alpha: .06);
                          return GestureDetector(
                            key: ValueKey('hbf-day-$k'),
                            onTap: () => setState(
                              () => on ? _sel.remove(k) : _sel.add(k),
                            ),
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(10),
                                border: on
                                    ? Border.all(color: tokens.accent, width: 2)
                                    : null,
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
                                          ? tokens.accent
                                          : ok
                                              ? (h.isPos
                                                  ? HK.ok700
                                                  : HK.teal600)
                                              : trig
                                                  ? HK.rose500
                                                  : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (ok)
                                        _dot(
                                            h.isPos ? HK.ok500 : HK.teal500),
                                      if (hasV)
                                        _dot(trig
                                            ? HK.rose500
                                            : tokens.accent),
                                      if (e?.backfilled ?? false)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 2),
                                          child: Container(
                                            width: 5,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: HK.amber500,
                                                width: 1.2,
                                              ),
                                            ),
                                          ),
                                        ),
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
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _legend(HK.ok500, '有打卡'),
                _legend(tokens.accent, '有数值'),
                _legend(HK.amber500, '补记'),
              ],
            ),
    ];

    final body = <Widget>[
            // 补记时刻
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '补记时刻',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (lab, v) in kHabitAtChips)
                        GestureDetector(
                          key: ValueKey('hbf-at-$v'),
                          onTap: () => setState(() => _at = v),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: _at == v
                                  ? tokens.accent
                                  : scheme.onSurface.withValues(alpha: .05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              v.isEmpty ? lab : '$lab $v',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color:
                                    _at == v ? Colors.white : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 补卡记录
            Container(
              decoration: hCardDeco(context),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '补卡记录',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        bfDays.isEmpty ? '暂无补记' : '${bfDays.length} 条',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (bfDays.isEmpty)
                    Text(
                      '还没有补卡记录 · 选日期后确认即生成',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final k in bfDays)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 46,
                              child: Text(
                                k.substring(5),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '周${'一二三四五六日'[parseDay(k).weekday - 1]}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                entries[k]?.checkAt ?? '—',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _logValText(h, entries[k]!),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            GestureDetector(
                              key: ValueKey('hbf-undo-$k'),
                              onTap: () => _undoDay(k),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      HK.rose500.withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '撤销',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: HK.rose500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 4),
                  Text(
                    '撤销后该天的打卡与数值一并取消',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 补记数值
            if (useVal)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  decoration: hCardDeco(context),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '补记数值',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            _sel.isEmpty
                                ? '未选日期'
                                : '将补记到所选 ${_sel.length} 天',
                            key: const ValueKey('hbf-valtip'),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (h.isGroup)
                        for (final (i, s) in h.subs.indexed)
                          _valRow(
                            context,
                            name: s.name,
                            unit: s.unit,
                            goal: s.goal,
                            controller: _valC[i],
                            keyName: 'hbf-val-$i',
                          )
                      else
                        _valRow(
                          context,
                          name: '数值',
                          unit: h.unit ?? '次',
                          goal: h.goal ?? 0,
                          controller: _valC.first,
                          keyName: 'hbf-val-0',
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '补卡计入连续天数',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch(
                  key: const ValueKey('hbf-streak'),
                  value: _countStreak,
                  onChanged: (v) => setState(() => _countStreak = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
    ];

    // 底部动作行钉在弹层底部（滚动区固有高度不可信，放外面才能保证可见）
    final footer = Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
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
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('btn-hbf-save'),
            onTap: _save,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: tokens.gradient,
              ),
              child: const Text(
                '确认补卡',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    // bottom sheet 按「固有高度」布局且不理会下方约束：必须用 LayoutBuilder
    // 把整块内容高度钉成有界值，否则中段滚动区按内容撑高、按钮被顶出屏幕。
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: min(c.maxHeight, 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...head,
              Expanded(
                child: SingleChildScrollView(child: Column(children: body)),
              ),
              footer,
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBtn(BuildContext context, IconData icon, String key,
          VoidCallback onTap) =>
      GestureDetector(
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

  Widget _dot(Color c) => Container(
        width: 4,
        height: 4,
        margin: const EdgeInsets.symmetric(horizontal: .5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );

  Widget _legend(Color c, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dot(c),
          const SizedBox(width: 3),
          Text(
            t,
            style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      );

  Widget _valRow(
    BuildContext context, {
    required String name,
    required String unit,
    required double goal,
    required TextEditingController controller,
    required String keyName,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            SizedBox(
              width: 64,
              child: TextField(
                key: ValueKey(keyName),
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              unit,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              '目标 ${goal % 1 == 0 ? goal.toInt() : goal}',
              style: TextStyle(
                fontSize: 9.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  String _logValText(Habit h, HabitEntry e) {
    final v = e.value ?? 0;
    if (h.isGroup) {
      final n = e.subValues.values.where((x) => x > 0).length;
      return n > 0 ? '量 $n 项' : '仅打卡';
    }
    return v > 0 ? '量 ${v % 1 == 0 ? v.toInt() : v} ${h.unit ?? '次'}' : '仅打卡';
  }
}

/// 打开补卡弹层；[preselectDay] 为 'YYYY-MM-DD'（日期速览带入）。
Future<void> showHabitBackfillSheet(
  BuildContext context,
  WidgetRef ref, {
  String? habitId,
  String? preselectDay,
}) => hBottomSheet<void>(
  context,
  (_) => _BackfillSheet(initHabitId: habitId, initDay: preselectDay),
);
