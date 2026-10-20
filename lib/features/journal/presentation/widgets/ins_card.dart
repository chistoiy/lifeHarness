import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/weather/weather.dart';
import '../../domain/journal_entry.dart';
import '../journal_providers.dart';
import 'journal_layout_kit.dart';
import '../../../../shared/widgets/image_attach.dart';
import '../../../../shared/widgets/ui_kit.dart' show AppToast;

/// INS 卡片流单卡（原型 ins-card：头像行 · 正文 · 图片 2×2 · 回望操作 · 次数与标签）。
class InsDiaryCard extends ConsumerStatefulWidget {
  const InsDiaryCard(
      {super.key,
      required this.entry,
      this.onOpen,
      this.onLongPress,
      this.selected = false});

  final JournalEntry entry;
  final VoidCallback? onOpen;

  /// 轮13：长按进入批量选中；选中态点卡=切换勾选，右上显 ✓。
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  ConsumerState<InsDiaryCard> createState() => _InsDiaryCardState();
}

class _InsDiaryCardState extends ConsumerState<InsDiaryCard> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 轮12-11：关联信息默认收起=右下角小图标（全屏钮左侧），点击展开。
  bool _refOpen = false;

  JournalEntry get entry => widget.entry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final d = entry.day;
    final wd = _weekdays[d.weekday - 1];
    final emo = moodEmoji(entry.mood);
    final imgs = entry.imagePaths;
    final todoCount = entry.todoLines().length;

    Future<void> react(bool liked, bool starred) async {
      await ref
          .read(journalRepositoryProvider)
          .setFlags(entry.id!, liked: liked, starred: starred);
      // 语义断链批 #26：点赞/星标单篇补丁（原整表 invalidate·全量重拉重组建卡片流）。
      ref
          .read(journalsProvider.notifier)
          .patch(entry.copyWith(liked: liked, starred: starred));
    }

    return GestureDetector(
      // 卡片整体=打开该篇（⛶ 钮独立走全屏浏览；多选态由 onOpen 改传切换勾选）
      onTap: widget.onOpen,
      onLongPress: widget.onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          border: Border.all(
              color: widget.selected ? tokens.accent : tokens.cardBorder,
              width: widget.selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, gradient: tokens.gradient),
                    // 演示残留批（2026-10-12）：演示名「CHIST」→ 读 R14-12 昵称
                    // helper（nickOrFallback），头像首字同源（settings_page 先例）。
                    child: Text(
                        ref
                            .watch(settingsControllerProvider)
                            .nickOrFallback
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${ref.watch(settingsControllerProvider).nickOrFallback} · ${_two(d.month)}-${_two(d.day)}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        Text(
                            '周$wd'
                            '${entry.weatherCode == null ? '' : ' · ${weatherText(entry.weatherCode!, tmax: entry.tempMax, tmin: entry.tempMin, compact: true)}'}'
                            '${emo == null ? '' : ' · 心情 $emo ${moodLabel(entry.mood) ?? ''}'}',
                            style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ],
                    ),
                  ),
                  // 轮13：多选态右上 ✓ 圆钮（替代分享钮）
                  if (widget.selected)
                    Container(
                      key: ValueKey('insel-${entry.id}'),
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: tokens.accent),
                      child: const Icon(Icons.check,
                          size: 14, color: Colors.white),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            // UI/UX批：裸 SnackBar → AppToast 统一口径。
                            onPressed: () =>
                                AppToast.show(context, '分享日记卡片 · 规划 V1.x'),
                            icon: const Icon(Icons.ios_share, size: 16)),
                        // 原型卡头右侧是**两枚**钮（⤴ 分享 / ⋯ 更多）。旧实现只有分享，
                        // 真机上右上一个孤零零的图标，与原型对不上。
                        // 文案不写「V1.x 规划」——U5 禁词闸明确不许把路线图版本号露给用户。
                        IconButton(
                            key: ValueKey('ins-more-${entry.id}'),
                            onPressed: () =>
                                AppToast.show(context, '更多操作 · 暂未开放'),
                            icon: const Icon(Icons.more_horiz, size: 18)),
                      ],
                    ),
                ],
              ),
            ),
            // 批2e 按原型 `insCardHtml` 调序：**图在文上**（原型卡头之后立刻是 `.ins-imgs`）。
            // 原实现正文在前、图在后，同一张卡在两种顺序下重心完全不同（原型是「图卡」）。
            if (imgs.isNotEmpty)
              Padding(
                // 原型 `.ins-imgs{padding:0 6px}`：图片几乎通栏，只留 6 的内缩。
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                child: _InsImageGrid(entryId: entry.id, paths: imgs),
              ),
            Padding(
              // 原型正文 `px-4 py-2`。
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Text(
                entry.content.isEmpty && imgs.isEmpty
                    ? '（今天还没写正文）'
                    : entry.previewText,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.75),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  // 轮10-6：ins 风操作行去 emoji=简约线性图标（选中填色）。
                  IconButton(
                    key: ValueKey('ins-like-${entry.id}'),
                    onPressed: () => react(!entry.liked, entry.starred),
                    icon: Icon(
                        entry.liked ? Icons.favorite : Icons.favorite_border,
                        size: 19,
                        color: entry.liked
                            ? kJournalLiked
                            : null),
                  ),
                  IconButton(
                    key: ValueKey('ins-star-${entry.id}'),
                    onPressed: () => react(entry.liked, !entry.starred),
                    icon: Icon(entry.starred ? Icons.star : Icons.star_border,
                        size: 19,
                        color: entry.starred
                            ? kJournalStarred
                            : null),
                  ),
                  IconButton(
                      // UI/UX批：裸 SnackBar → AppToast 统一口径。
                      onPressed: () =>
                          AppToast.show(context, '评论/批注 · 规划 V1.x'),
                      icon: const Icon(Icons.chat_bubble_outline, size: 19)),
                  const Spacer(),
                  // 轮12-11：关联信息收进小图标（全屏钮左侧），点击展开明细
                  if (todoCount > 0)
                    IconButton(
                      key: ValueKey('ins-ref-${entry.id}'),
                      tooltip: '本页关联',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _refOpen = !_refOpen),
                      icon: Icon(Icons.link,
                          size: 16,
                          color: _refOpen ? tokens.accent : null),
                    ),
                  TextButton(
                    key: ValueKey('ins-full-${entry.id}'),
                    onPressed: () => showDiaryFullView(context, entry),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen, size: 15),
                        SizedBox(width: 4),
                        Text('全屏',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_refOpen && todoCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                        left: BorderSide(color: tokens.accent, width: 3)),
                  ),
                  child: Text('本页关联 · ☑ $todoCount 个待办同步',
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.7,
                          color: scheme.onSurfaceVariant)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                '${entry.viewCount} 次回望'
                '${entry.tags.isEmpty ? '' : ' · ${entry.tags.map((t) => '#$t').join(' ')}'}',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// 卡内 2×2 方形网格：最多 4 格，超出末格盖 +N。
