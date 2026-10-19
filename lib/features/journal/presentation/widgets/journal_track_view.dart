import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';
import 'journal_layout_kit.dart';

/// 日记改版批1a · 日期轨道档（左栏日期块四档分层 + 右栏正文/图/互动）。
///
/// 本批只做**静态排版 + 滚动**，不做吸顶：`SliverPersistentHeader(pinned)` 属 1b，
/// 它要和滚动位置、日期块高度、多篇同日合并三件事一起调，放进 1b 单独验手感。
/// 现在用 `ListView.builder` 一天一项——性能上比全量 Column 好，且与列表档同构，
/// 换成 `CustomScrollView` 时只改外层，条目 widget 原样复用。
class JournalTrackView extends StatelessWidget {
  const JournalTrackView({
    super.key,
    required this.blocks,
    required this.onOpenEntry,
    this.selected = const <int>{},
    this.selectorMode = false,
    this.onToggleSelect,
  });

  final List<TrackDayBlock> blocks;
  final void Function(JournalEntry e) onOpenEntry;
  final Set<int> selected;
  final bool selectorMode;
  final void Function(JournalEntry e)? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // 轨道档条目少（一屏 3~4 个日期块），加 padding 与列表档对齐，切换档不跳动。
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: blocks.length,
      itemBuilder: (context, i) => _TrackDayTile(
        block: blocks[i],
        onOpenEntry: onOpenEntry,
        selected: selected,
        selectorMode: selectorMode,
        onToggleSelect: onToggleSelect,
      ),
    );
  }
}

class _TrackDayTile extends StatelessWidget {
  const _TrackDayTile({
    required this.block,
    required this.onOpenEntry,
    required this.selected,
    required this.selectorMode,
    this.onToggleSelect,
  });

  final TrackDayBlock block;
  final void Function(JournalEntry e) onOpenEntry;
  final Set<int> selected;
  final bool selectorMode;
  final void Function(JournalEntry e)? onToggleSelect;

  static const double _gutterW = 64; // 原型 w-16
  static const double _lineLeft = 26; // 原型 left:26px

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- 左栏：日号 22px extrabold ＞ 月份/星期 10px ----
            SizedBox(
              width: _gutterW,
              child: Stack(
                children: [
                  // 细竖线：整块通高（同日多篇时串起来，视觉上「同属一天」）
                  Positioned(
                    left: _lineLeft,
                    top: 26,
                    bottom: 0,
                    child: Container(width: 1, color: tokens.cardBorder),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        block.dayNo,
                        style: const TextStyle(
                          fontSize: kTrackDayNoSize,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${block.monthLabel} · ${block.weekLabel}',
                        style: TextStyle(
                          fontSize: kTrackMetaSize,
                          height: 1.2,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ---- 右栏：同日多篇依次排（首篇带摘要，后续篇补时刻）----
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < block.entries.length; j++)
                    Padding(
                      padding: EdgeInsets.only(bottom: j == block.entries.length - 1 ? 0 : 10),
                      child: _TrackEntry(
                        entry: block.entries[j],
                        timeLabel: block.timeOf(block.entries[j]),
                        first: j == 0,
                        onTap: () => selectorMode
                            ? (onToggleSelect?.call(block.entries[j]))
                            : onOpenEntry(block.entries[j]),
                        isSelected: block.entries[j].id != null &&
                            selected.contains(block.entries[j].id),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackEntry extends StatelessWidget {
  const _TrackEntry({
    required this.entry,
    required this.timeLabel,
    required this.first,
    required this.onTap,
    required this.isSelected,
  });

  final JournalEntry entry;
  final String timeLabel;
  final bool first;
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
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
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
                  // 首篇不重复时刻（日期块已给出日/月/周），后续篇用时刻行区分。
                  if (!first)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: kTrackMetaSize,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Text(
                    body,
                    maxLines: kTrackBodyMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.55),
                  ),
                  if (entry.imagePaths.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _TrackThumbs(entry: entry),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 互动三键（收藏＝心、点亮＝星）：与 INS 卡同语义，只读回显。
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.liked)
                  const Icon(Icons.favorite, size: 13, color: Color(0xFFE11D48)),
                if (entry.starred)
                  const Icon(Icons.star, size: 13, color: Color(0xFFF59E0B)),
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
    final tokens = context.tokens;
    final paths = entry.imagePaths.take(3).toList();
    return Row(
      children: [
        for (final p in paths)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(p),
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 34,
                  height: 34,
                  color: tokens.cardBorder,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined, size: 14),
                ),
              ),
            ),
          ),
        if (entry.imagePaths.length > 3)
          Text('+${entry.imagePaths.length - 3}',
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
