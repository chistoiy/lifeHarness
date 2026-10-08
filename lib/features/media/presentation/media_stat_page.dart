import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_session.dart';
import '../domain/media_item.dart';
import '../domain/media_stats.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 影音游全站统计（原型 `m-stat` · 路由 `/media/stat` · 规格＝词典 LH-C21）。
///
/// 五条铁口径（工单 §0 四项拍板＋词典铁口径）：
/// - 顶部两枚 chip＝设置项 `media.speedFold` 的**可见表达**，默认真实；切换只写 KV＋失效重取，
///   屏上八块读数全部同源重算（账本恒吃真实耗时，折算只在读侧算）；
/// - 近 30 天热力**恒 30 天窗口**，只吃口径／度量／构成，不吃年月钻取；点一格出当日读数行，再点收起；
/// - 年×月×度量×构成＝屏内四行筛选条，**不做二级屏**；右上图标＝一次回默认态；
/// - 没记录一律虚线格／「—」／整行不出现，**不拿 0 冒充真实读数**；
/// - 目标未设＝该块只出「未设目标」＋入口（目标屏属下一批＝置灰不隐藏），块内不许出现百分比。
class MediaStatPage extends ConsumerStatefulWidget {
  const MediaStatPage({super.key});

  @override
  ConsumerState<MediaStatPage> createState() => _MediaStatPageState();
}

class _MediaStatPageState extends ConsumerState<MediaStatPage> {
  /// 点选的热力日（`yyyy-MM-dd`；null＝没选，读数行整段不出现）。
  String? _day;

  MdsStatFilter get _f => ref.read(mdsStatFilterProvider);

  void _set(MdsStatFilter f) {
    final p = ref.read(mdsStatFilterProvider.notifier);
    p.state = f;
  }

  void _bump() {
    final t = ref.read(mediaTickProvider.notifier);
    t.state = t.state + 1;
  }

  /// 口径切换＝写 `media.speedFold` 并让 KV→设置→统计三层层层重取（不另存一份态）。
  Future<void> _setFold(bool fold) async {
    await ref.read(mediaRepositoryProvider).setKv('media.speedFold', fold ? 'true' : 'false');
    _bump();
  }

  void _reset() {
    _set(const MdsStatFilter());
    setState(() => _day = null);
    _setFold(false);
  }

