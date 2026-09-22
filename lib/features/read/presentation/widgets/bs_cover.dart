import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// 书脊色板（原型 BS_COV 8 组：渐变起/止 + 书脊纯色）。
const kBsCov = <(Color, Color, Color)>[
  (Color(0xFF334155), Color(0xFF0F172A), Color(0xFF1F2937)), // slate
  (Color(0xFF14B8A6), Color(0xFF047857), Color(0xFF0D9488)), // teal
  (Color(0xFFF59E0B), Color(0xFFC2410C), Color(0xFFD97706)), // amber
  (Color(0xFF818CF8), Color(0xFF7C3AED), Color(0xFF6D28D9)), // indigo
  (Color(0xFFFB7185), Color(0xFFDB2777), Color(0xFFDB2777)), // rose
  (Color(0xFF0EA5E9), Color(0xFF1D4ED8), Color(0xFF0284C7)), // sky
  (Color(0xFF65A30D), Color(0xFF166534), Color(0xFF4D7C0F)), // lime
  (Color(0xFF78716C), Color(0xFF262626), Color(0xFF57534E)), // stone
];

/// 分区徽标底色（原型 bsProgressBadge：已读 emerald/想读 amber/弃读 slate/在读 indigo%）。
Color bsStateColor(String state) => switch (state) {
  '已读' => const Color(0xFF10B981),
  '想读' => const Color(0xFFF59E0B),
  '弃读' => const Color(0xFF64748B),
  _ => const Color(0xFF6366F1),
};

/// 分区徽标文案：在读显百分比，其余显分区名。
String bsBadgeLabel(Book b) =>
    b.state == Book.kStateReading ? '${b.percent}%' : b.state;

/// 色板封面卡（LH-C06）：渐变底 + 右上分区徽标 + 作者行；有封面图则铺图。
class BsCover extends StatelessWidget {
  const BsCover({
    super.key,
    required this.book,
    this.width = 106,
    this.height = 159,
    this.radius = 10,
    this.badgeSize = 9,
    this.showAuthor = true,
    this.showBadge = true,
    this.onBadgeTap,
    this.onTap,
  });

  final Book book;
  final double width, height, radius, badgeSize;
  final bool showAuthor;
  final bool showBadge;

  /// 可点状态角标（LH-K17：点按循环切分区，不冒泡进详情）。
  final VoidCallback? onBadgeTap;

  /// 点封面本体（详情页：进书籍资料页 §3.3）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = kBsCov[book.paletteIdx];
    final img = book.coverPath;
    return GestureDetector(
      key: onTap == null ? null : ValueKey('cover-${book.id}'),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: img == null || !File(img).existsSync()
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [pal.$1, pal.$2],
                    )
                  : null,
              image: img != null && File(img).existsSync()
                  ? DecorationImage(
                      image: FileImage(File(img)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Stack(
              children: [
                if (showAuthor)
                  Positioned(
                    left: 7,
                    right: 7,
                    bottom: 6,
                    child: Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: .78),
                      ),
                    ),
                  ),
                if (showBadge)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: GestureDetector(
                      onTap: onBadgeTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: bsStateColor(book.state),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          bsBadgeLabel(book),
                          style: TextStyle(
                            fontSize: badgeSize,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 百分比写进进度条（LH-C06：填充≥62% 白字，否则灰字；不显页数与笔记数）。
class BkPctBar extends StatelessWidget {
  const BkPctBar({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context);
    final pct = book.percent;
    final w = switch (book.state) {
      '想读' => 0.0,
      '已读' => 1.0,
      _ => pct / 100,
    };
    final label = switch (book.state) {
      '已读' => '读完',
      '想读' => '未开始',
      _ => '$pct%',
    };
    final base = tokens.colorScheme.surfaceContainerHighest;
    return SizedBox(
      height: 14,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: base,
            ),
          ),
          FractionallySizedBox(
            widthFactor: w.clamp(0.0, 1.0),
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: book.state == '弃读'
                    ? const Color(0xFF94A3B8)
                    : tokens.colorScheme.primary,
              ),
            ),
          ),
          Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: w >= 0.62
                    ? Colors.white
                    : tokens.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 阅读模块线性图标映射（LH-K14 语义：书架=书脊架 · 设置=齿轮，禁 emoji）。
class BsIcons {
  static const shelf = Icons.menu_book_outlined;
  static const list = Icons.format_list_bulleted_rounded;
  static const quote = Icons.format_quote_outlined;
  static const chart = Icons.insights_outlined;
  static const cog = Icons.settings_outlined;
  static const timer = Icons.timer_outlined;
  static const pin = Icons.push_pin_outlined;
  static const more = Icons.more_horiz_rounded;
  static const think = Icons.psychology_outlined;
  static const book = Icons.auto_stories_outlined;
  static const time = Icons.schedule_outlined;
  static const toc = Icons.list_alt_rounded;
  static const rel = Icons.account_tree_outlined;
  static const search = Icons.search_rounded;
  static const swap = Icons.swap_vert_rounded;
  static const view = Icons.grid_view_rounded;
  static const manage = Icons.done_all_rounded;
  static const pen = Icons.edit_outlined;
  static const trash = Icons.delete_outline_rounded;
  static const check = Icons.check_rounded;
  static const close = Icons.close_rounded;
  static const add = Icons.add_rounded;
}
