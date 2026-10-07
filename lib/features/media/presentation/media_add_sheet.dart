import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../domain/media_item.dart';
import 'media_providers.dart';

/// 色板组数（无封面时取色下标回绕用，与 widgets/media_card.dart 的 kMdsCov 同数）。
/// 录入时就把 colorIdx 定下来，避免两处各写一套取色逻辑。
const int kMediaPaletteCount = 8;

/// 新条目录入弹层（LH-S32 · 原型 `m-sheet-add`）：**按 kind 分派四套字段**，
/// 不是同一张表单换个标题——每类写回的进度列与 [MediaItem.progressWay] 各不相同：
/// · 电影＝时长(min)＋进度方式（百分比 / 时间点）
/// · 剧集＝季数＋总集数＋看到第几集（ep 档）
/// · 音乐＝曲目数（循环次数＝听歌会话派生，不在录入里编）
/// · 游戏＝周目＋进度方式（剧情主线% / 周目数 / 成就完成度）
Future<void> showMediaAddSheet(
  BuildContext context,
  WidgetRef ref, {
  String initialKind = MediaItem.kMovie,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MediaAddSheet(initialKind: initialKind),
  );
}

class _MediaAddSheet extends ConsumerStatefulWidget {
  const _MediaAddSheet({required this.initialKind});

  final String initialKind;

  @override
  ConsumerState<_MediaAddSheet> createState() => _MediaAddSheetState();
}

class _MediaAddSheetState extends ConsumerState<_MediaAddSheet> {
  late String _kind = widget.initialKind;

  /// 进度方式随类型走：换类即回到该类默认档（刀3 钉这里）。
  late String _way = MediaItem.defaultWay(widget.initialKind);

  final _title = TextEditingController();
  final _creator = TextEditingController();
  final _publisher = TextEditingController();
  final _year = TextEditingController();
  final _duration = TextEditingController();
  final _progress = TextEditingController();
  final _seasons = TextEditingController();
  final _episodes = TextEditingController();
  final _curEp = TextEditingController();
  final _tracks = TextEditingController();
  final _playthroughs = TextEditingController();
  bool _saving = false;
  String? _titleErr;

