import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// LH UI 原语库（《docs/UI组件规范.md》§七）。
/// 新代码一律优先复用本文件组件；存量重复调用点按两档流程「路过替换」。
/// 微调某类外观时只改本文件/theme 一处，全 app 生效。

/// LH-T01 胶囊提示：全局统一深色胶囊 SnackBar（样式基线在 app_theme snackBarTheme）。
class AppToast {
  AppToast._();

  static void show(BuildContext context, String msg, {int ms = 1600}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: Duration(milliseconds: ms)));
  }
}

/// LH-K03 胶囊筛选 chip：选中=accent 实底白字，未选=卡底描边。
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? icon;

  /// 置灰不可点（协议锁定态——编辑已建服务时禁改协议，见 R2 项⑤b）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tap = enabled ? onTap : null;
    return GestureDetector(
      onTap: tap,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? tokens.accent : tokens.card,
            borderRadius: BorderRadius.circular(999),
            border: selected ? null : Border.all(color: tokens.cardBorder),
          ),
          child: Text(
            icon == null ? label : '$icon $label',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// LH-K09 横滑选择器（原型 .hpick/.hopt/.hon，V1.50 批3.6 V5）：
/// 横向可滑 + 松手吸附居中，替代上下滚轮 CWheel——左右滑或点选切换，选中项居中
/// accent 高亮。首尾留半格外边距使首末项可真正居中。每项 key=`hopt-<label>` 供测试点选。
class HPick extends StatefulWidget {
  const HPick({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.itemWidth = 76,
    this.height = 40,
  });

  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  final double itemWidth;
  final double height;

  @override
  State<HPick> createState() => _HPickState();
}

class _HPickState extends State<HPick> {
  final ScrollController _ctl = ScrollController();
  late int _cur = widget.index;
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(widget.index, animate: false));
  }

  @override
  void didUpdateWidget(HPick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && widget.index != _cur) {
      _cur = widget.index;
      _center(widget.index, animate: true);
    }
  }

  double _offsetFor(int i) => i * widget.itemWidth;

  void _center(int i, {required bool animate}) {
    if (!_ctl.hasClients || _viewport == 0) return;
    final target =
        (_offsetFor(i) - (_viewport - widget.itemWidth) / 2).clamp(0.0, _ctl.position.maxScrollExtent);
    if (animate) {
      _ctl.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _ctl.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _cur) return;
    setState(() => _cur = i);
    _center(i, animate: true);
    widget.onChanged(i);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(builder: (context, box) {
      _viewport = box.maxWidth;
      final pad = ((_viewport - widget.itemWidth) / 2).clamp(0.0, double.infinity);
      return SizedBox(
        height: widget.height,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            if (_ctl.hasClients) {
              final i = (_ctl.offset / widget.itemWidth).round().clamp(0, widget.items.length - 1);
              if (i != _cur) {
                setState(() => _cur = i);
                widget.onChanged(i);
              }
              _center(i, animate: true);
            }
            return false;
          },
          child: ListView.builder(
            controller: _ctl,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemCount: widget.items.length,
            itemBuilder: (context, i) {
              final on = i == _cur;
              return GestureDetector(
                key: ValueKey('hopt-${widget.items[i]}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _select(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: widget.itemWidth,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? tokens.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: on
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .10),
                                blurRadius: 4,
                                offset: const Offset(0, 1))
                          ]
                        : null,
                  ),
                  child: Text(
                    widget.items[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: on
                          ? tokens.accent
                          : Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: .72),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

/// LH-K05 色点图例：`(标签, 颜色)` 横排。
class DotLegend extends StatelessWidget {
  const DotLegend({super.key, required this.items, this.trailing});

  final List<(String, Color)> items;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (label, color) in items)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                const SizedBox(width: 3),
                Text(label, style: TextStyle(fontSize: 9, color: muted)),
              ],
            ),
          ),
        if (trailing != null)
          Text(trailing!, style: TextStyle(fontSize: 9, color: muted)),
      ],
    );
  }
}

/// LH-K06 心情表情行：点选放大 1.25，未选 45% 透明（数据无关，回调下标）。
class MoodRow extends StatelessWidget {
  const MoodRow({
    super.key,
    required this.emojis,
    this.selected,
    required this.onPick,
    this.keyPrefix = 'mood',
  });

  final List<String> emojis;
  final int? selected;
  final ValueChanged<int> onPick;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < emojis.length; i++)
          GestureDetector(
            key: ValueKey('$keyPrefix-$i'),
            onTap: () => onPick(i),
            child: AnimatedScale(
              scale: selected == i ? 1.25 : 1,
              duration: const Duration(milliseconds: 150),
              child: Opacity(
                opacity: selected == null || selected == i ? 1 : .45,
                child: Text(emojis[i], style: const TextStyle(fontSize: 24)),
              ),
            ),
          ),
      ],
    );
  }
}

/// LH-C04 分节卡：描边卡 + 节标题 + 内容（日记模板分节/其他分节表单共用）。
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// LH-L04 空态补录行：描边占位行，点击=补录/添加入口。
class EmptyDashRow extends StatelessWidget {
  const EmptyDashRow({super.key, required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(
          child: Text(text,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}
