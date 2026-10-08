import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/image_attach.dart' show ImageSquareCard, pickAndStoreImage;
import '../../../shared/widgets/lh_wheel.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_body.dart';
import '../domain/health_calc.dart';
import '../domain/health_ex.dart';
import '../domain/health_models.dart';
import '../domain/health_report.dart';
import '../domain/health_symptom.dart';
import '../domain/health_vital.dart';
import 'health_providers.dart';

part 'health_sheets_ex.dart';
part 'health_sheets_sym.dart';
part 'health_sheets_report.dart';

/// 健康 · 睡眠录入（原型 `sheetHSleep` · 规格＝LH-S 弹层族）。
///
/// 「记一笔」二选一入口已摘：两卡各自直达（喝水＝卡内 ＋1 杯；睡眠＝睡眠屏 FAB/顶栏钮），不再让用户在类别里挑。
///
/// 三条口径写在离代码最近的地方：
/// - **时间选择一律就地内嵌滚轮**（LH-K39），禁「点击→弹层→再选」两段式，也不拉系统选择器；
/// - 弹层自带 `viewInsets` 抬升（Flutter 3.38 起 `showModalBottomSheet` 不再自动抬升，既定坑）；
/// - 跨弹层的写库不携带发起页的失效 ref：入口先抓 container，关闭后只用它失效 provider。
Future<void> showHealthSleepSheet(BuildContext context, {SleepRecord? editing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SleepSheet(editing: editing),
  );
}

class _SleepSheet extends ConsumerStatefulWidget {
  const _SleepSheet({this.editing});

  final SleepRecord? editing;

