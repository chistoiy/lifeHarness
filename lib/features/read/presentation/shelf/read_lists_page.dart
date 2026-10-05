import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/book.dart';
import '../../domain/book_list.dart';
import '../../domain/book_quote.dart';
import '../read_providers.dart';
import '../read_sheets.dart';
import '../widgets/bs_cover.dart';

/// 书单列表 + 详情（原型 p-booklists / p-booklist · 计划 §4 批4）。
/// 分享长图 = RepaintBoundary 渲染（验收口径：1080 宽不裁切）；TXT/MD 落文件。

String booklistMd(BookList l, List<Book> ms, Map<String, int> qc) {
  final buf = StringBuffer('# ${l.name}');
  if ((l.note ?? '').isNotEmpty) buf.write('\n\n> ${l.note}');
  buf.write('\n\n| # | 书名 | 作者 | 出版社 | 状态 | 评分 | 摘录 |\n'
      '|---|---|---|---|---|---|---|\n');
  for (var i = 0; i < ms.length; i++) {
    final b = ms[i];
    buf.writeln(
        '| ${i + 1} | ${b.title} | ${b.author} | ${b.publisher ?? '—'} | '
        '${b.state} | ${b.rating > 0 ? b.rating : '—'} | ${qc[b.id] ?? 0} |');
  }
  buf.write(
      '\n共 ${ms.length} 本 · 由 LifeHarness 书架导出 · '
      '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-'
      '${DateTime.now().day.toString().padLeft(2, '0')}\n');
  return buf.toString();
}

String booklistTxt(BookList l, List<Book> ms) {
  final buf = StringBuffer(l.name);
  if ((l.note ?? '').isNotEmpty) buf.write('\n${l.note}');
  buf.write('\n————————————\n');
  for (var i = 0; i < ms.length; i++) {
    final b = ms[i];
    buf.writeln(
        '${i + 1}. ${b.title}　${b.author}　${b.state}'
        '${b.rating > 0 ? '　${b.rating}分' : ''}');
  }
  return buf.toString();
}

// ============================ 书单列表页 ============================

/// 年度书单：无则按 autoYear 生成后进入（原型 blDetailYear 4600）。
Future<void> openYearBooklist(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(readRepositoryProvider);
  final y = DateTime.now().year;
  var l = await repo.findAutoYear(y);
  if (l == null) {
    l = await repo.addList(
      BookList(
        name: '$y 年度书单',
        note: '以 $y 年处于「已读」的书为底稿，之后新增已读会自动进来',
        createdAt: 0,
        updatedAt: 0,
      ),
      autoYear: y,
    );
    ref.read(readTickProvider.notifier).state++;
  }
  if (!context.mounted) return;
  context.push('/read/list/${l.id}');
}

/// 评分显示＝`bsRateLabel`（read_providers.dart · 与选书弹层共用）。

