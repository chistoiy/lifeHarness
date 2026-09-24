import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';

/// 就地内嵌滚轮（红线 5：时间/数值输入一律内嵌滚轮，禁两段式弹层）。
/// 语义同 LInlinePicker（ledger 侧为 feature 私有不跨 import，此处独立实现）。
class CWheel extends StatefulWidget {
  const CWheel({
    super.key,
    required this.labels,
    required this.initialIndex,
    required this.onSelect,
    this.height = 120,
    this.fontSize = 15,
  });

  final List<String> labels;
  final int initialIndex;
  final ValueChanged<int> onSelect;
  final double height;
  final double fontSize;

  @override
  State<CWheel> createState() => _CWheelState();
}

class _CWheelState extends State<CWheel> {
  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
      initialItem: widget.initialIndex.clamp(0, widget.labels.length - 1));
  late int _last = widget.initialIndex;
  // CupertinoPicker 首帧布局必定自动回调一次，且回调发生在 build scope 内；
  // 直接透传 onSelect 会触发「setState during build」。首次回调无条件吞掉。
  bool _firstCallback = true;

  @override
  void didUpdateWidget(CWheel old) {
    super.didUpdateWidget(old);
    final idx = widget.initialIndex.clamp(0, widget.labels.length - 1);
    if (idx != _last && _ctl.hasClients && _ctl.selectedItem != idx) {
      _ctl.jumpToItem(idx);
      _last = idx;
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
    return SizedBox(
      height: widget.height,
      child: CupertinoPicker(
        scrollController: _ctl,
        itemExtent: 30,
        diameterRatio: 1.5,
        backgroundColor: Colors.transparent,
        onSelectedItemChanged: (i) {
          if (_firstCallback) {
            _firstCallback = false;
            _last = i;
            return;
          }
          if (i == _last) return;
          _last = i;
          // 惯性滚动结束回调可能落在别的 widget 构建期，统一延一帧再上报。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onSelect(i);
          });
        },
        children: [
          for (var i = 0; i < widget.labels.length; i++)
            Center(
              child: Text(
                widget.labels[i],
                style: TextStyle(
                  fontSize: i == _last ? widget.fontSize : widget.fontSize * .78,
                  fontWeight: i == _last ? FontWeight.w800 : FontWeight.w600,
                  color: i == _last ? tokens.accent : const Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


/// 呵护模块共用视觉件（原型 chip / toggle / 渐变 hero / 品牌日期选择器同构）。
/// 弹层统一走 [showCareSheet]（底部抽屉 + grabber，对齐 .sheet-panel）。

Color careHex(String s) {
  var s2 = s.replaceFirst('#', '');
  if (s2.length == 6) s2 = 'FF$s2';
  return Color(int.parse(s2, radix: 16));
}

/// 头像渐变色对（原型 abColors 四档 tailwind 渐变键）。
const Map<String, (String, String)> kBabyGradients = {
  'sky': ('#38bdf8', '#6366f1'),
  'amber': ('#fbbf24', '#f97316'),
  'rose': ('#fb7185', '#db2777'),
  'emerald': ('#34d399', '#0d9488'),
};

/// 宝宝页 hero 渐变（蓝→靛→紫）。
const kBabyHeroStops = ['#38bdf8', '#818cf8', '#c084fc'];

/// 周期页 hero 渐变（粉→桃→紫）。
const kCycleHeroStops = ['#f472b6', '#e879a0', '#c084fc'];

LinearGradient careGrad(List<String> stops, {Alignment? begin, Alignment? end}) =>
    LinearGradient(
      colors: stops.map(careHex).toList(),
      begin: begin ?? Alignment.topLeft,
      end: end ?? Alignment.bottomRight,
    );

/// 原型 .chip：描边胶囊；选中=brand 实底白字（与 PillChip 同语义，尺寸贴合原型）。
class CChip extends StatelessWidget {
  const CChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.dense = false,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool dense;

  /// 自定义选中色（默认 tokens.accent）。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final on = accent ?? tokens.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 5),
        decoration: BoxDecoration(
          color: selected ? on : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? on : (scheme.outlineVariant), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 单选 chips 行（原型 oneChip 组语义）。
class CSingleRow extends StatelessWidget {
  const CSingleRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onPick,
    this.wrap = true,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onPick;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: CChip(
            key: ValueKey('chip-$o'),
            label: o,
            selected: o == selected,
            onTap: () => onPick(o),
          ),
        ),
    ];
    return wrap
        ? Wrap(spacing: 0, runSpacing: 6, children: chips)
        : Row(mainAxisSize: MainAxisSize.min, children: chips);
  }
}

/// 迷你开关（原型 .toggle；尺寸贴合设置行）。
class CToggle extends StatelessWidget {
  const CToggle({super.key, required this.on, required this.onChanged, this.label});

  final bool on;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      toggled: on,
      label: label,
      child: GestureDetector(
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 24,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: on ? tokens.accent : context.tokens.cardBorder,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: const CircleAvatar(radius: 9, backgroundColor: Colors.white),
        ),
      ),
    );
  }
}

/// 呵护模块底部弹层统一容器（原型 sheet-panel：grabber + 顶部圆角 + 白底）。
Future<T?> showCareSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  bool secondary = false,
}) {
  final tokens = context.tokens;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: secondary,
    isScrollControlled: true,
    backgroundColor: tokens.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(bc).height * .88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.tokens.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(child: Builder(builder: builder)),
          ],
        ),
      ),
    ),
  );
}

