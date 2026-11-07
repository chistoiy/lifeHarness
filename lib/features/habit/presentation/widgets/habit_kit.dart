import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/habit.dart';

/// 卡片通用描边底（原型 .card）。
BoxDecoration hCardDeco(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(context.tokens.cardRadius),
    border: Border.all(color: context.tokens.cardBorder),
  );
}

/// 习惯模块视觉基元（原型 index_habitcheck.html Tailwind 色板 / HB_IC 线性图标）。
/// 状态语义色按原型色值常量集中于此，页面不再散落十六进制。
abstract final class HK {
  // brand（主题强调色近似 · hero/达成量点用）
  static const brand = Color(0xFF6366F1);
  // emerald 系（已达成）
  static const ok400 = Color(0xFF34D399);
  static const ok500 = Color(0xFF10B981);
  static const ok700 = Color(0xFF047857);
  // teal 系（负向「未触发」= 好状态，正向色 · AC 不羞辱人）
  static const teal400 = Color(0xFF2DD4BF);
  static const teal500 = Color(0xFF14B8A6);
  // rose 系（负向「触发」= 中性事实色，不做告警红底）
  static const rose400 = Color(0xFFFB7185);
  static const rose500 = Color(0xFFF43F5E);
  // amber 系（补记 ring-amber / 部分达标 / sun 档）
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  // sky 系（宽限卡 ring / 宽限钮文字）
  static const sky400 = Color(0xFF38BDF8);
  static const sky600 = Color(0xFF0284C7);
  // teal 600（「坚持」徽标文字）
  static const teal600 = Color(0xFF0D9488);

  /// 达成率三档文字色（原型 rate>=70 emerald / >=40 sun / else rose）。
  static Color rateText(int rate) =>
      rate >= 70 ? ok500 : rate >= 40 ? amber500 : rose500;
}

/// HB_IC key → Material 线性图标（禁 emoji · 与原型 stroke 线性同风格）。
abstract final class HIcons {
  /// 火焰常量（banner 内 const Icon 用 · 与 resolve('flame') 同值）。
  static const resolveFlame = Icons.local_fire_department_outlined;

  static IconData resolve(String key) => switch (key) {
    'run' => Icons.directions_run_outlined,
    'book' => Icons.menu_book_outlined,
    'med' => Icons.self_improvement_outlined,
    'water' => Icons.water_drop_outlined,
    'sleep' => Icons.bedtime_outlined,
    'write' => Icons.edit_note_outlined,
    'food' => Icons.lunch_dining_outlined,
    'phone' => Icons.smartphone_outlined,
    'smoke' => Icons.smoking_rooms_outlined,
    'early' => Icons.alarm_outlined,
    'code' => Icons.code_outlined,
    'plan' => Icons.event_note_outlined,
    'chart' => Icons.insights_outlined,
    'cog' => Icons.settings_outlined,
    'more' => Icons.more_horiz,
    'pen' => Icons.edit_outlined,
    'plus' => Icons.add,
    'check' => Icons.check,
    'close' => Icons.close,
    'undo' => Icons.undo,
    'cal' => Icons.calendar_today_outlined,
    'arch' => Icons.archive_outlined,
    'shield' => Icons.shield_outlined,
    'flame' => Icons.local_fire_department_outlined,
    'grid' => Icons.grid_view_rounded,
    'list' => Icons.format_list_bulleted_rounded,
    'doc' => Icons.description_outlined,
    'up' => Icons.arrow_upward,
    'down' => Icons.arrow_downward,
    'trash' => Icons.delete_outline,
    _ => Icons.check,
  };

  /// 习惯表单可选图标集（原型 heRender 12 枚内联）。
  static const pickerKeys = [
    'run',
    'book',
    'med',
    'water',
    'sleep',
    'write',
    'food',
    'phone',
    'smoke',
    'early',
    'code',
    'plan',
  ];
}

/// 圆环进度（原型 .ring-progress：底环 + 端点圆角弧 + 中心文案）。
class RingProgress extends StatelessWidget {
  const RingProgress({
    super.key,
    required this.value,
    this.size = 56,
    this.stroke = 6,
    this.color = Colors.white,
    this.bg = const Color(0x42FFFFFF),
    this.child,
  });

  /// 0..1。
  final double value;
  final double size;
  final double stroke;
  final Color color;
  final Color bg;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.clamp(0.0, 1.0),
          stroke: stroke,
          color: color,
          bg: bg,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.stroke,
    required this.color,
    required this.bg,
  });

  final double value;
  final double stroke;
  final Color color;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (math.min(size.width, size.height) - stroke) / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = bg,
    );
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.bg != bg;
}

/// 习惯类型图标瓦（原型 icon 底块：正向 brand 底 / 负向 rose 底）。
class HabitIconTile extends StatelessWidget {
  const HabitIconTile({
    super.key,
    required this.iconKey,
    required this.neg,
    this.size = 36,
    this.radius = 12,
    this.iconSize = 18,
  });

  final String iconKey;
  final bool neg;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = neg ? HK.rose500 : HK.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color.alphaBlend(tint.withValues(alpha: .12), scheme.surface),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(HIcons.resolve(iconKey), size: iconSize, color: tint),
    );
  }
}

