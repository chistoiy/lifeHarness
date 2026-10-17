part of 'health_sheets.dart';
// ==================== 运动录入（批4 · 原型 `sheetHEx`） ====================

/// 三模互算弹层：seg 决定**哪一项是被算出来的**，派生那一列只读回显。
///
/// 四条口径写在最近处：
/// · 派生值**不落输入框**——每次 build/保存都从另两档现算（`exTriad`），所以「按距离」下算出的配速
///   不会在切到「按时长」后被当成用户输入带进下一模式（原型是回写输入框，偏离见批4 工单 §3）；
/// · 非距离四类型（力量/瑜伽/球类/其他之外：`hasDistance` 假）＝距离与配速整列置灰、
///   保存折成 null（§五.4，展示与落库走同一条判据，不两处各判）；
/// · 时长是唯一必填项（算得出的时长也算），缺时长＝「至少填一个时长」，不静默写 0 分钟；
/// · 距离/配速读数跟着 `kmUnit()` 走（§五.10），**存储恒公制**，配速换算只改展示与录入解释。
Future<void> showHealthExerciseSheet(
  BuildContext context, {
  ExerciseRecord? editing,
  int? presetMinutes,
  String? presetSource,
  int? presetStartedAt,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExerciseSheet(
      editing: editing,
      presetMinutes: presetMinutes,
      presetSource: presetSource,
      presetStartedAt: presetStartedAt,
    ),
  );
}

class _ExerciseSheet extends ConsumerStatefulWidget {
  const _ExerciseSheet({
    this.editing,
    this.presetMinutes,
    this.presetSource,
    this.presetStartedAt,
  });

  final ExerciseRecord? editing;

  /// 计时器带进来的分钟数（开始计时跑完 → 直达本弹层，时长与来源已填好）。
  final int? presetMinutes;
  final String? presetSource;
  final int? presetStartedAt;

