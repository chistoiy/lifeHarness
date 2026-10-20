/// items 模块私有组件库（P7 系六屏共用；需求 V1.42 模块9 口径）。
///
/// `CWheel`/`InlineDateWheel`/`MiniBtn`/`GradButton`/`RoseOutlineButton`/
/// `ItemsToggle`/`showItemsSheet`/`itemsConfirm` 为 days_kit 同模式**独立复刻**
/// （feature 私有、跨模块禁 import，R1/R2）；关键防护保留：
/// ① CupertinoPicker 首帧自动回调无条件吞掉；② 选择变化 postFrameCallback 延一帧上报。
/// 图标全局纪律：禁 emoji，iconId/分类语义键一律映射 Material 线性图标；
/// 原型 📦💳♻️🗑 对应 inventory_2 / payments / recycle / delete_outline。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/item_calc.dart';
import '../domain/item_models.dart';

/// 原型 tailwind 色板里 items 用到的语义色（mint / sun(peach) / slate-400 / slate-900 hero）。
const kItemMint = Color(0xFF2DD4BF);
const kItemSun = Color(0xFFF59E0B);
const kItemPeach = Color(0xFFFB7185);
const kItemMuted = Color(0xFF94A3B8);
const kItemHeroBg = Color(0xFF0F172A); // slate-900 深色控制盘（HG-G1）

/// hex 字符串 → Color（days_kit `daysHex` 同款解析）。
Color itemsHex(String s) {
  var s2 = s.replaceFirst('#', '');
  if (s2.length == 6) s2 = 'FF$s2';
  return Color(int.parse(s2, radix: 16));
}

/// 环图/占比配色（原型 cols：accent/mint/sun/peach/sky）。
const kItemChartColors = [
  Color(0xFF6366F1),
  kItemMint,
  kItemSun,
  kItemPeach,
  Color(0xFF0EA5E9),
];

/// iconId 语义键 → Material 线性图标（原型 📦 等 emoji 的无 emoji 替代）。
IconData itemIconOf(String iconId) => switch (iconId) {
      'box' => Icons.inventory_2_outlined,
      'laptop' => Icons.devices_outlined,
      'appliance' => Icons.local_laundry_service_outlined,
      'chair' => Icons.chair_outlined,
      'cloth' => Icons.checkroom_outlined,
      'vehicle' => Icons.two_wheeler_outlined,
      'camera' => Icons.photo_camera_outlined,
      'phone' => Icons.smartphone_outlined,
      _ => Icons.inventory_2_outlined,
    };

/// 建档表单无图标选择器：列表/详情图标块按分类映射线性图标。
IconData itemCatIcon(String category) => switch (category) {
      '数码' => Icons.devices_outlined,
      '家电' => Icons.local_laundry_service_outlined,
      '家具' => Icons.chair_outlined,
      '服饰' => Icons.checkroom_outlined,
      '交通工具' => Icons.two_wheeler_outlined,
      _ => Icons.inventory_2_outlined,
    };

/// 数值补零（滚轮时刻类扩展用）。
String itemsP2(int v) => v.toString().padLeft(2, '0');

/// 金额展示统一口径：先二舍五入再走 fmtY（千分位 + 整数省小数），同原型
/// `fmtY(+v.toFixed(2))`。
String itemMoney(num v) => fmtY(double.parse(v.toStringAsFixed(2)));

/// 恒定两位小数金额（原型按次卡/Top5 `¥${x.toFixed(2)}` 口径：¥3.00 不省零）。
String itemMoney2(num v) => '¥${v.toStringAsFixed(2)}';

/// 时间轴事件金额列文案（原型 tl[].a 语义）：buy=¥9,999 · extra=+¥399 ·
/// recycle=−¥1,800 · scrap=报废。
String itemEvAmountText(ItemEvent e) => switch (e.kind) {
      kEvBuy => fmtY(e.amount),
      kEvExtra => '+${fmtY(e.amount)}',
      kEvRecycle => '−${fmtY(e.amount)}',
      _ => '报废',
    };

/// 时间轴事件色点（原型 tl-dot 类：buy=accent、extra=sun、recycle=mint、scrap=slate）。
Color itemEvDotColor(ItemEvent e, ThemeTokens tokens) => switch (e.kind) {
      kEvBuy => tokens.accent,
      kEvExtra => kItemSun,
      kEvRecycle => kItemMint,
      _ => kItemMuted,
    };

/// 就地内嵌滚轮（HG-D1 红线：时间/数值选择一律内嵌滚轮，禁两段式弹层）。
/// 模式复制自 days_kit `CWheel`（含首帧回调吞掉与 postFrameCallback 上报防护）。
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
                  color: i == _last ? tokens.accent : kItemMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 就地内嵌「年 / 月 / 日」三列滚轮（购入日期 / 保修到期；禁两段式弹层）。