  @override
  void dispose() {
    for (final c in [
      _title,
      _creator,
      _publisher,
      _year,
      _duration,
      _progress,
      _seasons,
      _episodes,
      _curEp,
      _tracks,
      _playthroughs,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pickKind(String k) => setState(() {
    _kind = k;
    _way = MediaItem.defaultWay(k);
  });

  int _num(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      // 校验写在字段旁（LH-K32），不借道提示条。
      setState(() => _titleErr = '请先写名称');
      return;
    }
    setState(() {
      _saving = true;
      _titleErr = null;
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    final prog = _num(_progress);
    final item = MediaItem(
      kind: _kind,
      title: title,
      creator: _creator.text.trim().isEmpty ? '未知' : _creator.text.trim(),
      creatorRole: MediaItem.creatorRoleLabel[_kind],
      publisher: _publisher.text.trim().isEmpty
          ? null
          : _publisher.text.trim(),
      publisherRole: MediaItem.publisherRoleLabel[_kind],
      releaseYear: int.tryParse(_year.text.trim()),
      colorIdx: (title.codeUnitAt(0) + title.length) % kMediaPaletteCount,
      state: MediaItem.initialState(_kind),
      // 时长：电影＝总时长，游戏＝主线时长，剧集＝单集时长（§2.1 列注释同口径）
      durationMin: _kind == MediaItem.kMusic ? 0 : _num(_duration),
      seasonsCount: _kind == MediaItem.kSeries ? _num(_seasons) : 0,
      episodesTotal: _kind == MediaItem.kSeries ? _num(_episodes) : 0,
      tracksCount: _kind == MediaItem.kMusic ? _num(_tracks) : 0,
      playthroughs: _kind == MediaItem.kGame ? _num(_playthroughs) : 0,
      mainPct: _kind == MediaItem.kGame && _way == MediaItem.kWayMainPct
          ? prog.clamp(0, 100)
          : _kind == MediaItem.kMovie && _way == MediaItem.kWayPct
          ? prog.clamp(0, 100)
          : 0,
      achPct: _kind == MediaItem.kGame && _way == MediaItem.kWayAchv
          ? prog.clamp(0, 100)
          : 0,
      progressWay: _way,
      // 进度终点按档解释：电影＝%或第几分钟，剧集＝第几集，
      // 游戏＝主线%/周目数，音乐没有录入位（循环次数走会话派生）。
      progressTo: switch ((_kind, _way)) {
        (MediaItem.kMovie, MediaItem.kWayPct) ||
        (MediaItem.kMovie, MediaItem.kWayMin) => prog.toString(),
        (MediaItem.kSeries, MediaItem.kWayEp) => _num(_curEp).toString(),
        (MediaItem.kGame, MediaItem.kWayMainPct) ||
        (MediaItem.kGame, MediaItem.kWayAchv) => prog.toString(),
        (MediaItem.kGame, MediaItem.kWayPlaythrough) =>
          _num(_playthroughs).toString(),
        _ => null,
      },
      source: '自建',
      createdAt: now,
      updatedAt: now,
      lastActivityAt: now,
    );
    final id = await ref.read(mediaRepositoryProvider).addItem(item);
    if (!mounted) return;
    final tick = ref.read(mediaTickProvider.notifier);
    tick.state = tick.state + 1;
    Navigator.of(context).pop();
    AppToast.show(context, '已入影音架');
    debugPrint('media_add_saved id=$id kind=${item.kind} way=${item.progressWay}');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                '新条目',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in MediaItem.kinds)
                    PillChip(
                      key: ValueKey('mds-add-kind-$k'),
                      label: MediaItem.labelOf(k),
                      selected: _kind == k,
                      onTap: () => _pickKind(k),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _field(
                controller: _title,
                label: '片名 / 专辑 / 游戏名',
                errorText: _titleErr,
                // 红字亮过后一输入就撤（不等到下次保存才发现自己已经填了）。
                onChanged: _titleErr == null
                    ? null
                    : (_) => setState(() => _titleErr = null),
              ),
              _field(
                controller: _creator,
                label: MediaItem.creatorRoleLabel[_kind] ?? '主创',
              ),
              _field(
                controller: _publisher,
                label: MediaItem.publisherRoleLabel[_kind] ?? '发行',
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _field(controller: _year, label: '年份', numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(
                      controller: _secondController(),
                      label: _secondLabel(),
                      numeric: true,
                    ),
                  ),
                ],
              ),
              _kindFields(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('mds-add-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('mds-add-save'),
                      onPressed: _saving ? null : _save,
                      child: const Text('保存 · 进入影音架'),
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

  TextEditingController _secondController() => switch (_kind) {
    MediaItem.kMovie => _duration,
    MediaItem.kSeries => _seasons,
    MediaItem.kMusic => _tracks,
    _ => _playthroughs,
  };

  String _secondLabel() => switch (_kind) {
    MediaItem.kMovie => '时长(min)',
    MediaItem.kSeries => '季数',
    MediaItem.kMusic => '曲目数',
    _ => '周目数',
  };

  /// 类型专属区（原型 #mdsAddKindFields 的 Flutter 版：真的能填，不只是说明行）。
  Widget _kindFields() {
    final ways = MediaItem.ways[_kind] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ways.length > 1) ...[
          const SizedBox(height: 4),
          Text(
            '进度方式',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in ways)
                PillChip(
                  key: ValueKey('mds-add-way-$w'),
                  label: _wayLabel(w),
                  selected: _way == w,
                  onTap: () => setState(() => _way = w),
                ),
            ],
          ),
        ],
        if (_kind == MediaItem.kSeries)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(controller: _episodes, label: '总集数', numeric: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(controller: _curEp, label: '看到第几集', numeric: true),
              ),
            ],
          )
        else if (_kind == MediaItem.kMusic)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '循环次数按听歌会话自动计，这里不填。',
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          _field(controller: _progress, label: _progressLabel(), numeric: true),
      ],
    );
  }

  /// 进度读数栏的标签按「类型 × 档」变（同一控件四种语义，值列也不同）。
  String _progressLabel() => switch ((_kind, _way)) {
    (MediaItem.kMovie, MediaItem.kWayPct) => '进度(%)',
    (MediaItem.kMovie, MediaItem.kWayMin) => '看到第几分钟',
    (MediaItem.kGame, MediaItem.kWayMainPct) => '主线进度(%)',
    (MediaItem.kGame, MediaItem.kWayAchv) => '成就完成度(%)',
    (MediaItem.kGame, MediaItem.kWayPlaythrough) => '已完成周目数',
    _ => '进度',
  };

  String _wayLabel(String w) => switch (w) {
    MediaItem.kWayPct => '百分比',
    MediaItem.kWayMin => '时间点',
    MediaItem.kWayEp => '按集',
    MediaItem.kWayLoops => '按循环',
    MediaItem.kWayMainPct => '剧情主线%',
    MediaItem.kWayPlaythrough => '周目',
    MediaItem.kWayAchv => '成就完成度',
    _ => w,
  };

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool numeric = false,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: ValueKey('mds-add-field-$label'),
        controller: controller,
        onChanged: onChanged,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
