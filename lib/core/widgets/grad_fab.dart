import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 渐变悬浮球（原型 #fab：56px 圆、grad 渐变、白字 ＋、点击旋转 45°）。
/// 通用壳层组件，不依赖任何 feature（守 R2）。
class GradFab extends StatelessWidget {
  const GradFab({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.rotation = 0,
    this.size = 56,
  });

  final Widget icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// 菜单展开时传 45°（原型 fabTap 的旋转过渡）。
  final double rotation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fab = Transform.rotate(
      angle: rotation,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Colors.black26,
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: tokens.gradient,
              boxShadow: [
                BoxShadow(
                  color: tokens.accent.withValues(alpha: .35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? fab : Tooltip(message: tooltip!, child: fab);
  }
}

/// 快捷记录菜单卡（原型 .fab-act：白底描边圆角卡 + 阴影）。
class FabActionCard extends StatelessWidget {
  const FabActionCard({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final dark = ThemeData.estimateBrightnessForColor(tokens.card) == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 176,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.cardBorder),
          boxShadow: const [
            BoxShadow(color: Color(0x1E0F172A), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: dark ? const Color(0xFFE2E8F0) : scheme.onSurface)),
      ),
    );
  }
}

/// 旋转角度工具（0 与 45° 之间过渡用 AnimatedRotation 即可，此处仅暴露常量）。
const double kFabOpenRotation = math.pi / 4;
