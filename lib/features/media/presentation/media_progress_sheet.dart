import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_session.dart';
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import 'media_providers.dart';

/// 进度录入弹层（LH-S33 · 原型 `m-sheet-progress`）：**按 kind 分派四套字段**，
/// 保存经 [MediaRepository.saveProgress] 真实回写各自的进度列——
/// · 电影＝时间点/百分比（两栏互算）＋分区＋评分
/// · 剧集＝季 + 集＋追更状态（在追/完结/弃剧/待续→映射在册分区）
/// · 音乐＝整专循环/单曲循环（循环次数＝会话派生，这里不落列）＋分区＋评分
/// · 游戏＝周目＋主线%＋支线%＋全成就%＋通关分区＋平台
///
/// 保存后按真实会话重算「日均 · 预计剩余 · 预计完成日」（原型 toast 那句的兑现）。
Future<void> showMediaProgressSheet(
  BuildContext context,
  WidgetRef ref,
  MediaItem item, {
  int? sessionMinutes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProgressSheet(item: item, sessionMinutes: sessionMinutes),
  );
}

class _ProgressSheet extends ConsumerStatefulWidget {
  const _ProgressSheet({required this.item, this.sessionMinutes});

  final MediaItem item;
  final int? sessionMinutes;

  @override
  ConsumerState<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends ConsumerState<_ProgressSheet> {
  late String _way = widget.item.progressWay;
  late String _state = widget.item.state;
  late final _pct = TextEditingController(
    text: widget.item.progressWay == MediaItem.kWayPct
        ? (widget.item.progressTo ?? '')
        : '',
  );
  late final _atMin = TextEditingController(
    text: widget.item.progressWay == MediaItem.kWayMin
        ? (widget.item.progressTo ?? '')
        : '',
  );
  late final _ep = TextEditingController(text: widget.item.progressTo ?? '');
  late final _season = TextEditingController(
    text: '${widget.item.seasonsCount}',
  );
  late final _loops = TextEditingController();
  late final _playthroughs = TextEditingController(
    text: '${widget.item.playthroughs}',
  );
  late final _mainPct = TextEditingController(
    text: '${widget.item.mainPct}',
  );
  late final _sidePct = TextEditingController(text: '${widget.item.sidePct}');
  late final _achPct = TextEditingController(text: '${widget.item.achPct}');
  late final _rating = TextEditingController(
    text: widget.item.myRating > 0 ? '${widget.item.myRating}' : '',
  );
  bool _saving = false;

  MediaItem get _item => widget.item;

  @override
  void dispose() {
    for (final c in [
      _pct,
      _atMin,
      _ep,
      _season,
      _loops,
      _playthroughs,
      _mainPct,
      _sidePct,
      _achPct,
      _rating,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  double? _ratingVal() {
    final v = double.tryParse(_rating.text.trim());
    return v?.clamp(0, 10);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    // 刀2 落点：kind→写回字段的这组分派退回单一 pct 口径，media_progress_sheet 即红。
    final pct = _n(_pct).clamp(0, 100);
    await ref
        .read(mediaRepositoryProvider)
        .saveProgress(
          item: _item,
          state: _state,
          myRating: _ratingVal(),
          way: _way,
          pct: switch (_item.kind) {
            MediaItem.kMovie => pct,
            MediaItem.kGame => _n(_mainPct).clamp(0, 100),
            _ => null,
          },
          atMin: _item.kind == MediaItem.kMovie && _way == MediaItem.kWayMin
              ? _n(_atMin)
              : null,
          ep: _item.kind == MediaItem.kSeries ? _n(_ep) : null,
          sidePct: _item.kind == MediaItem.kGame ? _n(_sidePct).clamp(0, 100) : null,
          achPct: _item.kind == MediaItem.kGame
              ? _n(_achPct).clamp(0, 100)
              : null,
          playthroughs: _item.kind == MediaItem.kGame ? _n(_playthroughs) : null,
        );
    // 音乐「记一次循环」＝补一条会话（循环次数派生自会话条数，别处不编数）。
    var loopAdded = false;
    if (_item.kind == MediaItem.kMusic && _n(_loops) > 0) {
      await ref
          .read(mediaRepositoryProvider)
          .addManualSession(
            itemId: _item.id,
            atMs: DateTime.now().millisecondsSinceEpoch,
            minutes: _n(_loops) * 60,
          );
      loopAdded = true;
    }
    final repo = ref.read(mediaRepositoryProvider);
    final fresh = await repo.itemById(_item.id);
    final closed = await repo.closedSessionsOf(_item.id);
    final eta = fresh == null ? null : mediaEtaOf(fresh, closed);
    if (!mounted) return;
    final tick = ref.read(mediaTickProvider.notifier);
    tick.state = tick.state + 1;
    Navigator.of(context).pop();
    AppToast.show(
      context,
      eta != null
          ? '进度已存 · 预计完成 ${eta.etaLabel}（${eta.label}）'
          : loopAdded
          ? '进度已存 · 循环 +1'
          : '进度已存',
    );
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '记进度 · ${_item.title}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              if (widget.sessionMinutes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '本次计时 ${widget.sessionMinutes} 分钟',
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 12),
              _kindBody(scheme),
              const SizedBox(height: 10),
              Text(
                '分区',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in MediaItem.states[_item.kind] ?? const [])
                    PillChip(
                      key: ValueKey('mds-prog-state-$s'),
                      label: s,
                      selected: _state == s,
                      onTap: () => setState(() => _state = s),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _field(controller: _rating, label: '我的评分（0–10）', numeric: true),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('mds-prog-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('mds-prog-save'),
                      onPressed: _saving ? null : _save,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 四套字段区（原型 mRenderProgressSheet 的 Flutter 版：真的能写回各自的列）。
  Widget _kindBody(ColorScheme scheme) {
    switch (_item.kind) {
      case MediaItem.kMovie:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in MediaItem.ways[MediaItem.kMovie] ?? const [])
                  PillChip(
                    key: ValueKey('mds-prog-way-$w'),
                    label: w == MediaItem.kWayPct ? '百分比' : '时间点(分钟)',
                    selected: _way == w,
                    onTap: () => setState(() => _way = w),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_way == MediaItem.kWayPct)
              _field(controller: _pct, label: '看到百分之几', numeric: true)
            else
              _field(
                controller: _atMin,
                label: _item.durationMin > 0
                    ? '看到第几分钟（总长 ${_item.durationMin}min）'
                    : '看到第几分钟',
                numeric: true,
              ),
          ],
        );
      case MediaItem.kSeries:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(controller: _season, label: '季', numeric: true)),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                controller: _ep,
                label: _item.episodesTotal > 0
                    ? '看到第几集（共 ${_item.episodesTotal} 集）'
                    : '看到第几集',
                numeric: true,
              ),
            ),
          ],
        );
      case MediaItem.kMusic:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              controller: _loops,
              label: '本次循环（0＝不记）',
              numeric: true,
            ),
            Text(
              '循环 ${_item.listenLoops ?? 0} 次 · 按听歌会话自动计',
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        );
      case MediaItem.kGame:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(controller: _playthroughs, label: '周目', numeric: true),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(controller: _mainPct, label: '主线%', numeric: true),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(controller: _sidePct, label: '支线%', numeric: true),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(controller: _achPct, label: '全成就%', numeric: true),
                ),
              ],
            ),
            if ((_item.publisher ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '平台 · ${_item.publisher}',
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool numeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: ValueKey('mds-prog-field-$label'),
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
