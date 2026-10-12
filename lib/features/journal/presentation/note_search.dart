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

  /// UI/UX批（2026-10-12）：日记纳入搜索（原型壳 sheetSearch 全局搜索
  /// SEARCH_DB 本就含「📔 日记」条目与「日记」范围 chip——此批兑现该口径，
  /// 不再只搜笔记）。双源并发查询，结果笔记在前、日记在后。
  Future<(List<Note>, List<JournalEntry>)> _fut =
      Future.value((const <Note>[], const <JournalEntry>[]));

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
          ? Future.value((const <Note>[], const <JournalEntry>[]))
          : Future(() async => (
                await ref.read(noteDaoProvider).list(query: q),
                await ref.read(journalRepositoryProvider).search(q),
              ));
    });
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
            const NoteSheetHeader(title: '搜索', sub: '笔记与日记 · 标题/正文/分节同时匹配'),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('note-search-input'),
              controller: _ctl,
              autofocus: true,
              onChanged: _run,
              decoration: InputDecoration(
                hintText: '输入关键词…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
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
            const SizedBox(height: 10),
            Flexible(
              child: _q.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Text('输入关键词开始搜索',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant))),
                    )
                  : FutureBuilder<(List<Note>, List<JournalEntry>)>(
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
                        final (notes, diaries) =
                            snap.data ?? (const <Note>[], const <JournalEntry>[]);
                        if (notes.isEmpty && diaries.isEmpty) {
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
                          itemCount: notes.length + diaries.length,
                          itemBuilder: (_, i) {
                            // 笔记在前（原口径不动）；日记行=日期＋预览（篇目无标题列）。
                            if (i < notes.length) {
                              final n = notes[i];
                              return NoteSheetRow(
                                key: ValueKey('note-search-hit-${n.id}'),
                                icon: Icons.article_outlined,
                                label: n.title.isEmpty ? '未命名笔记' : n.title,
                                onTap: () {
                                  // 先取 router 再收屏：pop 后本 context 即失效。
                                  final router = GoRouter.of(context);
                                  Navigator.of(context).pop();
                                  router.push('/note/edit', extra: n.id);
                                },
                              );
                            }
                            final e = diaries[i - notes.length];
                            String two(int v) => v.toString().padLeft(2, '0');
                            return NoteSheetRow(
                              key: ValueKey('diary-search-hit-${e.id}'),
                              icon: Icons.auto_stories_outlined,
                              label: '${two(e.day.month)}-${two(e.day.day)} '
                                  '${e.content.isEmpty ? '（只打了心情卡）' : e.previewText.replaceAll('\n', ' ')}',
                              onTap: () {
                                final router = GoRouter.of(context);
                                Navigator.of(context).pop();
                                router.push('/journal/edit',
                                    extra: DiaryEditArg(entryId: e.id));
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