/// 小号灰底圆角钮（原型 w-7/w-8 rounded-lg bg-slate-100 系列）。
class HSmallBtn extends StatelessWidget {
  const HSmallBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 32,
    this.tip,
    this.disabled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tip;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = Opacity(
      opacity: disabled ? .35 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            scheme.onSurface.withValues(alpha: .06),
            scheme.surface,
          ),
          borderRadius: BorderRadius.circular(size >= 32 ? 12 : 8),
        ),
        child: Icon(icon, size: size * .55, color: scheme.onSurfaceVariant),
      ),
    );
    final btn = InkWell(onTap: disabled ? null : onTap, child: w);
    return tip == null ? btn : Tooltip(message: tip!, child: btn);
  }
}

/// 胶囊小标签（原型 bg-white/20 rounded-full px-2 py-1 font-bold 系列）。
class HPill extends StatelessWidget {
  const HPill({
    super.key,
    required this.text,
    this.icon,
    this.bg = const Color(0x33FFFFFF),
    this.fg = Colors.white,
    this.onTap,
    this.bold = true,
  });

  final String text;
  final IconData? icon;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        color: fg,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: icon == null
            ? t
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 11, color: fg),
                  const SizedBox(width: 3),
                  t,
                ],
              ),
      ),
    );
  }
}

/// 强调色浅底小钮（原型 .mini-btn：accent 12% 底 · 11px 粗体）。
class HMiniBtn extends StatelessWidget {
  const HMiniBtn(this.text, {super.key, this.onTap, this.flex = false});

  final String text;
  final VoidCallback? onTap;
  final bool flex;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final w = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
    final tap = InkWell(onTap: onTap, child: w);
    return flex ? Expanded(child: tap) : tap;
  }
}

/// 列表卡七日点阵（原型 hbDots：21px 圆角方点 · 正向 ✓ / 负向触发 ! ·
/// 今日 brand 描边 · 宽限 sky 描边 · 数值/时刻/补记进 tooltip）。
/// ⚠ 动态状态样式只进 decoration，绝不落进文本节点（§5-11）。
class HabitWeekDots extends StatelessWidget {
  const HabitWeekDots({
    super.key,
    required this.habit,
    required this.flags,
    required this.todayIdx,
    this.frozens = const [],
    this.valTips = const [],
  });

  final Habit habit;
  final List<bool> flags;
  final List<bool> frozens;
  final int todayIdx;
  final List<String> valTips;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Tooltip(
            message:
                i < valTips.length && valTips[i].isNotEmpty
                    ? valTips[i]
                    : '周${'一二三四五六日'[i]}',
            child: Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color:
                    flags[i]
                        ? HK.ok400
                        : habit.isNeg
                        ? HK.rose500.withValues(alpha: .12)
                        : scheme.onSurface.withValues(alpha: .06),
                border:
                    i == todayIdx
                        ? Border.all(color: HK.brand, width: 1)
                        : i < frozens.length && frozens[i]
                        ? Border.all(color: HK.sky400, width: 1)
                        : null,
              ),
              alignment: Alignment.center,
              child: Text(
                // 正向达成显 ✓；负向「未触发」不显符号、「触发」显 !（原型同构）。
                flags[i] ? (habit.isNeg ? '' : '✓') : (habit.isNeg ? '!' : ''),
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color:
                      flags[i]
                          ? Colors.white
                          : habit.isNeg
                          ? HK.rose400
                          : scheme.onSurface.withValues(alpha: .4),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 组卡子项 chips 行（原型 hbSubChips：达标 emerald 底 / 有部分 amber 底 /
/// 空 slate 底 + 末尾达成规则文案 chip）。禁跨单位求和（§5-3）。
class HabitSubChips extends StatelessWidget {
  const HabitSubChips({super.key, required this.habit, required this.values});

  final Habit habit;
  final Map<int, double> values;

  static String ruleText(Habit h) => switch (h.groupRule) {
    Habit.kRuleAll => '全部完成才算达成',
    Habit.kRuleAny => '任一完成即达成',
    _ => '完成 ≥${(h.subs.length / 2).ceil()} 项达成',
  };

  static String n(double v) => v % 1 == 0 ? '${v.toInt()}' : '$v';

  @override
  Widget build(BuildContext context) {
    if (!habit.isGroup) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    Widget chip(TextSpan span, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(span, style: const TextStyle(fontSize: 10, height: 1.3)),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in habit.subs)
          () {
            final v = values[s.id] ?? 0;
            final met = s.goal > 0 && v >= s.goal;
            final fg =
                met
                    ? HK.ok500
                    : v > 0
                    ? HK.amber600
                    : scheme.onSurfaceVariant;
            return chip(
              TextSpan(
                style: TextStyle(color: fg),
                children: [
                  TextSpan(text: '${s.name} '),
                  TextSpan(
                    text: n(v),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '/${n(s.goal)}${s.unit}'),
                ],
              ),
              met
                  ? HK.ok500.withValues(alpha: .12)
                  : v > 0
                  ? HK.amber500.withValues(alpha: .12)
                  : scheme.onSurface.withValues(alpha: .06),
            );
          }(),
        chip(
          TextSpan(
            text: ruleText(habit),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          scheme.onSurface.withValues(alpha: .06),
        ),
      ],
    );
  }
}
