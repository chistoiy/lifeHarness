import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/ai_review.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/book.dart';
import '../../domain/book_quote.dart';
import '../../domain/book_toc.dart';
import '../reader/epub_state_ui.dart';
import '../read_actions.dart';
import '../read_providers.dart';
import '../read_sheets.dart';
import '../widgets/bs_cover.dart';

/// 二级页参数（tab: c=目录 q=书摘 r=相关）。
class BookDetailArg {
  const BookDetailArg({this.tab = 'c'});
  final String tab;
}

/// 详情页 = 沉浸阅读视图（原型 p-bookDetail · §3.2 拆两屏之阅读屏）。
/// 批2 接：可点信息芯片（计时明细/记进度）、封面→书籍资料页、
/// 目录两级卡（只读 + 编辑就地微调 + 粘贴导入）、顶栏计时按 timerUI 分流。
class BookDetailPage extends ConsumerStatefulWidget {
  const BookDetailPage({
    super.key,
    required this.bookId,
    this.initialTab = 'c',
  });
  final String bookId;
  final String initialTab;

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  late String _tab = widget.initialTab;
  bool _tocEdit = false;
  bool _tocOpen = false; // 轮3：目录列表默认收起（展开钮 toc-fold）
  // 轮3：已收起的部分章节（key＝part id 字符串）。
  final Set<String> _tocPartFold = {};
  String? _chapF; // 书摘按章节筛选（点目录节跳入）
  String _qSeg = 'all'; // 书摘 tab 分段 chips（原型 bdQSeg · 全部/划线/想法/星标）