  @override
  ConsumerState<_SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends ConsumerState<_SleepSheet> {
  static const _qualities = ['很好', '好', '一般', '差'];

  late final TextEditingController _date = TextEditingController(text: widget.editing?.date ?? dayKey(DateTime.now()));
  late final TextEditingController _deep = TextEditingController(text: _num(widget.editing?.deepMin));
  late final TextEditingController _light = TextEditingController(text: _num(widget.editing?.lightMin));
  late final TextEditingController _rem = TextEditingController(text: _num(widget.editing?.remMin));
  late final TextEditingController _awake = TextEditingController(text: _num(widget.editing?.awakeMin));

  late int _bedH = hhmmToMin(widget.editing?.bedTime ?? '23:00')! ~/ 60;
  late int _bedM = hhmmToMin(widget.editing?.bedTime ?? '23:00')! % 60;
  late int _wakeH = hhmmToMin(widget.editing?.wakeTime ?? '07:00')! ~/ 60;
  late int _wakeM = hhmmToMin(widget.editing?.wakeTime ?? '07:00')! % 60;
  late String? _quality = widget.editing?.quality;
  String? _err;

  static String _num(int? v) => v == null ? '' : '$v';

  @override
  void dispose() {
    _date.dispose();
    _deep.dispose();
    _light.dispose();
    _rem.dispose();
    _awake.dispose();
    super.dispose();
  }

  String get _bed => minToHhmm(_bedH * 60 + _bedM);
  String get _wake => minToHhmm(_wakeH * 60 + _wakeM);
  int get _duration => sleepDurationMin(_bed, _wake);

  /// 分期四段与总时长差 >20 分钟＝提示核对，**不阻断保存**（§五.4）。
  bool get _stagesOff {
    final st = ref.read(healthSettingsProvider);
    if (!st.stageLog()) return false;
    return stagesOffByMoreThan20(
      deep: int.tryParse(_deep.text.trim()),
      light: int.tryParse(_light.text.trim()),
      rem: int.tryParse(_rem.text.trim()),
      awake: int.tryParse(_awake.text.trim()),
      totalMin: _duration,
    );
  }

  Future<void> _save() async {
    final day = DateTime.tryParse(_date.text.trim());
    if (day == null) {
      setState(() => _err = '日期格式 yyyy-MM-dd');
      return;
    }
    final pid = ref.read(activeHealthProfileProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(healthRepositoryProvider);
    final rec = SleepRecord(
      id: widget.editing?.id,
      profileId: pid,
      date: dayKey(day),
      bedTime: _bed,
      wakeTime: _wake,
      durationMin: _duration,
      quality: _quality,
      deepMin: int.tryParse(_deep.text.trim()),
      lightMin: int.tryParse(_light.text.trim()),
      remMin: int.tryParse(_rem.text.trim()),
      awakeMin: int.tryParse(_awake.text.trim()),
    );
    await repo.saveSleep(rec);
    container.invalidate(healthTodayProvider);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, '已记录 ${_hm(_duration)} · 归属日 ${rec.date}');
  }

  Future<void> _delete() async {
    final id = widget.editing?.id;
    if (id == null) return;
    final ok = await lhConfirm(context, '删除这一晚的睡眠记录？达标概览会同步重算。');
    if (!ok || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await ref.read(healthRepositoryProvider).deleteSleep(id);
    container.invalidate(healthTodayProvider);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(healthSettingsProvider);
    final goalMin = st.sleepGoalHours() * 60;
    final onTime = fellAsleepOnTime(_bed, st.bedLine());
    return _sheetShell(
      context,
      title: widget.editing == null ? '记一晚睡眠' : '改这一晚',
      children: [
        _inlineDate(context, _date, '日期'),
        const SizedBox(height: 8),
        // ---- 四枚就地滚轮：入睡时·入睡分·醒来时·醒来分（禁两段式）----
        Row(
          children: [
            Expanded(child: _wheelLabel(context, '入睡 时', _bedH, 24, (v) => setState(() => _bedH = v), 'hsBedH')),
            Expanded(child: _wheelLabel(context, '入睡 分', _bedM, 60, (v) => setState(() => _bedM = v), 'hsBedM')),
            Expanded(child: _wheelLabel(context, '醒来 时', _wakeH, 24, (v) => setState(() => _wakeH = v), 'hsWakeH')),
            Expanded(child: _wheelLabel(context, '醒来 分', _wakeM, 60, (v) => setState(() => _wakeM = v), 'hsWakeM')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('时长 ${_hm(_duration)}',
                key: const ValueKey('hs-duration'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text('目标 ${_hm(goalMin)}', style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text(onTime ? '按时入睡' : '晚于界线 ${st.bedLine()}',
                key: const ValueKey('hs-ontime'),
                style: TextStyle(fontSize: 10.5, color: onTime ? null : Theme.of(context).colorScheme.error)),
          ],
        ),
        const SizedBox(height: 10),
        Text('质量', style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Wrap(
          key: const ValueKey('hs-quality'),
          spacing: 8,
          children: [
            for (final q in _qualities)
              _chip(context, label: q, on: _quality == q, onTap: () => setState(() => _quality = _quality == q ? null : q)),
          ],
        ),
        if (st.stageLog()) ...[
          const SizedBox(height: 10),
          Text('分期（分钟）', style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _numField(context, '深睡', _deep, 'hs-deep')),
              const SizedBox(width: 6),
              Expanded(child: _numField(context, '浅睡', _light, 'hs-light')),
              const SizedBox(width: 6),
              Expanded(child: _numField(context, 'REM', _rem, 'hs-rem')),
              const SizedBox(width: 6),
              Expanded(child: _numField(context, '清醒', _awake, 'hs-awake')),
            ],
          ),
          if (_stagesOnShow)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('四段合计与总时长差超过 20 分钟，回头核对一下',
                  key: const ValueKey('hs-stages-warn'),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
            ),
        ],
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_err!, key: const ValueKey('hs-err'), style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            if (widget.editing?.id != null) ...[
              TextButton(
                key: const ValueKey('hs-delete'),
                onPressed: _delete,
                child: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: FilledButton(key: const ValueKey('hs-save'), onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ],
    );
  }

  /// 只在填了分期时才提示（全空＝未记录分期，§五.3）。
  bool get _stagesOnShow {
    final any = [_deep.text, _light.text, _rem.text, _awake.text].any((t) => t.trim().isNotEmpty);
    return any && _stagesOff;
  }
}

// ==================== 公共小件 ====================

Widget _sheetShell(BuildContext context, {required String title, required List<Widget> children}) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    // 键盘抬起由弹层自己吃 viewInsets（3.38 起框架不再自动抬升）。
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 640),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget _wheelLabel(BuildContext context, String label, int value, int count, ValueChanged<int> onSelect, String keyPrefix) =>
    _wheel(
      context,
      label: label,
      labels: [for (var i = 0; i < count; i++) i.toString().padLeft(2, '0')],
      index: value.clamp(0, count - 1),
      onSelect: onSelect,
      keyPrefix: keyPrefix,
    );

/// 通用就地滚轮（LH-K39）：标签由调用侧给，所以「5 分钟一档」「0.1 步长」这类档位不必再另造一个小件。
Widget _wheel(BuildContext context,
    {required String label,
    required List<String> labels,
    required int index,
    required ValueChanged<int> onSelect,
    required String keyPrefix,
    Key? key}) {
  final scheme = Theme.of(context).colorScheme;
  return Column(
    children: [
      Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      LHWheel(
        key: key,
        labels: labels,
        initialIndex: index,
        onSelect: onSelect,
        height: 108,
        itemExtent: 28,
        keyPrefix: keyPrefix,
      ),
    ],
  );
}

Widget _inlineDate(BuildContext context, TextEditingController c, String label) {
  final scheme = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      TextField(
        key: const ValueKey('hs-date'),
        controller: c,
        style: const TextStyle(fontSize: 12.5),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'yyyy-MM-dd',
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    ],
  );
}

Widget _numField(BuildContext context, String label, TextEditingController c, String key) {
  final scheme = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
      TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ],
  );
}

Widget _chip(BuildContext context, {required String label, required bool on, required VoidCallback onTap}) {
  final scheme = Theme.of(context).colorScheme;
  return InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: on ? scheme.primary : scheme.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? scheme.onPrimary : scheme.onSurfaceVariant)),
    ),
  );
}

