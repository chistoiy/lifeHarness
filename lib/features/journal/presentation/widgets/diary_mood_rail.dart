import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/diary_edit_kit.dart';

/// 日记编辑页「心情行」（原型 `#moodRail` + `#moodMoreBtn` + `#moodMoreRow`，§4d ①）。
///
/// 三条口径（产品原话「Emoji 做成可横向滚动的单选组」）：
/// ① **可横向滚动**的单选组——不是等分铺满（等分一屏塞七枚，字号一放大就挤成一排点）；
/// ② 选中＝淡底 + 放大 1.08 + 描边环 + **右上角小叉**（小叉＝取消，与再点一次同效）；
/// ③ 未选中降饱和（`Opacity` 一档），否则整行花花绿绿抢正文。
///
/// 抽成独立件的理由：页面本体已 1156 行（红线 1200），且**结构化模板档也要挂这一行**
/// （原型把心情行放在页码级、与模板无关），两处共用。
class DiaryMoodRail extends StatelessWidget {
  const DiaryMoodRail({
    super.key,
    required this.mood,
    required this.onMood,
    required this.moreOpen,
    required this.onToggleMore,
    this.enabled = true,
    this.extraHint,
  });

  /// 当前心情（库内序号 1..7；null＝未记）。
  final int? mood;

  /// 点一枚（同值＝取消，由调用方按 `moodToggled` 处理）。
  final ValueChanged<String> onMood;

  /// 「更多」行是否展开。
  final bool moreOpen;
  final VoidCallback onToggleMore;

  /// 只读态（展示既有篇但不许改的地方；本页恒 true，留给批2b 选标签弹层预览用）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: ListView(
                  key: const ValueKey('diary-mood-rail'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  children: [
                    for (final m in kMoodMain)
                      _chip(context, tokens, scheme, m.$2, m.$3, 'mood-main-${m.$1}'),
                  ],
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('diary-mood-more'),
              onPressed: enabled ? onToggleMore : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 32),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                foregroundColor: tokens.accent,
              ),
              child: Text(moreOpen ? '收起' : '更多',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        if (moreOpen)
          SizedBox(
            height: 44,
            child: ListView(
              key: const ValueKey('diary-mood-more-row'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              children: [
                for (var i = 0; i < kMoodExtra.length; i++)
                  _chip(context, tokens, scheme, kMoodExtra[i].$1, kMoodExtra[i].$2,
                      'mood-extra-$i'),
              ],
            ),
          ),
      ],
    );
  }

  bool _extraPicked(String emoji) =>
      diaryMoodIndex(emoji) == null && emoji == extraHint;

  /// 额外两枚的页内选中提示（父层按 `extraHint` 传进来，切走即清）。
  final String? extraHint;

  /// 单枚：36×36 圆角块；选中＝淡底 + ring + 放大 + 右上小叉。
  Widget _chip(BuildContext context, tokens, ColorScheme scheme, String emoji,
      String label, String slot) {
    // 额外两枚（😍/🤔）库内无序号，`moodSelected` 对它们恒 false ⇒ 点了只做「视觉回显」，
    // 不冒充已记录——否则用户以为记下了，重开发现没了（比不显示更糟）。
    final on = moodSelected(mood, emoji) || _extraPicked(emoji);
    final chip = SizedBox(
      width: 36,
      height: 44,
      child: Center(
        child: AnimatedScale(
          scale: on ? 1.08 : 1,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? tokens.accent.withValues(alpha: .12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: on ? tokens.accent.withValues(alpha: .42) : Colors.transparent),
            ),
            child: Opacity(
              opacity: on ? 1 : .62,
              child: Text(emoji,
                  semanticsLabel: '心情 $label',
                  style: const TextStyle(fontSize: 19, height: 1)),
            ),
          ),
        ),
      ),
    );
    if (!enabled) return KeyedSubtree(key: ValueKey(slot), child: chip);
    return GestureDetector(
      key: ValueKey(slot),
      behavior: HitTestBehavior.opaque,
      onTap: () => onMood(emoji),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          if (on)
            Positioned(
              top: 2,
              right: 4,
              child: GestureDetector(
                key: const ValueKey('diary-mood-clear'),
                onTap: () => onMood(emoji), // 小叉与「再点一次」同一入口
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Icon(Icons.close, size: 9, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
