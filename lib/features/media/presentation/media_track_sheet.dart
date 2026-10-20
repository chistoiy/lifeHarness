import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import '../domain/media_stats.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 单条目轨迹（原型 `m-sheet-track` · 词典 LH-S37 · 批7）。
///
/// **只读**动作面（与阅读侧 `sheetTrack` 同形）：逐次柱状＋时段分布＋里程碑＋跳明细入口。
/// 三条钉死的口径：
/// - 改与删一律在计时明细整屏（批4 拍板①），本弹层不铺编辑态；
/// - 柱高恒按**真实耗时**，倍速 >1 才在柱顶出角标（1x 不重复报同一个数）；
/// - 里程碑四类各一套，**算不出的整行不出现**——不铺「未达成」占位，也不编日期。
Future<void> showMediaTrackSheet(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TrackSheet(item: item),
  );
}

class _TrackSheet extends ConsumerWidget {
  const _TrackSheet({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final rows = (ref.watch(mediaTrackSessionsProvider(item.id)).valueOrNull ??
            const <MediaSession>[])
        .where((s) => s.endedAt != null)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final total = rows.fold<int>(0, (t, s) => t + s.minutes);
    final last = rows.length > kMdsTrackCols ? rows.sublist(rows.length - kMdsTrackCols) : rows;
    var max = 0;
    for (final s in last) {
      if (s.minutes > max) max = s.minutes;
    }
    final hours = mdsTrackHours(rows);
    var hmax = 0.0;
    for (final h in hours) {
      if (h.value > hmax) hmax = h.value;
    }
    final miles = mdsMilestonesOf(item, rows);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Text('条目轨迹',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  ),
                  Text(
                    rows.isEmpty ? '' : '${rows.length} 次 · 真实 ${mdsHm(total)}',
                    key: const ValueKey('mds-track-sub'),
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Text(item.title,
                    key: const ValueKey('mds-track-title'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis),
              ),
              if (rows.isEmpty)
                EmptyDashRow(text: '还没有计时记录')
              else ...[
                const _Head('逐次'),
                SizedBox(
                  key: const ValueKey('mds-track-bars'),
                  height: 86,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < last.length; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: i == last.length - 1 ? 0 : 1.5),
                            child: Column(
                              key: ValueKey('mds-track-col-${last[i].id}'),
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  (last[i].speed ?? 1) > 1 ? _spdLabel(last[i].speed!) : '',
                                  key: ValueKey('mds-track-spd-${last[i].id}'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 7.5, color: scheme.onSurfaceVariant),
                                ),
                                Container(
                                  height: (6 + 44 * (last[i].minutes / (max == 0 ? 1 : max)))
                                      .clamp(6.0, 50.0)
                                      .toDouble(),
                                  decoration: BoxDecoration(
                                    color: mdsKindColor(item.kind),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                  ),
                                ),
                                Text(_mdOf(last[i].startedAt),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(fontSize: 7, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const _Head('时段分布'),
                for (final h in hours)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      key: ValueKey('mds-track-hour-${h.key}'),
                      children: [
                        SizedBox(width: 34, child: Text(h.label, style: const TextStyle(fontSize: 11))),
                        Expanded(
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: scheme.onSurface.withValues(alpha: .07),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: hmax == 0 ? 0 : (h.value / hmax).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: mdsKindColor(item.kind),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: Text(h.value > 0 ? mdsHm(h.value.round()) : '—',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                _Head('里程碑', key: const ValueKey('mds-track-mile-head')),
                if (miles.isEmpty)
                  EmptyDashRow(text: '还没有达成的里程碑')
                else
                  for (final m in miles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        key: ValueKey('mds-track-mile-${m.label}'),
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(m.label, style: const TextStyle(fontSize: 11.5))),
                          Text(_ymd(m.date),
                              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                const SizedBox(height: 6),
                // 改与删一律在明细整屏（批4 拍板①）——这里只给一条去路。
                InkWell(
                  key: const ValueKey('mds-track-sesslog'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/media/item/${item.id}/sessions');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                            child: Text('计时明细',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                        Text('${rows.length} 条 · 真实 ${mdsHm(total)}',
                            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                        Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
      );
}

/// 倍速标签（整数不带小数点，Dart double 会印成 1.0x——明细屏同一条口径）。
String _spdLabel(double v) => v == v.truncateToDouble() ? '${v.round()}x' : '${v}x';

String _mdOf(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
