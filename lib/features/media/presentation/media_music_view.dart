import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_note.dart';
import '../domain/media_item.dart';
import '../domain/media_note.dart';
import 'media_playlist_parser.dart';
import 'media_providers.dart';

/// 听后感挂在 `media_notes` 表、不绑定具体 `media_items` 条目时的占位 item_id。
/// 走既有表与 DAO（notes/addNote/updateNote），零 DB 迁移；导入落 `origin=import`。
const String kM5ListenItemId = 'music-view';

/// M5 · 音乐特化架面（架面屏**内部视图切换**：默认不走这里＝仍渲染现行扁平架面）。
/// 听后感流＝曲目（body）·心情（tag）·短评（thought）·时间戳（createdAt）四要素，
/// 数据复用 media_notes 表；「记一条／导入歌单」两个入口均为纯本地、零网络、零新增依赖。
/// 全屏颜色一律吃 Theme.of(context).colorScheme，不硬编码色值（doclint 色值棘轮）。
class MediaMusicView extends ConsumerWidget {
  const MediaMusicView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notes = ref.watch(mediaMusicNotesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '听后感流',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              _ActionBtn(
                key: const ValueKey('mds-add-listen'),
                icon: Icons.edit_note_outlined,
                label: '记一条',
                onTap: () => m5OpenListenEditor(context, null),
              ),
              const SizedBox(width: 8),
              _ActionBtn(
                key: const ValueKey('mds-import-playlist'),
                icon: Icons.playlist_add_outlined,
                label: '导入歌单',
                onTap: () => m5OpenPlaylistImport(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: notes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '听后感没加载出来：$e',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            data: (list) => list.isEmpty
                ? _empty(scheme)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) => MediaListenCard(note: list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _empty(ColorScheme scheme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music_outlined,
                size: 38, color: scheme.outlineVariant),
            const SizedBox(height: 10),
            Text(
              '还没有听后感 · 记一条或导入歌单',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
}

/// 听后感卡：曲目 · 心情 chip · 短评 · 时间戳；点击进编辑（复用 updateNote）。
class MediaListenCard extends StatelessWidget {
  const MediaListenCard({super.key, required this.note});

  final MediaNote note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mood = (note.tag ?? '').trim();
    final brief = (note.thought ?? '').trim();
    final stamp = m5FormatStamp(note.createdAt);
    return Card(
      key: ValueKey('mds-listen-${note.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => m5OpenListenEditor(context, note),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.album_outlined, size: 26, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        if (mood.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              mood,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (brief.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        brief,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    if (stamp.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        stamp,
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: scheme.onPrimaryContainer),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新增／编辑听后感入口（新增＝addNote、编辑＝updateNote，均在册判重同源）。
Future<void> m5OpenListenEditor(BuildContext context, MediaNote? note) async {
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ListenEditorSheet(note: note),
  );
}

class _ListenEditorSheet extends ConsumerStatefulWidget {
  const _ListenEditorSheet({this.note});

  final MediaNote? note;

  @override
  ConsumerState<_ListenEditorSheet> createState() => _ListenEditorSheetState();
}

class _ListenEditorSheetState extends ConsumerState<_ListenEditorSheet> {
  late final TextEditingController _song;
  late final TextEditingController _mood;
  late final TextEditingController _brief;

  @override
  void initState() {
    super.initState();
    _song = TextEditingController(text: widget.note?.body ?? '');
    _mood = TextEditingController(text: widget.note?.tag ?? '');
    _brief = TextEditingController(text: widget.note?.thought ?? '');
  }

  @override
  void dispose() {
    _song.dispose();
    _mood.dispose();
    _brief.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _song.text.trim();
    if (body.isEmpty) {
      AppToast.show(context, '先写下曲目名');
      return;
    }
    final repo = ref.read(mediaRepositoryProvider);
    final mood = _mood.text.trim();
    final brief = _brief.text.trim();
    final cur = widget.note;
    if (cur == null) {
      await repo.addNote(MediaNote(
        itemId: kM5ListenItemId,
        kind: MediaItem.kMusic,
        noteType: MediaNote.kLong,
        body: body,
        tag: mood.isEmpty ? null : mood,
        thought: brief.isEmpty ? null : brief,
        origin: MediaNote.kOriginManual,
      ));
    } else {
      await repo.updateNote(cur.copyWith(
        body: body,
        tag: mood.isEmpty ? '' : mood,
        thought: brief.isEmpty ? '' : brief,
      ));
    }
    ref.read(mediaTickProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.note == null ? '记一条听后感' : '编辑听后感',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _song,
              decoration: const InputDecoration(
                labelText: '曲目',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mood,
              decoration: const InputDecoration(
                labelText: '心情',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _brief,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '短评',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
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

/// 导入歌单入口：粘贴文本 → parsePlaylistText 纯本地解析 → 逐条落 origin=import 听后感。
/// 零网络、零新增依赖、零 DB 迁移。
Future<void> m5OpenPlaylistImport(BuildContext context) async {
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PlaylistImportSheet(),
  );
}

class _PlaylistImportSheet extends ConsumerStatefulWidget {
  const _PlaylistImportSheet();

  @override
  ConsumerState<_PlaylistImportSheet> createState() =>
      _PlaylistImportSheetState();
}

class _PlaylistImportSheetState extends ConsumerState<_PlaylistImportSheet> {
  final _ctrl = TextEditingController();
  List<String> _parsed = const <String>[];
  bool _preview = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _parse() {
    final list = parsePlaylistText(_ctrl.text);
    setState(() {
      _parsed = list;
      _preview = true;
    });
  }

  Future<void> _apply() async {
    if (_parsed.isEmpty) {
      AppToast.show(context, '没有解析出曲目');
      return;
    }
    final repo = ref.read(mediaRepositoryProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final title in _parsed) {
      await repo.addNote(MediaNote(
        itemId: kM5ListenItemId,
        kind: MediaItem.kMusic,
        noteType: MediaNote.kLong,
        body: title,
        origin: MediaNote.kOriginImport,
        createdAt: now,
      ));
    }
    ref.read(mediaTickProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '导入歌单',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              '粘贴歌单文本 · 纯本地解析（零网络）',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '每行一首，或「艺人 - 曲目」；# 开头行会被忽略',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_preview) ...[
              const SizedBox(height: 8),
              Text(
                '解析出 ${_parsed.length} 首曲目',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _parse,
                    child: const Text('解析'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('确认导入'),
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
