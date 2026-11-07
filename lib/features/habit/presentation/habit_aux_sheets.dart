import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_dict.dart';
import 'habit_providers.dart';
import 'habit_sheets.dart';
import 'widgets/habit_kit.dart';

/// 负向「记一次触发」弹层（原型 sheetHabitTrigger · LH-S17）。
/// §5-10：触发是一等事实数据——文案与配色保持中性（rose 仅作品类标识，不评判）。
class _TrigSheet extends ConsumerStatefulWidget {
  const _TrigSheet({required this.h});

  final Habit h;

  @override
  ConsumerState<_TrigSheet> createState() => _TrigSheetState();
}

class _TrigSheetState extends ConsumerState<_TrigSheet> {
  static const kReasons = ['熬夜', '应酬', '情绪', '赶时间', '忘记', '他人带动'];

  String? _reason;
  // 原型 tgAmt：数值输入框，默认带出目标量
  late final TextEditingController _amtC = TextEditingController(
    text: '${(h.goal ?? 1).toInt()}',
  );
  final _note = TextEditingController();

  Habit get h => widget.h;

  @override
  void dispose() {
    _amtC.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(habitRepositoryProvider);
    final todayK = dayKey(DateTime.now());
    final amt = (double.tryParse(_amtC.text.trim()) ?? 0);
    final a = amt < 0 ? 0.0 : amt;
    final unit = widget.h.unit;
    await repo.recordTrigger(
      widget.h.id,
      day: todayK,
      amount: unit == null || unit.isEmpty ? null : a,
      amountText: unit == null || unit.isEmpty ? null : '$a $unit',
      reasons: _reason == null ? const [] : [_reason!],
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      checkAt: hhmmNow(),
    );
    // 本周额度口径：滚动 7 日窗触发计数 vs negLimit（原型 triggers/target）
    final to = dayKey(DateTime.now());
    final from = dayKey(DateTime.now().subtract(const Duration(days: 6)));
    final used = await repo.slipCountIn(widget.h.id, from, to);
    final left = (widget.h.negLimit - used).clamp(0, widget.h.negLimit);
    ref.read(habitTickProvider.notifier).state++;
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messengerToast(
      m,
      '已记录 · 这次 ${a % 1 == 0 ? a.toInt() : a} ${unit?.isNotEmpty == true ? unit : '次'}'
      ' · 本周 $used/${widget.h.negLimit}'
      '${left > 0 ? ' · 还剩 $left 次额度' : ' · 本周额度已用满'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final hasUnit = widget.h.unit != null && widget.h.unit!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '记一次触发 · ${widget.h.name}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '如实记录即可 · 只统计，不评判',
            style: TextStyle(
              fontSize: 10.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '当时情境',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in kReasons)
                HPill(
                  key: ValueKey('htrig-reason-$r'),
                  text: r,
                  bg:
                      _reason == r
                          ? HK.brand
                          : scheme.onSurface.withValues(alpha: .05),
                  fg: _reason == r ? Colors.white : scheme.onSurface,
                  onTap: () => setState(
                    () => _reason = _reason == r ? null : r,
                  ),
                ),
            ],
          ),
          if (hasUnit) ...[
            const SizedBox(height: 12),
            Row(
              key: const ValueKey('htrig-amt-row'),
              children: [
                Text(
                  '这次数量',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: TextField(
                    key: const ValueKey('htrig-amt'),
                    controller: _amtC,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.h.unit!,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            key: const ValueKey('htrig-note'),
            maxLines: 2,
            maxLength: 80,
            decoration: const InputDecoration(
              hintText: '补一句（可选）',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Row(
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
                  key: const ValueKey('btn-htrig-save'),
                  onTap: _save,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: tokens.gradient,
                    ),
                    child: const Text(
                      '记录',
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
        ],
      ),
    );
  }
}

Future<void> showHabitTriggerSheet(BuildContext context, Habit h) =>
    hBottomSheet(context, (_) => _TrigSheet(h: h));

/// 字典管理弹层（原型 sheetHabitMgr · LH-S22）：分类/单位增删改+排序+迁移。
class _MgrSheet extends ConsumerStatefulWidget {
  const _MgrSheet({required this.kind});

  /// cat | unit
  final String kind;

  @override
  ConsumerState<_MgrSheet> createState() => _MgrSheetState();
}

class _MgrSheetState extends ConsumerState<_MgrSheet> {
  final _new = TextEditingController();
  int? _mergeOpen;

  bool get _isUnit => widget.kind == HabitDict.kUnit;
  String get _noun => _isUnit ? '单位' : '分类';

  Future<void> _reload() async {
    ref.read(habitTickProvider.notifier).state++;
    setState(() {});
  }

  Future<void> _add() async {
    final v = _new.text.trim();
    final m = ScaffoldMessenger.of(context);
    if (v.isEmpty) {
      messengerToast(m, '先输入名称');
      return;
    }
    final list = await ref.read(habitRepositoryProvider).dictOf(widget.kind);
    if (list.any((d) => d.name == v)) {
      messengerToast(m, '已有同名$_noun');
      return;
    }
    await ref.read(habitRepositoryProvider).addDict(widget.kind, v);
    _new.clear();
    messengerToast(m, '已添加「$v」');
    await _reload();
  }

  Future<void> _rename(HabitDict d, String nv) async {
    final m = ScaffoldMessenger.of(context);
    final v = nv.trim();
    if (v.isEmpty || v == d.name) {
      setState(() {});
      return;
    }
    final repo = ref.read(habitRepositoryProvider);
    final ok = await repo.renameDict(widget.kind, d.id, v);
    if (!ok) {
      messengerToast(m, '已有同名 · 未改名');
    } else {
      messengerToast(
        m,
        '「${d.name}」已改为「$v」· 同步 ${await repo.dictRefCount(widget.kind, v)} 处',
      );
    }
    await _reload();
  }

  Future<void> _del(HabitDict d) async {
    final m = ScaffoldMessenger.of(context);
    final repo = ref.read(habitRepositoryProvider);
    final list = await repo.dictOf(widget.kind);
    if (list.length <= 1) {
      messengerToast(m, '至少保留一个$_noun');
      return;
    }
    if (await repo.dictRefCount(widget.kind, d.name) > 0) {
      setState(() => _mergeOpen = d.id);
      messengerToast(m, '「${d.name}」仍被使用 · 选择去向后可删除');
      return;
    }
    await repo.deleteDict(widget.kind, d.id);
    messengerToast(m, '已删除「${d.name}」');
    await _reload();
  }

  Future<void> _merge(HabitDict d, String? to) async {
    final m = ScaffoldMessenger.of(context);
    if (to == null || to == d.name) {
      messengerToast(m, '请选择迁移目标');
      return;
    }
    final n = await ref
        .read(habitRepositoryProvider)
        .mergeDict(widget.kind, d.name, to);
    setState(() => _mergeOpen = null);
    messengerToast(m, '已把 $n 处迁到「$to」· 并删除「${d.name}」');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = ref.watch(habitDataProvider).valueOrNull;
    final items =
        _isUnit
            ? list?.units ?? const <HabitDict>[]
            : list?.cats ?? const <HabitDict>[];
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
                  _isUnit ? '记录量单位' : '习惯分类',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text(
                  '收起',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          Text(
            _isUnit
                ? '改名即时同步到习惯与组内子项 · 删除前需先安置使用者'
                : '改名即时同步到已归属习惯 · 删除前需先安置其下习惯',
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (i, d) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      key: ValueKey('hm-row-${d.name}'),
                      decoration: hCardDeco(context),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _RenameField(
                                  init: d.name,
                                  onCommit: (v) => _rename(d, v),
                                ),
                              ),
                              _mvBtn(
                                context,
                                'btn-hm-up-${d.name}',
                                Icons.arrow_upward,
                                i > 0,
                                () async {
                                  await ref
                                      .read(habitRepositoryProvider)
                                      .moveDict(widget.kind, d.id, -1);
                                  await _reload();
                                },
                              ),
                              _mvBtn(
                                context,
                                'btn-hm-down-${d.name}',
                                Icons.arrow_downward,
                                i < items.length - 1,
                                () async {
                                  await ref
                                      .read(habitRepositoryProvider)
                                      .moveDict(widget.kind, d.id, 1);
                                  await _reload();
                                },
                              ),
                              _mvBtn(
                                context,
                                'btn-hm-del-${d.name}',
                                Icons.delete_outline,
                                true,
                                () => _del(d),
                                danger: true,
                              ),
                            ],
                          ),
                          FutureBuilder<int>(
                            future: ref
                                .read(habitRepositoryProvider)
                                .dictRefCount(widget.kind, d.name),
                            builder: (context, snap) {
                              final n = snap.data ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Text(
                                      n > 0 ? '被 $n 处使用' : '暂无使用',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (n > 0)
                                      const Spacer(),
                                    if (n > 0)
                                      GestureDetector(
                                        key: ValueKey('btn-hm-mig-${d.name}'),
                                        onTap: () => setState(
                                          () => _mergeOpen =
                                              _mergeOpen == d.id
                                              ? null
                                              : d.id,
                                        ),
                                        child: Text(
                                          '迁移后删除',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: HK.brand,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          if (_mergeOpen == d.id)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _MergePicker(
                                      items: items
                                          .where((x) => x.id != d.id)
                                          .toList(),
                                      onPick: (to) => _merge(d, to),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '已清空 · 添加一个开始归类',
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
                child: TextField(
                  key: const ValueKey('hm-new'),
                  controller: _new,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: '新$_noun名称',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                key: const ValueKey('btn-hm-add'),
                onTap: _add,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: context.tokens.gradient,
                  ),
                  child: const Text(
                    '添加',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: hCardDeco(context),
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mvBtn(
    BuildContext context,
    String key,
    IconData icon,
    bool on,
    VoidCallback onTap, {
    bool danger = false,
  }) => GestureDetector(
    key: ValueKey(key),
    onTap: on ? onTap : null,
    child: Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.only(left: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            danger
                ? HK.rose500.withValues(alpha: .12)
                : Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: .06,
                ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 14,
        color:
            on
                ? (danger ? HK.rose500 : Theme.of(context).colorScheme.onSurfaceVariant)
                : Theme.of(context).colorScheme.onSurfaceVariant.withValues(
                  alpha: .3,
                ),
      ),
    ),
  );
}

/// 就地改名输入框（失焦/回车提交）。
class _RenameField extends StatefulWidget {
  const _RenameField({required this.init, required this.onCommit});

  final String init;
  final void Function(String) onCommit;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.init);

  @override
  void didUpdateWidget(covariant _RenameField old) {
    super.didUpdateWidget(old);
    if (old.init != widget.init) _c.text = widget.init;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    onSubmitted: widget.onCommit,
    focusNode: () {
      final fn = FocusNode();
      fn.addListener(() {
        if (!fn.hasFocus) widget.onCommit(_c.text);
      });
      return fn;
    }(),
    decoration: const InputDecoration(isDense: true),
  );
}

/// 迁移目标选择（下拉取其余项）。
class _MergePicker extends StatefulWidget {
  const _MergePicker({required this.items, required this.onPick});

  final List<HabitDict> items;
  final void Function(String?) onPick;

  @override
  State<_MergePicker> createState() => _MergePickerState();
}

class _MergePickerState extends State<_MergePicker> {
  String? _to;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('hm-mv-sel'),
            isExpanded: true,
            value:
                _to != null && widget.items.any((x) => x.name == _to)
                    ? _to
                    : (widget.items.isEmpty ? null : widget.items.first.name),
            hint: const Text('迁移到…', style: TextStyle(fontSize: 11)),
            items: [
              for (final x in widget.items)
                DropdownMenuItem(value: x.name, child: Text(x.name)),
            ],
            onChanged: (v) => setState(() => _to = v),
          ),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        key: const ValueKey('btn-hm-merge'),
        onTap: () => widget.onPick(_to ?? (widget.items.isEmpty ? null : widget.items.first.name)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(
              alpha: .06,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '迁移并删除',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ],
  );
}

Future<void> showHabitMgrSheet(BuildContext context, String kind) =>
    hBottomSheet(context, (_) => _MgrSheet(kind: kind));