  @override
  Widget build(BuildContext context) {
    final stat = ref.watch(mediaStatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('影音统计'),
        actions: [
          IconButton(
            key: const ValueKey('mds-stat-reset'),
            tooltip: '回到默认',
            icon: const Icon(Icons.restore),
            onPressed: _reset,
          ),
        ],
      ),
      body: stat.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '统计没加载出来',
          error: e,
          onRetry: () => ref.invalidate(mediaStatProvider),
        ),
        data: (r) => _body(context, r),
      ),
    );
  }

  Widget _body(BuildContext context, MdsStatRead r) {
    final fold = ref.watch(mediaSpeedFoldProvider).valueOrNull ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        // ---- 口径两枚（＝media.speedFold）----
        Wrap(
          key: const ValueKey('mds-stat-fold'),
          spacing: 8,
          children: [
            PillChip(
              key: const ValueKey('mds-stat-fold-real'),
              label: '真实时长',
              selected: !fold,
              onTap: () => _setFold(false),
            ),
            PillChip(
              key: const ValueKey('mds-stat-fold-fold'),
              label: '折算时长',
              selected: fold,
              onTap: () => _setFold(true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _drill(context, r),
        const SizedBox(height: 6),
        _heatCard(context, r, fold),
        _trendCard(context, r, fold),
        _kindsCard(context, r),
        _hoursCard(context, r),
        _ratingCard(context, r),
        _goalCard(context),
        _totalsCard(context, r),
      ],
    );
  }

  // ==================== 四行钻取筛选条 ====================

  Widget _drill(BuildContext context, MdsStatRead r) {
    return Column(
      key: const ValueKey('mds-stat-drill'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chipRow(
          '年',
          [
            _chip('mds-stat-year-all', '全部', _f.year == null, () => _set(_f.copyWith(clearYear: true, clearMonth: true))),
            for (final y in r.years)
              _chip('mds-stat-year-$y', '$y', _f.year == y, () => _set(_f.copyWith(year: y, clearMonth: true))),
          ],
        ),
        _chipRow(
          '月',
          [
            _chip('mds-stat-month-all', '全年', _f.month == null, () => _set(_f.copyWith(clearMonth: true))),
            for (var m = 1; m <= 12; m++)
              _chip('mds-stat-month-$m', '$m 月', _f.month == m, () => _set(_f.copyWith(month: m))),
          ],
        ),
        _chipRow(
          '度量',
          [
            for (final (v, label) in kMdsMetrics)
              _chip('mds-stat-metric-$v', label, _f.metric == v, () => _set(_f.copyWith(metric: v))),
          ],
        ),
        _chipRow(
          '构成',
          [
            _chip('mds-stat-kind-all', '全部', _f.kind == 'all', () => _set(_f.copyWith(kind: 'all'))),
            for (final k in MediaItem.kinds)
              _chip('mds-stat-kind-$k', MediaItem.labelOf(k), _f.kind == k, () => _set(_f.copyWith(kind: k))),
          ],
        ),
      ],
    );
  }

  Widget _chipRow(String label, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 34,
              child: Text(label,
                  style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < chips.length; i++)
                      Padding(
                        padding: EdgeInsets.only(right: i == chips.length - 1 ? 0 : 8),
                        child: chips[i],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _chip(String key, String label, bool on, VoidCallback onTap) =>
      PillChip(key: ValueKey(key), label: label, selected: on, onTap: onTap);

  // ==================== 八块读数 ====================

  Widget _heatCard(BuildContext context, MdsStatRead r, bool fold) => _card(
        key: const ValueKey('mds-stat-heat'),
        title: '近 $kMdsHeatDays 天 · ${_f.metricWord}热力 · ${fold ? '折算' : '真实'}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (final c in r.heat) _heatCell(context, c)],
            ),
            if (_day != null) ...[
              const SizedBox(height: 10),
              _dayRead(context, r),
            ],
          ],
        ),
      );

  Widget _heatCell(BuildContext context, MdsHeatCell c) {
    final scheme = Theme.of(context).colorScheme;
    final k = _dayKey(c.day);
    final sel = _day == k;
    final alpha = switch (c.level) {
      3 => .95,
      2 => .7,
      1 => .45,
      _ => 0.0,
    };
    return GestureDetector(
      key: ValueKey('mds-stat-heat-$k'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _day = sel ? null : k),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: alpha == 0 ? null : (c.topKind == null ? scheme.primary : mdsKindColor(c.topKind!)).withValues(alpha: alpha),
          border: alpha == 0
              ? Border.all(color: scheme.outlineVariant)
              : (sel ? Border.all(color: scheme.primary, width: 2) : null),
        ),
      ),
    );
  }

  Widget _dayRead(BuildContext context, MdsStatRead r) {
    final scheme = Theme.of(context).colorScheme;
    final c = r.heat.where((e) => _dayKey(e.day) == _day).toList();
    if (c.isEmpty) return const SizedBox.shrink();
    final cell = c.first;
    final head = '${_mdOf(cell.day)} · ${_wdOf(cell.day)}';
    if (cell.count == 0) {
      return Container(
        key: const ValueKey('mds-stat-dayread'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
        child: Text('$head · 没记录', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      );
    }
    return Wrap(
      key: const ValueKey('mds-stat-dayread'),
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(head, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        for (final k in cell.kinds)
          Text('${mdsKindWord(k)} ${mdsMetricText(_f.metric, cell.kindValues[k] ?? 0)}',
              key: ValueKey('mds-stat-dayread-$k'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: mdsKindColor(k))),
        Text('${cell.count} 条', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _trendCard(BuildContext context, MdsStatRead r, bool fold) {
    final bars = r.trend;
    final max = bars.fold<double>(0, (t, b) => b.value > t ? b.value : t);
    final scheme = Theme.of(context).colorScheme;
    return _card(
      key: const ValueKey('mds-stat-trend'),
      title: '${_f.windowLabel}趋势 · ${_f.metricWord} · ${fold ? '折算' : '真实'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 74,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in bars)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        key: ValueKey('mds-stat-trend-${b.key}'),
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (b.hasData)
                            Text(mdsMetricText(_f.metric, b.value),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 7.5, color: scheme.onSurfaceVariant)),
                          Container(
                            height: b.hasData
                                ? (6 + 40 * (b.value / (max == 0 ? 1 : max))).clamp(6.0, 46.0).toDouble()
                                : 2,
                            decoration: b.hasData
                                ? BoxDecoration(
                                    color: _f.kind == 'all' ? scheme.primary : mdsKindColor(_f.kind),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                  )
                                : BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              for (final b in bars)
                Expanded(
                  child: Text(b.label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.clip,
                      style: TextStyle(fontSize: 7.5, color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kindsCard(BuildContext context, MdsStatRead r) => _card(
        key: const ValueKey('mds-stat-kinds'),
        title: '类型构成',
        child: r.kinds.isEmpty
            ? EmptyDashRow(text: '这个窗口没有记录')
            : Column(
                children: [
                  for (final s in r.kinds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        key: ValueKey('mds-stat-kind-row-${s.kind}'),
                        children: [
                          _dot(s.kind),
                          const SizedBox(width: 6),
                          SizedBox(width: 38, child: Text(MediaItem.labelOf(s.kind), style: const TextStyle(fontSize: 11.5))),
                          Expanded(
                            child: _bar(s.pct / 100, mdsKindColor(s.kind)),
                          ),
                          const SizedBox(width: 8),
                          Text('${mdsMetricText(_f.metric, s.value)} · ${s.pct}%',
                              key: ValueKey('mds-stat-kind-val-${s.kind}'),
                              style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                ],
              ),
      );

  Widget _hoursCard(BuildContext context, MdsStatRead r) {
    var max = 0.0;
    for (final h in r.hours) {
      if (h.value > max) max = h.value;
    }
    final scheme = Theme.of(context).colorScheme;
    return _card(
      key: const ValueKey('mds-stat-hours'),
      title: '时段分布',
      child: Column(
        children: [
          for (final h in r.hours)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                key: ValueKey('mds-stat-hour-${h.key}'),
                children: [
                  SizedBox(width: 34, child: Text(h.label, style: const TextStyle(fontSize: 11))),
                  Expanded(child: _bar(max == 0 ? 0 : h.value / max, scheme.primary)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 62,
                    child: Text(h.value > 0 ? mdsMetricText(_f.metric, h.value) : '—',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _ratingCard(BuildContext context, MdsStatRead r) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      key: const ValueKey('mds-stat-rating'),
      title: '平均评分',
      child: r.ratingAvg == null
          ? EmptyDashRow(text: '这个窗口没有评分记录')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(r.ratingAvg!.toStringAsFixed(1),
                        key: const ValueKey('mds-stat-rating-avg'),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('分 · ${r.ratingCount} 部已评分',
                          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    for (final e in r.ratingByKind.entries)
                      Text('${MediaItem.labelOf(e.key)} ${e.value.toStringAsFixed(1)}',
                          key: ValueKey('mds-stat-rating-${e.key}'),
                          style: TextStyle(fontSize: 10.5, color: mdsKindColor(e.key))),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _goalCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      key: const ValueKey('mds-stat-goal'),
      title: '目标达成',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmptyDashRow(text: '未设目标'),
          const SizedBox(height: 8),
          // 目标屏属下一批：能力未开放＝置灰不隐藏（批3 §2 判断2 同口径），不铺假读数。
          Opacity(
            opacity: .55,
            child: InkWell(
              key: const ValueKey('mds-stat-goal-entry'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => AppToast.show(context, '影音目标还没上线'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Row(
                  children: [
                    const Expanded(
                        child: Text('影音目标', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                    Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalsCard(BuildContext context, MdsStatRead r) => _card(
        key: const ValueKey('mds-stat-totals'),
        title: '跨 kind 总时长',
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final e in r.kindMinutes.entries)
              _totalChip('mds-stat-total-${e.key}', '${mdsKindWord(e.key)} ${e.value > 0 ? mdsHm(e.value) : '—'}',
                  mdsKindColor(e.key)),
            _totalChip('mds-stat-total-all', '总计 ${r.totalMinutes > 0 ? mdsHm(r.totalMinutes) : '—'}', schemePrimary(context)),
          ],
        ),
      );

  Color schemePrimary(BuildContext context) => Theme.of(context).colorScheme.primary;

  Widget _totalChip(String key, String text, Color tone) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tone.withValues(alpha: .55)),
        ),
        child: Text(text, key: ValueKey(key), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _dot(String kind) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: mdsKindColor(kind), borderRadius: BorderRadius.circular(2)),
      );

  Widget _bar(double frac, Color tone) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 6,
      decoration: BoxDecoration(color: scheme.onSurface.withValues(alpha: .07), borderRadius: BorderRadius.circular(3)),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: frac.clamp(0.0, 1.0),
        child: Container(decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(3))),
      ),
    );
  }

  Widget _card({required Key key, required String title, required Widget child}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          key: key,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ),
      );

  static String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _mdOf(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _wdOf(DateTime d) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][d.weekday - 1];
}
