import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/book.dart';
import '../epub_state_ui.dart' show BrCoverStateOverlay;

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

/// 本地导入书角标（原型 .br-local：右下角黑半透胶囊 + 下载线性图标 + 「本地」）。
class BrLocalBadge extends StatelessWidget {
  const BrLocalBadge({super.key, this.fontSize = 8});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('br-local-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_outlined,
            size: fontSize - 1,
            color: Colors.white,
            semanticLabel: null,
          ),
          const SizedBox(width: 2),
          Text(
            '本地',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表行标题后的「本地」小胶囊（原型 brRowBadge：8px 黑底白字圆药丸）。
class BrLocalInlineBadge extends StatelessWidget {
  const BrLocalInlineBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('br-local-inline'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '本地',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 列表行标题后的三态小胶囊（批3.5：预载中/已清缓存 · 琥珀底白字）。
class BrStateInlineBadge extends StatelessWidget {
  const BrStateInlineBadge({super.key, required this.st});

  /// 'pre' | 'cl'（就绪不渲染由调用方判断）。
  final String st;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('br-state-inline'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFD97706),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        st == 'pre' ? '预载中' : '已清缓存',
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

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
    this.showLocalBadge = true,
    this.showStateOverlay = false,
    this.onBadgeTap,
    this.onTap,
  });

  final Book book;
  final double width, height, radius, badgeSize;
  final bool showAuthor;
  final bool showBadge;

  /// 本地 EPUB 书右下角「本地」角标（墙/轨道/详情封面共用；V1.50）。
  final bool showLocalBadge;

  /// 批3.5 三态覆盖层（预载进度/已清缓存）；大封面处开启。
  final bool showStateOverlay;

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
                if (showLocalBadge && book.local)
                  Positioned(right: 3, bottom: 3, child: const BrLocalBadge()),
                if (showStateOverlay && book.local)
                  Positioned.fill(child: BrCoverStateOverlay(book: book)),
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
