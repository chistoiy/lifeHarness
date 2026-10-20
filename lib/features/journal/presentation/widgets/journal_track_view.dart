import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';
import 'journal_layout_kit.dart';

/// 日记改版批1b · 日期轨道档的**单日块**（左栏日期块四档分层 + 右栏正文/图/互动 + 日期块吸顶）。
///
/// 1a 是 `ListView.builder` 一天一项、不吸顶；1b 把外层换 `CustomScrollView`（见
/// `journal_page_track.dart`），本文件负责「一块长什么样」，吸顶由块首那枚
/// `SliverPersistentHeader` 承担。
///
/// 为什么单日块要产出 **两条 sliver** 而不是一个 widget：`SliverPersistentHeader`
/// 必须是 sliver，而条目区是 box，两者没法塞进同一个 widget —— 只能由外层
/// `CustomScrollView` 平铺。所以导出的是 [trackBlockSlivers] 函数而非 widget 类。
///
/// 硬口径（工单 §6 第 2 条 + 原型 §2）：
/// - 左栏四档分层＝日号 22px ＞ 月份 10px ＞ 星期 10px ＞ 时刻 10px，视觉主角是日号；
/// - 同日多篇：日期块**只渲一次**（首篇处），后续条目左栏留空轨 + 细竖线；
/// - 吸顶块必须自绘底色，且**只铺左栏那一条**——铺满整行会把右栏正文盖成实色。
const double kTrackGutterW = 64; // 原型 w-16
const double kTrackLineLeft = 26; // 原型 left:26px
const double kTrackGap = 8;

/// 日期块高度：四档分行的实测总高。
///
/// 为什么需要预知：`SliverPersistentHeader` 的 min/maxExtent 必须在 build 之前给出，
/// 不能靠 child 自己量。按「22 日号 / 12 月·周 / 12 时刻」三行＋行间距算，
/// 末行（时刻）只有在有篇时才占位。
double trackDateBlockHeight(TrackDayBlock block, {double textScale = 1}) {
  const metaLine = 12.0; // kTrackMetaSize(10) × 1.2 行高
  final lines = block.entries.isEmpty ? 2 : 3;
  final h = kTrackDayNoSize + 2 + metaLine * lines + 2 * (lines - 1);
  return h * textScale.clamp(1.0, 1.6);
}

/// 该块的两条 sliver：① 吸顶的日期头；② 该天全部条目。
List<Widget> trackBlockSlivers({
  required TrackDayBlock block,
  required void Function(JournalEntry e) onOpenEntry,
  Set<int> selected = const <int>{},
  bool selectorMode = false,
  void Function(JournalEntry e)? onToggleSelect,
}) {
  return [
    SliverPersistentHeader(
      pinned: true,
      delegate: TrackDateHeader(block: block),
    ),
    SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var j = 0; j < block.entries.length; j++)
            TrackRow(
              block: block,
              entry: block.entries[j],
              first: j == 0,
              bottomGap: j == block.entries.length - 1 ? 16 : 10,
              onTap: () => selectorMode
                  ? onToggleSelect?.call(block.entries[j])
                  : onOpenEntry(block.entries[j]),
              isSelected: block.entries[j].id != null &&
                  selected.contains(block.entries[j].id),
            ),
        ],
      ),
    ),
  ];
}

/// 吸顶的日期头：**只铺左栏那一条底色**，右栏透明让正文从旁边滚过去。
///
/// 若铺满整行，正文会被一块不透明色带拦腰截断；只铺 64+8 宽就与原型
/// （`.dw-date{background:var(--page)}` 只裹住左栏那块）一致。
class TrackDateHeader extends SliverPersistentHeaderDelegate {
  TrackDateHeader({required this.block});

  final TrackDayBlock block;

  @override
  double get minExtent => trackDateBlockHeight(block);