/// 品牌日期选择结果：picked=选定日；cleared=true 表示「清除」。
class CareDateResult {
  const CareDateResult.pick(this.date) : cleared = false;
  const CareDateResult.clear()
      : cleared = true,
        date = null;

  final DateTime? date;
  final bool cleared;
}

/// sheetCareDate 品牌日期选择器（红线 5：禁原生 date picker）。
/// 形态=渐变头部（年 + 「9月19日 周五」）+ 月份翻切 + 周一起网格 + 清除/取消/设置。
Future<CareDateResult?> showCareDatePick(
  BuildContext context, {
  DateTime? initial,
  bool allowClear = false,
}) {
  return showModalBottomSheet<CareDateResult>(
    context: context,
    useRootNavigator: true, // 二级弹层之上仍置顶（z-[60] 同构）
    isScrollControlled: true,
    backgroundColor: context.tokens.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _CareDatePicker(initial: initial, allowClear: allowClear),
  );
}

class _CareDatePicker extends StatefulWidget {
  const _CareDatePicker({required this.initial, required this.allowClear});
  final DateTime? initial;
  final bool allowClear;

  @override
  State<_CareDatePicker> createState() => _CareDatePickerState();
}

class _CareDatePickerState extends State<_CareDatePicker> {
  static const _wd = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  late DateTime _focus = DateTime(
      (widget.initial ?? DateTime.now()).year,
      (widget.initial ?? DateTime.now()).month);
  late DateTime? _sel = widget.initial;

  void _move(int d) => setState(() => _focus = DateTime(_focus.year, _focus.month + d));

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(_focus.year, _focus.month, 1);
    final dim = DateTime(_focus.year, _focus.month + 1, 0).day;
    final lead = (first.weekday - 1); // 周一起
    final head = _sel == null
        ? '请选择日期'
        : '${_sel!.month}月${_sel!.day}日 ${_wd[_sel!.weekday - 1]}';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: tokens.cardBorder, borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: careGrad(kCycleHeroStops,
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_focus.year}年',
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
                  const SizedBox(height: 2),
                  Text(head,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _stepBtn('‹', () => _move(-1)),
                Text('${_focus.year}年${_focus.month}月',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                _stepBtn('›', () => _move(1)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final w in _wd)
                  Expanded(
                    child: Text(w.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                for (var d = 1; d <= dim; d++)
                  Builder(builder: (_) {
                    final date = DateTime(_focus.year, _focus.month, d);
                    final on = _sel != null &&
                        date.year == _sel!.year &&
                        date.month == _sel!.month &&
                        date.day == _sel!.day;
                    final isToday = date == today;
                    return GestureDetector(
                      onTap: () => setState(() => _sel = date),
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: on
                              ? careGrad(kCycleHeroStops,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text('$d',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: on || isToday ? FontWeight.w800 : FontWeight.w500,
                              color: on
                                  ? Colors.white
                                  : isToday
                                      ? tokens.accent
                                      : scheme.onSurface,
                            )),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.allowClear)
                  TextButton(
                    onPressed: () => Navigator.pop(context, const CareDateResult.clear()),
                    child: const Text('清除'),
                  ),
                const Spacer(),
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
                    onPressed: () => _sel == null
                        ? AppToast.show(context, '先选择日期')
                        : Navigator.pop(context, CareDateResult.pick(_sel!)),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: const Text('设置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(String t, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.tokens.cardBorder.withValues(alpha: .4),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      );
}

/// 分节小标题（原型 .row-title / text-[10px] 灰细标签）。
class CLabel extends StatelessWidget {
  const CLabel(this.text, {super.key, this.top = 12});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant)),
    );
  }
}

/// HH:MM 补零助手（event_sheet/baby_view 共用）。
String careP2(int v) => v.toString().padLeft(2, '0');