  Map<String, ({int minutes, int times})> get agg =>
      ref.watch(workbenchProvider).valueOrNull?.agg ?? const {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final b = books.where((e) => e.id == widget.bookId).firstOrNull;
    if (b == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书籍')),
        body: const SizedBox.shrink(),
      );
    }
    final allQ =
        (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])
            .where((q) => q.bookId == b.id && q.deletedAt == null)
            .toList();
    final byChap = _chapF == null
        ? allQ
        : allQ.where((q) => (q.chapter ?? '未分章') == _chapF).toList();
    final quotes = switch (_qSeg) {
      'line' => byChap.where((q) => q.kind == BookQuote.kKindMark).toList(),
      'think' => byChap.where((q) => q.kind == BookQuote.kKindThought).toList(),
      'star' => byChap.where((q) => q.starred).toList(),
      _ => byChap,
    };
    final relGroups = _relGroups(b, books);
    final running = ref.watch(runningSessionProvider).valueOrNull;
    final onTimer = running != null && running.bookId == b.id;
    final pal = kBsCov[b.paletteIdx];

    return Scaffold(
      // 真机验收轮1：详情页右下「＋记摘录」FAB（原型 FAB_CFG p-bookDetail 5898）。
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('bd-quote-fab'),
        tooltip: '记摘录',
        onPressed: () => showQuoteSheet(context, ref, bookId: b.id),
        child: const Icon(BsIcons.add, size: 20),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // 沉浸头图（.bd-bg：封面色板模糊背景 + 蒙层）
                Stack(
                  children: [
                    Positioned.fill(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [pal.$1, pal.$2],
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .18),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 44),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b.title,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${b.author}'
                                        '${b.translator != null && b.translator!.isNotEmpty ? ' · 译 ${b.translator}' : ''}'
                                        '${b.publisher != null && b.publisher!.isNotEmpty ? '\n${b.publisher}' : ''}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.5,
                                          color: Colors.white.withValues(
                                            alpha: .85,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // 信息行（LH-K15 可点芯片：条/页/时长/进度）
                                      Row(
                                        children: [
                                          _chip(
                                            '${allQ.length} 条',
                                            BsIcons.quote,
                                            'bd-quotes-chip',
                                            () {
                                              setState(() {
                                                _tab = 'q';
                                                _chapF = null;
                                              });
                                            },
                                          ),
                                          _chip(
                                            bsPosLabel(b),
                                            BsIcons.book,
                                            'bd-pages-chip',
                                            () => showProgressSheet(
                                              context,
                                              ref,
                                              b,
                                            ),
                                          ),
                                          _chip(
                                            bsFmt(agg[b.id]?.minutes ?? 0),
                                            BsIcons.time,
                                            'bd-min-chip',
                                            () => context.push(
                                              '/read/log/${b.id}',
                                            ),
                                          ),
                                          _chip(
                                            '${b.percent}%',
                                            BsIcons.pin,
                                            'bd-pct-chip',
                                            () => showProgressSheet(
                                              context,
                                              ref,
                                              b,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  children: [
                                    BsCover(
                                      book: b,
                                      width: 92,
                                      height: 132,
                                      radius: 12,
                                      onTap: () =>
                                          context.push('/read/info/${b.id}'),
                                      onBadgeTap: () =>
                                          cycleBookState(context, ref, b),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '书籍资料',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        color: Colors.white.withValues(
                                          alpha: .75,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => context.pop(),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            // 顶栏页内动作（LH-K13：36 圆·19px 线性·无文字）
                            _hdrBtn(
                              'bd-timer',
                              BsIcons.timer,
                              onTimer,
                              () => readTimerEntry(ref, context, b),
                            ),
                            _hdrBtn('bd-more', BsIcons.more, false, () async {
                              final gone = await showBookOpsSheet(
                                context,
                                ref,
                                b,
                              );
                              if (gone == true && context.mounted) {
                                context.pop();
                              }
                            }),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // 轮5.3：本地文件紧凑条上移到信息行之下、三 tab 之上（原整卡在尾部）。
                if (b.local)
                  _localEpubStrip(
                    cs,
                    b,
                    allQ.where((q) => q.cf != null).length,
                  ),
                // 三 tab（§3.2：目录 / 书摘 N / 相关 N＝四分组命中共 N 本）
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      _seg('seg-c', '目录', 'c', b),
                      const SizedBox(width: 8),
                      _seg('seg-q', '书摘 ${allQ.length}', 'q', b),
                      const SizedBox(width: 8),
                      _seg(
                        'seg-r',
                        '相关 ${relGroups.fold(0, (t, g) => t + g.ls.length)}',
                        'r',
                        b,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: switch (_tab) {
                    'c' => _tocTab(cs, tokens, b),
                    'q' => Column(
                      // 真机反馈 V1.46②：分段筛选行靠左（原型 bdQSeg 即 flex 起首，
                      // 实现默认 center 偏离）。
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_chapF != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Text(
                                  '章节 · $_chapF',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  key: const ValueKey('qf-clear'),
                                  onTap: () => setState(() => _chapF = null),
                                  child: Text(
                                    '清除',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // 分段 chips（原型 bdQSegChips · 点段过滤，再点回全部）
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (k, label) in [
                                ('all', '全部 ${allQ.length}'),
                                (
                                  'line',
                                  '划线 ${allQ.where((q) => q.kind == BookQuote.kKindMark).length}',
                                ),
                                (
                                  'think',
                                  '想法 ${allQ.where((q) => q.kind == BookQuote.kKindThought).length}',
                                ),
                                ('star', '星标 ${allQ.where((q) => q.starred).length}'),
                              ])
                                GestureDetector(
                                  key: ValueKey('qseg-$k'),
                                  onTap: () => setState(
                                    () => _qSeg = _qSeg == k ? 'all' : k,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: _qSeg == k
                                          ? tokens.accent.withValues(alpha: .12)
                                          : cs.surfaceContainerHighest,
                                      border: Border.all(
                                        color: _qSeg == k
                                            ? tokens.accent
                                            : cs.outlineVariant.withValues(
                                                alpha: .4,
                                              ),
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: _qSeg == k
                                            ? tokens.accent
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (quotes.isEmpty) _noQuotes(cs, tokens, b),
                        for (final q in quotes) _quoteCard(cs, q),
                      ],
                    ),
                    _ => _related(cs, tokens, b, relGroups),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 本地文件紧凑条（V1.53.2 轮5.3 · 原型 brDstrip）：原「本地 EPUB」整卡
  /// 上移到信息行之下并压成两行 —— 一行格式/体积/说明钮，一行进度/位置/划线 + 三动作。
  /// 未就绪（预载中/已清缓存）时仍保留批3.5 的四态行，重载/重选入口不丢。
  Widget _localEpubStrip(ColorScheme cs, Book b, int hlCount) {
    final ep = b.epub;
    if (ep == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    final sizeMb = '${(ep.size / (1024 * 1024)).toStringAsFixed(1)} MB';
    Widget mini(String key, IconData ic, Color fg, VoidCallback onTap) =>
        GestureDetector(
          key: ValueKey(key),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(color: fg.withValues(alpha: .35)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ic, size: 14, color: fg),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('brDstrip'),
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.cardBorder),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ep.fmt,
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$sizeMb · 无 DRM · 图文混排',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('brDinfo'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showBrLocalInfo(context, ref, b, hlCount),
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        '?',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '进度 ${b.percent}% · 位置 ${bsPosLabel(b)} · 划线 $hlCount 处',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('br-d-open'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      if (await brTapGuarded(context, ref, b)) return;
                      if (mounted) context.push('/read/reader/${b.id}');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: tokens.gradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '打开阅读器',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  mini('br-d-search', Icons.search_rounded, cs.onSurface, () =>
                      brOpenBookSearch(context, ref, b)),
                  const SizedBox(width: 6),
                  mini('br-d-del', Icons.delete_outline_rounded,
                      const Color(0xFFE11D48), () async {
                    // 轮4：弹层 resolve 时提交已落库。全删（或纸质/电子书写 keep
                    // 直接进回收站）后书行已没——详情页不再有空壳可留，出栈回书架；
                    // 本地书 keep＝留架摘缓存，页面随 readTick 重取自然转为无缓存态。
                    await showBrDelSheet(context, ref, b);
                    if (!mounted) return;
                    final nb =
                        await ref.read(readRepositoryProvider).bookById(b.id);
                    if (!mounted) return;
                    if (nb == null || nb.isDeleted) Navigator.of(context).pop();
                  }),
                ],
              ),
            ],
          ),
        ),
        if (ep.state != 'rdy') _cacheRow(cs, b, ep),
      ],
    );
  }

  /// 本地副本与缓存行（原型 brDcache · 批3.5 四态：预载中/已清可读/已清丢失/就绪）。
  Widget _cacheRow(ColorScheme cs, Book b, EpubRef ep) {
    final tokens = context.tokens;
    Widget body;
    switch (ep.state) {
      case 'pre':
        body = Column(
          key: const ValueKey('br-dcache-pre'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '整本预载中 · 分页后台续算 · 点封面可直接进入阅读',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Consumer(
                builder: (_, ref2, _) {
                  ref2.watch(epubPreloadProvider);
                  final pr =
                      (ref2.read(epubPreloadProvider).info(b.id)?.pr ?? ep.pr)
                          .clamp(0, 100) /
                      100;
                  return LinearProgressIndicator(
                    value: pr,
                    minHeight: 4,
                    backgroundColor: cs.surfaceContainerHighest,
                  );
                },
              ),
            ),
          ],
        );
      case 'cl':
        final srcOk = (ep.srcPath != null && File(ep.srcPath!).existsSync());
        body = Column(
          key: ValueKey(srcOk ? 'br-dcache-cl' : 'br-dcache-lost'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              srcOk
                  ? '本地副本已清理 · 源文件仍可读 · 记录与书摘完整保留'
                  : '本地副本已清理 · 原文件已不存在 · 记录与书摘完整保留',
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: srcOk ? cs.onSurfaceVariant : const Color(0xFFE11D48),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              key: ValueKey(srcOk ? 'br-d-reload' : 'br-d-repick'),
              onTap: () => srcOk
                  ? brShowReloadSheet(context, ref, b)
                  : brShowLostSheet(context, ref, b),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: srcOk ? tokens.gradient : null,
                  color: srcOk ? null : const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  srcOk ? '重新载入本地副本' : '重新选择文件',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        );
      default:
        body = Row(
          key: const ValueKey('br-dcache-rdy'),
          children: [
            Expanded(
              child: Text(
                '本地副本 + 分页缓存 · 源文件在原始位置保留',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ),
            GestureDetector(
              key: const ValueKey('br-d-clearcache'),
              onTap: () => brShowCacheSheet(context, ref, b),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x59D97706)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '清理缓存',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD97706),
                  ),
                ),
              ),
            ),
          ],
        );
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: const Color(0xFFD97706), width: 3),
        ),
      ),
      child: body,
    );
  }

  /// 可点信息芯片（LH-K15：虚线下划线 · 可改数值不做纯文本）。
  Widget _chip(String t, IconData ic, String key, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: GestureDetector(
          key: ValueKey(key),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ic, size: 12, color: Colors.white.withValues(alpha: .85)),
              const SizedBox(width: 3),
              Text(
                t,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: .85),
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: Colors.white.withValues(alpha: .6),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _hdrBtn(String key, IconData ic, bool active, VoidCallback onTap) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? Colors.white.withValues(alpha: .28)
                : Colors.black.withValues(alpha: .18),
          ),
          child: Icon(ic, size: 19, color: active ? tokens.g3 : Colors.white),
        ),
      ),
    );
  }

  Widget _seg(String key, String label, String tab, Book b) => GestureDetector(
    key: ValueKey(key),
    onTap: () => setState(() => _tab = tab),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: _tab == tab
            ? context.tokens.accent.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: _tab == tab ? context.tokens.accent : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: _tab == tab ? context.tokens.accent : null,
        ),
      ),
    ),
  );

  // ---- 目录卡（两级 · 只读 / 编辑就地微调 / 粘贴导入 · §3.3 §3.4） ----

  /// 批4-C「目录 AI 补全」：审阅发送 read.toc → chapters 转导入解析结构 →
  /// 复用既有目录导入弹层（预览 N 部分/M 节 → 确认替换），绝不静默覆盖。
  Future<void> _aiToc(Book b) async {
    final res = await aiRunWithReview(
      context,
      ref,
      taskId: 'read.toc',
      vars: {'title': b.title, 'author': b.author},
    );
    if (res == null || !mounted) return;
    final chapters = res.requireJson()['chapters'];
    final parts = tocPartsFromChapters(chapters is List ? chapters : const []);
    if (parts.isEmpty) {
      readToast(context, 'AI 未返回可用章节 · 未写入目录');
      return;
    }
    await showTocImportSheet(
      context,
      ref,
      b.id,
      bookTitle: b.title,
      aiParts: parts,
    );
  }

  Widget _tocTab(ColorScheme cs, dynamic tokens, Book b) {
    final nodes = ref.watch(tocProvider(b.id)).valueOrNull;
    if (nodes == null) return const SizedBox(height: 60);
    final groups = tocTree(nodes, hideEmptyParts: !_tocEdit);
    final secCount = groups.fold(0, (t, g) => t + g.sections.length);
    // 每节划线角标：该书该章摘录计数（原型 renderToc 4730 q 位）
    final chapQ = <String, int>{};
    for (final q
        in (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])) {
      if (q.bookId == b.id && q.deletedAt == null && (q.chapter ?? '').isNotEmpty) {
        chapQ[q.chapter!] = (chapQ[q.chapter!] ?? 0) + 1;
      }
    }
    // 在读节＝最后一个 startPage ≤ readPages 的小节（原型 done/read 点）
    final withPage = [
      for (final g in groups)
        for (final s in g.sections)
          if (s.startPage != null) s,
    ];
    final cur = withPage.isEmpty
        ? null
        : withPage.lastWhere(
            (s) => s.startPage! <= b.readPages,
            orElse: () => withPage.first,
          );
    final curActive =
        cur != null && cur.startPage! <= b.readPages && b.isReading;
    final repo = ref.read(readRepositoryProvider);
    Future<void> act(Future<void> Function() f) async {
      await f();
      if (!mounted) return;
      ref.read(readTickProvider.notifier).state++;
      setState(() {});
    }

    return Container(
      width: double.infinity,
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
              // 轮3：标题「目录 · N 节」本身可点＝展开/收起列表。
              GestureDetector(
                key: const ValueKey('toc-title'),
                behavior: HitTestBehavior.opaque,
                onTap: groups.isEmpty
                    ? null
                    : () => setState(() => _tocOpen = !_tocOpen),
                child: Text(
                  '目录 · $secCount 节',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const Spacer(),
              // 原型行序：编辑 → AI 补全 → 导入目录，恒 12px 间隔防误触
              if (groups.isNotEmpty) ...[
                GestureDetector(
                  key: const ValueKey('toc-edit'),
                  onTap: () => setState(() {
                    if (_tocEdit) {
                      act(() => repo.tocPrune(b.id).then((_) {}));
                    }
                    _tocEdit = !_tocEdit;
                  }),
                  child: Text(
                    _tocEdit ? '完成' : '编辑',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (!_tocEdit) ...[
                  GestureDetector(
                    key: const ValueKey('toc-ai'),
                    onTap: () => _aiToc(b),
                    child: Text(
                      'AI 补全',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
              GestureDetector(
                key: const ValueKey('toc-import'),
                onTap: () =>
                    showTocImportSheet(context, ref, b.id, bookTitle: b.title),
                child: Text(
                  '导入目录',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent,
                  ),
                ),
              ),
              // 轮3：目录与章间笔记列表默认收起，展开钮常驻行尾
              if (groups.isNotEmpty) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  key: const ValueKey('toc-fold'),
                  onTap: () => setState(() => _tocOpen = !_tocOpen),
                  child: Text(
                    _tocOpen ? '收起' : '展开',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '这本书还没有目录 · ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('toc-empty-ai'),
                    onTap: () => _aiToc(b),
                    child: Text(
                      'AI 补全',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                  Text(
                    ' 或 ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('toc-empty-import'),
                    onTap: () => showTocImportSheet(
                      context,
                      ref,
                      b.id,
                      bookTitle: b.title,
                    ),
                    child: Text(
                      '导入',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_tocEdit)
            for (final g in groups) ...[
              TocEditRow(
                node: g.part,
                onRename: (v) => act(() => repo.renameToc(g.part.id!, v)),
                onMove: (d) => act(() => repo.moveToc(g.part.id!, d)),
                onDelete: () => act(() => repo.deleteToc(g.part.id!)),
                onAddSection: () =>
                    act(() => repo.addTocSection(g.part.id!).then((_) {})),
              ),
              for (final s in g.sections)
                TocEditRow(
                  node: s,
                  onRename: (v) => act(() => repo.renameToc(s.id!, v)),
                  onMove: (d) => act(() => repo.moveToc(s.id!, d)),
                  onDelete: () => act(() => repo.deleteToc(s.id!)),
                ),
            ]
          else if (_tocOpen)
            for (final g in groups) ...[
              // 轮3：部分章节行点击＝就地展开/收起其小节。
              GestureDetector(
                key: ValueKey('toc-p-${g.part.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  final k = '${g.part.id}';
                  if (!_tocPartFold.remove(k)) _tocPartFold.add(k);
                }),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Row(
                    children: [
                      Icon(
                        _tocPartFold.contains('${g.part.id}')
                            ? Icons.chevron_right_rounded
                            : Icons.expand_more_rounded,
                        size: 14,
                        color: const Color(0xFF0F172A),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          g.part.title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Text(
                        '${g.sections.where((s) => _tocDone(b, s, cur, curActive)).length}'
                        '/${g.sections.length}',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_tocPartFold.contains('${g.part.id}'))
              for (final s in g.sections)
                GestureDetector(
                  key: ValueKey('toc-s-${s.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    _chapF = s.title;
                    _tab = 'q';
                  }),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, top: 5, bottom: 5),
                    child: Row(
                      children: [
                        // 状态点（原型 toc-dot：done 绿 / 在读品牌色 / 未读灰）
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _tocDone(b, s, cur, curActive)
                                ? const Color(0xFF34D399)
                                : identical(cur, s) && curActive
                                ? tokens.accent as Color
                                : cs.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _tocDone(b, s, cur, curActive) ||
                                      (identical(cur, s) && curActive)
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        // 该节划线摘录数角标（原型 q 位：划线图标+N）
                        if ((chapQ[s.title] ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Row(
                              children: [
                                Icon(
                                  BsIcons.quote,
                                  size: 10,
                                  color: tokens.accent as Color,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${chapQ[s.title]}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.accent as Color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_tocDone(b, s, cur, curActive))
                          Icon(
                            BsIcons.check,
                            size: 12,
                            color: const Color(0xFF10B981),
                          )
                        else if (identical(cur, s) && curActive)
                          Text(
                            '在读',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent as Color,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          if (_tocEdit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                key: const ValueKey('toc-addpart'),
                onTap: () => act(() => repo.addTocPart(b.id).then((_) {})),
                child: Text(
                  '＋ 加部分',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _noQuotes(ColorScheme cs, dynamic tokens, Book b) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 26),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    ),
    child: Column(
      children: [
        Text('还没有摘录', style: TextStyle(fontSize: 12, color: cs.onSurface)),
        const SizedBox(height: 8),
        GestureDetector(
          key: const ValueKey('bd-add-quote'),
          onTap: () => showQuoteSheet(context, ref, bookId: b.id),
          child: Text(
            '记一条',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: tokens.accent as Color,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _quoteCard(ColorScheme cs, BookQuote q) => GestureDetector(
    key: ValueKey('bd-q-${q.id}'),
    behavior: HitTestBehavior.opaque,
    // §3.4：摘录卡 → 摘录操作弹层（收藏/编辑/转日记/转待办/转笔记/复制/删除）。
    onTap: () => showQuoteOpsSheet(context, ref, q),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3.5,
            height: q.body.length > 40 ? 60 : 34,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | q.colorInt),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.kind == BookQuote.kKindMark ? '「${q.body}」' : q.body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: cs.onSurface,
                  ),
                ),
                if (q.thought != null && q.thought!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      q.thought!,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Row(
                    children: [
                      Expanded(child: _qMeta(cs, q)),
                      // 只在已收藏时显示小星（§3.3 卡片平铺动作清空）。
                      if (q.starred)
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Color(0xFFF59E0B),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _qMeta(ColorScheme cs, BookQuote q) {
    final d = DateTime.fromMillisecondsSinceEpoch(q.createdAt);
    return Text(
      [
        if ((q.chapter ?? '').isNotEmpty) q.chapter!,
        if (q.page != null) '${q.page} 页',
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      ].join(' · '),
      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
    );
  }

  /// 目录节划线状态（原型 renderToc：done 绿点勾 / read 品牌点+「在读」）。
  bool _tocDone(Book b, TocNode s, TocNode? cur, bool curActive) {
    if (s.startPage == null) return false;
    if (b.state == Book.kStateDone) return true;
    if (b.pages <= 0) return false;
    return s.startPage! <= b.readPages && !(identical(s, cur) && curActive);
  }

  /// 相关推荐四分组（原型 bsRelGroups 4720）：同作者/同系列/同标签/同出版社，
  /// 各取 6 本，空组丢弃。
  List<({String lbl, List<Book> ls})> _relGroups(Book b, List<Book> all) {
    final pool = all.where((x) => !x.isDeleted && x.id != b.id).toList();
    final gs = <({String lbl, List<Book> ls})>[
      (
        lbl: '同作者 ${b.author}',
        ls: pool.where((x) => x.author == b.author).take(6).toList(),
      ),
      if ((b.series ?? '').isNotEmpty)
        (
          lbl: '同系列 ${b.series}',
          ls: pool.where((x) => (x.series ?? '') == b.series).take(6).toList(),
        ),
      (
        lbl: '同标签',
        ls: pool
            .where((x) => x.tags.any((t) => b.tags.contains(t)))
            .take(6)
            .toList(),
      ),
      if ((b.publisher ?? '').isNotEmpty && b.publisher != '—')
        (
          lbl: '同出版社',
          ls: pool
                  .where(
                    (x) =>
                        (x.publisher ?? '').isNotEmpty &&
                        x.publisher == b.publisher,
                  )
                  .take(6)
                  .toList(),
        ),
    ];
    return gs.where((g) => g.ls.isNotEmpty).toList();
  }

  Widget _related(
    ColorScheme cs,
    dynamic tokens,
    Book b,
    List<({String lbl, List<Book> ls})> groups,
  ) {
    if (groups.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
        ),
        child: Text(
          '还没有同作者 / 同系列 / 同标签的书',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      );
    }
    final qCount = <String, int>{};
    for (final q
        in (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])) {
      if (q.deletedAt == null) qCount[q.bookId] = (qCount[q.bookId] ?? 0) + 1;
    }
    return Column(
      children: [
        for (final g in groups)
          Container(
            key: ValueKey('relgrp-${g.lbl}'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${g.lbl} · ${g.ls.length} 本',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                for (final x in g.ls)
                  GestureDetector(
                    key: ValueKey('rel-${x.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/read/book/${x.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          BsCover(
                            book: x,
                            width: 28,
                            height: 40,
                            radius: 5,
                            showAuthor: false,
                            showBadge: false,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  x.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${x.author} · ${x.state} · ${qCount[x.id] ?? 0} 条摘录',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 轮5.3 · 本地文件与缓存说明半屏（详情页紧凑条「?」入口 · 原型 sheetBrLocalInfo）。
///
/// 原「本地 EPUB」整卡的说明文字收进这里，正文只留两行紧凑条；
/// 清理缓存沿用批3.5 三态弹层（源文件永不删除）。
Future<void> showBrLocalInfo(
  BuildContext context,
  WidgetRef ref,
  Book b,
  int hlCount,
) async {
  final ep = b.epub;
  if (ep == null) return;
  final cs = Theme.of(context).colorScheme;
  final sizeMb = '${(ep.size / (1024 * 1024)).toStringAsFixed(1)} MB';
  final stateTxt = switch (ep.state) {
    'pre' => '整本预载中（点封面可直接进入阅读 · 后台续算）',
    'cl' => '本地副本已清理 · 记录与书摘保留',
    _ => '本地副本 + 分页缓存已就绪',
  };
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sc) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          key: const ValueKey('sheetBrLocalInfo'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '本地文件与缓存',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  ep.fmt,
                  key: const ValueKey('brLiFmt'),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '文件路径',
              style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                ep.path,
                key: const ValueKey('brLiPath'),
                style: const TextStyle(fontSize: 10.5, height: 1.5),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '体积 / 加密 / 版式',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '$sizeMb · 无 DRM · 图文混排',
                  key: const ValueKey('brLiMeta'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '阅读位置 / 划线 / 进度',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${bsPosLabel(b)} · $hlCount 处 · ${b.percent}%',
                  key: const ValueKey('brLiPos'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '删除时询问阅读数据去留：默认保留（释放源文件与缓存，卡片留在书架，重新导入自动挂回），'
              '或全量删除（阅读数据一并删除，书籍记录进回收站）。',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.6,
                color: cs.onSurfaceVariant,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '缓存：$stateTxt · 只回收分页表与私有副本，随时可重新载入。',
                key: const ValueKey('brLiCache'),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brLiOk'),
                    onPressed: () => Navigator.of(sc).pop(),
                    child: const Text('知道了'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brLiClean'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD97706),
                      side: const BorderSide(color: Color(0x66D97706)),
                    ),
                    onPressed: () {
                      Navigator.of(sc).pop();
                      brShowCacheSheet(context, ref, b);
                    },
                    child: const Text('清理缓存'),
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
