import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/book_quote.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'widgets/bs_cover.dart';

/// 笔记库（原型 p-quotes · §3.4：三统计 + 搜索 + 复习 + 标签/范围筛选 +
/// 四视图 卡片·行·按章节·图片墙）。跨书只做视图层聚合，不改归属（§9 已拍板②）。
class QuotesLibPage extends ConsumerStatefulWidget {
  const QuotesLibPage({super.key, this.bookId});

  /// 入口带书时「本书」范围以此为准（详情页 → 笔记库）。
  final String? bookId;

  @override
  ConsumerState<QuotesLibPage> createState() => _QuotesLibPageState();
}

class _QuotesLibPageState extends ConsumerState<QuotesLibPage> {
  static const _views = ['card', 'line', 'chap', 'img'];
  static const _viewNames = ['卡片视图', '紧凑行视图', '按章节分组', '图片墙'];

  String _kw = '';
  String? _tg; // 划线颜色分类（全部＝null）
  String _scope = 'all'; // all / cur / fav
  int _view = 0;

  String _fmtDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final s = '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return d.year == now.year ? s : '${d.year}-$s';
  }

  List<BookQuote> _filtered(List<BookQuote> all, String curBook) {
    final kwL = _kw.toLowerCase();
    return all.where((q) {
      if (_tg != null && q.tag != _tg) return false;
      if (_scope == 'cur' && q.bookId != curBook) return false;
      if (_scope == 'fav' && !q.starred) return false;
      if (kwL.isEmpty) return true;
      return q.body.toLowerCase().contains(kwL) ||
          (q.thought?.toLowerCase().contains(kwL) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final books =
        (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
            .where((b) => !b.isDeleted)
            .toList();
    final all = ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[];
    final byId = {for (final b in books) b.id: b};
    final curBook =
        widget.bookId ??
        ShelfSort.byLastRead(
          books.where((b) => b.state == Book.kStateReading).toList(),
        ).firstOrNull?.id ??
        books.firstOrNull?.id ??
        '';
    // 展示口径设置（批5 阅读设置全键生效；此处先按默认值渲染）。
    String kv(String key, String def) =>
        ref.watch(readKvProvider((key, def))).valueOrNull ?? def;
    final qtLines = kv('read.qtLines', '3');
    final simple = kv('read.simple', 'false') == 'true';
    final imgCols = int.tryParse(kv('read.imgCols', '5')) ?? 5;
    final list = _filtered(all, curBook);
    final thN = all.where((q) => q.kind == BookQuote.kKindThought).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记库'),
        actions: [
          IconButton(
            key: const ValueKey('ql-review'),
            icon: const Icon(BsIcons.think, size: 20),
            tooltip: '复习',
            onPressed: () => showReviewSheet(context, ref),
          ),
          IconButton(
            key: const ValueKey('ql-add'),
            icon: const Icon(BsIcons.add, size: 20),
            tooltip: '记摘录',
            onPressed: () => showQuoteSheet(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // 三统计：摘录（划线）/ 感想 / 覆盖本书
          Row(
            children: [
              _stat(cs, '${all.length - thN}', '摘录'),
              const SizedBox(width: 8),
              _stat(cs, '$thN', '感想'),
              const SizedBox(width: 8),
              _stat(cs, '${all.map((q) => q.bookId).toSet().length}', '覆盖'),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('ql-kw'),
            onChanged: (v) => setState(() => _kw = v),
            decoration: InputDecoration(
              hintText: '搜索全部摘录与感想',
              hintStyle: const TextStyle(fontSize: 12.5),
              prefixIcon: const Icon(BsIcons.search, size: 18),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          // 颜色分类 chips（全部 + 五色）
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _tgChip(cs, tokens, null, '全部'),
                for (final t in BookQuote.colorTags) _tgChip(cs, tokens, t, t),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  key: const ValueKey('ql-scope'),
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('全部书')),
                    ButtonSegment(value: 'cur', label: Text('本书')),
                    ButtonSegment(value: 'fav', label: Text('标星')),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) =>
                      setState(() => _scope = s.first),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                key: const ValueKey('ql-view'),
                tooltip: _viewNames[_view],
                onPressed: () {
                  setState(() => _view = (_view + 1) % _views.length);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(_viewNames[_view]),
                        duration: const Duration(milliseconds: 900),
                      ),
                    );
                },
                icon: Icon(switch (_views[_view]) {
                  'card' => BsIcons.view,
                  'line' => BsIcons.list,
                  'chap' => BsIcons.toc,
                  _ => Icons.photo_library_outlined,
                }, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .4),
                ),
              ),
              child: Text(
                '没有匹配的摘录',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            )
          else
            switch (_views[_view]) {
              'card' => Column(
                children: [
                  for (final q in list) _card(q, byId, cs, simple, qtLines),
                ],
              ),
              'line' => Column(
                children: [
                  for (final q in list) _row(q, byId, cs),
                ],
              ),
              'chap' => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _chapGroups(list, byId, cs, simple, qtLines),
              ),
              _ => _imgWall(list, byId, cs, imgCols),
            },
        ],
      ),
    );
  }

  Widget _stat(ColorScheme cs, String v, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Column(
        children: [
          Text(
            v,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );

  Widget _tgChip(
    ColorScheme cs,
    ThemeTokens tokens,
    String? tg,
    String label,
  ) {
    final on = _tg == tg;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        key: ValueKey('ql-tg-${tg ?? 'all'}'),
        onTap: () => setState(() => _tg = tg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: on
                ? tokens.accent.withValues(alpha: .12)
                : cs.surfaceContainerHighest,
            border: Border.all(
              color: on ? tokens.accent : cs.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tg != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF000000 | int.parse(
                      BookQuote.colorHex[tg]!,
                      radix: 16,
                    )),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: on ? tokens.accent : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(
    BookQuote q,
    Map<String, Book> byId,
    ColorScheme cs,
    bool simple,
    String qtLines,
  ) {
    final b = byId[q.bookId];
    final color = Color(0xFF000000 | q.colorInt);
    final accent = context.tokens.accent;
    final lines = int.tryParse(qtLines) ?? 3;
    return GestureDetector(
      key: ValueKey('ql-q-${q.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showQuoteOpsSheet(context, ref, q),
      child: Container(
        width: double.infinity,
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
            if (!simple)
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    q.tag,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '· ${b?.title ?? ''} · ${q.chapter ?? '未分章'}'
                      '${q.page == null ? '' : ' · P${q.page}'} · ${_fmtDate(q.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ),
                  for (final t in q.tags)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        '#$t',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  if (q.starred)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              q.kind == BookQuote.kKindMark ? '「${q.body}」' : q.body,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.75,
                fontWeight: q.thought == null ? FontWeight.w500 : FontWeight.w600,
              ),
            ),
            if (q.imagePaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(q.imagePaths.first),
                    height: 80,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
              ),
            if (q.thought != null && q.kind == BookQuote.kKindMark)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '想法：${q.thought}',
                  style: TextStyle(fontSize: 11.5, height: 1.6, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BookQuote q, Map<String, Book> byId, ColorScheme cs) {
    final b = byId[q.bookId];
    return GestureDetector(
      key: ValueKey('qlr-${q.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showQuoteOpsSheet(context, ref, q),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .35)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF000000 | q.colorInt),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.kind == BookQuote.kKindMark ? '「${q.body}」' : q.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${b?.title ?? ''} · ${q.chapter ?? '未分章'} · ${_fmtDate(q.createdAt)}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (q.starred)
              const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
          ],
        ),
      ),
    );
  }

  /// 按章节分组：书名 · 章节（或 未分章）。分组 item key 带组前缀（批1 测试坑）。
  List<Widget> _chapGroups(
    List<BookQuote> list,
    Map<String, Book> byId,
    ColorScheme cs,
    bool simple,
    String qtLines,
  ) {
    final groups = <String, List<BookQuote>>{};
    for (final q in list) {
      final k = '${byId[q.bookId]?.title ?? ''} · ${q.chapter ?? '未分章'}';
      (groups[k] ??= []).add(q);
    }
    return [
      for (final e in groups.entries) ...[
        Padding(
          key: ValueKey('qlg-${e.value.first.id}'),
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.key,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${e.value.length} 条',
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        for (final q in e.value) _card(q, byId, cs, simple, qtLines),
      ],
    ];
  }

  /// 图片墙无图兜底：书色板渐变 + 「文字卡」角标（原型 qtImgWall）。
  Widget _palCell(Book? b, ColorScheme cs) {
    final pal = kBsCov[(b?.paletteIdx ?? 0) % kBsCov.length];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.$1, pal.$2],
        ),
      ),
      alignment: Alignment.bottomCenter,
      child: b == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '文字卡',
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.white.withValues(alpha: .7),
                ),
              ),
            ),
    );
  }

  Widget _imgWall(List<BookQuote> list, Map<String, Book> byId, ColorScheme cs, int cols) {
    final withImg = list.where((q) => q.imagePaths.isNotEmpty).toList();
    final src = withImg.isEmpty ? list : withImg;
    return GridView.count(
      crossAxisCount: cols.clamp(1, 5),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: .62,
      children: [
        for (final q in src)
          GestureDetector(
            key: ValueKey('qli-${q.id}'),
            onTap: () => showQuoteOpsSheet(context, ref, q),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .4),
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: q.imagePaths.isNotEmpty
                        ? Image.file(
                            File(q.imagePaths.first),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          )
                        : _palCell(byId[q.bookId], cs),
                  ),
                  SizedBox(
                    height: 40,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Text(
                        q.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 8.5, height: 1.3, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
