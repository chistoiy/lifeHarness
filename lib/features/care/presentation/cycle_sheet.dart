import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/care_models.dart';
import '../domain/care_events.dart';
import '../domain/cycle_calc.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// 周期着色（原型 cycleCells 口径：经期 peach/rose、排卵 violet、易孕 mint/teal、
/// 点滴 rose-200、今天 brand 描边）。预测位用半透明底表示「虚线描边=系统预测」。
const kCycP = '#fb7185'; // 经期
const kCycO = '#8b5cf6'; // 排卵
const kCycF = '#2dd4bf'; // 易孕
const kCycS = '#fecdd3'; // 点滴
const kCycToday = '#6366f1';

({String kind, bool predicted})? _dayKindAt(
    Map<String, CycleDay> days, CycleNow? now, DateTime d) {
  final key = careDayKey(d);
  final st = days[key]?.state;
  if (st == 'p1' || st == 'p') return (kind: 'p', predicted: false);
  if (st == 's') return (kind: 's', predicted: false);
  if (now == null) return null;
  if (now.ovDay != null && careDayKey(now.ovDay!) == key) {
    return (kind: 'o', predicted: true);
  }
  if (careDayKey(now.nextStart) == key) return (kind: 'p', predicted: true);
  if (now.fertileStart != null &&
      now.fertileEnd != null &&
      !d.isBefore(now.fertileStart!) &&
      !d.isAfter(now.fertileEnd!)) {
    return (kind: 'f', predicted: true);
  }
  return null;
}

Color? _kindColor(String kind) => switch (kind) {
      'p' => careHex(kCycP),
      'o' => careHex(kCycO),
      'f' => careHex(kCycF),
      's' => careHex(kCycS),
      _ => null,
    };