String _hm(int m) {
  final v = m < 0 ? 0 : m;
  final h = v ~/ 60, mm = v % 60;
  if (h == 0) return '$mm 分钟';
  return mm == 0 ? '$h 小时' : '$h 小时 $mm 分';
}

// ==================== 体征录入（批2.5 · 原型 sheetHVital） ====================

/// 五类体征共用一张表单：切类型即换字段组与测量时段（原型 `vtSetType`）。
///
/// 三条口径写在最近处：
/// · 数值/时刻一律就地内嵌滚轮（LH-K39，禁两段式）；分钟＝5 分钟一档（原型 `hMins`），
///   血糖/体温按 0.1 步长出档——档位集合就是可选集合，编辑既有时刻若不在档上就近归档，不假装能选；
/// · 参考区间只吃 `health_calc.vitalRef`：预览行与瓦片走同一个 `vitalLevel`，此处不抄第二份区间；
/// · `diet_note` 列本批不写（原型这张表单只有备注一个输入框，饮食情况按原型写进备注）。
Future<void> showHealthVitalSheet(BuildContext context, {String? kind, HealthVital? editing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VitalSheet(kind: kind, editing: editing),
  );
}

class _VitalSheet extends ConsumerStatefulWidget {
  const _VitalSheet({this.kind, this.editing});

  final String? kind;
  final HealthVital? editing;

  @override
  ConsumerState<_VitalSheet> createState() => _VitalSheetState();
}

class _VitalSheetState extends ConsumerState<_VitalSheet> {
  late String _kind = widget.editing?.kind ?? widget.kind ?? 'bp';

  /// null＝还没点选过日期，此时按固定钟的「今天」（见 `_draft` 与 chips 的同一口径）。
  late String? _date = widget.editing?.date;
  late int _h = _min(widget.editing?.time) ~/ 60;

  /// 5 分钟一档的档号（0~11）。
  late int _mIdx = (_min(widget.editing?.time) % 60 / 5).round().clamp(0, 11);

