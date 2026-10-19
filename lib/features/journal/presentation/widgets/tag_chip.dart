import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/tag.dart';

/// 标签胶囊（批2b · 原型 `.dtag`）。
///
/// 颜色只走语义色名 → 主题令牌（4 主题 × 明暗自动跟随），**禁写死色值**；
/// 色名按标签在池内的次序轮转（[tagToneAt]），保证同一标签在筛选段与编辑页
/// 拿到同一个色。
Color tagToneColor(String tone, ThemeTokens tokens) => switch (tone) {
      'emerald' => const Color(0xFF10B981),
      'amber' => const Color(0xFFF59E0B),
      'rose' => const Color(0xFFF43F5E),
      'sky' => const Color(0xFF0EA5E9),
      'violet' => tokens.accentLight,
      _ => tokens.accent,
    };

/// 一枚已选标签：色点 + 名称（+ 可选移除叉）。
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.name,
    this.toneIndex = 0,
    this.count,
    this.onTap,
    this.onRemove,
  });

  final String name;
  final int toneIndex;

  /// 胶囊尾部的引用数（选标签弹层里显示；编辑页标签行不显示）。
  final int? count;
  final VoidCallback? onTap;

  /// 非空时出右侧 ✕（就地移除，不进弹层才删得了——原型同款）。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tone = tagToneColor(tagToneAt(toneIndex), tokens);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: dark
              ? tone.withValues(alpha: .12)
              : tokens.accent.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: dark
                  ? tone.withValues(alpha: .22)
                  : tokens.accent.withValues(alpha: .18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(name,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white.withValues(alpha: .78) : tokens.text1)),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text('$count',
                style: TextStyle(
                    fontSize: 11,
                    color: tokens.text2,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              key: ValueKey('dtag-x-$name'),
              onTap: onRemove,
              child: Icon(Icons.close,
                  size: 12, color: tokens.text2.withValues(alpha: .55)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// 末尾的「＋ 标签」虚线胶囊（编辑页标签行唯一入口）。
class TagAddChip extends StatelessWidget {
  const TagAddChip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      key: const ValueKey('dtag-add'),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: tokens.text2.withValues(alpha: .45),
              style: BorderStyle.solid),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, size: 12, color: tokens.text2),
          const SizedBox(width: 3),
          Text('标签',
              style: TextStyle(fontSize: 11, color: tokens.text2)),
        ]),
      ),
    );
  }
}