/// 月历网格（p-care 迷你卡 / p-cycleCal 全屏共用；周日首）。
class CycleMonthGrid extends StatelessWidget {
  const CycleMonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.days,
    required this.now,
    required this.onDay,
    this.big = false,
  });

  final int year;
  final int month;
  final Map<String, CycleDay> days;
  final CycleNow? now;
  final ValueChanged<DateTime> onDay;
  final bool big;

  static const _tagText = {'p': '经期', 'o': '排卵', 'f': '易孕', 's': '点滴'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now().withoutTimeCare();
    final first = DateTime(year, month, 1);
    final dim = DateTime(year, month + 1, 0).day;
    final lead = first.weekday % 7; // 周日=0
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
              Expanded(
                child: Text(w,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: big ? 1.05 : 1.45,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= dim; d++) Builder(builder: (_) {
              final date = DateTime(year, month, d);
              final mark = _dayKindAt(days, now, date);
              final isToday = careDayKey(date) == careDayKey(today);
              final color = mark == null ? null : _kindColor(mark.kind);
              final faded = mark != null && mark.predicted;
              return GestureDetector(
                key: ValueKey('cyday-$year-$month-$d'),
                onTap: () => onDay(date),
                child: Container(
                  margin: EdgeInsets.all(big ? 3 : 1.5),
                  decoration: BoxDecoration(
                    color: color?.withValues(alpha: faded ? .18 : (big ? .3 : .25)),
                    borderRadius: BorderRadius.circular(10),
                    border: isToday
                        ? Border.all(color: careHex(kCycToday), width: 2)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$d',
                          style: TextStyle(
                            fontSize: big ? 12 : 11,
                            fontWeight: color != null
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: color == null
                                ? scheme.onSurfaceVariant
                                : Color.alphaBlend(
                                    color.withValues(alpha: .65), Colors.white),
                          )),
                      if (big && mark != null)
                        Text(_tagText[mark.kind] ?? '',
                            style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w700,
                                color: (color ?? scheme.onSurfaceVariant)
                                    .withValues(alpha: .9))),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}

/// 打开日记录补录弹层（openCycleDay 同构：回填既有日记录）。
Future<void> showCycleDaySheet(BuildContext context, DateTime day) async {
  await showCareSheet<void>(
    context,
    builder: (bc) => _CycleDaySheet(day: day),
  );
}

class _CycleDaySheet extends ConsumerStatefulWidget {
  const _CycleDaySheet({required this.day});
  final DateTime day;

  @override
  ConsumerState<_CycleDaySheet> createState() => _CycleDaySheetState();
}

class _CycleDaySheetState extends ConsumerState<_CycleDaySheet> {
  String _state = '';
  String? _flow;
  final _tempCtl = TextEditingController();
  String? _ovu;
  final Set<String> _syms = {};
  final _noteCtl = TextEditingController();
  bool _loaded = false;

  static const _stateOpts = [
    ('', '未记录'),
    ('s', '点滴出血'),
    ('p1', '经期第 1 天'),
    ('p', '经期持续'),
  ];

  @override
  void dispose() {
    _tempCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(careRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final key = careDayKey(widget.day);
    final temp = double.tryParse(_tempCtl.text.trim());
    final wasP1 = (_state == 'p1');
    await repo.saveCycleDay(CycleDay(
      day: key,
      state: _state,
      flow: _state == 'p1' || _state == 'p' || _state == 's' ? _flow : null,
      temp: temp,
      ovu: _ovu,
      syms: _syms.toList(),
      note: _noteCtl.text.trim().isEmpty ? null : _noteCtl.text.trim(),
    ));
    careTouch(ref);
    if (mounted) Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(wasP1
              ? '✔ 已标记 $key 为经期第 1 天 · 周期重新预测：旧预测已存档'
              : '✔ $key 已保存 · 状态/体温/试纸将参与预测修正'),
          duration: const Duration(milliseconds: 2000),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final d = (await ref.read(careDataProvider.future)).cycleDays[careDayKey(widget.day)];
        if (d == null || !mounted) return;
        setState(() {
          _state = d.state;
          _flow = d.flow;
          _ovu = d.ovu;
          _syms.addAll(d.syms);
          if (d.temp != null) _tempCtl.text = '${d.temp}';
          _noteCtl.text = d.note ?? '';
        });
      });
    }
    final key = careDayKey(widget.day);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🌸 日记录 · $key',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const CLabel('经期状态', top: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (v, label) in _stateOpts)
                CChip(
                  key: ValueKey('cy-state-$v'),
                  label: label,
                  selected: _state == v,
                  onTap: () => setState(() {
                    _state = _state == v ? '' : v;
                    if (_state != 'p1' && _state != 'p' && _state != 's') _flow = null;
                  }),
                ),
            ],
          ),
          const CLabel('经量（经期时）'),
          CSingleRow(
            options: const ['少', '中', '多'],
            selected: _flow,
            onPick: (v) => setState(() => _flow = _flow == v ? null : v),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CLabel('基础体温（可选）', top: 0),
                    TextField(
                      key: const ValueKey('cy-temp'),
                      controller: _tempCtl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: '36.5 ℃',
                        hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.cardBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.cardBorder),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CLabel('排卵试纸', top: 0),
                    CSingleRow(
                      options: const ['弱阳', '强阳'],
                      selected: _ovu,
                      onPick: (v) => setState(() => _ovu = _ovu == v ? null : v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const CLabel('感受（多选）'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in kSymPool)
                CChip(
                  key: ValueKey('cy-sym-$s'),
                  label: s,
                  dense: true,
                  selected: _syms.contains(s),
                  onTap: () => setState(() => _syms.contains(s) ? _syms.remove(s) : _syms.add(s)),
                ),
            ],
          ),
          const CLabel('备注'),
          TextField(
            key: const ValueKey('cy-note'),
            controller: _noteCtl,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: '如：痛经 1h，热敷后缓解',
              hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.cardBorder),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('cy-save'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('保存后自动重算预测并保留旧预测存档 · 敏感数据默认不出本机',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