  late final Map<String, double> _vals = {
    if (widget.editing != null)
      for (final f in widget.editing!.spec.fields)
        f.col: widget.editing!.field(f.col) ?? _mid(f),
  };
  late String _slot = widget.editing?.slot ?? vitalSpecs[_kind]!.slots.first;
  late final TextEditingController _note = TextEditingController(text: widget.editing?.note ?? '');

  VitalSpec get _spec => vitalSpecs[_kind]!;

  /// 解析不出＝按原型的默认 07:30（缺失不猜成 00:00，避免把「未填」记成凌晨）。
  static int _min(String? t) => hhmmToMin(t) ?? 7 * 60 + 30;

  /// 未填数值时的默认档＝区间中点（原型 `vtFields` 的 `(lo+hi)/2`），再由 `_indexOf` 归到最近一档。
  /// 不做「取半程步数」那类换算：那会把收缩压顶到 205、体温顶到 73.5，一开屏就报「超出参考范围」。
  static double _mid(VitalField f) => double.parse(((f.lo + f.hi) / 2).toStringAsFixed(2));

  bool _has(String col) => _spec.fields.any((f) => f.col == col);

  double? _valueOf(String col) {
    if (!_has(col)) return null;
    return _vals[col] ?? _mid(_spec.fields.firstWhere((f) => f.col == col));
  }

  /// 落库与上屏都写「07:30」这种补零形式：`health_vital` 的排序是 `time ASC`（字符串序），
  /// 「7:30」会排到「10:00」后面。`minToHhmm` 的时位不补零（睡眠那两处沿用旧形），此处自理。
  String get _time =>
      '${_h.toString().padLeft(2, '0')}:${(_mIdx * 5).toString().padLeft(2, '0')}';

  /// 当前表单内容（未落库的草稿）；预览行与保存走同一个构造，避免两处口径漂移。
  /// 日期未点选时取**固定钟的今天**——和下面那排日期 chips 同源，不另用 `DateTime.now()`
  /// （否则时钟一偏移，默认日期就落在 chips 之外，选中态会整排熄灭）。
  HealthVital _draft(int profileId, DateTime now) => HealthVital(
        id: widget.editing?.id,
        profileId: profileId,
        date: _date ?? dayKey(now),
        time: _time,
        kind: _kind,
        sys: _valueOf('sys')?.round(),
        dia: _valueOf('dia')?.round(),
        hr: _valueOf('hr')?.round(),
        val: _valueOf('val'),
        slot: _slot,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );

