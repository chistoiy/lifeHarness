/// 批5①（工单 §2 · 2026-10-12）· 记录页搜索（原顶栏搜索钮只弹
/// 「全局搜索 · 即将开放」＝看得见点不通的僵尸钮）。
///
/// UI/UX批（2026-10-12）：纳入日记——原型壳全局搜索（sheetSearch）的
/// SEARCH_DB 与范围 chips 本就含「日记」，此前只搜笔记是欠账。
///
/// 基建其实早在：`NoteDao.list(query:)` 已是 `title LIKE ? OR content LIKE ?`；
/// 日记侧本批补 `JournalDao.search()`（正文＋结构化分节 LIKE）。缺的只是入口。
/// 形态＝搜索半屏：输入即时过滤（DAO 侧 LIKE），点结果收屏跳编辑页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../shared/linkage/mindmap_mounts.dart';
import '../domain/note.dart';
import '../domain/journal_entry.dart';
import 'diary_edit_page.dart' show DiaryEditArg;
import 'journal_providers.dart';
import 'widgets/note_sheet_lang.dart';

/// 打开「搜索笔记」半屏。查询走 DAO（标题+正文 LIKE），不另建索引表。
Future<void> showNoteSearchSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (bc) => Padding(
      // 键盘顶起时不遮输入框。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(bc).bottom),
      child: const _NoteSearchBody(),
    ),
  );
}

class _NoteSearchBody extends ConsumerStatefulWidget {
  const _NoteSearchBody();

  @override
  ConsumerState<_NoteSearchBody> createState() => _NoteSearchBodyState();
}

class _NoteSearchBodyState extends ConsumerState<_NoteSearchBody> {
  final _ctl = TextEditingController();
  String _q = '';

  /// 批7 A3（2026-11-08）：最近搜索（本机持久化）。只在输入为空时出现，点即搜、可清空。
  /// 只记「提交过的查询」——点结果行或键盘搜索键，不按每次按键记，避免历史被半截词刷屏。
  static const _histKey = 'note_search_history';
  static const _histMax = 6;
  List<String> _hist = const [];

  @override
  void initState() {
    super.initState();
    _hist = ref.read(sharedPreferencesProvider).getStringList(_histKey) ??
        const <String>[];
  }

  Future<void> _remember(String q) async {
    final v = q.trim();
    if (v.isEmpty) return;
    final list = <String>[v, ..._hist.where((e) => e != v)]
        .take(_histMax)
        .toList();
    await ref.read(sharedPreferencesProvider).setStringList(_histKey, list);
    if (mounted) setState(() => _hist = list);
  }

  Future<void> _clearHist() async {
    await ref.read(sharedPreferencesProvider).remove(_histKey);
    if (mounted) setState(() => _hist = const <String>[]);
  }

  /// UI/UX批（2026-10-12）：日记纳入搜索（原型壳 sheetSearch 全局搜索
  /// SEARCH_DB 本就含「📔 日记」条目与「日记」范围 chip——此批兑现该口径，
  /// 不再只搜笔记）。双源并发查询，结果笔记在前、日记在后。
  /// 思维导图批2（F4-3）：加第三源＝跨图已挂载节点（经 linkage 出口，
  /// journal 不直连 mindmap——R1 合规面），结果排在最后。
  Future<(List<Note>, List<JournalEntry>, List<MmSearchHit>)> _fut =
      Future.value((const <Note>[], const <JournalEntry>[], const <MmSearchHit>[]));

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _run(String raw) {
    final q = raw.trim();
    setState(() {
      _q = q;
      _fut = q.isEmpty
          ? Future.value(
              (const <Note>[], const <JournalEntry>[], const <MmSearchHit>[]))
          : Future(() async => (
                await ref.read(noteDaoProvider).list(query: q),
                await ref.read(journalRepositoryProvider).search(q),
                // 第三源降级口径：导图源不可用（如测试环境 AppDatabase 未开）
                // 只少一路结果，不拖垮笔记/日记主搜。
                await mmSearchMountedNodes(q).catchError((_) => <MmSearchHit>[]),
              ));
    });
  }

  /// 最近搜索行（只在输入为空时出现）：点即搜、可清空。
  Widget _histRow(ColorScheme scheme) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Text('最近',
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final k in _hist) ...[
                  _histChip(k, scheme),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('note-search-hist-clear'),
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: _clearHist,
            child: Text('清空',
                style:
                    TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _histChip(String k, ColorScheme scheme) => InkWell(
        key: ValueKey('note-search-hist-$k'),
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          _ctl.text = k;
          _ctl.selection = TextSelection.collapsed(offset: k.length);
          _run(k);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.onSurface.withValues(alpha: .14)),
          ),
          child: Text(k,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
        ),
      );

