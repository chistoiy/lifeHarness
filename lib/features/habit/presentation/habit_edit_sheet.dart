import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/wheel_date.dart';
import '../../../core/widgets/wheel_time.dart';
import '../../../shared/linkage/habit_mounts.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_dict.dart';
import '../domain/habit_template.dart';
import 'habit_aux_sheets.dart';
import 'habit_auto_sheets.dart';
import 'habit_providers.dart';
import 'habit_sheets.dart';
import 'widgets/habit_kit.dart';

/// 新建/编辑习惯表单（原型 sheetHabitEdit · 全字段一次性落地；
/// 组子项/达成规则随批2 联调，负向触发弹层在批2）。
/// 长表单保存钮＝常驻 footer（Column+Expanded 滚动区），永不随滚动消失。
Future<void> showHabitEditSheet(
  BuildContext context,
  WidgetRef ref,
  Habit? habit,
) => _hSheetEdit(context, _HabitEditSheet(orig: habit));

Future<T?> _hSheetEdit<T>(BuildContext context, Widget child) =>
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
        child: SafeArea(child: child),
      ),
    );

class _SubDraft {
  _SubDraft({required this.name, required this.goal, required this.unit});
  final TextEditingController name;
  final TextEditingController goal;
  String unit;
}

class _HabitEditSheet extends ConsumerStatefulWidget {
  const _HabitEditSheet({this.orig});
  final Habit? orig;

  @override
  ConsumerState<_HabitEditSheet> createState() => _HabitEditSheetState();
}

