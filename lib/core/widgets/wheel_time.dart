import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// V1.26.2 内嵌轮式时间选择器：**直接嵌在表单里上下滑动切换时/分，无任何二次弹层**。
/// 与原型内嵌滚轮同款（5 分一档 · .witem：非选中 12px 灰、选中 19px 加粗主题色）。
class InlineWheelTime extends StatefulWidget {
  const InlineWheelTime({
    super.key,
    required this.initial,
    required this.onChanged,
    this.height = 96,
  });

  final TimeOfDay initial;

  /// 滑动落定时回调（不触发本组件重建）。
  final void Function(int hour, int minute) onChanged;
  final double height;

  @override
  State<InlineWheelTime> createState() => _InlineWheelTimeState();
}

class _InlineWheelTimeState extends State<InlineWheelTime> {
  // items 为静态单例：跨 rebuild 保持同一 List 实例，避免 CupertinoPicker
  // 每次拿到新 delegate（与 time_pick_sheet 的约定一致）。用 List.generate
  // 而非手写三段式 for 推导——空增量在推导里是静默无限循环（见 R4 守护）。
  static final List<int> _hours = List.generate(24, (i) => i);
  static final List<int> _minutes = List.generate(12, (i) => i * 5);

  late final FixedExtentScrollController _hCtl =
      FixedExtentScrollController(initialItem: widget.initial.hour);
  late final FixedExtentScrollController _mCtl = FixedExtentScrollController(
      initialItem: (widget.initial.minute / 5).round().clamp(0, 11));
  late final ValueNotifier<int> _hSelN = ValueNotifier<int>(widget.initial.hour);
  late final ValueNotifier<int> _mSelN = ValueNotifier<int>(
      (widget.initial.minute / 5).round().clamp(0, 11));
  late int _h = widget.initial.hour;
  late int _m = (widget.initial.minute / 5).round().clamp(0, 11) * 5;
  int _lastEmitted = -1;

  @override
  void dispose() {
    _hCtl.dispose();
    _mCtl.dispose();
    _hSelN.dispose();
    _mSelN.dispose();
    super.dispose();
  }

  /// 只在取值真的变了才回调：picker 首帧/重复上报会带同样的值上来，去重后
  /// 父层不必为"没变"重算（对齐 wheel_date 的等值守卫）。
  void _emit() {
    final v = _h * 60 + _m;
    if (v == _lastEmitted) return;
    _lastEmitted = v;
    widget.onChanged(_h, _m);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          Expanded(
              child: _wheel(_hours, _hCtl, _hSelN, (i) {
            _h = i;
            _emit();
          })),
          Text(':',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          Expanded(
              child: _wheel(_minutes, _mCtl, _mSelN, (i) {
            _m = i * 5;
            _emit();
          })),
        ],
      ),
    );
  }

  Widget _wheel(List<int> items, FixedExtentScrollController ctl,
      ValueNotifier<int> selN, ValueChanged<int> onSelect) {
    return CupertinoPicker(
      scrollController: ctl,
      itemExtent: 32,
      diameterRatio: 1.4,
      backgroundColor: Colors.transparent,
      // 只更新选中态 ValueNotifier + 回调父层，**不 setState**：重建仅经
      // ValueListenableBuilder 换中心行样式（原型 .witem.on 19px 主题色）。
      //
      // 为什么不必担心"回调→重建→回调"回环（已核对 Flutter 3.38.9 源码）：
      // `_ListWheelScrollViewState._reportSelectedItemChanged` 由 ScrollUpdateNotification
      // 驱动，且 `currentItemIndex != _lastReportedItemIndex` 自带等值守卫，该索引只在
      // initState 取 initialItem、**rebuild 时不重置**（该类无 didUpdateWidget）；
      // `_CupertinoPickerState.didUpdateWidget` 也只重接 controller listener。
      onSelectedItemChanged: (i) {
        if (selN.value != i) selN.value = i;
        onSelect(i);
      },
      children: [
        for (var idx = 0; idx < items.length; idx++)
          ValueListenableBuilder<int>(
            valueListenable: selN,
            builder: (context, sel, child) => Center(
              key: ValueKey('iw$idx'),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 120),
                style: idx == sel
                    ? TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: context.tokens.accent)
                    : const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8)),
                child: Text(items[idx].toString().padLeft(2, '0')),
              ),
            ),
          ),
      ],
    );
  }
}
