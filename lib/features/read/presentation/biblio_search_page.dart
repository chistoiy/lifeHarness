import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/isbn_enrich.dart';
import 'book_form_page.dart';
import 'isbn_scan_page.dart';
import 'read_sheets.dart' show readToast;
import 'widgets/bs_cover.dart';

/// V1.44「先搜后加」· 添加图书搜索页（原型 p-biblioSearch · renderBsr）。
/// 一个搜索框收「书名 / 作者 / ISBN」，350ms 防抖打 [IsbnEnrich.searchList]
/// （suggest 先行、搜索页兜底，熔断期回空）；本批数据源只接豆瓣，其余源置灰
/// 标「未接入」。点结果行＝直接进预填可改整页表单（无独立条目详情页）。
/// 右下角一个 FAB＝二选一（扫描 ISBN 录入 / 手动输入），不再并排摆两个入口。
class BiblioSearchPage extends ConsumerStatefulWidget {
  const BiblioSearchPage({super.key});

  @override
  ConsumerState<BiblioSearchPage> createState() => _BiblioSearchPageState();
}

class _BiblioSearchPageState extends ConsumerState<BiblioSearchPage> {
  static const _debounceMs = 350;

  /// 原型 BSR_SRC：本批只接豆瓣，其余源保留但置灰（不做假结果）。
  static const _srcs = <(String, bool)>[
    ('豆瓣读书', true),
    ('纸间书摘', false),
    ('起点中文网', false),
    ('纵横中文网', false),
    ('晋江文学城', false),
  ];

  final TextEditingController _q = TextEditingController();
  String _src = '豆瓣读书';
  List<DoubanSearchRow> _rows = const [];
  bool _searching = false;
  bool _menu = false; // FAB 二选一菜单展开态
  Timer? _t;
  int _seq = 0;

  @override
  void dispose() {
    _t?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _t?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _rows = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _t = Timer(
      const Duration(milliseconds: _debounceMs),
      () => _runSearch(v),
    );
  }

  Future<void> _runSearch(String q) async {
    final seq = ++_seq;
    final rows = await IsbnEnrich.searchList(
      q,
      fetch: ref.read(isbnPageFetcherProvider),
    );
    if (!mounted || seq != _seq) return;
    setState(() {
      _rows = rows;
      _searching = false;
    });
  }

  /// 无 GoRouter（widget 测试直挂 MaterialApp）时退回 Navigator，语义一致。
  void _openForm(Object? seed) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/read/book-form', extra: seed);
    } else {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => BookFormPage(seed: seed)));
    }
  }

  Future<void> _fabScan() async {
    setState(() => _menu = false);
    String? code;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      code = await router.push<String>('/read/scan');
    } else {
      code = await Navigator.of(
        context,
      ).push<String>(MaterialPageRoute(builder: (_) => const IsbnScanPage()));
    }
    if (!mounted || code == null) return;
    // 扫回条码＝把 code 填进搜索框并触发搜索（onChanged 走同一条防抖链）。
    _q.text = code;
    _onQueryChanged(code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('添加图书', style: TextStyle(fontSize: 15)),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 搜索框（原型 bsrQ：放大镜 + 清除钮有字才显）。
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(BsIcons.search, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('bsr-q'),
                      controller: _q,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '书名 / 作者 / ISBN',
                        hintStyle: TextStyle(fontSize: 12.5),
                        border: InputBorder.none,
                      ),
                      onChanged: _onQueryChanged,
                    ),
                  ),
                  if (_q.text.isNotEmpty)
                    GestureDetector(
                      key: const ValueKey('bsr-clear'),
                      onTap: () {
                        _q.clear();
                        _onQueryChanged('');
                      },
                      child: Icon(
                        BsIcons.close,
                        size: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 源 chips 一行：豆瓣可用，其余置灰「· 未接入」。
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (name, ok) in _srcs)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        key: ValueKey('bsr-chip-$name'),
                        onTap: () {
                          if (!ok) {
                            readToast(context, '该源未接入 · 本批只支持豆瓣');
                            return;
                          }
                          setState(() => _src = name);
                          if (_q.text.trim().length >= 2) {
                            _runSearch(_q.text);
                          }
                        },
                        child: Opacity(
                          opacity: ok ? 1 : .4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: _src == name && ok
                                  ? tokens.accent.withValues(alpha: .12)
                                  : cs.surfaceContainerHighest,
                              border: Border.all(
                                color: _src == name && ok
                                    ? tokens.accent
                                    : tokens.cardBorder,
                              ),
                            ),
                            child: Text(
                              ok ? name : '$name · 未接入',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _src == name && ok
                                    ? tokens.accent
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _list(cs, tokens)),
          ],
        ),
      ),
      // 右下角一个 FAB：点开二选一（扫描 ISBN 录入 / 手动输入）。
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_menu) ...[
            _mini(context, 'bsr-fab-scan', '扫描 ISBN 录入', _fabScan),
            const SizedBox(height: 8),
            // V1.50 导入入口（原型顺序：扫描 → 导入本地 → 手动）。
            _mini(context, 'bsr-fab-epub', '导入本地图书（EPUB）', () {
              setState(() => _menu = false);
              context.push('/read/import-epub');
            }),
            const SizedBox(height: 8),
            _mini(context, 'bsr-fab-manual', '手动输入', () {
              setState(() => _menu = false);
              _openForm(null);
            }),
            const SizedBox(height: 10),
          ],
          FloatingActionButton(
            key: const ValueKey('bsr-fab'),
            heroTag: 'bsr-fab',
            onPressed: () => setState(() => _menu = !_menu),
            backgroundColor: tokens.accent,
            child: Icon(
              _menu ? BsIcons.close : BsIcons.add,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(ColorScheme cs, ThemeTokens tokens) {
    if (_rows.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _row(cs, tokens, _rows[i]),
      );
    }
    // 空态三档：熔断受限 / 未起手提示 / 无结果。
    final String text;
    if (DoubanGuard.active()) {
      text = '豆瓣访问受限 · 稍后再试';
    } else if (_q.text.trim().isEmpty || _searching) {
      text = '搜书名、作者或 ISBN';
    } else {
      text = '豆瓣未收录此书名 / 条码';
    }
    return Center(
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _row(ColorScheme cs, ThemeTokens tokens, DoubanSearchRow r) {
    final sub = [r.author, r.publisher, r.pubDate]
        .where((e) => (e ?? '').isNotEmpty)
        .join(' / ');
    return GestureDetector(
      key: ValueKey('bsr-row-${r.subjectId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openForm(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面缩略：有 URL 走网络图（失败回退色块）；无 URL 直接色块。
            _cover(r),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if ((r.price ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '定价 ${r.price}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // 右侧评分 10 分制（不换算本地 5 星 · 原型 bsrStar）。
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: r.rating == null
                  ? Text(
                      '未评分',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : Text(
                      '${r.rating}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 列表缩略封面：Image.network 失败/无图回退书脊色块（测试环境不渲染真图）。
  Widget _cover(DoubanSearchRow r) {
    final pal = kBsCov[r.subjectId.hashCode % kBsCov.length];
    Widget block() => Container(
      width: 36,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.$1, pal.$2],
        ),
      ),
    );
    final u = r.coverUrl;
    if (u == null || u.isEmpty) return block();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        u,
        // doubanio 防盗链：裸请求 403（真机 2026-09-27 列表不显封面实证）。
        headers: doubanImageHeaders(),
        width: 36,
        height: 52,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => block(),
      ),
    );
  }

  Widget _mini(
    BuildContext context,
    String key,
    String label,
    VoidCallback onTap,
  ) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