class _HabitEditSheetState extends ConsumerState<_HabitEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _goal;
  late String _icon;
  late String _type;
  late String _cat;
  late String _cycle;
  late final Set<int> _days;
  late String _target; // 负向额度 / 月度次数（select 值）
  late String _valMode; // off|one|group
  late String _unit;
  late String _rule;
  late final List<_SubDraft> _subs;
  late String _remindMode; // off|on
  late String _remindVal;
  late final Set<String> _srcs;
  late bool _todoOn;
  late String _todoForm;
  late String _start;
  late String _goalFrom;

  Habit? get o => widget.orig;

  @override
  void initState() {
    super.initState();
    final h = o;
    _name = TextEditingController(text: h?.name ?? '');
    _icon = h?.icon ?? 'run';
    _type = h?.type ?? Habit.kPos;
    _cat = h?.cat ?? '健康';
    _cycle = h?.cycle ?? Habit.kDay;
    _days = {if (h != null) ...h.weekDays};
    _target =
        '${h == null ? 2 : (h.isNeg ? h.negLimit : (h.monthTarget ?? 6))}';
    _valMode = h == null ? 'off' : (h.isGroup ? 'group' : (h.hasVal ? 'one' : 'off'));
    _unit = h?.unit?.isNotEmpty == true ? h!.unit! : '分钟';
    _goal = TextEditingController(text: '${h?.goal ?? 30}');
    _rule = h?.groupRule ?? Habit.kRuleAll;
    _subs = [
      for (final s in h?.subs ?? <HabitSub>[])
        _SubDraft(
          name: TextEditingController(text: s.name),
          goal: TextEditingController(text: '${s.goal % 1 == 0 ? s.goal.toInt() : s.goal}'),
          unit: s.unit,
        ),
    ];
    _remindMode = (h?.remindAt?.isNotEmpty ?? false) ? 'on' : 'off';
    _remindVal = h?.remindAt?.isNotEmpty == true ? h!.remindAt! : '07:00';
    _srcs = {if (h != null) ...h.sourceKinds else '手动打卡'};
    _todoOn = h?.todoId != null || h == null;
    _todoForm = h?.todoForm ?? 'norm';
    _start = h?.startDate ?? dayKey(DateTime.now());
    _goalFrom = dayKey(DateTime.now());
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    for (final s in _subs) {
      s.name.dispose();
      s.goal.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool forStart}) async {
    final p = await showWheelDatePick(
      context,
      DateTime.parse(forStart ? _start : _goalFrom),
    );
    if (p == null) return;
    setState(() {
      final k = dayKey(p);
      if (forStart) {
        _start = k;
      } else {
        _goalFrom = k;
      }
    });
  }

  /// 模板填充（原型 hbTplUse 同口径：只带出表单字段，额度保持默认，可继续修改）。
  void _applyTpl(HabitTemplate t) {
    setState(() {
      _name.text = t.name;
      _icon = t.icon;
      _type = t.type;
      _cat = t.cat;
      _cycle = t.cycle;
      _days
        ..clear()
        ..addAll(t.weekDays);
      _valMode = t.isGroup
          ? 'group'
          : (t.unit?.isNotEmpty ?? false)
          ? 'one'
          : 'off';
      _unit = t.unit?.isNotEmpty ?? false ? t.unit! : '分钟';
      _goal.text = HabitSubChips.n(t.goal ?? 1);
      _rule = t.groupRule ?? Habit.kRuleAll;
      _subs
        ..clear()
        ..addAll([
          for (final s in t.subs)
            _SubDraft(
              name: TextEditingController(text: s.name),
              goal: TextEditingController(text: HabitSubChips.n(s.goal)),
              unit: s.unit,
            ),
        ]);
      _remindMode = t.remind != null ? 'on' : 'off';
      if (t.remind != null) _remindVal = t.remind!;
    });
    habitToast(context, '已按模板填充「${t.name}」· 可继续修改');
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.isEmpty) {
      habitToast(context, '先给习惯起个名字');
      return;
    }
    final grp = _valMode == 'group';
    if (_type == Habit.kNeg && grp) {
      habitToast(context, '负向习惯不支持组打卡');
      return;
    }
    final subs = <HabitSub>[
      for (final s in _subs)
        if (s.name.text.trim().isNotEmpty &&
            (double.tryParse(s.goal.text) ?? 0) > 0)
          HabitSub(
            name: s.name.text.trim(),
            unit: s.unit,
            goal: double.parse(s.goal.text),
            sort: _subs.indexOf(s),
          ),
    ];
    if (grp && subs.isEmpty) {
      habitToast(context, '组习惯至少要有 1 个子项');
      return;
    }
    final neg = _type == Habit.kNeg;
    final tgt = int.tryParse(_target) ?? (neg ? 2 : 6);
    final base = o;
    // L10 自动生成关联待办（默认开 · 标题约定「打卡：<习惯名>」，todo_id 回写）。
    var linkedTodoId = base?.todoId;
    if (_srcs.contains('待办勾选') && _todoOn && linkedTodoId == null) {
      final tid = await habitCreateLinkedTodo(ref, n, form: _todoForm);
      linkedTodoId = tid?.toString();
    }
    final habit = Habit(
      id: base?.id ?? '',
      name: n,
      icon: _icon,
      type: _type,
      cat: _cat,
      cycle: _cycle,
      weekDays: [..._days]..sort(),
      monthTarget: !neg && _cycle == Habit.kMonth ? tgt : null,
      negLimit: neg ? tgt : 0,
      unit: _valMode == 'one' ? _unit : null,
      goal: _valMode == 'one' ? (double.tryParse(_goal.text) ?? 0) : null,
      groupRule: grp ? _rule : null,
      sourceKinds: _srcs.toList(),
      remindAt: _remindMode == 'on' ? _remindVal : null,
      todoId: linkedTodoId,
      todoForm: _srcs.contains('待办勾选') ? _todoForm : null,
      startDate: base?.startDate ?? _start,
      streak: base?.streak ?? 0,
      best: base?.best ?? 0,
      archivedAt: base?.archivedAt,
      createdAt: base?.createdAt ?? 0,
      subs: subs,
    );
    final repo = ref.read(habitRepositoryProvider);
    final saved = await repo.saveHabit(habit);
    // 逐习惯提醒即时重排（remindAll × dnd 门控 · NotificationService 未就绪时 no-op）。
    await NotificationService.registerHabitReminder(
      habitId: saved.id,
      title: saved.name,
      hhmm: saved.remindAt,
      enabled: saved.remindAt?.isNotEmpty == true &&
          await repo.kvBool('habit.remindAll', true) &&
          !habitInDnd(await repo.kvInt('habit.dnd', 1), saved.remindAt ?? ''),
    );
    ref.read(habitTickProvider.notifier).state++;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messengerToast(
      messenger,
      '已保存「${saved.name}」· ${saved.dueText}'
      '${grp ? ' · 组内 ${subs.length} 项' : (_valMode == 'one' ? ' · 目标 ${saved.goal} ${saved.unit}' : '')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final d = ref.watch(habitDataProvider).valueOrNull;
    final cats = [
      for (final c in d?.cats ?? const <HabitDict>[]) c.name,
      if ((d?.cats ?? const []).isEmpty) '健康',
    ];
    final units = [
      for (final u in d?.units ?? const <HabitDict>[]) u.name,
      if ((d?.units ?? const []).isEmpty) '分钟',
    ];

    Widget tf(TextEditingController c, {double w = 64, TextInputType? kb}) =>
        SizedBox(
          width: w,
          child: TextField(
            controller: c,
            keyboardType: kb ?? const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  o == null ? '新建习惯' : '编辑习惯',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            children: [
              TextField(
                key: const ValueKey('he-name'),
                controller: _name,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '习惯名称，如：晨间跑步 30 分钟',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  PillChip(
                    label: '从模板填充',
                    key: const ValueKey('btn-he-tpl'),
                    onTap: () async {
                      final t = await showHabitTplSheet(context);
                      if (t != null && mounted) _applyTpl(t);
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '带出分类 / 频率 / 目标量 / 提醒',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const _SecHead('图标'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in HIcons.pickerKeys)
                    GestureDetector(
                      onTap: () => setState(() => _icon = k),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: k == _icon ? tokens.gradient : null,
                          border: k == _icon
                              ? null
                              : Border.all(color: scheme.outlineVariant),
                        ),
                        child: Icon(
                          HIcons.resolve(k),
                          size: 18,
                          color: k == _icon
                              ? Colors.white
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const _SecHead('类型'),
              Row(
                children: [
                  Expanded(
                    child: PillChip(
                      label: '正向 · 要坚持',
                      selected: _type == Habit.kPos,
                      onTap: () => setState(() => _type = Habit.kPos),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillChip(
                      label: '负向 · 要减少',
                      selected: _type == Habit.kNeg,
                      onTap: () => setState(() {
                        _type = Habit.kNeg;
                        if (_valMode == 'group') _valMode = 'one';
                      }),
                    ),
                  ),
                ],
              ),
              const _SecHead('分类'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in cats)
                    PillChip(
                      label: c,
                      selected: c == _cat,
                      onTap: () => setState(() => _cat = c),
                    ),
                  PillChip(
                    label: '＋ 自定义',
                    onTap: () => showHabitMgrSheet(context, HabitDict.kCat),
                  ),
                ],
              ),
              const _SecHead('频率'),
              Row(
                children: [
                  for (final (i, it) in const [
                    ('day', '每天'),
                    ('week', '每周固定日'),
                    ('month', '每月 N 次'),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: PillChip(
                        label: it.$2,
                        selected: it.$1 == _cycle,
                        onTap: () => setState(() => _cycle = it.$1),
                      ),
                    ),
                  ],
                ],
              ),
              if (_cycle == Habit.kWeek)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (i, w) in const ['一', '二', '三', '四', '五', '六', '日'].indexed)
                        PillChip(
                          label: w,
                          selected: _days.contains(i),
                          onTap: () => setState(
                            () => _days.contains(i)
                                ? _days.remove(i)
                                : _days.add(i),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_type == Habit.kNeg || _cycle == Habit.kMonth)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    decoration: hCardDeco(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _type == Habit.kNeg ? '周期内允许出现上限' : '每月目标次数',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DropdownButton<String>(
                              value: _target,
                              underline: const SizedBox(),
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface,
                              ),
                              items: [
                                for (final v in const [
                                  '1',
                                  '2',
                                  '3',
                                  '4',
                                  '5',
                                  '6',
                                  '8',
                                  '10',
                                  '12',
                                  '15',
                                  '20',
                                  '30',
                                ])
                                  DropdownMenuItem(value: v, child: Text(v)),
                              ],
                              onChanged: (v) => setState(() => _target = v ?? '2'),
                            ),
                            Text(
                              _type == Habit.kNeg
                                  ? (_cycle == Habit.kMonth ? '次 / 月' : '次 / 周')
                                  : '次 / 月 目标',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _type == Habit.kNeg
                              ? '未触发日自动积累 · 用满额度当周记为未守住'
                              : '每月累计达成该次数即视为本月完成',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const _SecHead('记录量', hint: '（打卡时填数值 · 可周 / 月 / 年汇总）'),
              Row(
                children: [
                  for (final (i, it) in [
                    ('off', '只打卡不记量'),
                    ('one', '记单一数值'),
                    if (_type != Habit.kNeg) ('group', '分成一组子项'),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: PillChip(
                        label: it.$2,
                        selected: it.$1 == _valMode,
                        onTap: () => setState(() => _valMode = it.$1),
                      ),
                    ),
                  ],
                ],
              ),
              if (_valMode == 'one')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    decoration: hCardDeco(context),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              '单次目标',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            tf(_goal, w: 64),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                alignment: WrapAlignment.end,
                                children: [
                                  for (final u in units)
                                    PillChip(
                                      label: u,
                                      selected: u == _unit,
                                      onTap: () => setState(() => _unit = u),
                                    ),
                                  PillChip(
                                    label: '＋ 自定义',
                                    onTap: () =>
                                        showHabitMgrSheet(context, HabitDict.kUnit),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              '目标生效',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: () => _pickDate(forStart: false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  child: Text(
                                    _goalFrom,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              '可指定日期',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '打卡时弹记量面板 · 达标才算完成，未达标也可只记录',
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_valMode == 'group')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    decoration: hCardDeco(context),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '组内子项',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            HMiniBtn(
                              '＋ 子项',
                              onTap: () => setState(
                                () => _subs.add(
                                  _SubDraft(
                                    name: TextEditingController(),
                                    goal: TextEditingController(text: '10'),
                                    unit: '个',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_subs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '还没有子项 · 点右上「＋ 子项」，例如：深蹲 20 个 / 跑步 20 分钟',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        for (final (i, s) in _subs.indexed)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 84,
                                  child: TextField(
                                    controller: s.name,
                                    style: const TextStyle(fontSize: 11.5),
                                    decoration: InputDecoration(
                                      hintText: '子项名',
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                tf(s.goal, w: 48),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: DropdownButton<String>(
                                    value: units.contains(s.unit)
                                        ? s.unit
                                        : units.first,
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurface,
                                    ),
                                    items: [
                                      for (final u in units)
                                        DropdownMenuItem(
                                          value: u,
                                          child: Text(u),
                                        ),
                                    ],
                                    onChanged: (v) => setState(
                                      () => s.unit = v ?? s.unit,
                                    ),
                                  ),
                                ),
                                HSmallBtn(
                                  icon: HIcons.resolve('close'),
                                  size: 28,
                                  onTap: () =>
                                      setState(() => _subs.removeAt(i)),
                                ),
                              ],
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.only(top: 10, bottom: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '组达成规则',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (final (i, r) in const [
                              (Habit.kRuleAll, '全部达标'),
                              (Habit.kRuleHalf, '过半达标'),
                              (Habit.kRuleAny, '任一达标'),
                            ].indexed) ...[
                              if (i > 0) const SizedBox(width: 6),
                              Expanded(
                                child: PillChip(
                                  label: r.$2,
                                  selected: r.$1 == _rule,
                                  onTap: () => setState(() => _rule = r.$1),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (o != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    decoration: hCardDeco(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '开始跟踪',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            InkWell(
                              onTap: () => _pickDate(forStart: true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  _start,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '已跟踪 ${dayStart(DateTime.now()).difference(parseDay(_start)).inDays + 1} 天 · 日均与达成率按此起算（可在打卡设置切换）',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const _SecHead('提醒时间'),
              Row(
                children: [
                  for (final (i, it) in const [
                    ('off', '不提醒'),
                    ('on', '每天定点'),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: PillChip(
                        label: it.$2,
                        selected: it.$1 == _remindMode,
                        onTap: () => setState(() => _remindMode = it.$1),
                      ),
                    ),
                  ],
                ],
              ),
              if (_remindMode == 'on')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    decoration: hCardDeco(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InlineWheelTime(
                            initial: _tod(_remindVal),
                            onChanged: (h2, m) => _remindVal =
                                '${h2.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
                          ),
                        ),
                        const Text(
                          '滚动选择',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const _SecHead('自动达成源', hint: '（满足任一即自动打卡，无需手动）'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in const [
                    '待办勾选',
                    '番茄完成',
                    '阅读计时',
                    '日程事件',
                    '手动打卡',
                  ])
                    PillChip(
                      label: s,
                      selected: _srcs.contains(s),
                      onTap: () => setState(() {
                        _srcs.contains(s) ? _srcs.remove(s) : _srcs.add(s);
                        if (_srcs.isEmpty) _srcs.add('手动打卡');
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '生成关联待办',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '勾选待办即回写打卡',
                          style: TextStyle(
                            fontSize: 9,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _todoOn,
                    onChanged: (v) => setState(() => _todoOn = v),
                  ),
                ],
              ),
              if (_todoOn && _srcs.contains('待办勾选'))
                Row(
                  children: [
                    Expanded(
                      child: PillChip(
                        label: '常规待办',
                        selected: _todoForm == 'norm',
                        onTap: () => setState(() => _todoForm = 'norm'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PillChip(
                        label: '时间段 · 番茄',
                        selected: _todoForm == 'pomo',
                        onTap: () => setState(() => _todoForm = 'pomo'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: hCardDeco(context),
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
                  key: const ValueKey('btn-he-save'),
                  onTap: _save,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: tokens.gradient,
                    ),
                    child: const Text(
                      '保存',
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
          ),
        ),
      ],
    );
  }

  static TimeOfDay _tod(String hhmm) => TimeOfDay(
    hour: int.tryParse(hhmm.split(':').first) ?? 7,
    minute: int.tryParse(hhmm.split(':').last) ?? 0,
  );
}

/// 表单小节标题（原型 11px bold slate-500）。
class _SecHead extends StatelessWidget {
  const _SecHead(this.text, {this.hint});
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
          children: hint == null
              ? null
              : [
                  TextSpan(
                    text: hint,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}
