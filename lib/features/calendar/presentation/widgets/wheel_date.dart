import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 轮式日期选择（V1.22.1 · 图1 · 顶栏年/月/日点击跳转）。
/// 形态=底部弹层（原型 sheetDatePick：居中标题+周几提示+三列滚轮+取消/确定大按钮）。
/// 当月天数（避开 DateTime(y,m+1,0)：day-0 归一化在 FakeAsync 时区解析下会挂死）。
int daysInMonthOf(int y, int m) {
  const dm = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (m != 2) return dm[m - 1];
  return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
}

Future<DateTime?> showWheelDatePick(BuildContext context, DateTime initial) async {
  return showModalBottomSheet<DateTime>(
    context: context,
    builder: (bc) => _WheelDate(initial: initial),
  );
}

class _WheelDate extends StatefulWidget {
  const _WheelDate({required this.initial});
  final DateTime initial;

  @override
  State<_WheelDate> createState() => _WheelDateState();
}

class _WheelDateState extends State<_WheelDate> {
  late int _y = widget.initial.year;
  late int _m = widget.initial.month;
  late int _d = widget.initial.day;

  static const _years = [2024, 2025, 2026, 2027, 2028];
  static const _wd = ['一', '二', '三', '四', '五', '六', '日'];

  int get _daysInMonth => daysInMonthOf(_y, _m);

  // 等值守卫：picker 首帧回调无条件 setState 会同帧无限重建（挂死）。
  void _setY(int v) { if (v != _y) setState(() => _y = v); }
  void _setM(int v) { if (v != _m) setState(() => _m = v); }
  void _setD(int v) { if (v != _d) setState(() => _d = v); }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final clampedD = _d.clamp(1, _daysInMonth);
    final preview = DateTime(_y, _m, clampedD);
    final isToday = preview == DateTime.now().withoutTime;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('选择日期',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                children: [
                  TextSpan(text:
                      '${_m.toString().padLeft(2, '0')}月${clampedD.toString().padLeft(2, '0')}日 周${_wd[preview.weekday - 1]}'),
                  if (isToday)
                    const TextSpan(
                        text: ' · 今天',
                        style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 136,
              child: Row(
                children: [
                  _col(_years.map((y) => '$y').toList(), _years.indexOf(_y),
                      (i) => _setY(_years[i]), '年'),
                  _col(
                      [for (var m = 1; m <= 12; m++) m.toString().padLeft(2, '0')],
                      _m - 1,
                      (i) => _setM(i + 1),
                      '月'),
                  _col(
                      [
                    for (var d = 1; d <= _daysInMonth; d++)
                      d.toString().padLeft(2, '0')
                  ], clampedD - 1, (i) => _setD(i + 1), '日'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style:
                        OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: tokens.gradient,
                          borderRadius: BorderRadius.circular(12)),
                      child: TextButton(
                        onPressed: () =>
                            Navigator.pop(context, DateTime(_y, _m, clampedD)),
                        child: const Text('确定',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700)),
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

  Widget _col(List<String> items, int index, ValueChanged<int> onSel, String unit) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: _ColWheel(
              key: ValueKey('$unit-${items.length}'),
              items: items,
              index: index,
              onSel: onSel,
            ),
          ),
          Text(unit, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

extension on DateTime {
  DateTime get withoutTime => DateTime(year, month, day);
}

/// 单列滚轮：StatefulWidget 自持 controller（build 内 new 会导致重挂循环触发
/// onSelectedItemChanged → setState 死循环）。
class _ColWheel extends StatefulWidget {
  const _ColWheel({super.key, required this.items, required this.index, required this.onSel});
  final List<String> items;
  final int index;
  final ValueChanged<int> onSel;

  @override
  State<_ColWheel> createState() => _ColWheelState();
}

class _ColWheelState extends State<_ColWheel> {
  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
      initialItem: widget.index.clamp(0, widget.items.length - 1));

  @override
  void didUpdateWidget(_ColWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        _ctl.hasClients &&
        _ctl.selectedItem != widget.index) {
      _ctl.jumpTo(widget.index.clamp(0, widget.items.length - 1) * 34.0);
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
            child: Text(widget.items[i],
                style: TextStyle(
                  fontSize: i == widget.index ? 19 : 12,
                  fontWeight: i == widget.index ? FontWeight.w800 : FontWeight.w600,
                  color: i == widget.index ? tokens.accent : const Color(0xFF94A3B8),
                )),
          ),
      ],
    );
  }
}
