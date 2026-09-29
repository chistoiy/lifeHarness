import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/day_models.dart';
import '../../../shared/calendar/lunar.dart';
import 'days_kit.dart';
import 'days_providers.dart';

/// P8b 日子编辑（新建 / 修改共用；需求 V1.42 模块11 · 原型 de* 系 3965-4011 对译）。
///
/// 口径：四种重复方式条件区全部就地内嵌滚轮（once/solar-year=InlineDateWheel、
/// lunar=月/日两 CWheel + 逐年实算公历提示行、monthly=日号 CWheel）；
/// 提前提醒六档多选；准备事项行内维护；两联动 toggle 默认开；
/// 编辑态删除走二次确认（文案同原型 dayDel 语义）。
class DayEditPage extends ConsumerStatefulWidget {
  const DayEditPage({super.key, required this.dayId});

  /// null=新建。
  final int? dayId;

  @override
  ConsumerState<DayEditPage> createState() => _DayEditPageState();
}

class _PrepDraft {
  _PrepDraft({this.id, this.todoId, required this.text, this.done = false});
  int? id;
  int? todoId;
  String text;
  bool done;
}

class _DayEditPageState extends ConsumerState<DayEditPage> {
  final _titleCtl = TextEditingController();
  final _prepCtl = TextEditingController();

  String _icon = 'cake';
  String _color = 'rose';
  DayRepeat _rep = DayRepeat.solarYear;
  late DateTime _target = _defaultTarget();
  int _lunarMonth = 8; // 原型默认 八月廿七
  int _lunarDay = 27;
  int _monthDay = 30;
  final Set<int> _rem = {7, 0};
  final List<_PrepDraft> _preps = [];
  bool _prepToTodo = true;
  bool _linkDiary = true;

  bool _inited = false;
  DayEntry? _origin; // 编辑态原始行（category/pinned/archived/note 承接）

