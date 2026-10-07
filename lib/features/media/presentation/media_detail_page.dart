import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import 'media_actions.dart';
import 'media_progress_sheet.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 条目详情（原型 `m-detail` · 路由 `/media/item/:id`）：
/// 沉浸头图＋信息行（创作者/发行方芯片可点反查·进度虚线词点开弹层·评分）
/// ＋按 kind 四套结构＋统计行（累计/次数/日均·预计完成日）＋底部动作条。
///
/// 三条诚实口径：
/// - 名场面时间线/曲目列表/成就墙＝**笔记批与资料面未开工**，空态虚线行，不照抄原型演示数据；
/// - 「记笔记」「识图」钮置灰不隐藏（§九.4 能力边界显式声明）；
/// - 均速/预计剩余/预计完成日只在真算得出时出现（[mediaEtaOf] 返回 null 即隐藏）。
class MediaDetailPage extends ConsumerWidget {
  const MediaDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemDetailProvider(itemId));
    return Scaffold(
      appBar: AppBar(
        title: Text(item.valueOrNull?.title ?? '条目'),
        actions: [
          IconButton(
            key: const ValueKey('mds-detail-timer'),
            tooltip: '计时',
            icon: const Icon(Icons.timer_outlined),
            onPressed: item.valueOrNull == null
                ? null
                : () => mediaTimerTap(context, ref, item.valueOrNull!),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('mds-detail-ops'),
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) async {
              if (v == 'trash' && item.valueOrNull != null && context.mounted) {
                await _trashItem(context, ref, item.valueOrNull!);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'trash', child: Text('移入回收站')),
            ],
          ),
        ],
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '条目没加载出来',
          error: e,
          onRetry: () => ref.invalidate(mediaItemDetailProvider(itemId)),
        ),
        data: (x) {
          if (x == null) {
            return EmptyDashRow(
              text: '这条已不在架上',
              onTap: () => context.pop(),
            );
          }
          return _body(context, ref, x);
        },
      ),
    );
  }

  Future<void> _trashItem(
    BuildContext context,
    WidgetRef ref,
    MediaItem x,
  ) async {
    final ok = await lhConfirm(context, '把「${x.title}」移入回收站？7 天内可找回。');
    if (!ok || !context.mounted) return;
    await ref.read(mediaRepositoryProvider).softDelete([x.id]);
    if (!context.mounted) return;
    final tick = ref.read(mediaTickProvider.notifier);
    tick.state = tick.state + 1;
    context.pop();
  }

  Widget _body(BuildContext context, WidgetRef ref, MediaItem x) {
    final scheme = Theme.of(context).colorScheme;
    final sessions = ref.watch(mediaSessionsProvider(x.id)).valueOrNull ?? const [];
    final closed = sessions.where((s) => s.endedAt != null).toList();
    final minutes = ref.watch(mediaMinutesProvider(x.id)).valueOrNull ?? 0;
    final running = ref.watch(mediaRunningSessionProvider).valueOrNull;
    final on = running != null && running.itemId == x.id;
    final eta = mediaEtaOf(x, closed);
    final pct = x.progressPercent;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ---- 沉浸头图：实物封面大图（无封面＝色板渐变＋首字，§九.3）----
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: x.kind == MediaItem.kGame ? 16 / 10 : 3 / 4,
            child: Hero(
              tag: 'mds-cover-${x.id}',
              child: MdsCoverArt(item: x),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if ((x.subtitle ?? '').isNotEmpty)
          Text(
            x.subtitle!,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        Text(
          x.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        // ---- 信息行：角色芯片（点＝跨 kind 反查同值条目）----
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _tapChip(
              context: context,
              key: ValueKey('mds-chip-creator'),
              label: '${x.creatorRole ?? MediaItem.creatorRoleLabel[x.kind] ?? '主创'} · ${x.creator}',
              onTap: () => context.push(
                Uri(path: '/media/shelf', queryParameters: {'q': x.creator}).toString(),
              ),
            ),
            if ((x.publisher ?? '').isNotEmpty)
              _tapChip(
                context: context,
                key: ValueKey('mds-chip-pub'),
                label: '${x.publisherRole ?? '发行'} · ${x.publisher}',
                onTap: () => context.push(
                  Uri(path: '/media/shelf', queryParameters: {'q': x.publisher}).toString(),
                ),
              ),
            if (x.releaseYear != null && x.releaseYear! > 0)
              _plainChip(context, '${x.releaseYear}'),
            if (x.rating > 0) _plainChip(context, '评分 ${x.rating}'),
            if (x.myRating > 0) _plainChip(context, '我的 ${x.myRating}'),
            if (on)
              _plainChip(context, mediaTimerWord(x.kind), color: mdsStateColor('i')),
          ],
        ),
        const SizedBox(height: 10),
        // ---- 进度行（虚线词＝点开四套进度弹层）----
        _progressLine(context, ref, x, pct),
        if (pct != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              key: const ValueKey('mds-detail-bar'),
              minHeight: 6,
              value: pct / 100,
              backgroundColor: scheme.outlineVariant,
              valueColor: AlwaysStoppedAnimation(
                mdsProgressColor(context, x.progressTone),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // ---- 统计行：累计 · 计时次数 · 日均/预计完成（算不出即隐藏）----
        _statsRow(context, x, minutes, closed.length, eta),
        if (x.tags.isNotEmpty || (x.grp ?? '').isNotEmpty || (x.source ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in x.tags) _plainChip(context, t),
              if ((x.grp ?? '').isNotEmpty) _plainChip(context, '分组 · ${x.grp}'),
              if ((x.source ?? '').isNotEmpty) _plainChip(context, x.source!),
            ],
          ),
        ],
        if ((x.intro ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            x.intro!,
            style: const TextStyle(fontSize: 12, height: 1.75),
          ),
        ],
        const SizedBox(height: 14),
        // ---- 按 kind 四套结构 ----
        _kindSection(context, ref, x, sessions, minutes),
        const SizedBox(height: 18),
        // ---- 底部动作条（原型 mRenderDetail 尾行四钮）----
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('mds-detail-timerbtn'),
                onPressed: () => mediaTimerTap(context, ref, x),
                icon: Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                label: Text(on ? '■ 结束' : '▶ 计时'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('mds-detail-progress'),
                onPressed: () => showMediaProgressSheet(context, ref, x),
                child: const Text('＋ 记进度'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('mds-detail-note'),
                // 笔记批未开工＝置灰不隐藏（能力边界显式声明）
                onPressed: null,
                child: const Text('＋ 记笔记'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _progressLine(
    BuildContext context,
    WidgetRef ref,
    MediaItem x,
    int? pct,
  ) {
    final word = switch (x.kind) {
      MediaItem.kMovie => x.progressWay == MediaItem.kWayMin
          ? '看到第 ${x.progressTo ?? 0} 分钟'
          : '进度 ${pct ?? 0}%',
      MediaItem.kSeries => '看到第 ${x.progressTo ?? 0} 集',
      MediaItem.kMusic => '循环 ${x.listenLoops ?? 0} 次',
      MediaItem.kGame => switch (x.progressWay) {
        MediaItem.kWayAchv => '成就 ${x.achPct}%',
        MediaItem.kWayPlaythrough => '${x.playthroughs} 周目',
        _ => '主线 ${x.mainPct}%',
      },
      _ => '',
    };
    return InkWell(
      key: const ValueKey('mds-detail-progline'),
      onTap: () => showMediaProgressSheet(context, ref, x),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '进度 '),
              TextSpan(
                text: word,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dashed,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (x.durationMin > 0 && x.kind == MediaItem.kMovie)
                TextSpan(
                  text: ' · 时长 ${x.durationMin}min',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
      ),
    );
  }

  Widget _statsRow(
    BuildContext context,
    MediaItem x,
    int minutes,
    int sessionCount,
    MediaEta? eta,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final cells = <(String, String)>[
      ('累计', x.kind == MediaItem.kGame || minutes >= 60
          ? '${(minutes / 60).toStringAsFixed(1)}h'
          : '$minutes 分钟'),
      ('计时次数', '$sessionCount'),
      if (x.kind == MediaItem.kMusic)
        ('循环', '${x.listenLoops ?? 0} 次'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final (label, v) in cells) ...[
              _statCell(scheme, label, v),
              const SizedBox(width: 8),
            ],
          ],
        ),
        // 算得出才显示；没有总时长/没有 pace 就整行消失（不编数）。
        if (eta != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${eta.label} · 预计完成 ${eta.etaLabel}',
              key: const ValueKey('mds-detail-eta'),
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _statCell(ColorScheme scheme, String label, String value) => Container(
    key: ValueKey('mds-stat-$label'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            fontFeatures: kMediaTabular,
          ),
        ),
      ],
    ),
  );

  /// 四套类型结构（原型 mRenderDetail extra 分支的 Flutter 真数据版）。
  Widget _kindSection(
    BuildContext context,
    WidgetRef ref,
    MediaItem x,
    List<MediaSession> sessions,
    int minutes,
  ) {
    final scheme = Theme.of(context).colorScheme;
    switch (x.kind) {
      case MediaItem.kSeries:
        final seen = int.tryParse(x.progressTo ?? '') ?? 0;
        final eps = x.episodesTotal.clamp(0, 60);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(scheme, '季 · 集'),
            if (x.seasonsCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 1; i <= x.seasonsCount; i++)
                      _plainChip(context, 'S$i', selected: i == 1),
                  ],
                ),
              ),
            if (eps == 0)
              const EmptyDashRow(text: '还没登记总集数 · 在录入弹层补上')
            else
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '共 $eps 集 · 已看 $seen 集',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        );
      case MediaItem.kMusic:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(scheme, '曲目'),
            if (x.tracksCount == 0)
              const EmptyDashRow(text: '还没登记曲目 · 在录入弹层补上')
            else
              Text(
                '${x.tracksCount} 曲 · 循环 ${x.listenLoops ?? 0} 次（按听歌会话自动计）',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
          ],
        );
      case MediaItem.kGame:
        final rings = <(String, int)>[
          ('主线', x.mainPct),
          if (x.sidePct > 0) ('支线', x.sidePct),
          if (x.achPct > 0) ('全成就', x.achPct),
        ];
        final logs = sessions.where((s) => s.endedAt != null).take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(scheme, '进度 · 周目'),
            Row(
              children: [
                for (final (label, v) in rings) ...[
                  _ring(context, label, v),
                  const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 8),
            _plainChip(context, '${x.playthroughs} 周目'),
            const SizedBox(height: 12),
            _sectionTitle(scheme, '游玩记录'),
            if (logs.isEmpty)
              const EmptyDashRow(text: '还没有游玩记录 · 点下方「▶ 计时」开始')
            else
              for (final s in logs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fmtDay(s.startedAt),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                      Text(
                        '${s.minutes} 分钟',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: kMediaTabular,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );
      default: // movie
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(scheme, '名场面时间线'),
            const EmptyDashRow(text: '名场面记录随影音笔记批开放 · 现在可计时与记进度'),
          ],
        );
    }
  }

  Widget _ring(BuildContext context, String label, int v) => SizedBox(
    key: ValueKey('mds-ring-$label'),
    width: 54,
    child: Column(
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: v / 100,
                strokeWidth: 4,
                backgroundColor: schemeOf(context).outlineVariant,
                valueColor: AlwaysStoppedAnimation(schemeOf(context).primary),
              ),
              Text(
                '$v',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: kMediaTabular,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 9.5)),
      ],
    ),
  );

  static ColorScheme schemeOf(BuildContext context) =>
      Theme.of(context).colorScheme;

  Widget _sectionTitle(ColorScheme scheme, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _tapChip({
    required Key key,
    required BuildContext context,
    required String label,
    required VoidCallback onTap,
  }) => InkWell(
    key: key,
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10.5)),
    ),
  );

  Widget _plainChip(
    BuildContext context,
    String label, {
    bool selected = false,
    Color? color,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: color?.withValues(alpha: .14) ??
          Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  String _fmtDay(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.month} 月 ${d.day} 日';
  }
}
