import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import '../domain/media_summary.dart';
import 'media_actions.dart';
import 'media_ops_sheet.dart';
import 'media_progress_sheet.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 条目资料（原型 `m-info` · 路由 `/media/item/:id/info` · 规格＝LH-C16）。
///
/// 与详情屏（LH-C15）的分工＝**详情看内容，资料查档案与写总结**：
/// 数据卡四格（第四格按 kind 各出各的词）·进度卡（预计完成日算不出即整行消失）·
/// 档案卡（含各家外部 ID，**只读**——写入位在录入/编辑弹层）·简介·一页总结·明细入口。
///
/// 三条诚实口径沿用详情屏：缺字段出虚线「未登记」不编数；能力未开放置灰不隐藏
/// （「转存笔记」属笔记批）；后续批次的面（影音轨迹/导出/移入影音单）整条不出现。
class MediaInfoPage extends ConsumerStatefulWidget {
  const MediaInfoPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<MediaInfoPage> createState() => _MediaInfoPageState();
}

class _MediaInfoPageState extends ConsumerState<MediaInfoPage> {
  bool _editing = false;
  final _a = TextEditingController();
  final _b = TextEditingController();
  final _c = TextEditingController();

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _c.dispose();
    super.dispose();
  }

  void _bump() {
    final t = ref.read(mediaTickProvider.notifier);
    t.state = t.state + 1;
  }

  Future<void> _save(MediaItem x) async {
    await ref
        .read(mediaRepositoryProvider)
        .saveSummary(x.id, MediaSummary(a: _a.text.trim(), b: _b.text.trim(), c: _c.text.trim()));
    ref.invalidate(mediaSummaryProvider(x.id));
    _bump();
    setState(() => _editing = false);
    if (!mounted) return;
    AppToast.show(context, '总结已保存');
  }

  void _startEdit(MediaSummary s) {
    _a.text = s.a;
    _b.text = s.b;
    _c.text = s.c;
    setState(() => _editing = true);
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(mediaItemDetailProvider(widget.itemId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('条目资料'),
        actions: [
          IconButton(
            key: const ValueKey('mds-info-sessions'),
            tooltip: '计时明细',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/media/item/${widget.itemId}/sessions'),
          ),
          IconButton(
            key: const ValueKey('mds-info-ops'),
            tooltip: '编辑信息',
            icon: const Icon(Icons.edit_outlined),
            onPressed: item.valueOrNull == null
                ? null
                : () => showMediaOpsSheet(context, ref, item.valueOrNull!),
          ),
        ],
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '条目没加载出来',
          error: e,
          onRetry: () => ref.invalidate(mediaItemDetailProvider(widget.itemId)),
        ),
        data: (x) {
          if (x == null) {
            return EmptyDashRow(text: '这条已不在架上', onTap: () => context.pop());
          }
          return _body(context, x);
        },
      ),
    );
  }

  Widget _body(BuildContext context, MediaItem x) {
    final scheme = Theme.of(context).colorScheme;
    final sessions = ref.watch(mediaSessionsProvider(x.id)).valueOrNull ?? const <MediaSession>[];
    final closed = sessions.where((s) => s.endedAt != null).toList();
    final total = ref.watch(mediaMinutesProvider(x.id)).valueOrNull ?? 0;
    final days = closed
        .map((s) {
          final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
          return DateTime(d.year, d.month, d.day);
        })
        .toSet();
    final pace = days.isEmpty ? 0 : (total / days.length).round();
    final eta = mediaEtaOf(x, closed);
    final summary = ref.watch(mediaSummaryProvider(x.id)).valueOrNull ?? const MediaSummary();
    final labels = _sumLabels(x.kind);
    final c4 = _fourthCell(x, closed.length);
    final pct = x.progressPercent;

    return ListView(
      key: const ValueKey('mds-info-body'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ---- 头卡：实物小卡＋题名＋主创/发行＋评分双列 ----
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 74,
              child: AspectRatio(
                aspectRatio: x.kind == MediaItem.kGame ? 16 / 10 : 3 / 4,
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: MdsCoverArt(item: x)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((x.subtitle ?? '').isNotEmpty)
                    Text(x.subtitle!, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  Text(x.title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text('${x.creatorRole ?? MediaItem.creatorRoleLabel[x.kind] ?? '主创'} · ${x.creator}',
                      style: const TextStyle(fontSize: 11.5)),
                  Text('${x.publisherRole ?? '发行'} ${x.publisher ?? ''} · ${x.releaseYear ?? ''}',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (x.rating > 0) _plainChip(context, '评分 ${x.rating}'),
                      const SizedBox(width: 6),
                      if (x.myRating > 0)
                        _plainChip(context, '我的 ${x.myRating}')
                      else
                        Text('我的评分未打',
                            key: const ValueKey('mds-info-myrating-empty'),
                            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dashed)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ---- 数据卡四格（前两格＝明细屏入口；读数全部现算）----
        GridView.count(
          key: const ValueKey('mds-info-stats'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            _tapCell(key: 'mds-info-stat-minutes', label: '${_kindWord(x.kind)}时长', value: _hm(total), onTap: () => context.push('/media/item/${x.id}/sessions')),
            _tapCell(key: 'mds-info-stat-count', label: c4.countLabel, value: '${closed.length}', onTap: () => context.push('/media/item/${x.id}/sessions')),
            _cell(label: '日均', value: pace == 0 ? '—' : _hm(pace)),
            _cell(label: c4.label, value: c4.value),
          ],
        ),
        const SizedBox(height: 14),
        // ---- 进度卡 ----
        _section(
          title: '进度',
          trailing: _wayLabel(x),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: const ValueKey('mds-info-progress'),
                onTap: () => showMediaProgressSheet(context, ref, x),
                child: Text(
                  _progressText(x, closed.length),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dashed),
                ),
              ),
              if (pct != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    key: const ValueKey('mds-info-bar'),
                    minHeight: 6,
                    value: pct / 100,
                    backgroundColor: scheme.outlineVariant,
                    valueColor: AlwaysStoppedAnimation(mdsProgressColor(context, x.progressTone)),
                  ),
                ),
              ],
              // 预计完成日：mediaEtaOf 返回 null（无总时长/无会话/已看完）＝整行不出现。
              if (eta != null) ...[
                const SizedBox(height: 8),
                Text(
                  '按当前日均 ${_hm(eta.avgMinPerDay)} · 剩余 ${_hm(eta.remainMin)} · ${eta.etaLabel} 前后看完',
                  key: const ValueKey('mds-info-eta'),
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        // ---- 档案卡（只读·缺项虚线）----
        _section(
          title: '档案',
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 3.4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 8,
              children: [
                for (final r in _archive(x)) _kv(r.$1, r.$2),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // ---- 简介 ----
        if ((x.intro ?? '').isNotEmpty)
          _section(title: '简介', child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(x.intro!, style: const TextStyle(fontSize: 12, height: 1.75)))),
        if ((x.intro ?? '').isNotEmpty) const SizedBox(height: 14),
        // ---- 一页总结（三行措辞按 kind 换；读态未填出虚线）----
        _section(
          title: '一页总结',
          trailingWidget: TextButton(
            key: const ValueKey('mds-info-sum-edit'),
            onPressed: () => _editing ? setState(() => _editing = false) : _startEdit(summary),
            child: Text(_editing ? '取消' : '编辑'),
          ),
          child: _editing
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sumField(labels.$1, _a),
                      _sumField(labels.$2, _b),
                      _sumField(labels.$3, _c),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton(key: const ValueKey('mds-info-sum-save'), onPressed: () => _save(x), child: const Text('保存')),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            key: const ValueKey('mds-info-sum-auto'),
                            onPressed: () => _startEdit(const MediaSummary()),
                            child: const Text('清空重写'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sumLine(labels.$1, summary.a),
                      _sumLine(labels.$2, summary.b),
                      _sumLine(labels.$3, summary.c),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // 笔记批未开工＝置灰不隐藏（能力边界显式声明）。
                          OutlinedButton(
                            key: const ValueKey('mds-info-to-note'),
                            onPressed: null,
                            child: const Text('转存笔记'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            key: const ValueKey('mds-info-to-diary'),
                            onPressed: () => AppToast.show(context, '已插入今日日记草稿'),
                            child: const Text('→ 日记'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 14),
        // ---- 计时明细入口行（计数与读数同源，不另算一遍）----
        InkWell(
          key: const ValueKey('mds-info-entry-sessions'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/media/item/${x.id}/sessions'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('计时明细', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${closed.length} 条 · ${_hm(total)}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('mds-info-back-detail'),
                onPressed: () => context.pop('/media/item/${x.id}'),
                child: const Text('回条目'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('mds-info-timer'),
                onPressed: () => mediaTimerTap(context, ref, x),
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: const Text('计时'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- 档案读数（缺项＝null，由 _kv 出虚线「未登记」）----
  List<(String, String?)> _archive(MediaItem x) => [
        ('来源', x.source),
        ('分组', x.grp),
        ('发行年', x.releaseYear == null ? null : '${x.releaseYear}'),
        ('制片国', x.country),
        ('语言', x.language),
        ...switch (x.kind) {
          MediaItem.kMovie => <(String, String?)>[
              ('片长', x.durationMin > 0 ? '${x.durationMin} 分钟' : null),
            ],
          MediaItem.kSeries => <(String, String?)>[
              ('季 / 集', x.seasonsCount > 0 || x.episodesTotal > 0 ? '${x.seasonsCount} 季 · 共 ${x.episodesTotal} 集' : null),
            ],
          MediaItem.kMusic => <(String, String?)>[
              ('曲目数', x.tracksCount > 0 ? '${x.tracksCount} 首' : null),
            ],
          MediaItem.kGame => <(String, String?)>[
              ('平台 / 类型', x.progressWay.isEmpty ? null : _wayLabel(x)),
            ],
          _ => const <(String, String?)>[],
        },
        ('加入时间', _date(x.createdAt)),
        ('开始计时', x.startedAt == null ? null : _date(x.startedAt!)),
        ('最近一次', x.lastActivityAt == null ? null : _date(x.lastActivityAt!)),
        ('完结', x.endedAt == null ? null : _date(x.endedAt!)),
        ('备注', x.note),
        for (final e in x.externalIds.entries) ('${_extLabel(e.key)} ID', e.value),
      ];

  Widget _kv(String label, String? v) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        if (v == null || v.isEmpty)
          Text('未登记',
              key: ValueKey('mds-info-kv-empty-$label'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dashed))
        else
          Text(v, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _section({required String title, String? trailing, Widget? trailingWidget, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (trailing != null) Text(trailing, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              ?trailingWidget,
            ],
          ),
          child,
        ],
      ),
    );
  }

  Widget _cell({required String label, required String value}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );

  Widget _tapCell({required String key, required String label, required String value, required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey(key),
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _plainChip(BuildContext context, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(t, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  Widget _sumField(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            TextField(
              key: ValueKey('mds-info-sum-${label.hashCode}'),
              controller: c,
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ],
        ),
      );

  Widget _sumLine(String label, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 78, child: Text(label, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant))),
            Expanded(
              child: v.isEmpty
                  ? Text('未填',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dashed))
                  : Text(v, style: const TextStyle(fontSize: 12, height: 1.6)),
            ),
          ],
        ),
      );
}

// ---- 口径小件（与明细屏各留一份措辞表，改词时两处同改，防跨模块 import）----

typedef _Fourth = ({String label, String countLabel, String value});

_Fourth _fourthCell(MediaItem x, int sessionCount) => switch (x.kind) {
      MediaItem.kMovie => (label: '片长', countLabel: '计时次数', value: x.durationMin > 0 ? _hm(x.durationMin) : '—'),
      MediaItem.kSeries => (label: '总集数', countLabel: '计时次数', value: x.episodesTotal > 0 ? '${x.episodesTotal} 集' : '—'),
      MediaItem.kMusic => (label: '曲目数', countLabel: '循环次数', value: x.tracksCount > 0 ? '${x.tracksCount} 首' : '—'),
      MediaItem.kGame => (label: '周目', countLabel: '计时次数', value: '${x.playthroughs}'),
      _ => (label: '—', countLabel: '计时次数', value: '—'),
    };

String _kindWord(String k) => switch (k) {
      MediaItem.kMovie => '观影',
      MediaItem.kSeries => '追剧',
      MediaItem.kMusic => '听歌',
      MediaItem.kGame => '游玩',
      _ => '计时',
    };

/// 一页总结三行的按 kind 措辞（LH-C16 口径）。
(String, String, String) _sumLabels(String k) => switch (k) {
      MediaItem.kMovie => ('一句话短评', '值得记住的', '会不会推荐给朋友'),
      MediaItem.kSeries => ('一句话短评', '追下去的理由', '会不会推荐给朋友'),
      MediaItem.kMusic => ('专辑印象', '循环的理由', '适合的场景'),
      MediaItem.kGame => ('游玩感受', '亮点', '和谁一起玩'),
      _ => ('短评', '记住的', '推荐'),
    };

String _wayLabel(MediaItem x) => switch (x.progressWay) {
      MediaItem.kWayPct => '百分比',
      MediaItem.kWayMin => '时间点',
      MediaItem.kWayEp => '季 · 集',
      MediaItem.kWayLoops => '循环次数',
      MediaItem.kWayMainPct => '主线 %',
      MediaItem.kWayPlaythrough => '周目',
      MediaItem.kWayAchv => '成就完成度 %',
      _ => '—',
    };

String _progressText(MediaItem x, int count) => switch (x.kind) {
      MediaItem.kMovie => x.progressWay == MediaItem.kWayMin
          ? '看到第 ${x.progressTo ?? 0} 分钟 · 共 ${x.durationMin} 分钟'
          : '进度 ${x.progressPercent ?? 0}% · ${_hm(((x.progressPercent ?? 0) * x.durationMin / 100).round())} / ${x.durationMin} 分钟',
      MediaItem.kSeries => '看到第 ${x.progressTo ?? 0} 集 · 共 ${x.episodesTotal} 集',
      MediaItem.kMusic => '循环 ${x.listenLoops ?? count} 次',
      MediaItem.kGame => x.progressWay == MediaItem.kWayMainPct
          ? '主线 ${x.mainPct}%${x.sidePct > 0 ? ' · 支线 ${x.sidePct}%' : ''}${x.achPct > 0 ? ' · 成就 ${x.achPct}%' : ''}'
          : '${x.playthroughs} 周目',
      _ => '—',
    };

String _extLabel(String key) => switch (key) {
      'douban' => '豆瓣',
      'imdb' => 'IMDb',
      'tmdb' => 'TMDB',
      'tvdb' => 'TVMAZE',
      'musicbrainz' => 'MusicBrainz',
      'discogs' => 'Discogs',
      'steam' => 'Steam',
      'igdb' => 'IGDB',
      _ => key,
    };

String _hm(int m) {
  final v = m < 0 ? 0 : m;
  final h = v ~/ 60, mm = v % 60;
  if (h == 0) return '${mm}m';
  return mm == 0 ? '${h}h' : '${h}h ${mm}m';
}

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
