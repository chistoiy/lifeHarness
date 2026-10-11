/// 批5①（工单 §2 · 2026-10-12）·**笔记搜索**（原顶栏搜索钮只弹
/// 「全局搜索 · 即将开放」＝看得见点不通的僵尸钮）。
///
/// 基建其实早在：`NoteDao.list(query:)` 已是 `title LIKE ? OR content LIKE ?`
/// （见 note_dao.dart），缺的只是一个入口——故本批是「兑现」而非「新建能力」。
/// 形态＝搜索半屏：输入即时过滤（DAO 侧 LIKE），点结果收屏跳编辑页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/note.dart';
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
  Future<List<Note>> _fut = Future.value(const <Note>[]);

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
          ? Future.value(const <Note>[])
          : ref.read(noteDaoProvider).list(query: q);
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
            const NoteSheetHeader(title: '搜索笔记', sub: '标题与正文同时匹配'),
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
                  : FutureBuilder<List<Note>>(
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
                        final hits = snap.data ?? const <Note>[];
                        if (hits.isEmpty) {
                          return Padding(
                            key: const ValueKey('note-search-empty'),
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: Text('没有匹配「$_q」的笔记',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant))),
                          );
                        }
                        return ListView.builder(
                          key: const ValueKey('note-search-list'),
                          shrinkWrap: true,
                          itemCount: hits.length,
                          itemBuilder: (_, i) {
                            final n = hits[i];
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
