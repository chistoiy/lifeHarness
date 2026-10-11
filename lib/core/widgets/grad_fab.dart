import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../nav/nav_collapse.dart' show ShellFabInset, kNavCollapseDuration;
import '../theme/app_theme.dart';

/// 渐变悬浮球（原型 #fab：56px 圆、grad 渐变、白字 ＋、点击旋转 45°）。
/// 通用壳层组件，不依赖任何 feature（守 R2）。
///
/// **底栏收起态补偿**（V1.65）：悬浮球是页面级 `floatingActionButton`，锚在**页面** Scaffold
/// 底边；壳层底栏一收，body 变高、页面底边下移，球就会跟着往下掉（产品拍板「不落底」）。
/// 这里读壳层的 [ShellFabInset] 把这段高度补回去，让球**按屏幕位置钉住**。壳外页面读不到＝0，
/// 行为与从前完全一致。
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
    final out = tooltip == null ? fab : Tooltip(message: tooltip!, child: fab);
    // 底栏收起时把「飘出来的那段高度」补在球下方＝球的**屏幕上位置不动**。
    // 一律包一层（哪怕是 0）——否则 0↔正数 切换时首帧会跳而不是补间。
    return AnimatedPadding(
      duration: kNavCollapseDuration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: ShellFabInset.of(context)),
      child: out,
    );
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