  void _setKind(String k) {
    setState(() {
      _kind = k;
      // 换类＝字段组与时段整套换掉（原型 `vtSetType`）：时段回到新类的第一档，旧值不跨类残留。
      _slot = vitalSpecs[k]!.slots.first;
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // 跨弹层的写库不带发起页的失效 ref（既定坑）：先抓 container，pop 之后只用它。
    final container = ProviderScope.containerOf(context, listen: false);
    final rec = _draft(container.read(activeHealthProfileProvider), ref.read(healthClockProvider)());
    await container.read(healthRepositoryProvider).saveVital(rec);
    container.invalidate(healthTodayProvider);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.of(context).pop();
    final over = rec.flag != null && rec.flag != 'normal';
    AppToast.show(context,
        '已记录 ${rec.spec.name} ${rec.valueText} ${rec.spec.unit}${over ? ' · 超出参考范围' : ''}');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(healthClockProvider)();
    final today = dayKey(now);
    final days = [for (var i = 0; i < 8; i++) dayKey(now.subtract(Duration(days: i)))];
    final pid = ref.watch(activeHealthProfileProvider);
    final date = _date ?? today;
    final profile = (ref.watch(healthProfilesProvider).valueOrNull ?? const <HealthProfile>[])
        .where((p) => p.id == pid)
        .firstOrNull;
    final draft = _draft(pid, now);
    // 预览行已经印过一次参考区间；`deltaText` 在没有基线时回落的也是它——同一行里不重复两遍，
    // 只有真的比到基线（「较基线 …」「较静息 …」）才追加这一段。
    final delta = draft.deltaText(profile);
    final baseTx = delta.startsWith('较') ? ' · $delta' : '';
    return _sheetShell(
      context,
      title: widget.editing == null
          ? '记录体征'
          : '修改 ${widget.editing!.date.substring(5)} 的${widget.editing!.spec.name}',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final k in vitalOrder)
              _keyed(
                  _chip(context, label: vitalSpecs[k]!.name, on: k == _kind, onTap: () => _setKind(k)),
                  ValueKey('hv-type-$k')),
          ],
        ),
        const SizedBox(height: 10),
        Text('日期', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(
          key: const ValueKey('hv-dates'),
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PillChip(
                    key: ValueKey('hv-date-$d'),
                    label: '${d == today ? '今天' : d.substring(5)} ${dayWd(d).substring(1)}',
                    selected: d == date,
                    onTap: () => setState(() => _date = d),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 两柱各占一半：Row 的直接子项宽度是不受限的，LHWheel 不包 Expanded 就会拿到
            // w=Infinity（CupertinoPicker 的 LayoutBuilder 当场炸 performLayout）。
            Expanded(
              child: _wheel(context,
                  label: '时',
                  labels: [for (var i = 0; i < 24; i++) i.toString().padLeft(2, '0')],
                  index: _h,
                  onSelect: (v) => setState(() => _h = v),
                  keyPrefix: 'hvHH'),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _wheel(context,
                  label: '分',
                  labels: [for (var i = 0; i < 12; i++) (i * 5).toString().padLeft(2, '0')],
                  index: _mIdx,
                  onSelect: (v) => setState(() => _mIdx = v),
                  keyPrefix: 'hvMM'),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 34),
              child: Text(_time, key: const ValueKey('hv-time'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          key: const ValueKey('hv-fields'),
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final f in _spec.fields)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: f == _spec.fields.last ? 0 : 6),
                  child: _wheel(
                    context,
                    label: f.label,
                    keyPrefix: 'hv-${f.col}',
                    // 换类型＝整根柱换掉：给柱挂上「类型+列」的 key，让 LHWheel 重建而不是复用 State。
                    // 复用会在旧列表还没换成长度更大的新列表时就 jumpToItem，新档位被旧长度截断
                    // （实测：体温 71 档 → 血糖 193 档，跳 96 被压成 70，读数出成 9.8 而不是中点 12.4）。
                    key: ValueKey('hv-wheel-$_kind-${f.col}'),
                    labels: [for (final v in f.values) f.step < 1 ? v.toStringAsFixed(1) : v.toStringAsFixed(0)],
                    index: _indexOf(f, _valueOf(f.col)),
                    onSelect: (i) => setState(() => _vals[f.col] = f.values[i]),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(_spec.slotLabel, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in _spec.slots)
              _keyed(_chip(context, label: s, on: s == _slot, onTap: () => setState(() => _slot = s)),
                  ValueKey('hv-slot-$s')),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('hv-note'),
          controller: _note,
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: '如 服药后 2 小时测',
            label: const Text('备注', style: TextStyle(fontSize: 11)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('hv-preview'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${draft.spec.name} ${draft.valueText} ${draft.spec.unit} · ${draft.spec.refLabel} · '
            '${switch (draft.flag) { 'low' => '低于参考值', 'high' => '高于参考值', _ => '落在参考范围' }}'
            '$baseTx',
            style: const TextStyle(fontSize: 10.5),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('hv-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(key: const ValueKey('hv-save'), onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ],
    );
  }

  /// 值 → 档号：取离得最近的那一档（浮点档位不做精确相等比较）。
  int _indexOf(VitalField f, double? v) {
    final vals = f.values;
    if (v == null) return vals.length ~/ 2;
    var best = 0;
    for (var i = 0; i < vals.length; i++) {
      if ((vals[i] - v).abs() < (vals[best] - v).abs()) best = i;
    }
    return best;
  }
}

/// 给既有私有小件补一枚 Key（不改 `_chip` 签名，免得睡眠弹层跟着改）。
Widget _keyed(Widget w, Key k) => KeyedSubtree(key: k, child: w);

// ==================== 身体数据录入（批3 · 原型 sheetHWeight） ====================

/// 体重两柱（整 kg + 0.1 kg）＋身高柱＋四枚选填柱，「—」＝不写入／不改写。
///
/// 四条口径写在最近处：
/// · 档表、单位、周变化基线**只吃 `health_body` 域层**——此处不出现第二份 35~120，改档不漏屏；
/// · 录入柱恒按 kg（存储单位，§五.10）：原型把 `HT.kgUnit` 标在这根 kg 柱旁是演示错位，
///   照抄会让「斤」档的用户以为在录斤，落库数直接翻倍；
/// · 同日重记＝整行覆盖（`saveBody` 按 (profile_id,date) 唯一索引 replace），所以「—」档
///   必须**回填原值**而不是写 null，否则改一次体重会把该行的腰围/体脂清掉（刀2 钉的就是这条）；
/// · 预览行与落库共用同一组取值函数，所见即所存，不在两处各算一次 BMI。
Future<void> showHealthWeightSheet(BuildContext context, {BodyRecord? editing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WeightSheet(editing: editing),
  );
}

class _WeightSheet extends ConsumerStatefulWidget {
  const _WeightSheet({this.editing});

  final BodyRecord? editing;

  @override
  ConsumerState<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends ConsumerState<_WeightSheet> {
  /// 一条记录都没有时的起步体重＝原型 `hBodyPreview` 的 `||69`。
  static const double _fallbackKg = 69;

  /// null＝还没点过日期：新建按「今天」，编辑保持原日期（chips 里点别的才改归属日）。
  late String? _date = widget.editing?.date;

  /// null＝还没滚过＝起步档由 `_kgWholeIdx`/`_heightIndex` 现算（不能用 `late`：
  /// 读未赋值的 late 字段直接 LateError，批3 首跑弹层当场抓到）。
  int? _kgWhole;
  int? _kgDec;
  int? _heightIdx;
  final Map<String, int?> _opt = {};

  List<BodyRecord> get _all => ref.read(healthBodyProvider).valueOrNull ?? const [];

  double get _kg => kgAt(_kgWholeIdx(_all), _kgDecIdx(_all));

  /// 身高柱的起步档：编辑＝本条自己的（没填就停「—」），新建＝带出档案最近一次填过的。
  /// 新建回填是为了让 BMI 一开屏就有读数；编辑不回填是为了不把「没填」悄悄写成 170。
  int get _heightIndex => _heightIdx ??
      heightIndexOf(widget.editing != null ? widget.editing!.heightCm : latestHeightCm(_all));

  double? get _heightCm => heightValueAt(_heightIndex) ?? widget.editing?.heightCm;

  /// 「—」＝保留原值（整行覆盖下写 null 会清掉同列旧读数）。
  double? _optional(String col) {
    final f = bodyField(col);
    final prev = bodyFieldValue(widget.editing, col);
    return f.valueAt(_opt[col] ?? f.indexOf(prev)) ?? prev;
  }

  BodyRecord _draft(int pid, DateTime now) => BodyRecord(
        id: widget.editing?.id,
        profileId: pid,
        date: _date ?? dayKey(now),
        kg: _kg,
        heightCm: _heightCm,
        fatPct: _optional('fat'),
        waistCm: _optional('waist'),
        hipCm: _optional('hip'),
        neckCm: _optional('neck'),
      );

  /// 预览/落库的 BMI 回落链＝本条身高 → 档案最近身高 → 没有就算不出（出「—」，不拿 170 兜底）。
  double? _bmiOf(BodyRecord r) => bmi(kg: r.kg, cm: r.heightCm ?? latestHeightCm(_all));

  Future<void> _save() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final pid = container.read(activeHealthProfileProvider);
    final rec = _draft(pid, container.read(healthClockProvider)());
    await container.read(healthRepositoryProvider).saveBody(rec);
    container.invalidate(healthTodayProvider);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.of(context).pop();
    final b = _bmiOf(rec);
    AppToast.show(context,
        '已记录 ${rec.date} · ${rec.kg!.toStringAsFixed(1)} kg · BMI ${bodyBmiTx(b)}${b == null ? '' : '（${bodyLevelTx(b)}）'}');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(healthClockProvider)();
    final today = dayKey(now);
    final days = [for (var i = 0; i < 8; i++) dayKey(now.subtract(Duration(days: i)))];
    final date = _date ?? today;
    final all = ref.watch(healthBodyProvider).valueOrNull ?? const <BodyRecord>[];
    final goalKg = ref.watch(healthGoalsProvider).valueOrNull?['weight_goal'];
    final kg = _kg;
    final heightCm = _heightCm;
    final b = bmi(kg: kg, cm: heightCm ?? latestHeightCm(all));
    final baseline = bodyWeekBaseline(all);
    return _sheetShell(
      context,
      title: widget.editing == null ? '记录身体数据' : '修改 ${widget.editing!.date.substring(5)} 的记录',
      children: [
        Text('日期', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(
          key: const ValueKey('hw-dates'),
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PillChip(
                    key: ValueKey('hw-date-$d'),
                    label: '${d == today ? '今天' : d.substring(5)} ${dayWd(d).substring(1)}',
                    selected: d == date,
                    onTap: () => setState(() => _date = d),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _wheel(context,
                  label: '体重 kg',
                  labels: kgWholeLabels,
                  index: _kgWholeIdx(all),
                  onSelect: (v) => setState(() => _kgWhole = v),
                  key: const ValueKey('hw-kg-i'),
                  keyPrefix: 'hwKgI'),
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 10,
              child: Text('.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _wheel(context,
                  label: '小数',
                  labels: kgDecLabels,
                  index: _kgDecIdx(all),
                  onSelect: (v) => setState(() => _kgDec = v),
                  key: const ValueKey('hw-kg-d'),
                  keyPrefix: 'hwKgD'),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 34),
              child: Text(kg.toStringAsFixed(1),
                  key: const ValueKey('hw-kg'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _wheel(context,
            label: '身高 cm · 选「—」则不改',
            labels: heightLabels,
            index: _heightIndex,
            onSelect: (v) => setState(() => _heightIdx = v),
            key: const ValueKey('hw-height'),
            keyPrefix: 'hwH'),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('选填项', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
            const Spacer(),
            Text('「—」＝不写入', style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          key: const ValueKey('hw-fields'),
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final f in bodyOptionalFields)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: f == bodyOptionalFields.last ? 0 : 4),
                  child: _wheel(context,
                      label: f.unit == '%' ? '${f.label} %' : '${f.label} cm',
                      labels: f.labels,
                      index: _opt[f.col] ?? f.indexOf(bodyFieldValue(widget.editing, f.col)),
                      onSelect: (i) => setState(() => _opt[f.col] = i),
                      key: ValueKey('hw-${f.col}'),
                      keyPrefix: 'hw-${f.col}'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('hw-preview'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '预览 ${kg.toStringAsFixed(1)} kg · BMI ${bodyBmiTx(b)}'
            '${b == null ? '' : ' ${bodyLevelTx(b)}'} · 距目标 ${goalKg == null ? '未设' : bodyGoalTx(kg - goalKg)}'
            ' · 周变化 ${bodyDeltaTx(baseline == null ? null : kg - baseline, 'kg')}',
            style: const TextStyle(fontSize: 10.5),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('hw-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(key: const ValueKey('hw-save'), onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ],
    );
  }

  /// 起步档＝**用户没滚过**时用种子值，滚过就用滚轮的档（种子要依赖 watch 到的实测序列）。
  int _kgWholeIdx(List<BodyRecord> all) =>
      _kgWhole ?? kgWholeIndexOf(widget.editing?.kg ?? latestKg(all) ?? _fallbackKg);

  int _kgDecIdx(List<BodyRecord> all) =>
      _kgDec ?? kgDecIndexOf(widget.editing?.kg ?? latestKg(all) ?? _fallbackKg);
}