  static DateTime _defaultTarget() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 28);
  }

  @override
  void initState() {
    super.initState();
    if (widget.dayId == null) _inited = true; // 新建无需回填
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _prepCtl.dispose();
    super.dispose();
  }

  void _applyOrigin(DayEntry d) {
    _origin = d;
    _titleCtl.text = d.title;
    _icon = d.iconId;
    _color = d.colorKey;
    _rep = d.repeat;
    _target = d.targetDate ?? _defaultTarget();
    _lunarMonth = d.lunarMonth ?? 8;
    _lunarDay = d.lunarDay ?? 27;
    _monthDay = d.monthDay ?? 30;
    _rem
      ..clear()
      ..addAll(d.remOffsets);
    _preps
      ..clear()
      ..addAll(d.preps
          .map((p) => _PrepDraft(
              id: p.id, todoId: p.todoId, text: p.text, done: p.done)));
    _prepToTodo = d.prepToTodo;
    _linkDiary = d.linkDiary;
  }

  @override
  Widget build(BuildContext context) {
    // 编辑态初值从 daysDataProvider 回填（loading 显骨架）。
    if (!_inited) {
      final async = ref.watch(daysDataProvider);
      if (!async.hasValue) {
        return Scaffold(
          appBar: AppBar(centerTitle: true, title: const Text('编辑日子')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      final d =
          async.value!.days.where((x) => x.id == widget.dayId).firstOrNull;
      if (d != null) _applyOrigin(d);
      _inited = true;
    }
    final editing = _origin != null;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(editing ? '编辑日子' : '新建日子'),
            Text(editing ? _origin!.title : '倒数 · 纪念日 · 循环提醒',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          TextField(
            key: const ValueKey('d-edit-title'),
            controller: _titleCtl,
            textCapitalization: TextCapitalization.none,
            decoration: _inp('标题，如：妈妈生日'),
          ),
          const _Lbl('图标'),
          DayIconPickRow(
              selected: _icon, onPick: (v) => setState(() => _icon = v)),
          const _Lbl('卡片颜色'),
          DayColorPickRow(
              selected: _color, onPick: (v) => setState(() => _color = v)),
          const _Lbl('重复方式'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in DayRepeat.values)
                PillChip(
                  key: ValueKey('d-edit-rep-${r.wire}'),
                  label: r.label,
                  selected: _rep == r,
                  onTap: () => setState(() => _rep = r),
                ),
            ],
          ),
          ..._dateSection(context),
          const _Lbl('提前提醒（多级可多选）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in kDayRemOffsets)
                PillChip(
                  key: ValueKey('d-edit-rem-$v'),
                  label: v == 0 ? '当天' : '提前 $v 天',
                  selected: _rem.contains(v),
                  onTap: () => setState(
                      () => _rem.contains(v) ? _rem.remove(v) : _rem.add(v)),
                ),
            ],
          ),
          const _Lbl('准备事项（可勾选 · 保存后一键转待办）'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('d-edit-prep-inp'),
                  controller: _prepCtl,
                  decoration: _inp('添加一条准备事项，回车确认'),
                  onSubmitted: (_) => _addPrep(),
                ),
              ),
              const SizedBox(width: 8),
              MiniBtn(
                key: const ValueKey('d-prep-add'),
                icon: Icons.add,
                label: '添加',
                onTap: _addPrep,
              ),
            ],
          ),
          for (var i = 0; i < _preps.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _prepRow(i),
            ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('d-edit-toggles'),
            decoration: context.cardDecoration,
            child: Column(
              children: [
                _toggleRow('准备事项勾选后生成待办（联动 L3）', _prepToTodo,
                    (v) => setState(() => _prepToTodo = v), first: true),
                _toggleRow('关联当年日记 · 每年此日回看往年记录（联动 L5）',
                    _linkDiary, (v) => setState(() => _linkDiary = v)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GradButton(
            key: const ValueKey('d-edit-save'),
            label: editing ? '保存修改' : '创建日子',
            onTap: _save,
          ),
          if (editing) ...[
            const SizedBox(height: 8),
            RoseOutlineButton(
              key: const ValueKey('d-edit-del'),
              label: '删除此日子',
              onTap: _delete,
            ),
          ],
        ],
      ),
    );
  }

  /// 条件区：once/solar-year=InlineDateWheel；lunar=两 CWheel+实算提示；monthly=日号 CWheel。
  List<Widget> _dateSection(BuildContext context) {
    switch (_rep) {
      case DayRepeat.once:
      case DayRepeat.solarYear:
        return [
          const _Lbl('目标日期'),
          Container(
            key: const ValueKey('d-edit-date-wheel'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: context.cardDecoration,
            child: InlineDateWheel(
              value: _target,
              onChanged: (v) => setState(() => _target = v),
            ),
          ),
        ];
      case DayRepeat.lunar:
        return [
          const _Lbl('农历日期'),
          Container(
            key: const ValueKey('d-edit-lunar-wheels'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: context.cardDecoration,
            child: Row(
              children: [
                Expanded(
                  child: CWheel(
                    key: const ValueKey('d-lunar-month'),
                    labels: const [
                      '正月', '二月', '三月', '四月', '五月', '六月',
                      '七月', '八月', '九月', '十月', '冬月', '腊月'
                    ],
                    initialIndex: _lunarMonth - 1,
                    onSelect: (i) => setState(() => _lunarMonth = i + 1),
                  ),
                ),
                Expanded(
                  child: CWheel(
                    key: const ValueKey('d-lunar-day'),
                    labels: [for (var dd = 1; dd <= 30; dd++) lunarLabel(1, dd).substring(2)],
                    initialIndex: _lunarDay - 1,
                    onSelect: (i) => setState(() => _lunarDay = i + 1),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_lunarHint(),
                key: const ValueKey('d-lunar-hint'),
                style: const TextStyle(fontSize: 10, color: kDaysMuted)),
          ),
        ];
      case DayRepeat.monthly:
        return [
          const _Lbl('每月哪天'),
          Container(
            key: const ValueKey('d-edit-month-wheel'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: context.cardDecoration,
            child: CWheel(
              key: const ValueKey('d-month-day-wheel'),
              labels: [for (var dd = 1; dd <= 31; dd++) '每月 $dd 日'],
              initialIndex: _monthDay - 1,
              onSelect: (i) => setState(() => _monthDay = i + 1),
            ),
          ),
        ];
    }
  }

  /// 「对应公历」实算：今年或明年 >= 今天的首次换算（lunarToSolarInYear）。
  String _lunarHint() {
    final now = ref.read(daysClockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? occ;
    for (final y in [now.year, now.year + 1]) {
      final c = lunarToSolarInYear(y, _lunarMonth, _lunarDay);
      if (c != null && !c.isBefore(today)) {
        occ = c;
        break;
      }
    }
    final s = occ == null ? '—' : fmtDateYmd(occ);
    return '农历 ${lunarLabel(_lunarMonth, _lunarDay)} · 对应公历 $s（逐年自动换算）';
  }

  Widget _prepRow(int i) {
    final p = _preps[i];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('d-edit-prep-$i'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          GestureDetector(
            key: ValueKey('d-edit-prep-check-$i'),
            onTap: () => setState(() => p.done = !p.done),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: p.done ? context.tokens.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: p.done ? context.tokens.accent : kDaysMuted),
              ),
              child: p.done
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.text,
              style: TextStyle(
                fontSize: 12,
                decoration: p.done ? TextDecoration.lineThrough : null,
                color: p.done ? kDaysMuted : null,
              ),
            ),
          ),
          GestureDetector(
            key: ValueKey('d-edit-prep-del-$i'),
            onTap: () => setState(() => _preps.removeAt(i)),
            child: const Icon(Icons.close, size: 16, color: kDaysMuted),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String label, bool on, ValueChanged<bool> onChanged,
      {bool first = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (!first) Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 11.5))),
              DaysToggle(on: on, onChanged: onChanged),
            ],
          ),
        ),
      ],
    );
  }

  void _addPrep() {
    final v = _prepCtl.text.trim();
    if (v.isEmpty) return;
    setState(() => _preps.add(_PrepDraft(text: v)));
    _prepCtl.clear();
  }

  Future<void> _save() async {
    final t = _titleCtl.text.trim();
    if (t.isEmpty) {
      AppToast.show(context, '先填标题');
      return;
    }
    final isNew = _origin == null;
    final entry = DayEntry(
      id: _origin?.id,
      title: t,
      iconId: _icon,
      colorKey: _color,
      category: _origin?.category ?? '倒数',
      repeat: _rep,
      targetDate:
          (_rep == DayRepeat.once || _rep == DayRepeat.solarYear) ? _target : null,
      lunarMonth: _rep == DayRepeat.lunar ? _lunarMonth : null,
      lunarDay: _rep == DayRepeat.lunar ? _lunarDay : null,
      monthDay: _rep == DayRepeat.monthly ? _monthDay : null,
      remOffsets: kDayRemOffsets.where(_rem.contains).toList(),
      note: _origin?.note,
      pinned: _origin?.pinned ?? false,
      archived: _origin?.archived ?? false,
      linkDiary: _linkDiary,
      prepToTodo: _prepToTodo,
      preps: [
        for (final p in _preps)
          DayPrep(
              id: p.id,
              dayId: _origin?.id ?? 0,
              text: p.text,
              done: p.done,
              todoId: p.todoId),
      ],
    );
    final repo = ref.read(daysRepositoryProvider);
    if (isNew) {
      await repo.addDay(entry);
    } else {
      await repo.updateDay(entry);
    }
    if (!mounted) return;
    daysTouch(ref);
    AppToast.show(
        context,
        isNew
            ? '已创建「$t」· 提醒 ${entry.remOffsets.length} 档已注册'
            : '「$t」已更新');
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await daysConfirm(context, '确认删除此日子？准备事项一并移除');
    if (!ok || !mounted) return;
    await ref.read(daysRepositoryProvider).purgeDay(_origin!.id!);
    if (!mounted) return;
    daysTouch(ref);
    AppToast.show(context, '已删除日子 · 关联待办保留');
    // 结果回传：来源详情页据此连退，不停在「已不存在」空态
    Navigator.pop(context, 'purged');
  }

  InputDecoration _inp(String hint) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: context.tokens.accent)),
      );
  }
}

/// 分节小标题（原型 text-xs font-bold 节头）。
class _Lbl extends StatelessWidget {
  const _Lbl(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );
}
