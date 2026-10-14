import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/ai/ai_review.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/book.dart';
import '../../domain/book_quote.dart';
import '../read_providers.dart';
import '../read_sheets.dart';
import '../widgets/bs_cover.dart';

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
  // 批4-C「AI 感想生成」：页面原无多选态 → 新增长按多选（偏差已登记）。
  final Set<int> _sel = {};

  void _toggleSel(BookQuote q) {
    final id = q.id;
    if (id == null) return;
    setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));
  }

  String _fmtDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final s = '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return d.year == now.year ? s : '${d.year}-$s';
  }

  List<BookQuote> _filtered(
    List<BookQuote> all,
    String curBook,
    Map<String, Book> byId,
  ) {
    final kwL = _kw.toLowerCase();
    return all.where((q) {
      if (_tg != null && q.tag != _tg) return false;
      if (_scope == 'cur' && q.bookId != curBook) return false;
      if (_scope == 'fav' && !q.starred) return false;
      if (kwL.isEmpty) return true;
      // 原型 4845：搜索命中 原文 + 想法 + 书名。
      final title = (byId[q.bookId]?.title ?? '').toLowerCase();
      return q.body.toLowerCase().contains(kwL) ||
          (q.thought?.toLowerCase().contains(kwL) ?? false) ||
          title.contains(kwL);
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
    final list = _filtered(all, curBook, byId);
    final thN = all.where((q) => q.kind == BookQuote.kKindThought).length;

    return Scaffold(
      appBar: AppBar(title: const Text('笔记库')), // 轮5：标题居中
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
          // 原型 865-868：搜索框同行＝复习渐变钮 + 「+」记摘录钮。
          Row(
            children: [
              Expanded(
                child: TextField(
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
              ),
              const SizedBox(width: 8),
              GestureDetector(
                key: const ValueKey('ql-review'),
                onTap: () => showReviewSheet(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [tokens.accent, tokens.accentLight],
                    ),
                  ),
                  child: const Text(
                    '复习',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                key: const ValueKey('ql-add'),
                tooltip: '记摘录',
                onPressed: () => showQuoteSheet(context, ref),
                icon: const Icon(BsIcons.add, size: 18),
              ),
            ],
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
          const SizedBox(height: 14),
          _exportCard(cs, tokens, all, byId),
        ],
      ),
    );
  }

  /// 「导出与分享」整卡（原型 876-884 · 导出 MD 接真库，B 类占位按口径 toast）。
  Widget _exportCard(
    ColorScheme cs,
    ThemeTokens tokens,
    List<BookQuote> all,
    Map<String, Book> byId,
  ) {
    final markN =
        all.where((q) => q.kind == BookQuote.kKindMark).length;
    final thN = all.length - markN;
    return Container(
      key: const ValueKey('ql-export'),
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
              const Expanded(
                child: Text(
                  '导出与分享',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '联动 L5',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniBtn(
                keyName: 'qlx-md',
                label: '导出 MD',
                onTap: () => _exportMd(markN, thN),
              ),
              _miniBtn(
                keyName: 'qlx-card',
                label: '书摘卡片',
                onTap: () => readToast(context, '图片卡片规划中（V1.x）'),
              ),
              _miniBtn(
                keyName: 'qlx-todo',
                label: '摘录 → 待办',
                onTap: () => readToast(
                  context,
                  '逐条点摘录卡「→待办」生成（联动 L5）',
                ),
              ),
              _miniBtn(
                keyName: 'qlx-ai',
                label: 'AI 感想生成',
                onTap: () => _aiInsights(all, byId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportMd(int markN, int thN) async {
    // 轮5：真机「点了没反应」——点击即回反馈，异常也要说出来。
    readToast(context, '导出中…');
    try {
      final repo = ref.read(readRepositoryProvider);
      final txt = await repo.buildQuotesMd();
      final dir = await getApplicationDocumentsDirectory();
      final f = File(p.join(dir.path, 'share', '全部书摘.md'));
      await f.parent.create(recursive: true);
      await f.writeAsString(txt);
      if (!mounted) return;
      readToast(
        context,
        '已导出 Markdown：$markN 条摘录 + $thN 条感想 · 按书名分章 · ${f.path}',
      );
    } catch (e) {
      if (mounted) readToast(context, '导出失败：$e');
    }
  }

  /// 批4-C「AI 感想生成」：对长按多选的摘录逐条（单次 ≤3）走
  /// read.quote_insight → 审阅弹层 → aiConfirmWrite 确认 → 写入该条 [BookQuote.thought]
  /// 感想字段（既有独立字段，不覆盖用户原文：已有感想则换行追加；
  /// AI tags 并入 [BookQuote.tags] 多选标签）。未选中只提示、不发起。
  Future<void> _aiInsights(
    List<BookQuote> all,
    Map<String, Book> byId,
  ) async {
    final picked = all
        .where((q) => q.id != null && _sel.contains(q.id) && q.deletedAt == null)
        .toList();
    if (picked.isEmpty) {
      readToast(context, '先长按选择要生成感想的摘录');
      return;
    }
    final batch = picked.take(3).toList();
    final repo = ref.read(readRepositoryProvider);
    var done = 0;
    for (final q in batch) {
      if (!mounted) return; // 上一轮 await 后页面可能已销毁
      final bookTitle = byId[q.bookId]?.title ?? '';
      final res = await aiRunWithReview(
        context,
        ref,
        taskId: 'read.quote_insight',
        vars: {'quote': q.body, 'book': bookTitle},
      );
      if (res == null) return; // 用户取消或失败（失败已 toast 归因）
      if (!mounted) return;
      final j = res.requireJson();
      final insight = '${j['insight'] ?? ''}'.trim();
      if (insight.isEmpty) continue;
      final rawTags = j['tags'];
      final aiTags = rawTags is List
          ? rawTags.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
          : const <String>[];
      final ok = await aiConfirmWrite(
        context,
        title: '写入摘录感想${bookTitle.isEmpty ? '' : ' · 《$bookTitle》'}',
        preview: aiTags.isEmpty
            ? insight
            : '$insight\n标签：${aiTags.join('、')}',
      );
      if (!ok || !mounted) continue;
      final old = (q.thought ?? '').trim();
      final mergedTags = <String>[
        ...q.tags,
        for (final t in aiTags)
          if (!q.tags.contains(t)) t,
      ];
      await repo.updateQuote(
        q.copyWith(
          thought: old.isEmpty ? insight : '$old\n$insight',
          tags: mergedTags,
        ),
      );
      _sel.remove(q.id);
      done++;
    }
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    setState(() {});
    readToast(
      context,
      done == 0
          ? '未写入感想 · 可重试'
          : '已生成 $done 条感想${picked.length > 3 ? '（单次最多 3 条，其余请再点一次）' : ''}',
    );
  }

  Widget _miniBtn({
    required String keyName,
    required String label,
    required VoidCallback onTap,
    Color? tone,
  }) {
    return GestureDetector(
      key: ValueKey(keyName),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: (tone ?? context.tokens.accent).withValues(alpha: .12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: tone ?? context.tokens.accent,
          ),
        ),
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()], // F3-5 等宽读数
            ),
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
    final sel = q.id != null && _sel.contains(q.id);
    return GestureDetector(
      key: ValueKey('ql-q-${q.id}'),
      behavior: HitTestBehavior.opaque,
      // 原型 4854：点卡片直接进编辑表单（操作弹层保留在书籍详情页入口）。
      onTap: () => showQuoteEditPage(context, ref, editing: q),
      // 批4-C：长按＝切换多选（AI 感想生成入口的选中态）。
      onLongPress: () => _toggleSel(q),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? accent : cs.outlineVariant.withValues(alpha: .4),
            width: sel ? 1.6 : 1,
          ),
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
                      // read.fullCh（§6）：完整显示章节名＝过长换行不截断。
                      maxLines:
                          (ref.watch(readKvProvider(('read.fullCh', 'false')))
                                          .valueOrNull ??
                                      'false') ==
                                  'true'
                              ? null
                              : 1,
                      overflow:
                          (ref.watch(readKvProvider(('read.fullCh', 'false')))
                                          .valueOrNull ??
                                      'false') ==
                                  'true'
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
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
              // 原型 4856：划线＝「原文」；感想卡正文前加「想法：」前缀。
              q.kind == BookQuote.kKindMark ? '「${q.body}」' : '想法：${q.body}',
              // read.qtLines<4 才截断（=4 不截 · 原型 4856 条件）。
              maxLines: lines < 4 ? lines : null,
              overflow: lines < 4 ? TextOverflow.ellipsis : TextOverflow.visible,
              style: kFontBody.apply(TextStyle(
                fontSize: 12.5,
                height: 1.75,
                fontWeight: q.thought == null ? FontWeight.w500 : FontWeight.w600,
              )),
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
                  style: kFontBody.apply(TextStyle(
                      fontSize: 11.5, height: 1.6, color: cs.onSurfaceVariant)),
                ),
              ),
            // 原型 4859：卡内快捷行 →日记 →待办 →笔记 标星。
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  TextButton(
                    key: ValueKey('qlq-diary-${q.id}'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _quickAct(q, b, 0),
                    child: const Text('→日记', style: TextStyle(fontSize: 10.5)),
                  ),
                  TextButton(
                    key: ValueKey('qlq-todo-${q.id}'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(44, 44), // F3-8 热区
                    ),
                    onPressed: () => _quickAct(q, b, 1),
                    child: const Text('→待办', style: TextStyle(fontSize: 10.5)),
                  ),
                  TextButton(
                    key: ValueKey('qlq-note-${q.id}'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(44, 44), // F3-8 热区
                    ),
                    onPressed: () => _quickAct(q, b, 2),
                    child: const Text('→笔记', style: TextStyle(fontSize: 10.5)),
                  ),
                  // V1.46④（真机反馈「笔记库的内容没办法删除」）：卡内直显
                  // 删除（软删＋SnackBar 撤销），与原型 qtDel 同位。
                  TextButton(
                    key: ValueKey('qlq-del-${q.id}'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(44, 44), // F3-8 热区
                      foregroundColor: const Color(0xFFEF4444),
                    ),
                    onPressed: q.id == null ? null : () => _delQuote(q),
                    child: const Text('删除', style: TextStyle(fontSize: 10.5)),
                  ),
                  const Spacer(),
                  if (sel)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: context.tokens.accent, // F3-3 收 accent
                      ),
                    ),
                  GestureDetector(
                    key: ValueKey('qlq-star-${q.id}'),
                    onTap: () => _quickAct(q, b, 3),
                    // F3-8：命中槽高 44（文字视觉不变，水平留 8 命中余量）。
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        q.starred ? '取消标星' : '标星',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: q.starred
                              ? const Color(0xFFF59E0B)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// V1.46④：卡内删除＝软删 + SnackBar 撤销（无二次弹层，撤销即恢复；
  /// 与全 app「删除可撤销」纪律一致，见 log/物品批同款）。
  /// T4（交互整改批一）：改走 AppToast.showUndo——带撤销的条排他存续，
  /// 且显式 persist:false 不再永挂（框架默认 action != null 即永挂）。
  Future<void> _delQuote(BookQuote q) async {
    final repo = ref.read(readRepositoryProvider);
    await repo.softDeleteQuote(q.id!);
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    AppToast.showUndo(
      context,
      '已删除这条记录',
      ms: 4000,
      onUndo: () async {
        await repo.restoreQuote(q.id!);
        if (!mounted) return;
        ref.read(readTickProvider.notifier).state++;
      },
    );
  }

  /// 卡内快捷动作（复用 b3 的 quoteToDiary/quoteToTodo/quoteToNote/setStarred 链路）。
  Future<void> _quickAct(BookQuote q, Book? b, int to) async {
    if (q.id == null) return;
    final repo = ref.read(readRepositoryProvider);
    if (to == 3) {
      await repo.setQuoteStarred(q.id!, !q.starred);
    } else {
      if (b == null) return;
      switch (to) {
        case 0:
          await repo.quoteToDiary(q, b);
        case 1:
          await repo.quoteToTodo(q, b);
        default:
          await repo.quoteToNote(q, b);
      }
    }
    ref.read(readTickProvider.notifier).state++;
    if (!mounted) return;
    switch (to) {
      case 0:
        readToast(context, '已插入今日日记草稿（联动 L5）');
      case 1:
        readToast(context, '已生成待办（联动 L5）');
      case 2:
        readToast(context, '已转存为笔记 · 入「摘录」文件夹');
      default:
        break;
    }
  }

  Widget _row(BookQuote q, Map<String, Book> byId, ColorScheme cs) {
    final b = byId[q.bookId];
    final sel = q.id != null && _sel.contains(q.id);
    return GestureDetector(
      key: ValueKey('qlr-${q.id}'),
      behavior: HitTestBehavior.opaque,
      // 原型 4861：行视图点行同样直接进编辑表单。
      onTap: () => showQuoteEditPage(context, ref, editing: q),
      // 批4-C：行视图同样长按多选。
      onLongPress: () => _toggleSel(q),
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
                  color: sel
                      ? context.tokens.accent
                      : Color(0xFF000000 | q.colorInt),
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
            if (sel)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: context.tokens.accent, // F3-3 收 accent
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
  /// 原型 4873：无图时整墙回退全量 + 底部提示行。
  Widget _imgWall(List<BookQuote> list, Map<String, Book> byId, ColorScheme cs, int cols) {
    final withImg = list.where((q) => q.imagePaths.isNotEmpty).toList();
    final src = withImg.isEmpty ? list : withImg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
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
                // 原型 4873：图片墙点格进编辑表单。
                onTap: () => showQuoteEditPage(context, ref, editing: q),
                // 批4-C：图片墙格同样长按多选。
                onLongPress: () => _toggleSel(q),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: q.id != null && _sel.contains(q.id)
                          ? context.tokens.accent
                          : cs.outlineVariant.withValues(alpha: .4),
                      width: q.id != null && _sel.contains(q.id) ? 2 : 1,
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
        ),
        if (withImg.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: EmptyDashRow(
              key: ValueKey('qlim-hint'),
              text: '还没有带图片的摘录 · 记摘录时点「加图片」',
            ),
          ),
      ],
    );
  }

  /// 图片墙无图色板格子（书色板渐变 + 「文字卡」角标）。
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
}
