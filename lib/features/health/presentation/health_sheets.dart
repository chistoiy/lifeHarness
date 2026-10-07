import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/lh_wheel.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_calc.dart';
import '../domain/health_models.dart';
import 'health_providers.dart';

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

Widget _wheelLabel(BuildContext context, String label, int value, int count, ValueChanged<int> onSelect, String keyPrefix) {
  final scheme = Theme.of(context).colorScheme;
  return Column(
    children: [
      Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      LHWheel(
        labels: [for (var i = 0; i < count; i++) i.toString().padLeft(2, '0')],
        initialIndex: value.clamp(0, count - 1),
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