  @override
  ConsumerState<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends ConsumerState<_ExerciseSheet> {
  // late＋在初始化器里读 widget：字段初始化期 widget 尚未赋值（批3 首跑当场抓到的坑）。
  late String _type = widget.editing?.type ?? exTypes.first;
  late String? _date = widget.editing?.date;

  /// 改档后「保存并再记」＝同一天同类型再来一条，所以 id 单独可变（不是 editing 的别名）。
  late int? _id = widget.editing?.id;
  late String _source = widget.presetSource ?? widget.editing?.source ?? '手动';
  late final int? _startedAt = widget.editing?.startedAt ?? widget.presetStartedAt;
  ExMode _mode = ExMode.pace;

  late final TextEditingController _km = TextEditingController(
      text: widget.editing?.distanceKm == null
          ? ''
          : exKmTx(widget.editing!.distanceKm!, _unit));
  late final TextEditingController _min = TextEditingController(
      text: widget.editing != null
          ? '${widget.editing!.durationMin}'
          : (widget.presetMinutes == null ? '' : '${widget.presetMinutes}'));
  late final TextEditingController _pace = TextEditingController(
      text: widget.editing?.paceSec == null
          ? ''
          : paceLabelFor(widget.editing!.paceSec, _unit));
  late final TextEditingController _kcal =
      TextEditingController(text: widget.editing?.kcal?.toString() ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.editing?.note ?? '');

  @override
  void dispose() {
    for (final c in [_km, _min, _pace, _kcal, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _unit => ref.read(healthSettingsProvider).kmUnit();

  double? get _kmInput {
    final v = double.tryParse(_km.text.trim());
    if (v == null) return null;
    if (v <= 0) return null;
    return displayToKm(v, _unit);
  }

  int? get _minInput {
    final v = int.tryParse(_min.text.trim());
    return (v == null || v <= 0) ? null : v;
  }

  int? get _paceInput => parsePaceSec(_pace.text);

  /// 三值现算（同一函数也用于落库，回显与存储不可能分叉）。
  ({double? km, int? min, int? paceSec}) get _triad =>
      exTriad(type: _type, mode: _mode, km: _kmInput, min: _minInput, paceSec: _paceInput);

  /// 该列能不能编辑＝「是距离类」且「不是本档算出来的那一项」。
  bool _editable(String field) => hasDistance(_type) && _mode.readOnlyField != field;

  Future<void> _save({bool again = false}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final pid = container.read(activeHealthProfileProvider);
    final now = container.read(healthClockProvider)();
    final preview = _triad;
    if ((preview.min ?? 0) <= 0) {
      AppToast.show(context, '至少填一个时长');
      return;
    }
    final note = _note.text.trim();
    final rec = exDraft(
      id: _id,
      profileId: pid,
      date: _date ?? dayKey(now),
      type: _type,
      mode: _mode,
      km: _kmInput,
      min: _minInput,
      paceSec: _paceInput,
      kcal: int.tryParse(_kcal.text.trim()),
      note: note.isEmpty ? null : note,
      source: _source,
      startedAt: _startedAt,
    );
    final repo = container.read(healthRepositoryProvider);
    if (_id == null) {
      await repo.addExercise(rec);
    } else {
      await repo.updateExercise(rec);
    }
    container.invalidate(healthTodayProvider);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return;
    AppToast.show(context, exSavedTx(rec, _unit));
    if (!again) {
      Navigator.of(context).pop();
      return;
    }
    // 「保存并再记」保留日期/类型/时长（连跑同一节课最常见），清掉距离与配速重填。
    setState(() {
      _id = null;
      _km.clear();
      _pace.clear();
      _kcal.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(healthClockProvider)();
    final today = dayKey(now);
    final days = [for (var i = 0; i < 8; i++) dayKey(now.subtract(Duration(days: i)))];
    final date = _date ?? today;
    final unit = ref.watch(healthSettingsProvider).kmUnit();
    final t = _triad;
    return _sheetShell(
      context,
      title: _id == null ? '记录运动' : '修改 $date 的$_type',
      children: [
        Wrap(
          key: const ValueKey('hx-types'),
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final ty in exTypes)
              _keyed(
                  _chip(context,
                      label: ty, on: ty == _type, onTap: () => setState(() => _type = ty)),
                  ValueKey('hx-type-$ty')),
          ],
        ),
        const SizedBox(height: 10),
        Text('日期', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(
          key: const ValueKey('hx-dates'),
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PillChip(
                    key: ValueKey('hx-date-$d'),
                    label: '${d == today ? '今天' : d.substring(5)} ${dayWd(d).substring(1)}',
                    selected: d == date,
                    onTap: () => setState(() => _date = d),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (hasDistance(_type)) ...[
          SegRow<ExMode>(
            key: const ValueKey('hx-mode'),
            keyPrefix: 'hx-mode',
            value: _mode,
            items: const [
              (id: ExMode.pace, label: '按距离'),
              (id: ExMode.distance, label: '按时长'),
              (id: ExMode.duration, label: '按配速'),
            ],
            onChanged: (v) => setState(() => _mode = v),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                  child: _field('距离 · $unit', 'hx-km',
                      editable: _editable('km'),
                      controller: _km,
                      readout: t.km == null ? '—' : exKmTx(t.km!, unit))),
              const SizedBox(width: 6),
              Expanded(child: _field('时长 · 分', 'hx-min', editable: _editable('min'), controller: _min, readout: '${t.min ?? '—'}')),
              const SizedBox(width: 6),
              Expanded(
                  child: _field('配速 ${exDistUnitTx(unit)}', 'hx-pace',
                      editable: _editable('pace'),
                      controller: _pace,
                      readout: paceLabelFor(t.paceSec, unit),
                      numeric: false)),
            ],
          ),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _field('时长 · 分', 'hx-min', editable: true, controller: _min, readout: '')),
              const SizedBox(width: 6),
              Expanded(child: _field('距离', 'hx-km', editable: false, readout: '不计')),
              const SizedBox(width: 6),
              Expanded(child: _field('配速', 'hx-pace', editable: false, readout: '不计')),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(exCalcTx(type: _type, mode: _mode, km: _kmInput, min: _minInput, paceSec: _paceInput, unit: unit),
            key: const ValueKey('hx-calc'),
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        _field('kcal（选填）', 'hx-kcal', editable: true, controller: _kcal, readout: ''),
        const SizedBox(height: 10),
        _field('备注', 'hx-note', editable: true, controller: _note, readout: '', numeric: false),
        const SizedBox(height: 10),
        Text('来源', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Wrap(
          key: const ValueKey('hx-srcs'),
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in exSources)
              _keyed(
                  _chip(
                      context,
                      label: exSourceEnabled(s) ? s : '$s · 暂不可用',
                      on: s == _source,
                      onTap: () {
                        if (exSourceEnabled(s)) setState(() => _source = s);
                      }),
                  ValueKey('hx-src-$s')),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('hx-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('hx-again'),
                onPressed: () => _save(again: true),
                child: const Text('再记一条'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(key: const ValueKey('hx-save'), onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ],
    );
  }

  /// 三列共用的一件：可编辑＝输入框，不可编辑＝只读回显框（派生值/置灰档）。
  /// 只读框挂同一个 key，测试与语义树找到的永远是那一列，不会因模式切换换寻址。
  Widget _field(String label, String key,
      {required bool editable,
      TextEditingController? controller,
      required String readout,
      bool numeric = true}) {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            key: ValueKey('$key-label'),
            style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
        if (editable)
          TextField(
            key: ValueKey(key),
            controller: controller,
            // 边填边重算：三值回显、只读列与底部闭合串都吃输入框现值，不重建立刻变成「填了看不见」。
            onChanged: (_) => setState(() {}),
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
                isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9), border: border),
          )
        else
          Container(
            key: ValueKey(key),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: .04),
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(readout,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// 保存成功提示条（原型 `hExSave` 的回显串）。
String exSavedTx(ExerciseRecord r, String unit) =>
    '已存 ${r.date} · ${r.type} ${r.durationMin} 分钟'
    '${r.distanceKm == null ? '' : ' · ${exKmTx(r.distanceKm!, unit)} $unit'}'
    '${r.paceSec == null ? '' : ' · 均配速 ${paceLabelFor(r.paceSec, unit)}'}'
    ' · ${r.kcal ?? estKcal(r.type, r.durationMin)} kcal';

