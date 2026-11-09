import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_session.dart';
import '../data/media_repository.dart';
import '../domain/media_session.dart';
import '../domain/media_stats.dart';
import 'media_providers.dart';

/// 影音游「计时明细」整屏（原型 `index-media.html#m-sesslog` · L693 骨架 + `mRenderSess`）。
///
/// 为什么单独立屏：批4 拍板①「改与删一律在整屏」——轨迹弹层只读数，明细的增改删全在这里，
/// 一屏一个写入口，避免弹层与整屏两套编辑态。写口早就备好（`addManualDetail` /
/// `updateSessionDetail` / `deleteSession`，批4b A1 就是为这屏写的），本屏纯 UI 接线。
///
/// 口径（与原型/写口一致）：
/// · 汇总里的「折算」读 `MediaSession.billedMinutes`，**不另算一套**；
/// · 列表按 `MM` 分组降序、组内按开始时间降序（同格口径：原型 `mSessSorted`）；
/// · 补记与行内改共用同一份编辑行，保存分别走 `addManualDetail` / `updateSessionDetail`。
class MediaSesslogPage extends ConsumerStatefulWidget {
  const MediaSesslogPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<MediaSesslogPage> createState() => _MediaSesslogPageState();
}

class _MediaSesslogPageState extends ConsumerState<MediaSesslogPage> {
  /// 正在编辑的会话 id；-1＝新建补记态；null＝没有编辑态。
  int? _editing;
  bool _adding = false;
  final _minCtrl = TextEditingController();
  double _speed = 1;

  @override
  void dispose() {
    _minCtrl.dispose();
    super.dispose();
  }

  MediaRepository get _repo => ref.read(mediaRepositoryProvider);

  void _refresh() {
    ref.invalidate(mediaTrackSessionsProvider(widget.itemId));
    ref.invalidate(mediaItemDetailProvider(widget.itemId));
  }

  void _startAdd() {
    setState(() {
      _adding = true;
      _editing = null;
      _minCtrl.text = '30';
      _speed = 1;
    });
  }

  void _startEdit(MediaSession s) {
    setState(() {
      _adding = false;
      _editing = s.id;
      _minCtrl.text = '${s.minutes}';
      _speed = s.speed ?? 1;
    });
  }

  void _cancel() => setState(() {
        _adding = false;
        _editing = null;
      });

  Future<void> _saveNew(MediaSession? kindOf) async {
    final min = int.tryParse(_minCtrl.text.trim()) ?? 0;
    if (min <= 0) return;
    final item = await ref.read(mediaItemDetailProvider(widget.itemId).future);
    if (item == null) return;
    await _repo.addManualDetail(
      itemId: widget.itemId,
      kind: item.kind,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
      minutes: min,
      speed: _speed == 1 ? null : _speed,
    );
    if (!mounted) return;
    _cancel();
    _refresh();
  }

  Future<void> _saveEdit(MediaSession s) async {
    final min = int.tryParse(_minCtrl.text.trim()) ?? 0;
    if (min <= 0 || s.id == null) return;
    await _repo.updateSessionDetail(
      s.id!,
      minutes: min,
      speed: _speed == 1 ? null : _speed,
    );
    if (!mounted) return;
    _cancel();
    _refresh();
  }

  Future<void> _delete(MediaSession s) async {
    if (s.id == null) return;
    await _repo.deleteSession(s.id!);
    if (!mounted) return;
    _cancel();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(mediaTrackSessionsProvider(widget.itemId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('计时明细'),
        actions: [
          IconButton(
            key: const ValueKey('mds-sess-add'),
            tooltip: '补记一次',
            icon: const Icon(Icons.add),
            onPressed: _startAdd,
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取失败：$e')),
        data: (rows) {
          final closed = rows.where((s) => s.endedAt != null).toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
          final total = closed.fold<int>(0, (a, s) => a + s.minutes);
          final billed = closed.fold<int>(0, (a, s) => a + s.billedMinutes());
          final days = closed
              .map((s) => _dayKey(s.startedAt))
              .toSet()
              .length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _summary(context, scheme, total, billed, days, closed.length),
              if (_adding) ...[
                const SizedBox(height: 12),
                _editRow(context, scheme, null),
              ],
              const SizedBox(height: 14),
              if (closed.isEmpty && !_adding)
                const EmptyDashRow(
                  key: ValueKey('mds-sess-empty'),
                  text: '还没有计时记录 · 右上角「＋」补记一次',
                ),
              for (final g in _groupByMonth(closed)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Text('${g.$1} 月 · ${g.$2.length} 次',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ),
                for (final s in g.$2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _editing == s.id
                        ? _editRow(context, scheme, s)
                        : _sessRow(context, scheme, s),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _summary(BuildContext context, ColorScheme scheme, int total,
      int billed, int days, int count) {
    final pace = days == 0 ? 0 : (total / days).round();
    Widget one(String label, String value) => Expanded(
          key: ValueKey('mds-sess-stat-$label'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
            ],
          ),
        );
    return Container(
      key: const ValueKey('mds-sess-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            one('累计', mdsHm(total)),
            one('折算', mdsHm(billed)),
            one('天数', '$days'),
            one('日均', mdsHm(pace)),
          ]),
          const SizedBox(height: 6),
          Text('共 $count 次', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _sessRow(BuildContext context, ColorScheme scheme, MediaSession s) {
    final t = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    final et = DateTime.fromMillisecondsSinceEpoch(
        s.endedAt ?? s.startedAt + s.minutes * 60000);
    return InkWell(
      key: ValueKey('mds-sess-${s.id}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => _startEdit(s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Text('${_two(t.month)}-${_two(t.day)}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_hhmm(t)} — ${_hhmm(et)}'
              '${s.speed != null && s.speed! > 1 ? ' · ${s.speed}x' : ''}'
              '${s.source == MediaSession.kSrcManual ? ' · 补记' : ''}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(mdsHm(s.minutes),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _editRow(BuildContext context, ColorScheme scheme, MediaSession? s) {
    return Container(
      key: const ValueKey('mds-sess-edit'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('时长（分钟）', style: TextStyle(fontSize: 11.5)),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: TextField(
                key: const ValueKey('mds-sess-min'),
                controller: _minCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true, labelText: '分钟'),
              ),
            ),
            const Spacer(),
            TextButton(
              key: const ValueKey('mds-sess-del'),
              onPressed: s == null ? null : () => _delete(s),
              child: const Text('删除'),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final v in const [1.0, 1.25, 1.5, 2.0])
                ChoiceChip(
                  key: ValueKey('mds-sess-spd-$v'),
                  label: Text(v == 1 ? '原速' : '${v}x'),
                  selected: _speed == v,
                  onSelected: (_) => setState(() => _speed = v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(
              key: const ValueKey('mds-sess-cancel'),
              onPressed: _cancel,
              child: const Text('取消'),
            ),
            const Spacer(),
            FilledButton(
              key: const ValueKey('mds-sess-save'),
              onPressed: () => s == null ? _saveNew(null) : _saveEdit(s),
              child: const Text('保存'),
            ),
          ]),
        ],
      ),
    );
  }

  /// 按月分组（`MM` 降序，组内已按开始时间降序）。
  List<(String, List<MediaSession>)> _groupByMonth(List<MediaSession> rows) {
    final map = <String, List<MediaSession>>{};
    for (final s in rows) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      map.putIfAbsent(_two(t.month), () => <MediaSession>[]).add(s);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys) (k, map[k]!)];
  }

  static String _dayKey(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.year}-${_two(t.month)}-${_two(t.day)}';
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  static String _hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
}