class _InsImageGrid extends StatelessWidget {
  const _InsImageGrid({required this.entryId, required this.paths});

  final int? entryId;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final shown = paths.take(4).toList();
    final rows = <Widget>[];
    for (var i = 0; i < shown.length; i += 2) {
      final pair = shown.sublist(i, (i + 2).clamp(0, shown.length));
      rows.add(Row(
        children: [
          for (var j = 0; j < pair.length; j++) ...[
            if (j > 0) const SizedBox(width: 6),
            Expanded(
              child: _cell(context, i + j, pair[j],
                  last: i + j == 3 && paths.length > 4,
                  extra: paths.length - 4),
            ),
          ],
          if (pair.length == 1) const Spacer(),
        ],
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _cell(BuildContext context, int idx, String path,
      {bool last = false, int extra = 0}) {
    return GestureDetector(
      key: ValueKey('ins-img-$entryId-$idx'),
      onTap: () => showImageLightbox(context, path),
      child: ClipRRect(
        // 原型 `.ins-img{border-radius:14px}`（旧实现 10，四角明显更方）。
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(path),
                  fit: BoxFit.cover,
                  // UI/流畅批：缩略图降采样（原整图解码；格宽约半卡宽，200 逻辑像素足够）。
                  cacheWidth:
                      (MediaQuery.devicePixelRatioOf(context) * 200).round(),
                  errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0x14000000),
                      child: Center(
                          child: Text('图片已丢失',
                              style: TextStyle(fontSize: 10))))),
              if (last)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0x73000000),
                    child: Center(
                        child: Text('+$extra',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ⛶ 全屏单帖浏览（原型 ins-full：黑底放大正文+图片纵排 · 点任意处关闭）。
void showDiaryFullView(BuildContext context, JournalEntry entry) {
  final d = entry.day;
  final body = entry.kind == 'rich'
      ? entry.plainBody
      : JournalEntry.bodyWithoutImages(entry.content);
  final imgs = entry.imagePaths;
  showDialog<void>(
    context: context,
    barrierColor: const Color(0xF2000000),
    builder: (bc) => GestureDetector(
      key: ValueKey('diary-full-${entry.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(bc).pop(),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                      '${d.year}-${_p2(d.month)}-${_p2(d.day)} · ${moodEmoji(entry.mood) ?? ''} ${moodLabel(entry.mood) ?? ''}'.trim(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const Spacer(),
                  const Icon(Icons.close, color: Colors.white54, size: 20),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                body.isEmpty ? '（今天还没写正文）' : body,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, height: 1.9),
              ),
              for (final p in imgs)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(p),
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Text('图片已丢失',
                            style: TextStyle(color: Colors.white54))),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _p2(int v) => v.toString().padLeft(2, '0');