  @override
  double get maxExtent => trackDateBlockHeight(block);

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final tokens = context.tokens;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        key: ValueKey('track-head-${block.day.month}-${block.day.day}'),
        width: kTrackGutterW + kTrackGap,
        height: trackDateBlockHeight(block, textScale: scale),
        color: tokens.page,
        child: SizedBox(width: kTrackGutterW, child: DateBlock(block: block)),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant TrackDateHeader old) =>
      old.block.dayNo != block.dayNo ||
      old.block.monthLabel != block.monthLabel ||
      old.block.weekLabel != block.weekLabel ||
      old.block.entries.length != block.entries.length;
}

/// 左栏四档分层：日号 22px ＞ 月 10px ＞ 星期 10px ＞ 时刻 10px。
class DateBlock extends StatelessWidget {
  const DateBlock({super.key, required this.block});

  final TrackDayBlock block;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final meta = TextStyle(
      fontSize: kTrackMetaSize,
      height: 1.2,
      color: scheme.onSurfaceVariant,
    );
    final firstTime =
        block.entries.isEmpty ? '' : block.timeOf(block.entries.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 日号 + 月份同基线（原型 flex items-baseline gap-1）。
        // 月份直接用 `monthLabel`（已带「月」字），别再拼一次，否则成「10月月」。
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              block.dayNo,
              style: TextStyle(
                fontSize: kTrackDayNoSize,
                fontWeight: FontWeight.w800,
                height: 1.0,
                letterSpacing: -0.3,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 3),
            Flexible(child: Text(block.monthLabel, style: meta)),
          ],
        ),
        const SizedBox(height: 2),
        Text(block.weekLabel, style: meta),
        if (firstTime.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            firstTime,
            style: meta.copyWith(
              color: tokens.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// 一行条目：左栏 64px（首篇留空——日号在吸顶头里；后续篇画细竖线 + 时刻），右栏正文。
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.block,
    required this.entry,
    required this.first,
    required this.bottomGap,
    required this.onTap,
    required this.isSelected,
  });

  final TrackDayBlock block;
  final JournalEntry entry;
  final bool first;
  final double bottomGap;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- 左栏：首篇空（日号在吸顶头里）；后续篇只画竖线 + 时刻 ----
            SizedBox(
              width: kTrackGutterW,
              child: Stack(
                children: [
                  Positioned(
                    left: kTrackLineLeft,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 1, color: tokens.cardBorder),
                  ),
                  if (!first)
                    Positioned(
                      left: 0,
                      top: 2,
                      child: Text(
                        block.timeOf(entry),
                        style: TextStyle(
                          fontSize: kTrackMetaSize,
                          height: 1.2,
                          color: tokens.accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: kTrackGap),
            Expanded(
              child: TrackEntry(
                entry: entry,
                onTap: onTap,
                isSelected: isSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrackEntry extends StatelessWidget {
  const TrackEntry({
    super.key,
    required this.entry,
    required this.onTap,
    required this.isSelected,
  });

  final JournalEntry entry;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final body = entry.content.isEmpty ? '（只打了心情卡）' : entry.previewText;
    return InkWell(
      key: ValueKey('track-entry-${entry.id}'),
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        decoration: isSelected
            ? BoxDecoration(
                color: tokens.accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    body,
                    maxLines: kTrackBodyMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (entry.imagePaths.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _TrackThumbs(entry: entry),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 互动两键（点亮＝心、收藏＝星）：与 INS 卡同语义，只读回显。
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.liked)
                  const Icon(Icons.favorite, size: 13, color: kJournalLiked),
                if (entry.starred)
                  const Icon(Icons.star, size: 13, color: kJournalStarred),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 轨道档缩略图：最多 3 枚 34×34 小方图（轨道是「扫一眼」档，不做大图）。
class _TrackThumbs extends StatelessWidget {
  const _TrackThumbs({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final paths = entry.imagePaths.take(3).toList();
    return Row(
      children: [
        for (final p in paths)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(p.replaceFirst('file://', '')),
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _thumbFallback(context),
              ),
            ),
          ),
      ],
    );
  }

  Widget _thumbFallback(BuildContext context) => Container(
        width: 34,
        height: 34,
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withValues(alpha: .10),
      );
}
