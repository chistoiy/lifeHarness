import 'package:flutter/material.dart';

import '../../../shared/widgets/lh_wheel.dart';

/// 数值目标就地改（健康工作台「目标」卡两行共用）。
///
/// 交互口径＝点行 → **本行下方展开滚轮**（禁「点击→弹层→再操作」两段式），
/// 滚轮选到哪一档**当场写库并生效**，不设「保存」按钮；再点行首收起。
class HealthGoalRow extends StatefulWidget {
  const HealthGoalRow({
    super.key,
    required this.rowKey,
    required this.wheelKey,
    required this.icon,
    required this.label,
    required this.valueText,
    required this.labels,
    required this.currentIndex,
    required this.onChanged,
    this.hint,
  });

  final Key rowKey;
  final Key wheelKey;
  final IconData icon;
  final String label;

  /// 行首下方的一行小字（原型目标页每行都带口径注，如「≥10 分钟计 1 次」）；不传就不占位。
  final String? hint;

  /// 行首读数（如「8 杯」），由调用侧按当前设置格式化。
  final String valueText;
  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  State<HealthGoalRow> createState() => _HealthGoalRowState();
}

class _HealthGoalRowState extends State<HealthGoalRow> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  void _pick(int v) {
    widget.onChanged(v);
    // 选完不自动收起：连改两档比"收—开"顺手，收起靠再点行首。
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: widget.rowKey,
          borderRadius: BorderRadius.circular(10),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: Row(
              children: [
                Icon(widget.icon, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    if (widget.hint != null)
                      Text(widget.hint!,
                          style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                Text(widget.valueText,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: scheme.primary)),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: LHWheel(
              key: widget.wheelKey,
              labels: widget.labels,
              initialIndex: widget.currentIndex,
              height: 106,
              itemExtent: 30,
              keyPrefix: '${widget.label}-',
              onSelect: _pick,
            ),
          ),
      ],
    );
  }
}
