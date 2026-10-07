import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../domain/media_item.dart';
import 'media_providers.dart';

/// 条目速览半屏（影音架点卡落的临时落面：详情屏 `m-detail` 属下一批，
/// 这里只给真实读数＋改分区入口，不放演示性动作）。
Future<void> showMediaPeekSheet(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _PeekSheet(ref: ref, item: item),
  );
}

class _PeekSheet extends ConsumerStatefulWidget {
  const _PeekSheet({required this.ref, required this.item});

  final WidgetRef ref;
  final MediaItem item;

  @override
  ConsumerState<_PeekSheet> createState() => _PeekSheetState();
}

class _PeekSheetState extends ConsumerState<_PeekSheet> {
  Future<void> _bumpTick() async {
    final n = ref.read(mediaTickProvider.notifier).state + 1;
    ref.read(mediaTickProvider.notifier).state = n;
  }

  Future<void> _setState(String s) async {
    await ref
        .read(mediaRepositoryProvider)
        .moveState(widget.item.id, widget.item.kind, s);
    await _bumpTick();
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, '已移到「$s」');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = widget.item.progressPercent;
    final rows = <(String, String)>[
      ('类型', MediaItem.labelOf(widget.item.kind)),
      ('主创', widget.item.creator),
      if ((widget.item.publisher ?? '').isNotEmpty)
        ('发行', widget.item.publisher!),
      if (widget.item.releaseYear != null && widget.item.releaseYear! > 0)
        ('年份', '${widget.item.releaseYear}'),
      if (widget.item.durationMin > 0) ('时长', '${widget.item.durationMin}min'),
      if (widget.item.kind == MediaItem.kSeries)
        ('季/集', '${widget.item.seasonsCount} 季 · 共 ${widget.item.episodesTotal} 集'),
      if (widget.item.kind == MediaItem.kMusic)
        ('曲目', '${widget.item.tracksCount} 曲 · 循环 ${widget.item.listenLoops ?? 0} 次'),
      if (widget.item.kind == MediaItem.kGame)
        ('周目', '${widget.item.playthroughs} 周目'),
      if (pct != null) ('进度', '$pct%'),
      if (widget.item.tags.isNotEmpty) ('标签', widget.item.tags.join(' · ')),
      if ((widget.item.source ?? '').isNotEmpty) ('来源', widget.item.source!),
    ];
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        k,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        v,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: kMediaTabularRead,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              '分区',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in MediaItem.states[widget.item.kind] ?? const [])
                  PillChip(
                    key: ValueKey('mds-peek-state-$s'),
                    label: s,
                    selected: widget.item.state == s,
                    onTap: widget.item.state == s ? null : () => _setState(s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 批量改分区（长按管理条动作①）：架面按单一类型筛时给该类分区；
/// 「全部」视图下给四档语义归并，落到每类各自的分区值（不循环切＝LH 口径）。
Future<void> showMediaBulkStateSheet(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
  String kindFilter,
) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _BulkStateSheet(kindFilter: kindFilter),
  );
  if (picked == null || !context.mounted) return;
  final n = await ref
      .read(mediaRepositoryProvider)
      .bulkMove(ids, picked, kindFilter);
  if (!context.mounted) return;
  final tick = ref.read(mediaTickProvider.notifier);
  tick.state = tick.state + 1;
  AppToast.show(context, n == 0 ? '目标分区不适用于所选条目' : '已移动 $n 条');
}

class _BulkStateSheet extends StatelessWidget {
  const _BulkStateSheet({required this.kindFilter});

  final String kindFilter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 单一类型＝该类真实分区；全部＝语义档（仓储侧再按各 kind 展开成具体值）。
    final options = kindFilter == 'all' || kindFilter.isEmpty
        ? [for (final (label, _) in MediaItem.stateGroups) label]
        : MediaItem.states[kindFilter] ?? const [];
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '改分区',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                PillChip(
                  key: ValueKey('mds-bulk-state-$o'),
                  label: o,
                  onTap: () => Navigator.of(context).pop(o),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 批量加标签（长按管理条动作②）。
Future<void> showMediaBulkTagSheet(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  final tag = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BulkTagSheet(),
  );
  if (tag == null || tag.trim().isEmpty || !context.mounted) return;
  final n = await ref.read(mediaRepositoryProvider).bulkAddTags(ids, tag);
  if (!context.mounted) return;
  final tick = ref.read(mediaTickProvider.notifier);
  tick.state = tick.state + 1;
  AppToast.show(context, n == 0 ? '这些条目已有该标签' : '已加标签 $n 条');
}

class _BulkTagSheet extends StatefulWidget {
  const _BulkTagSheet();

  @override
  State<_BulkTagSheet> createState() => _BulkTagSheetState();
}

class _BulkTagSheetState extends State<_BulkTagSheet> {
  final _c = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '加标签',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('mds-bulk-tag-input'),
              controller: _c,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '标签名',
                errorText: _err,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('mds-bulk-tag-save'),
                    onPressed: () {
                      final t = _c.text.trim();
                      if (t.isEmpty) {
                        // 就地校验（LH-K32），不借道提示条。
                        setState(() => _err = '请写标签名');
                        return;
                      }
                      Navigator.of(context).pop(t);
                    },
                    child: const Text('添加'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 读数行等宽字形（与 LH-K33 同档；本模块独立常量避免跨 feature import）。
const List<FontFeature> kMediaTabularRead = [FontFeature.tabularFigures()];
