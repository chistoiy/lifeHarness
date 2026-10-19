import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/diary_filter_kit.dart';
import '../../domain/journal_entry.dart';

/// 日记筛选弹层（批2c 重做）。
///
/// 原实现是一列 `ListTile`（每项 48px 独占一行），标签还硬编码只取前 4 条；
/// 原型早已改成「标记／标签两段 32px 胶囊横排 + 标签超一行折叠」，
/// 本文件把这一面补上，弹层高度从「6 项吃掉 288px」收到两组各一行。
///
/// 三条口径来自产品令，别顺手改：
/// ① **不超一行时不出「展开全部」按钮、也不裁剪**（按钮本身不占位、不多占一行）；
/// ② 展开状态在切筛选项后**保持**（用户展开过就该一直展开）——故选中只改本地态
///    与 settings，不弹关弹层；
/// ③ 选中即生效（列表在弹层后面实时跟着变），底部给实时计数与重置。
Future<void> showDiaryFilterSheet(
  BuildContext context, {
  required String cur,
  required List<String> tags,
  required List<JournalEntry> entries,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _DiaryFilterSheet(cur: cur, tags: tags, entries: entries),
  );
}

class _DiaryFilterSheet extends ConsumerStatefulWidget {
  const _DiaryFilterSheet({
    required this.cur,
    required this.tags,
    required this.entries,
  });

  final String cur;
  final List<String> tags;
  final List<JournalEntry> entries;

  @override
  ConsumerState<_DiaryFilterSheet> createState() => _DiaryFilterSheetState();
}

class _DiaryFilterSheetState extends ConsumerState<_DiaryFilterSheet> {
  late String _cur = widget.cur;

  /// 标签段是否展开。默认折叠一行；切筛选项**不重置**（口径②）。
  bool _tagOpen = false;

  /// 选中即生效：写 settings（冷启动恢复）+ 本地态（弹层不关，好看实时计数）。
  void _pick(String key) {
    setState(() => _cur = key);
    ref.read(settingsControllerProvider.notifier).setJournalFilter(key);
  }

