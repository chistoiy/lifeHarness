import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_session.dart';
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import 'media_actions.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 计时明细（原型 `m-sesslog` · 路由 `/media/item/:id/sessions` · 规格＝LH-C17）。
///
/// 整屏而非半屏弹层（2026-10-07 拍板：逐条要改要删，半屏放不下；与阅读侧 `p-readlog` 同形）。
/// 四条口径在屏上钉死：
/// - **行上的时长恒＝真实耗时**，折算只在倍速>1 时另出一列（1x 不重复报同一个数）；
/// - 改/删/补记都走仓储差量口（同一条 `time_blocks` UPDATE，`txn_id` 复用不新建）；
/// - 日期/时长/起讫/进度一律**就地内嵌输入**，不起二段弹层、不拉系统选择器；
/// - 无记录＝虚线空态，当前范围没有记录＝另一句空态，都不拿 0 冒充真实读数。
class MediaSesslogPage extends ConsumerStatefulWidget {
  const MediaSesslogPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<MediaSesslogPage> createState() => _MediaSesslogPageState();
}

class _MediaSesslogPageState extends ConsumerState<MediaSesslogPage> {
  static const _scopes = <(String, String)>[
    ('all', '全部'),
    ('month', '本月'),
    ('quarter', '近 3 月'),
  ];
  static const _speeds = <double>[1, 1.25, 1.5, 2];

  String _scope = 'all';
  int? _editing; // 展开行的会话 id（null＝没有）
  bool _adding = false;
  double _speed = 1;
  String? _err;
  final _date = TextEditingController();
  final _min = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _end = TextEditingController();

  @override
  void dispose() {
    _date.dispose();
    _min.dispose();
    _from.dispose();
    _to.dispose();
    _end.dispose();
    super.dispose();
  }

  void _bump() {
    final t = ref.read(mediaTickProvider.notifier);
    t.state = t.state + 1;
  }

  void _fill(MediaSession s) {
    final st = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    _date.text = _ymd(st);
    _min.text = '${s.minutes}';
    _from.text = _hhmm(st);
    _to.text = s.endedAt == null ? '' : _hhmm(DateTime.fromMillisecondsSinceEpoch(s.endedAt!));
    _end.text = s.toText ?? (s.toPct != null ? '${s.toPct}%' : (s.toUnit != null ? '${s.toUnit}' : ''));
    _speed = s.speed ?? 1;
    _err = null;
  }

  void _clearDraft() {
    final now = DateTime.now();
    _date.text = _ymd(now);
    _min.text = '';
    _from.text = _hhmm(now);
    _to.text = '';
    _end.text = '';
    _speed = 1;
    _err = null;
  }