class BookListsPage extends ConsumerWidget {
  const BookListsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final lists = ref.watch(bookListsProvider).valueOrNull ?? const <BookList>[];
    return Scaffold(
      appBar: AppBar(title: const Text('书单')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _entryCard(
                  cs,
                  keyName: 'bl-new-manual',
                  title: '手动创建书单',
                  sub: '把同一主题的书收进一张单子里',
                  onTap: () => showBooklistFormSheet(context, ref),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _entryCard(
                  cs,
                  keyName: 'bl-new-auto',
                  title: '生成年度书单',
                  sub: '以当年「已读」的书自动为底稿',
                  onTap: () =>
                      showBooklistFormSheet(context, ref, autoYear: DateTime.now().year),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的书单',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${lists.length} 个书单 · 可导出图片 / TXT / Markdown',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (lists.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: .4)),
              ),
              child: Text('还没有书单',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),
          for (final l in lists) _listCard(context, ref, cs, tokens, l),
        ],
      ),
    );
  }

  Widget _entryCard(
    ColorScheme cs, {
    required String keyName,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: ValueKey(keyName),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 84,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(sub,
                maxLines: 2,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _listCard(BuildContext context, WidgetRef ref, ColorScheme cs,
      ThemeTokens tokens, BookList l) {
    final members = ref.watch(listMembersProvider(l.id!)).valueOrNull ??
        const <Book>[];
    return GestureDetector(
      key: ValueKey('bl-item-${l.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/read/list/${l.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(l.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                _badge(cs, tokens, l),
                const Spacer(),
                Text('${members.length} 本',
                    style:
                        TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            ),
            if (members.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    for (final b in members.take(8))
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 22,
                            height: 32,
                            child: BsCover(book: b, width: 22, height: 32, radius: 4, showAuthor: false, showBadge: false),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if ((l.note ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.note!,
                    maxLines: 2,
                    style:
                        TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton(
                  key: ValueKey('bl-share-${l.id}'),
                  onPressed: () => showListShareSheet(context, ref, l),
                  child: const Text('分享', style: TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => context.push('/read/list/${l.id}'),
                  child: const Text('查看', style: TextStyle(fontSize: 11.5)),
                ),
                const Spacer(),
                GestureDetector(
                  key: ValueKey('bl-del-${l.id}'),
                  onTap: () async {
                    await ref
                        .read(readRepositoryProvider)
                        .softDeleteList(l.id!);
                    ref.read(readTickProvider.notifier).state++;
                    if (context.mounted) {
                      readToast(context, '已删除书单「${l.name}」· 书籍不受影响');
                    }
                  },
                  child: Text('删除',
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _badge(ColorScheme cs, ThemeTokens tokens, BookList l) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: l.isAuto
          ? tokens.accent.withValues(alpha: .12)
          : cs.surfaceContainerHighest,
    ),
    child: Text(
      l.badge,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: l.isAuto ? tokens.accent : cs.onSurfaceVariant,
      ),
    ),
  );
}

// ============================ 书单详情页 ============================

class BookListDetailPage extends ConsumerWidget {
  const BookListDetailPage({super.key, required this.listId});
  final int listId;

  Future<void> _pick(
      BuildContext context, WidgetRef ref, BookList l, List<Book> ms) async {
    await showBooklistFormSheet(
      context,
      ref,
      editing: l,
      initialIds: ms.map((b) => b.id).toList(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final lists =
        ref.watch(bookListsProvider).valueOrNull ?? const <BookList>[];
    final l = lists.where((x) => x.id == listId).firstOrNull;
    if (l == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书单')),
        body: const Center(child: Text('书单不存在或已删除')),
      );
    }
    final members =
        ref.watch(listMembersProvider(listId)).valueOrNull ?? const <Book>[];
    final quotes =
        ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[];
    final qc = <String, int>{};
    for (final q in quotes) {
      qc[q.bookId] = (qc[q.bookId] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              Flexible(
                child: Text(l.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 6),
              if (l.isAuto) _badge(cs, context.tokens, l),
              const Spacer(),
              Text('${members.length} 本',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
          if ((l.note ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l.note!,
                  style:
                      TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                key: const ValueKey('bld-share'),
                onPressed: () => showListShareSheet(context, ref, l),
                child: const Text('生成分享图', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('bld-md'),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: booklistMd(l, members, qc)));
                  if (context.mounted) {
                    readToast(context, 'Markdown 已复制到剪贴板');
                  }
                },
                child: const Text('复制 Markdown',
                    style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('bld-txt'),
                onPressed: () async {
                  final dir = await getApplicationDocumentsDirectory();
                  final f = File(
                      '${dir.path}${Platform.pathSeparator}share${Platform.pathSeparator}${l.name}.txt');
                  await f.parent.create(recursive: true);
                  await f.writeAsString(booklistTxt(l, members));
                  if (context.mounted) {
                    readToast(context, 'TXT 已导出到 ${f.path}');
                  }
                },
                child: const Text('下载 TXT', style: TextStyle(fontSize: 11.5)),
              ),
              if (!l.isAuto) ...[
                const Spacer(),
                OutlinedButton(
                  key: const ValueKey('bld-pick'),
                  onPressed: () => _pick(context, ref, l, members),
                  child: const Text('选书', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (members.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: .4)),
              ),
              child: Text(
                l.isAuto ? '今年还没有读完的书 · 标为已读会自动进来' : '书单还是空的 · 点「选书」开始收集',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          for (final (i, b) in members.indexed)
            Container(
              key: ValueKey('blm-${b.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: .4)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurfaceVariant)),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/read/book/${b.id}'),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: SizedBox(
                            width: 28,
                            height: 40,
                            child: BsCover(book: b, width: 28, height: 40, radius: 5, showAuthor: false, showBadge: false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 190,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800)),
                              Text(
                                // 原型 5354：作者 · 状态 · 评分 · N 条摘录。
                                '${b.author} · ${b.state}'
                                '${bsRateLabel(b.rating).isEmpty ? '' : ' · ${bsRateLabel(b.rating)}'}'
                                ' · ${qc[b.id] ?? 0} 条摘录',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (!l.isAuto)
                    GestureDetector(
                      key: ValueKey('blm-rm-${b.id}'),
                      onTap: () async {
                        await ref
                            .read(readRepositoryProvider)
                            .removeBookFromList(listId, b.id);
                        ref.read(readTickProvider.notifier).state++;
                        if (context.mounted) {
                          readToast(context, '已移出书单（书本身保留）');
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text('移出',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================ 分享书单（原型 sheetListShare 1014-1030） ============================

Future<void> showListShareSheet(
  BuildContext context,
  WidgetRef ref,
  BookList l,
) async {
  final repo = ref.read(readRepositoryProvider);
  final members = await repo.listMembers(l,
      desc: ((await repo.kv('read.yearSort')) ?? '') == '降序');
  final quotes = await repo.allQuotes();
  final qc = <String, int>{};
  for (final q in quotes) {
    qc[q.bookId] = (qc[q.bookId] ?? 0) + 1;
  }
  if (!context.mounted) return;
  final boundaryKey = GlobalKey();
  Future<String> writeFileAt(String name, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}share${Platform.pathSeparator}$name');
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
    return f.path;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) {
      final cs = Theme.of(bc).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('分享书单',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text('${l.name} · ${members.length} 本',
                    style: TextStyle(
                        fontSize: 10.5, color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: ShareLongImage(
                        list: l, members: members, qc: qc),
                  ),
                ),
                const SizedBox(height: 12),
                // 原型 1022-1027：2×2 四钮（保存为图片 / 复制 Markdown / 下载 TXT / 下载 .md）。
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('bls-img'),
                        onPressed: () async {
                          final ro =
                              boundaryKey.currentContext?.findRenderObject();
                          if (ro is! RenderRepaintBoundary) return;
                          // 640 逻辑宽 × 1.6875 ≈ 1080 物理宽（验收：1080 宽不裁切）。
                          final img = await ro.toImage(pixelRatio: 1080 / 640);
                          final bytes = await img.toByteData(
                              format: ui.ImageByteFormat.png);
                          final dir =
                              await getApplicationDocumentsDirectory();
                          final f = File(
                              '${dir.path}${Platform.pathSeparator}share${Platform.pathSeparator}${l.name}.png');
                          await f.parent.create(recursive: true);
                          await f.writeAsBytes(bytes!.buffer.asUint8List());
                          if (bc.mounted) Navigator.of(bc).pop();
                          if (context.mounted) {
                            readToast(context, '分享长图已保存：${f.path}');
                          }
                        },
                        child: const Text('保存为图片'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('bls-md'),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(
                                  text: booklistMd(l, members, qc)));
                          if (bc.mounted) {
                            readToast(bc, 'Markdown 已复制到剪贴板');
                          }
                        },
                        child: const Text('复制 Markdown',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('bls-txt'),
                        onPressed: () async {
                          // .md 与 TXT 同物双钮按原型，实现同函数分后缀。
                          await writeFileAt(
                              '${l.name}.txt', booklistTxt(l, members));
                          if (bc.mounted) {
                            readToast(bc, '已下载 ${l.name}.txt');
                          }
                        },
                        child: const Text('下载 TXT',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('bls-mdfile'),
                        onPressed: () async {
                          await writeFileAt(
                              '${l.name}.md', booklistMd(l, members, qc));
                          if (bc.mounted) {
                            readToast(bc, '已下载 ${l.name}.md');
                          }
                        },
                        child: const Text('下载 .md',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                // 原型 1028 脚注逐字。
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '图片在前端即时绘制（canvas）· 长图适合发群/朋友圈；'
                    'TXT 与 Markdown 便于贴进笔记或电子书店书单页',
                    style: TextStyle(
                        fontSize: 10,
                        height: 1.6,
                        color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 长图内容（原型 blDraw 版式：品牌行 / 标题 / 副行 / 书行 / 页脚）。
class ShareLongImage extends StatelessWidget {
  const ShareLongImage({
    super.key,
    required this.list,
    required this.members,
    required this.qc,
  });
  final BookList list;
  final List<Book> members;
  final Map<String, int> qc;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: const ValueKey('bls-img'),
      width: 640,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.accent.withValues(alpha: .07),
            const Color(0xFFF8FAFC),
          ],
        ),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIFEHARNESS · 我的书架',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: tokens.accent),
          ),
          const SizedBox(height: 10),
          Text(list.name,
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
          const SizedBox(height: 6),
          Text(
            '${(list.note ?? '').length > 30 ? '${(list.note ?? '').substring(0, 30)} · ' : (list.note ?? '')}${members.length} 本 · ${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),
          for (final (i, b) in members.indexed)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 50,
                      height: 64,
                      child: BsCover(book: b, width: 50, height: 64, radius: 6, showAuthor: false, showBadge: false),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${b.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A))),
                        const SizedBox(height: 4),
                        Text(
                          [
                            b.author,
                            if ((b.publisher ?? '').isNotEmpty) b.publisher!,
                            b.state,
                            if (b.rating > 0) '${b.rating} 分',
                            '${qc[b.id] ?? 0} 条摘录',
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            '本地优先的个人生活记录 · 数据只存在我自己的设备上',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}