  /// 量一段文字在胶囊字号下的宽——只用于折行估算，故与渲染同字体同字号。
  double _textW(String s, {required bool bold}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: kDfChipFontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final tags = widget.tags;
    final count = widget.entries.where((e) => diaryHit(e, _cur)).length;

    return Container(
      key: const ValueKey('df-sheet'),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text('筛选',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                GestureDetector(
                  key: const ValueKey('df-close'),
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close,
                      size: 18, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _groupTitle('标记', scheme),
                    Wrap(
                      spacing: kDfChipGap,
                      runSpacing: kDfChipGap,
                      children: [
                        for (final k in kDfMarkKeys)
                          _chip(
                            key: 'df-mark-$k',
                            label: dfMarkLabel(k),
                            icon: _markIcon(k),
                            on: _cur == k,
                            onTap: () => _pick(k),
                          ),
                      ],
                    ),
                    _groupTitle('标签', scheme),
                    if (tags.isEmpty)
                      Text(
                        '还没有标签 · 正文里写 #标签，保存时会自动归入筛选',
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: scheme.onSurfaceVariant),
                      )
                    else
                      _tagSection(tags, scheme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: scheme.onSurfaceVariant.withValues(alpha: .12)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '筛出 $count 篇',
                    key: const ValueKey('df-count'),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
                _resetBtn(scheme),
                const SizedBox(width: 8),
                _doneBtn(tokens, scheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTitle(String text, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1,
            color: scheme.onSurfaceVariant.withValues(alpha: .85),
          ),
        ),
      );

  IconData _markIcon(String k) => switch (k) {
        'starred' => Icons.favorite_border,
        'liked' => Icons.star_border,
        'todo' => Icons.check_box_outlined,
        _ => Icons.circle_outlined,
      };

  /// 标签段：一行以内直接铺开；超一行折叠成一行 + 末尾「展开全部 (N)」。
  ///
  /// 折叠**不靠「先裁再量」**（原型三次实错的坑，见 `diary_filter_kit` 文件头）：
  /// 先按容器宽度算行数，再决定挂不挂裁剪与按钮。
  Widget _tagSection(List<String> tags, ColorScheme scheme) {
    return LayoutBuilder(
      builder: (c, cons) {
        final widths = [
          for (final t in tags)
            dfChipWidth(_textW(t, bold: _cur == t)),
        ];
        final over = dfTagsOverflow(widths, cons.maxWidth);
        final chips = [
          for (final t in tags)
            _chip(
              key: 'df-tag-$t',
              label: t,
              icon: Icons.sell_outlined,
              on: _cur == t,
              onTap: () => _pick(_cur == t ? 'all' : t),
            ),
        ];
        // 口径①：一行以内——原样铺开，按钮不出现（也就不会多占一行）。
        if (!over) {
          return Wrap(spacing: kDfChipGap, runSpacing: kDfChipGap, children: chips);
        }
        // 展开态：全量折行铺开，按钮跟在末尾（随流换行，不另起一行）。
        if (_tagOpen) {
          return Wrap(
            spacing: kDfChipGap,
            runSpacing: kDfChipGap,
            children: [...chips, _moreBtn(tags.length, scheme)],
          );
        }
        // 折叠态：只露一整行（定高 32 + 裁掉溢出），按钮固定在行尾。
        return Row(
          children: [
            Expanded(
              child: ClipRect(
                // 常驻键：断言「折叠态只剩一行」靠它量高度（32），
                // 展开/不超一行时它整棵都不在树里——「不裁剪」也就有了可测判据。
                key: const ValueKey('df-tag-clip'),
                child: SizedBox(
                  height: kDfChipH,
                  child: Wrap(
                    spacing: kDfChipGap,
                    runSpacing: kDfChipGap,
                    children: chips,
                  ),
                ),
              ),
            ),
            const SizedBox(width: kDfChipGap),
            _moreBtn(tags.length, scheme),
          ],
        );
      },
    );
  }

  /// 一枚胶囊：高 32 / 圆角 16 / 14px 线性图标 + 文字；选中＝主色描边 + 6% 淡底 + 加粗。
  ///
  /// 底色走 `--accent` 派生淡档（`tokens.accent` 按 alpha 叠），**不写死色值**——
  /// 四主题 × 明暗共 8 组合下都得跟主题走（色值棘轮也吃这一条）。
  Widget _chip({
    required String key,
    required String label,
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final fg = on ? tokens.accent : scheme.onSurfaceVariant;
    return GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        height: kDfChipH,
        padding: const EdgeInsets.symmetric(horizontal: kDfChipPadX),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kDfChipH / 2),
          color: on ? tokens.accent.withValues(alpha: .06) : Colors.transparent,
          border: Border.all(
            color: on
                ? tokens.accent
                : scheme.onSurfaceVariant.withValues(alpha: .35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: kDfChipIcon, color: fg.withValues(alpha: on ? 1 : .7)),
            const SizedBox(width: kDfChipIconGap),
            Text(
              label,
              style: TextStyle(
                fontSize: kDfChipFontSize,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「展开全部 (N)」／「收起」：虚线描边在原型的表达是「非实心按钮」，
  /// Flutter 没有现成的 dashed border，改用低透明实线 + 更小字号，观感同档。
  Widget _moreBtn(int total, ColorScheme scheme) => GestureDetector(
        key: const ValueKey('df-more'),
        onTap: () => setState(() => _tagOpen = !_tagOpen),
        child: Container(
          height: kDfChipH,
          padding: const EdgeInsets.symmetric(horizontal: kDfChipPadX),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kDfChipH / 2),
            border: Border.all(
                color: scheme.onSurfaceVariant.withValues(alpha: .45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dfMoreLabel(open: _tagOpen, total: total),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 5),
              Icon(_tagOpen ? Icons.expand_less : Icons.expand_more,
                  size: 12, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      );

  Widget _resetBtn(ColorScheme scheme) => GestureDetector(
        key: const ValueKey('df-reset'),
        onTap: () => _pick('all'),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: scheme.onSurfaceVariant.withValues(alpha: .3)),
          ),
          child: Text('重置',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
        ),
      );

  Widget _doneBtn(ThemeTokens tokens, ColorScheme scheme) => GestureDetector(
        key: const ValueKey('df-done'),
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: tokens.accent,
          ),
          // 文字取 `onPrimary`（主色之上的前景），不写死白色——
          // 写死不跟主题与深浅走，且会撞深色观感棘轮闸。
          child: Text('完成',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary)),
        ),
      );
}
