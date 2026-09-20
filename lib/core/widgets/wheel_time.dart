import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// V1.26.2 内嵌轮式时间选择器：**直接嵌在表单里上下滑动切换时/分，无任何二次弹层**。
/// 与原型待办/时间模块内嵌滚轮同款（5 分一档 · 中间行放大）。放 core/widgets 供各模块共用。
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
  late final FixedExtentScrollController _hCtl =
      FixedExtentScrollController(initialItem: widget.initial.hour);
  late final FixedExtentScrollController _mCtl = FixedExtentScrollController(
      initialItem: (widget.initial.minute / 5).round().clamp(0, 11));
  late int _h = widget.initial.hour;
  late int _m = (widget.initial.minute / 5).round().clamp(0, 11) * 5;

  @override
  void dispose() {
    _hCtl.dispose();
    _mCtl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_h, _m);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          Expanded(
              child:
                  _wheel([for (var i = 0; i < 24; i++) i], _hCtl, (i) { _h = i; })),
          Text(':',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          Expanded(
              child: _wheel(
                  [for (var i = 0; i < 12; i++) i * 5],
                  _mCtl,
                  (i) { _m = i * 5; })),
        ],
      ),
    );
  }

  Widget _wheel(List<int> items, FixedExtentScrollController ctl,
      ValueChanged<int> onSelect) {
    final scheme = Theme.of(context).colorScheme;
    return CupertinoPicker(
      scrollController: ctl,
      itemExtent: 32,
      backgroundColor: scheme.surface,
      selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
          background: scheme.primary.withValues(alpha: .08)),
      onSelectedItemChanged: (i) {
        setState(() => onSelect(i));
        _emit();
      },
      children: [
        for (final v in items)
          Center(
            child: Text(v.toString().padLeft(2, '0'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
