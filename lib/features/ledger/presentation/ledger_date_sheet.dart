import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/wheel_date.dart' show daysInMonthOf;
import '../domain/ledger_calc.dart';

/// S2 日期/年月/时刻滚轮（原型 sheetLedgerDate · 就地内嵌滚轮，禁点选模拟）。
/// mode：'day'=年月日三列 · 'month'=年月两列 · 'time'=时分两列。
/// 返回选中值：day→'YYYY-MM-DD' · month→'YYYY-MM' · time→'HH:MM'。
Future<String?> showLDateSheet(
  BuildContext context, {
  String mode = 'day',
  String? value,
}) =>
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LDate(mode: mode, value: value),
    );

class _LDate extends StatefulWidget {
  const _LDate({required this.mode, this.value});

  final String mode;
  final String? value;

  @override
  State<_LDate> createState() => _LDateState();
}

class _LDateState extends State<_LDate> {
  static const _years = [2024, 2025, 2026, 2027, 2028];

  late int _y;
  late int _m;
  late int _d;
  late int _hh;
  late int _mm;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // 全模式预置：_set 的等值守卫会读取全部字段，未初始化会 LateInitializationError。
    _hh = now.hour;
    _mm = now.minute;
    _y = now.year;
    _m = now.month;
    _d = now.day;
    final v = widget.value;
    if (widget.mode == 'time') {
      final p = (v ?? '').split(':');
      _hh = int.tryParse(p.isNotEmpty ? p[0] : '') ?? now.hour;
      _mm = int.tryParse(p.length > 1 ? p[1] : '') ?? now.minute;
    } else {
      final base = v ?? (widget.mode == 'month' ? monthKey(now) : dayKey(now));
      final p = base.split('-').map(int.parse).toList();
      _y = p[0];
      _m = p.length > 1 ? p[1] : now.month;
      _d = p.length > 2 ? p[2] : now.day;
      if (!_years.contains(_y)) _y = _years.first;
    }
  }

  int get _daysInMonth => daysInMonthOf(_y, _m);

  String get _result => switch (widget.mode) {
    'time' =>
      '${_hh.toString().padLeft(2, '0')}:${_mm.toString().padLeft(2, '0')}',
    'month' =>
      '$_y-${_m.toString().padLeft(2, '0')}',
    _ =>
      '$_y-${_m.toString().padLeft(2, '0')}-${_d.clamp(1, _daysInMonth).toString().padLeft(2, '0')}',
  };

  // 等值守卫：picker 首帧无条件回调，同帧 setState 会无限重建（既定挂死坑）。
  void _set(void Function() f) {
    final old = (_y, _m, _d, _hh, _mm);
    f();
    if (old != (_y, _m, _d, _hh, _mm)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.mode == 'time'
        ? '选择时刻'
        : widget.mode == 'month'
        ? '选择年月'
        : '选择日期';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            if (widget.mode == 'day') ...[
              const SizedBox(height: 4),
              Text(
                '周${wdOf(_result)}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: Row(
                children: switch (widget.mode) {
                  'time' => [
                    _wheel([
                      for (var h = 0; h < 24; h++) '${p2(h)} 时',
                    ], _hh, (i) => _set(() => _hh = i)),
                    _wheel([
                      for (var m = 0; m < 60; m++) '${p2(m)} 分',
                    ], _mm, (i) => _set(() => _mm = i)),
                  ],
                  'month' => [
                    _wheel([
                      for (final y in _years) '$y 年',
                    ], _years.indexOf(_y), (i) => _set(() => _y = _years[i])),
                    _wheel([
                      for (var m = 1; m <= 12; m++) '$m 月',
                    ], _m - 1, (i) => _set(() => _m = i + 1)),
                  ],
                  _ => [
                    _wheel([
                      for (final y in _years) '$y 年',
                    ], _years.indexOf(_y), (i) => _set(() => _y = _years[i])),
                    _wheel([
                      for (var m = 1; m <= 12; m++) '$m 月',
                    ], _m - 1, (i) => _set(() => _m = i + 1)),
                    _wheel([
                      for (var d = 1; d <= _daysInMonth; d++) '$d 日',
                    ],
                    _d.clamp(1, _daysInMonth) - 1,
                    (i) => _set(() => _d = i + 1)),
                  ],
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: context.tokens.gradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, _result),
                        child: const Text(
                          '确定',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
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
    );
  }

  Widget _wheel(List<String> items, int index, ValueChanged<int> onSel) {
    return Expanded(
      child: _WheelCol(
        key: ValueKey(items.length),
        items: items,
        index: index.clamp(0, items.length - 1),
        onSel: onSel,
      ),
    );
  }
}

String p2(int v) => v.toString().padLeft(2, '0');

// ============ S5 金额滚轮（原型 sheetLedgerWheel · openWheel，预算/余额调整共用） ============

/// 单列金额滚轮：0~20000 步长 100（原型 items 201 格），初始定位
/// min(200, round(val/100))；右上「确定」回传选中值，未滚动保持原值取整
/// （原型 _whVal 语义）。返回 null=下滑/遮罩关闭（不落库）。
Future<double?> showLAmountWheel(
  BuildContext context, {
  required String title,
  required double value,
}) =>
    showModalBottomSheet<double>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LAmountWheel(title: title, value: value),
    );

class _LAmountWheel extends StatefulWidget {
  const _LAmountWheel({required this.title, required this.value});

  final String title;
  final double value;

  @override
  State<_LAmountWheel> createState() => _LAmountWheelState();
}

class _LAmountWheelState extends State<_LAmountWheel> {
  /// 原型 items=0..200 步长 100；显示 money(v).replace('¥','¥ ')。
  static final List<double> _items = [
    for (var i = 0; i <= 200; i++) i * 100.0,
  ];

  late double _val = math.max(0, widget.value.roundToDouble());

  @override
  Widget build(BuildContext context) {
    final idx = (_val / 100).round().clamp(0, _items.length - 1);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context, _val),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      '确定',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: context.tokens.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 170,
              child: _WheelCol(
                key: ValueKey(_items.length),
                items: [
                  for (final v in _items)
                    money(v).replaceFirst('¥', '¥ '),
                ],
                index: idx,
                onSel: (i) {
                  final v = _items[i];
                  if (v != _val) setState(() => _val = v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 单列滚轮（controller 自持 + didUpdateWidget 同步，同 wheel_date 先例）。
class _WheelCol extends StatefulWidget {
  const _WheelCol({
    super.key,
    required this.items,
    required this.index,
    required this.onSel,
  });

  final List<String> items;
  final int index;
  final ValueChanged<int> onSel;

  @override
  State<_WheelCol> createState() => _WheelColState();
}

class _WheelColState extends State<_WheelCol> {
  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
    initialItem: widget.index,
  );

  @override
  void didUpdateWidget(_WheelCol old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index &&
        _ctl.hasClients &&
        _ctl.selectedItem != widget.index) {
      _ctl.jumpTo(widget.index * 34.0);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return CupertinoPicker(
      scrollController: _ctl,
      itemExtent: 34,
      diameterRatio: 1.5,
      backgroundColor: Colors.transparent,
      onSelectedItemChanged: widget.onSel,
      children: [
        for (var i = 0; i < widget.items.length; i++)
          Center(
            child: Text(
              widget.items[i],
              style: TextStyle(
                fontSize: i == widget.index ? 18 : 11.5,
                fontWeight: i == widget.index
                    ? FontWeight.w800
                    : FontWeight.w600,
                color: i == widget.index
                    ? tokens.accent
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
      ],
    );
  }
}
