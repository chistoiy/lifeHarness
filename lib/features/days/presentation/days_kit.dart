/// days 模块私有组件库（P8 / P8a / P8b / P8c 四屏共用；需求 V1.42 模块11 口径）。
///
/// `CWheel` 为 care_kit.dart `CWheel` 先例的同模式独立实现（care 为 feature
/// 私有、跨模块不可 import，R2）——保留两处关键防护：
/// ① CupertinoPicker 首帧自动回调无条件吞掉；② 选择变化 postFrameCallback 延一帧上报。
/// 图标全局纪律：禁 emoji，kDayIcons / 提醒 kind 一律映射 Material 线性图标。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/day_models.dart';

/// 原型 tailwind 色板里 days 用到的语义色（rose / amber(sun) / slate-400）。
const kDaysRose = Color(0xFFF43F5E);
const kDaysAmber = Color(0xFFF59E0B);
const kDaysMuted = Color(0xFF94A3B8);

/// hex 字符串 → Color（care_kit `careHex` 同款解析）。
Color daysHex(String s) {
  var s2 = s.replaceFirst('#', '');
  if (s2.length == 6) s2 = 'FF$s2';
  return Color(int.parse(s2, radix: 16));
}

/// colorKey → 卡片渐变（kDayGradients hex 对；未知键回落 slate）。
LinearGradient dayGradientOf(String colorKey) {
  final pair = kDayGradients[colorKey] ?? kDayGradients['slate']!;
  return LinearGradient(
    colors: [daysHex(pair.$1), daysHex(pair.$2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// 12 个图标语义键 → Material 线性图标（原型 DE_ICONS 的无 emoji 替代）。
IconData dayIconOf(String iconId) => switch (iconId) {
      'cake' => Icons.cake_outlined,
      'heart' => Icons.favorite_border,
      'wallet' => Icons.account_balance_wallet_outlined,
      'alert' => Icons.warning_outlined,
      'medical' => Icons.local_hospital_outlined,
      'id' => Icons.credit_card_outlined,
      'flight' => Icons.flight_outlined,
      'gift' => Icons.card_giftcard_outlined,
      'school' => Icons.school_outlined,
      'home' => Icons.home_outlined,
      'hourglass' => Icons.hourglass_empty,
      'doc' => Icons.description_outlined,
      _ => Icons.event_outlined,
    };

/// 提醒条目图标键（cert/sub/warranty/id…）→ 线性图标。
IconData reminderIconOf(String iconId) => switch (iconId) {
      'cert' => Icons.verified_user_outlined,
      'id' => Icons.credit_card_outlined,
      'sub' => Icons.subscriptions_outlined,
      'warranty' => Icons.construction_outlined,
      _ => Icons.notifications_outlined,
    };

/// 数值补零（滚轮小时/预览时刻用）。
String daysP2(int v) => v.toString().padLeft(2, '0');

/// 就地内嵌滚轮（红线：时间/数值选择一律内嵌滚轮，禁两段式弹层）。
/// 模式复制自 care_kit `CWheel`（含首帧回调吞掉与 postFrameCallback 上报防护）。
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
                  color: i == _last ? tokens.accent : kDaysMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 就地内嵌「年 / 月 / 日」三列滚轮（P8b 目标日期；禁两段式弹层）。
/// 年列范围 now.year-100 .. now.year+10；日列随年月天数收敛。
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
            col('年', const ValueKey('d-date-year'),
                [for (final y in _years) '$y年'], yearIdx,
                (i) => _set(year: _years[i])),
            col('月', const ValueKey('d-date-month'),
                [for (var m = 1; m <= 12; m++) '$m月'], _v.month - 1,
                (i) => _set(month: i + 1)),
            col('日', const ValueKey('d-date-day'),
                [for (var d = 1; d <= dim; d++) '$d日'], _v.day - 1,
                (i) => _set(day: i + 1)),
          ],
        ),
      ],
    );
  }
}

/// 图标芯片行（P8b「图标」12 枚；选中=accent 描边+浅底）。
class DayIconPickRow extends StatelessWidget {
  const DayIconPickRow({
    super.key,
    required this.selected,
    required this.onPick,
  });

  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final id in kDayIcons)
          GestureDetector(
            key: ValueKey('d-edit-icon-$id'),
            onTap: () => onPick(id),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: id == selected
                    ? tokens.accent.withValues(alpha: .10)
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: id == selected ? tokens.accent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                dayIconOf(id),
                size: 20,
                color: id == selected ? tokens.accent : scheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }
}

/// 卡片颜色圆点行（P8b「卡片颜色」六档渐变；选中=ring 描边）。
class DayColorPickRow extends StatelessWidget {
  const DayColorPickRow({
    super.key,
    required this.selected,
    required this.onPick,
  });

  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        for (final key in kDayGradients.keys)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              key: ValueKey('d-edit-color-$key'),
              onTap: () => onPick(key),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: dayGradientOf(key),
                  border: key == selected
                      ? Border.all(color: tokens.accent, width: 3)
                      : null,
                  boxShadow: key == selected
                      ? [
                          BoxShadow(
                            color: tokens.accent.withValues(alpha: .45),
                            blurRadius: 0,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
              ),
            ),
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

/// 破删除描边钮（原型 border-rose-300 text-rose-500）。
class RoseOutlineButton extends StatelessWidget {
  const RoseOutlineButton({super.key, required this.label, required this.onTap});

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
          border: Border.all(color: kDaysRose.withValues(alpha: .45)),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kDaysRose)),
      ),
    );
  }
}

/// 迷你开关（原型 .toggle；与 care CToggle 同形态，feature 私有复刻）。
class DaysToggle extends StatelessWidget {
  const DaysToggle({super.key, required this.on, required this.onChanged});

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
Future<T?> showDaysSheet<T>(
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
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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

/// 破坏性操作二次确认（showDialog；文案与原型 confirm 一致，调用方传入）。
Future<bool> daysConfirm(BuildContext context, String message,
    {String okLabel = '删除'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (bc) => AlertDialog(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          key: const ValueKey('d-confirm-cancel'),
          onPressed: () => Navigator.pop(bc, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('d-confirm-ok'),
          onPressed: () => Navigator.pop(bc, true),
          child: Text(okLabel,
              style: const TextStyle(
                  color: kDaysRose, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}
