/// 目标 OKR 模块私有组件库（P10 / P10a / P10b / P10c 四屏共用；需求 V1.42 模块7）。
///
/// `MiniBtn`/`GradButton`/底部弹层/二次确认 为 days_kit 先例的同模式独立实现
/// （care/days 组件为 feature 私有、跨模块不可 import，R1）。数值输入用就地
/// TextField（原型即 input），周期/单位/数据源等枚举选择走底部弹层选项，
/// 禁系统原生 select 风格。图标全局纪律：禁 emoji（HG 批次口径）。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 原型 tailwind 色板里 goals 用到的语义色（emerald-500 / sun(amber) / slate-400 / rose-500）。
const kGoalsEmerald = Color(0xFF10B981);
const kGoalsAmber = Color(0xFFF59E0B);
const kGoalsMuted = Color(0xFF94A3B8);
const kGoalsRose = Color(0xFFF43F5E);

/// MM-DD（详情页截止展示）。
String goalsMonthDay(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// epoch ms → YYYY-MM-DD HH:mm（来源明细留痕时刻）。
String goalsStamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${p2(d.month)}-${p2(d.day)} ${p2(d.hour)}:${p2(d.minute)}';
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

/// 描边次级钮（原型 border-slate-300 圆角 14 粗字）。
class OutlineButton extends StatelessWidget {
  const OutlineButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.cardBorder),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// 破坏性描边钮（原型 border-rose-300 text-rose-500）。
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
          border: Border.all(color: kGoalsRose.withValues(alpha: .45)),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kGoalsRose)),
      ),
    );
  }
}

/// 周期/归档小标签（原型 chip !text-[9px]：浅底圆角小字）。
class GoalsTag extends StatelessWidget {
  const GoalsTag(this.text, {super.key, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: muted ? scheme.surfaceContainerHighest : tokens.accentLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: muted ? scheme.onSurfaceVariant : tokens.accent)),
    );
  }
}

/// 进度条（原型 h-1.5 / h-2 圆角条：gradient 渐变 / 归档灰 / 达成 emerald / 零灰底）。
class GoalsBar extends StatelessWidget {
  const GoalsBar({
    super.key,
    required this.pct,
    this.height = 6,
    this.gray = false,
    this.solid,
  });

  final int pct;
  final double height;

  /// 归档态：整条走 slate 灰（原型 bg-slate-400）。
  final bool gray;

  /// 指定实色（KR 迷你条达成=emerald / 零=kGoalsMuted）。
  final Color? solid;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: height,
        color: scheme.surfaceContainerHighest,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: (pct.clamp(0, 100)) / 100,
          child: Container(
            decoration: BoxDecoration(
              gradient:
                  gray || solid != null ? null : tokens.gradient,
              color: gray
                  ? kGoalsMuted
                  : solid,
            ),
          ),
        ),
      ),
    );
  }
}

/// 百分比环（原型 svg ring-progress：底色环 + accent/归档灰 弧 + 中心 %）。
class GoalsRing extends StatelessWidget {
  const GoalsRing({
    super.key,
    required this.pct,
    this.size = 80,
    this.gray = false,
  });

  final int pct;
  final double size;
  final bool gray;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = gray ? kGoalsMuted : tokens.accent;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(pct: pct, color: color),
        child: Center(
          child: Text('$pct%',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.pct, required this.color});
  final int pct;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - 9) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..color = const Color(0xFFE2E8F0).withValues(alpha: .35);
    canvas.drawCircle(center, radius, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    final sweep = (pct.clamp(0, 100)) / 100 * 2 * 3.141592653589793;
    if (sweep > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -3.141592653589793 / 2,
          sweep,
          false,
          arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.pct != pct || old.color != color;
}

/// LH-S 公共骨架：grabber 圆条 + 标题 15 w900 + 内容（统一弹层容器）。
Future<T?> showGoalsSheet<T>(
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
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(bc).height * .88),
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

/// 底部弹层单选（周期/单位/数据源等枚举；禁系统原生 select 风格）。
/// 返回被选条目标签；key 前缀 g-opt-。
Future<String?> showGoalsChoiceSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? selected,
}) {
  final tokens = context.tokens;
  final scheme = Theme.of(context).colorScheme;
  return showGoalsSheet<String>(context, title: title, builder: (bc) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              key: ValueKey('g-opt-$title-$o'),
              onTap: () => Navigator.pop(bc, o),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: o == selected
                      ? tokens.accentLight
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: o == selected ? tokens.accent : Colors.transparent),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(o,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: o == selected
                                  ? tokens.accent
                                  : scheme.onSurface)),
                    ),
                    if (o == selected)
                      Icon(Icons.check, size: 16, color: tokens.accent),
                  ],
                ),
              ),
            ),
        ],
      ));
}

/// 破坏性操作二次确认（HG-D2；文案与原型 confirm 一致，调用方传入）。
Future<bool> goalsConfirm(BuildContext context, String message,
    {String okLabel = '删除', Key? okKey}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (bc) => AlertDialog(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          key: const ValueKey('g-confirm-cancel'),
          onPressed: () => Navigator.pop(bc, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: okKey ?? const ValueKey('g-confirm-ok'),
          onPressed: () => Navigator.pop(bc, true),
          child: Text(okLabel,
              style: const TextStyle(
                  color: kGoalsRose, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// 口径说明浅底卡（原型 rounded-2xl bg-brand-50 说明块，文案逐字）。
class GoalsNoteCard extends StatelessWidget {
  const GoalsNoteCard(this.text, {super.key, this.top = 12});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: top),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.accentLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, height: 1.9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}