  /// 起讫＋日期 → 起点毫秒；任一格式不对即返回 null（就地报错，不猜）。
  int? _startMs() {
    final d = DateTime.tryParse(_date.text.trim());
    final f = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_from.text.trim());
    if (d == null || f == null) return null;
    return DateTime(d.year, d.month, d.day, int.parse(f.group(1)!), int.parse(f.group(2)!))
        .millisecondsSinceEpoch;
  }

  Future<void> _save(MediaItem x, {MediaSession? existing}) async {
    final ms = _startMs();
    final mins = int.tryParse(_min.text.trim());
    if (ms == null) {
      setState(() => _err = '日期或起点时刻格式不对');
      return;
    }
    if (mins == null || mins <= 0) {
      setState(() => _err = '时长要填大于 0 的分钟数');
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(mediaRepositoryProvider);
    final end = _end.text.trim();
    if (existing == null) {
      await repo.addManualDetail(
        itemId: x.id,
        kind: x.kind,
        startedAtMs: ms,
        minutes: mins,
        speed: _speed,
        toText: end.isEmpty ? null : end,
      );
    } else {
      await repo.updateSessionDetail(
        existing.id!,
        startedAtMs: ms,
        minutes: mins,
        speed: _speed,
        toText: end.isEmpty ? null : end,
      );
    }
    refreshTimeAfterMediaSession(container, [ms]);
    _bump();
    setState(() {
      _editing = null;
      _adding = false;
    });
    if (!mounted) return;
    AppToast.show(
      context,
      existing == null ? '已补记 ${_hm(mins)} · 账本同步' : '已更新 · 累计 ${_hm(_total(x, mins, existing))}',
    );
  }

  /// 保存后的累计（就地重算给 toast 用，不读缓存：写库后 tick 已自增，屏上下帧会重取）。
  int _total(MediaItem x, int newMin, MediaSession old) {
    final cur = ref.read(mediaSessionsProvider(x.id)).valueOrNull ?? const <MediaSession>[];
    return cur.fold<int>(0, (t, s) => s.id == old.id ? t + newMin : t + s.minutes);
  }

  Future<void> _delete(MediaItem x, MediaSession s) async {
    final ok = await lhConfirm(context, '删除这次计时（${_hm(s.minutes)}）？时间账本「娱乐」里同一条一并扣掉。');
    if (!ok || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await ref.read(mediaRepositoryProvider).deleteSession(s.id!);
    refreshTimeAfterMediaSession(container, [s.startedAt]);
    _bump();
    setState(() => _editing = null);
    if (!mounted) return;
    AppToast.show(context, '已删除这条 · 账本同条扣减');
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(mediaItemDetailProvider(widget.itemId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('计时明细'),
        actions: [
          IconButton(
            key: const ValueKey('mds-sess-add'),
            tooltip: '补记一次',
            icon: const Icon(Icons.add),
            onPressed: () => setState(() {
              _adding = true;
              _editing = null;
              _clearDraft();
            }),
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
    final all = (ref.watch(mediaSessionsProvider(x.id)).valueOrNull ?? const <MediaSession>[])
        .where((s) => s.endedAt != null)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final total = all.fold<int>(0, (t, s) => t + s.minutes);
    final folded = all.fold<int>(0, (t, s) => t + s.billedMinutes());
    final days = all
        .map((s) {
          final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
          return _ymd(d);
        })
        .toSet();
    final pace = days.isEmpty ? 0 : (total / days.length).round();

    final now = DateTime.now();
    bool inScope(MediaSession s) {
      if (_scope == 'all') return true;
      final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      final diff = (now.year - d.year) * 12 + (now.month - d.month);
      return _scope == 'month' ? diff == 0 : diff >= 0 && diff <= 2;
    }

    final view = all.where(inScope).toList();
    final groups = <String, List<MediaSession>>{};
    for (final s in view) {
      final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      groups.putIfAbsent('${d.year}-${d.month}', () => []).add(s);
    }
    final months = groups.keys.toList()
      ..sort((a, b) {
        final pa = a.split('-').map(int.parse).toList();
        final pb = b.split('-').map(int.parse).toList();
        return (pb[0] * 12 + pb[1]).compareTo(pa[0] * 12 + pa[1]);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ---- 条目头卡 ----
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 54,
              child: AspectRatio(
                aspectRatio: x.kind == MediaItem.kGame ? 16 / 10 : 3 / 4,
                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: MdsCoverArt(item: x)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_kindWord(x.kind), style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  Text(x.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
                  Text(x.creator, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ---- 汇总四格（真实与折算并列出，账本吃前者）----
        GridView.count(
          key: const ValueKey('mds-sess-stats'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            _cell('${_kindWord(x.kind)}时长 · 真实', _hm(total)),
            _cell('折算时长', _hm(folded)),
            _cell(x.kind == MediaItem.kMusic ? '循环次数' : '计时次数', '${all.length}'),
            _cell('日均', pace == 0 ? '—' : _hm(pace)),
          ],
        ),
        const SizedBox(height: 12),
        // ---- 范围三档：点选不循环 ----
        Wrap(
          spacing: 8,
          children: [
            for (final (v, label) in _scopes)
              _scopeChip(key: 'mds-sess-scope-$v', label: label, on: _scope == v, onTap: () => setState(() {
                    _scope = v;
                    _editing = null;
                  })),
          ],
        ),
        if (_adding) ...[
          const SizedBox(height: 10),
          _row(x, null, draft: true),
        ],
        if (months.isEmpty) ...[
          const SizedBox(height: 14),
          EmptyDashRow(text: all.isEmpty ? '还没有计时记录 · 点右上补记一次' : '当前范围没有记录'),
        ] else
          for (final m in months) ...[
            const SizedBox(height: 16),
            _monthHeader(m, groups[m]!),
            for (final s in groups[m]!)
              _row(x, s, open: _editing == s.id, draft: false),
          ],
      ],
    );
  }

  Widget _monthHeader(String key, List<MediaSession> rows) {
    final ym = key.split('-');
    final t = rows.fold<int>(0, (a, s) => a + s.minutes);
    return Row(
      children: [
        Text('${ym[0]} 年 ${int.parse(ym[1])} 月',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const Spacer(),
        Text('共 ${_hm(t)}',
            style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  /// 一条会话（或补记草稿）：折叠态只出读数，展开态就地改。
  Widget _row(MediaItem x, MediaSession? s, {bool open = false, bool draft = false}) {
    final scheme = Theme.of(context).colorScheme;
    final show = open || draft;
    final speed = draft ? _speed : (s!.speed ?? 1);
    final mins = draft ? (int.tryParse(_min.text.trim()) ?? 0) : s!.minutes;
    final st = s == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    final fold = (speed > 1 || show) ? '折算 ${_hm((mins * speed).round())}' : null;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        key: s == null ? const ValueKey('mds-sess-draft') : ValueKey('mds-sess-row-${s.id}'),
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Text(s == null ? '—' : _dayOf(st), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(s == null ? '补' : _wdOf(st), style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: draft || s == null
                    ? null
                    : () => setState(() {
                          _editing = open ? null : s.id;
                          _adding = false;
                          if (!open) _fill(s);
                        }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              s == null
                                  ? '补记一次'
                                  : '${_hhmm(st)}${s.endedAt == null ? '' : ' - ${_hhmm(DateTime.fromMillisecondsSinceEpoch(s.endedAt!))}'}'
                                      '${s.source == MediaSession.kSrcManual ? ' · 补记' : ''}',
                              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                            ),
                          ),
                          if (speed > 1) ...[
                            const SizedBox(width: 6),
                            _miniChip('${speed}x'),
                          ],
                          const Spacer(),
                          if (!draft && s != null)
                            Text(open ? '收起' : '修改',
                                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_hm(mins), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                          if (fold != null) ...[
                            const SizedBox(width: 8),
                            Text(fold,
                                key: s == null ? null : ValueKey('mds-sess-fold-${s.id}'),
                                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                          ],
                          const Spacer(),
                          if (s != null)
                            Flexible(
                              child: Text(_snapshot(s),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                            ),
                        ],
                      ),
                      if (show) _form(x, s),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(MediaItem x, MediaSession? s) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        key: const ValueKey('mds-sess-form'),
        children: [
          _field('日期', _date, 'yyyy-MM-dd', key: 'mds-sess-date'),
          Row(
            children: [
              Expanded(child: _field('时长', _min, '分钟', key: 'mds-sess-min', number: true)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('倍速', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                    Wrap(
                      key: const ValueKey('mds-sess-speeds'),
                      spacing: 6,
                      children: [
                        for (final v in _speeds)
                          _scopeChip(
                            key: 'mds-sess-speed-$v',
                            label: '${v}x',
                            on: _speed == v,
                            onTap: () => setState(() => _speed = v),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _field('起点', _from, 'HH:mm', key: 'mds-sess-from')),
              const SizedBox(width: 8),
              Expanded(child: _field('终点', _to, 'HH:mm', key: 'mds-sess-to', readOnly: true)),
            ],
          ),
          _field('进度终点', _end, _endHint(x.kind), key: 'mds-sess-end'),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_err!, key: const ValueKey('mds-sess-err'), style: TextStyle(fontSize: 11, color: scheme.error)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (s != null) ...[
                TextButton(
                  key: ValueKey('mds-sess-del-${s.id}'),
                  onPressed: () => _delete(x, s),
                  child: Text('删除这次', style: TextStyle(color: scheme.error)),
                ),
                const SizedBox(width: 4),
              ],
              TextButton(
                key: const ValueKey('mds-sess-cancel'),
                onPressed: () => setState(() {
                  _editing = null;
                  _adding = false;
                  _err = null;
                }),
                child: const Text('取消'),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('mds-sess-save'),
                onPressed: () => _save(x, existing: s),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
      {required String key, bool number = false, bool readOnly = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          TextField(
            key: ValueKey('$key-${_editing ?? "new"}'),
            controller: c,
            readOnly: readOnly,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value) => Container(
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

  Widget _scopeChip({required String key, required String label, required bool on, required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey(key),
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: on ? scheme.primary : scheme.onSurface.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? scheme.onPrimary : scheme.onSurfaceVariant)),
      ),
    );
  }

  Widget _miniChip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(t, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
      );

  // ---- 读数口径（全模块同一套措辞）----
  static String _kindWord(String k) => switch (k) {
        MediaItem.kMovie => '观影',
        MediaItem.kSeries => '追剧',
        MediaItem.kMusic => '听歌',
        MediaItem.kGame => '游玩',
        _ => '计时',
      };

  /// 该次进度起讫快照：按 kind 解释（不编数，取不到就只出有的那截）。
  static String _snapshot(MediaSession s) {
    final to = s.toText ??
        (s.toPct != null ? '${s.toPct}%' : (s.toUnit != null ? '${s.toUnit}' : null));
    final from = s.fromText ??
        (s.fromPct != null ? '${s.fromPct}%' : (s.fromUnit != null ? '${s.fromUnit}' : null));
    if (from == null && to == null) return '—';
    if (from == null || to == null) return to ?? from!;
    return '$from → $to';
  }

  static String _endHint(String k) => switch (k) {
        MediaItem.kMovie => '如 1:36:00 或 72%',
        MediaItem.kSeries => '如 S02E05',
        MediaItem.kMusic => '如 曲目 5',
        MediaItem.kGame => '如 主线 35%',
        _ => '进度',
      };

  static String _hm(int m) {
    final v = m < 0 ? 0 : m;
    final h = v ~/ 60, mm = v % 60;
    if (h == 0) return '${mm}m';
    return mm == 0 ? '${h}h' : '${h}h ${mm}m';
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _dayOf(DateTime d) => d.day.toString().padLeft(2, '0');
  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  static String _wdOf(DateTime d) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][d.weekday - 1];
}
