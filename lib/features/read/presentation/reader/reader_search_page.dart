import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/epub_doc.dart';

// 全书检索整页（V1.50 批3 · 事实源 `#p-readerSearch`）。
// 双入口之一（顶栏放大镜）；抽屉「搜本书」Tab 共用同款命中→跳原文链路。
// 仅本机检索已解析正文，零网络。

/// 一条命中：章序 + 段序 + 段文本。
typedef BrHit = ({int ci, int pi, String text});

/// 检索结果回传给阅读主屏（hits 全量 + 起始序号 + 关键词）。
typedef BrSearchResult = ({List<BrHit> hits, int idx, String q});

List<BrHit> brSearchDoc(EpubDoc doc, String query) {
  if (query.trim().isEmpty) return const [];
  final q = query.trim();
  return [
    for (var ci = 0; ci < doc.chapters.length; ci++)
      for (var pi = 0; pi < doc.chapters[ci].paras.length; pi++)
        if (doc.chapters[ci].paras[pi].text.contains(q))
          (ci: ci, pi: pi, text: doc.chapters[ci].paras[pi].text),
  ];
}

class ReaderSearchPage extends StatefulWidget {
  const ReaderSearchPage({super.key, required this.doc, required this.title});

  final EpubDoc doc;
  final String title;

  @override
  State<ReaderSearchPage> createState() => _ReaderSearchPageState();
}

class _ReaderSearchPageState extends State<ReaderSearchPage> {
  final _q = TextEditingController();
  List<BrHit> _hits = const [];
  // 轮4②：大合集全扫一次可达秒级，逐键同步扫会卡输入；防抖后再扫。
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _run(String s) {
    _debounce?.cancel();
    if (s.trim().isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _hits = brSearchDoc(widget.doc, s));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _q.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('全书检索', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 搜索框（就地输入即搜 · 原型 brSq）。
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, size: 15, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('brSq'),
                        controller: _q,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: '在本书中搜索关键词',
                          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                          border: InputBorder.none,
                        ),
                        onChanged: _run,
                      ),
                    ),
                    if (query.isNotEmpty)
                      GestureDetector(
                        key: const ValueKey('brSqX'),
                        onTap: () => _run(''),
                        child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF94A3B8)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                query.isEmpty
                    ? '输入关键词检索全书正文'
                    : '《${widget.title}》命中 ${_hits.length} 处 · 覆盖 ${widget.doc.chapters.length} 章正文 · 本机检索',
                key: const ValueKey('brSInfo'),
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: query.isEmpty
                    ? const SizedBox.shrink()
                    : _hits.isEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Text(
                              '未找到「$query」',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '换个关键词试试 · 检索仅在本机进行',
                              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        key: const ValueKey('brSHits'),
                        itemCount: _hits.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final h = _hits[i];
                          return InkWell(
                            key: ValueKey('brSHit-$i'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).pop((
                              hits: _hits,
                              idx: i,
                              q: query,
                            )),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.doc.chapters[h.ci].title} · epub/2/${h.ci + 2}/${h.pi}',
                                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 4),
                                  Text.rich(_mark(cs, h.text, query)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 关键词琥珀高亮（原型 mark.bg-amber-200）。
  InlineSpan _mark(ColorScheme cs, String text, String q) {
    final base = TextStyle(fontSize: 12, height: 1.6, color: cs.onSurface);
    final children = <InlineSpan>[];
    var rest = text;
    while (true) {
      final at = rest.indexOf(q);
      if (at < 0) break;
      if (at > 0) children.add(TextSpan(text: rest.substring(0, at), style: base));
      children.add(
        TextSpan(
          text: q,
          style: base.copyWith(
            backgroundColor: const Color(0xFFFDE68A).withValues(alpha: .8),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      rest = rest.substring(at + q.length);
    }
    if (rest.isNotEmpty) children.add(TextSpan(text: rest, style: base));
    return TextSpan(style: base, children: children);
  }
}