class InlineDateWheel extends StatefulWidget {
  const InlineDateWheel({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 120,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final double height;

  @override
  State<InlineDateWheel> createState() => _InlineDateWheelState();
}

class _InlineDateWheelState extends State<InlineDateWheel> {
  late DateTime _v = widget.value;

  /// 年列可选项（构建期一次性取当前年为锚，避免逐帧漂移）。
  late final List<int> _years = List.generate(
      100 + 10 + 1, (i) => DateTime.now().year - 100 + i);

  int get _yearStart => _years.first;

  void _set({int? year, int? month, int? day}) {
    final y = year ?? _v.year;
    final m = month ?? _v.month;
    final dim = DateTime(y, m + 1, 0).day;
    final d = (day ?? _v.day).clamp(1, dim);
    setState(() => _v = DateTime(y, m, d));
    widget.onChanged(_v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = DateTime(_v.year, _v.month + 1, 0).day;
    final yearIdx = (_v.year - _yearStart).clamp(0, _years.length - 1);
    Widget col(String label, Key key, List<String> labels, int idx,
            ValueChanged<int> onSelect) =>
        Expanded(
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              CWheel(
                key: key,
                labels: labels,
                initialIndex: idx,
                onSelect: onSelect,
                height: widget.height,
                fontSize: 14,
              ),
            ],
          ),
        );
    return Column(
      children: [
        Row(
          children: [
            col('年', const ValueKey('i-date-year'),
                [for (final y in _years) '$y年'], yearIdx,
                (i) => _set(year: _years[i])),
            col('月', const ValueKey('i-date-month'),
                [for (var m = 1; m <= 12; m++) '$m月'], _v.month - 1,
                (i) => _set(month: i + 1)),
            col('日', const ValueKey('i-date-day'),
                [for (var d = 1; d <= dim; d++) '$d日'], _v.day - 1,
                (i) => _set(day: i + 1)),
          ],
        ),
      ],
    );
  }
}

/// 迷你动作钮（原型 .mini-btn：小圆角浅底粗字，可带线性图标）。
class MiniBtn extends StatelessWidget {
  const MiniBtn({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.bg,
    this.fg,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bg ?? scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg ?? scheme.onSurface),
              const SizedBox(width: 3),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: fg ?? scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

/// 渐变主行动钮（原型 grad 钮：圆角 14、tokens 渐变、白粗字）。
class GradButton extends StatelessWidget {
  const GradButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: tokens.gradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// 破弃/描边钮（原型 border-peach/45 text-peach，如报废确认钮描边形态）。
class RoseOutlineButton extends StatelessWidget {
  const RoseOutlineButton(
      {super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kItemPeach.withValues(alpha: .45)),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kItemPeach)),
      ),
    );
  }
}

/// 迷你开关（原型 .toggle；feature 私有复刻，禁 import days_kit）。
class ItemsToggle extends StatelessWidget {
  const ItemsToggle({super.key, required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      toggled: on,
      child: GestureDetector(
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 24,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: on ? tokens.accent : tokens.cardBorder,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: const CircleAvatar(radius: 9, backgroundColor: Colors.white),
        ),
      ),
    );
  }
}

/// LH-S 公共骨架：grabber 圆条 + 标题 15 w900 + 内容（统一弹层容器）。
Future<T?> showItemsSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
}) {
  final tokens = context.tokens;
  return showModalBottomSheet<T>(
    context: context,
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
        child: Padding(
          // T1（交互整改批一）：3.38 起模态底栏不随键盘自动抬升，底边距并入键盘高度。
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.viewInsetsOf(bc).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Flexible(child: Builder(builder: builder)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 破坏性操作二次确认（showDialog；文案与原型 confirm 语义一致，调用方传入）。
Future<bool> itemsConfirm(BuildContext context, String message,
    {String okLabel = '确认'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (bc) => AlertDialog(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          key: const ValueKey('i-confirm-cancel'),
          onPressed: () => Navigator.pop(bc, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('i-confirm-ok'),
          onPressed: () => Navigator.pop(bc, true),
          child: Text(okLabel,
              style: const TextStyle(
                  color: kItemPeach, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// 成本流水时间轴（详情/决算共用；竖线 + 色点 + 金额/标签/日期/note，仅追加展示）。
class ItemTimeline extends StatelessWidget {
  const ItemTimeline({super.key, required this.events});

  final List<ItemEvent> events;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < events.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 2, color: scheme.outlineVariant),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      key: ValueKey('i-tl-dot-${events[i].id ?? i}'),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: itemEvDotColor(events[i], tokens),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 2, bottom: i == events.length - 1 ? 0 : 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: itemEvAmountText(events[i]),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: kItemMuted)),
                              TextSpan(
                                  text: ' ${events[i].label} ',
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700)),
                              TextSpan(
                                  text: events[i].date,
                                  style: TextStyle(
                                      fontSize: 11, color: scheme.onSurfaceVariant)),
                            ]),
                          ),
                          if ((events[i].note ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(events[i].note!,
                                  style: TextStyle(
                                      fontSize: 10,
                                      height: 1.5,
                                      color: scheme.onSurfaceVariant)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