  /// 空态（批7 A3）：原来只有一行灰字，半屏显得空。改线性图形 + 一句引导，
  /// 不写教学性说明文案（禁令）；深浅两档都走 scheme，不引硬编码色值。
  Widget _startHint(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest.withValues(alpha: .7)),
            alignment: Alignment.center,
            child: Icon(Icons.search,
                size: 26, color: scheme.onSurfaceVariant.withValues(alpha: .7)),
          ),
          const SizedBox(height: 10),
          Text('搜笔记、日记与导图节点',
              key: const ValueKey('note-search-hint'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const NoteSheetHeader(title: '搜索', sub: '笔记 / 日记 / 导图挂载节点'),
            const SizedBox(height: 10),
            // 批7 A3：原为默认下划线输入（偏轻，与半屏语言不搭）→ 填充圆角，与命名/移动半屏同款。
            TextField(
              key: const ValueKey('note-search-input'),
              controller: _ctl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _run,
              onSubmitted: (v) => _remember(v),
              decoration: InputDecoration(
                hintText: '输入关键词…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: .55),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('note-search-clear'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _ctl.clear();
                          _run('');
                        }),
              ),
            ),
            if (_q.isEmpty && _hist.isNotEmpty) ...[
              const SizedBox(height: 10),
              _histRow(scheme),
            ],
            const SizedBox(height: 10),
            Flexible(
              child: _q.isEmpty
                  ? _startHint(scheme)
                  : FutureBuilder<
                      (List<Note>, List<JournalEntry>, List<MmSearchHit>)>(
                      future: _fut,
                      builder: (c, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))),
                          );
                        }
                        final (notes, diaries, mmHits) = snap.data ??
                            (
                              const <Note>[],
                              const <JournalEntry>[],
                              const <MmSearchHit>[]
                            );
                        if (notes.isEmpty &&
                            diaries.isEmpty &&
                            mmHits.isEmpty) {
                          return Padding(
                            key: const ValueKey('note-search-empty'),
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: Text('没有匹配「$_q」的笔记或日记',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant))),
                          );
                        }
                        return ListView.builder(
                          key: const ValueKey('note-search-list'),
                          shrinkWrap: true,
                          itemCount:
                              notes.length + diaries.length + mmHits.length,
                          itemBuilder: (_, i) {
                            // 笔记在前（原口径不动）；日记行=日期＋预览（篇目无标题列）；
                            // 导图节点行=节点标题 · 图名（命中笔记标题时标来源）。
                            if (i < notes.length) {
                              final n = notes[i];
                              return NoteSheetRow(
                                key: ValueKey('note-search-hit-${n.id}'),
                                icon: Icons.article_outlined,
                                label: n.title.isEmpty ? '未命名笔记' : n.title,
                                onTap: () {
                                  _remember(_q); // 点结果＝一次被采纳的查询，记进最近搜索
                                  // 先取 router 再收屏：pop 后本 context 即失效。
                                  final router = GoRouter.of(context);
                                  Navigator.of(context).pop();
                                  router.push('/note/edit', extra: n.id);
                                },
                              );
                            }
                            if (i < notes.length + diaries.length) {
                              final e = diaries[i - notes.length];
                              String two(int v) =>
                                  v.toString().padLeft(2, '0');
                              return NoteSheetRow(
                                key: ValueKey('diary-search-hit-${e.id}'),
                                icon: Icons.auto_stories_outlined,
                                label:
                                    '${two(e.day.month)}-${two(e.day.day)} '
                                    '${e.content.isEmpty ? '（只打了心情卡）' : e.previewText.replaceAll('\n', ' ')}',
                                onTap: () {
                                  _remember(_q);
                                  final router = GoRouter.of(context);
                                  Navigator.of(context).pop();
                                  router.push('/journal/edit',
                                      extra: DiaryEditArg(entryId: e.id));
                                },
                              );
                            }
                            final h = mmHits[i - notes.length - diaries.length];
                            final src = h.noteTitle;
                            return NoteSheetRow(
                              key: ValueKey('mm-search-hit-${h.nodeId}'),
                              icon: Icons.account_tree_outlined,
                              label: src != null
                                  ? '${h.nodeTitle} · 来自笔记「$src」 · ${h.mapTitle}'
                                  : '${h.nodeTitle} · ${h.mapTitle}',
                              onTap: () {
                                _remember(_q);
                                final router = GoRouter.of(context);
                                Navigator.of(context).pop();
                                router.push('/mindmap/canvas?id=${h.mapId}');
                              },
                            );
                          },
                        );
                      }),
            ),
          ],
        ),
      ),
    );
  }
}
