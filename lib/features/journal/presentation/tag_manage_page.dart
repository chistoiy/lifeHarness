import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/tag.dart';
import 'journal_providers.dart';
import 'tag_sheets.dart';
import 'widgets/tag_chip.dart';

/// 标签管理（批2b · 原型 `p-sub-tags`，家＝`index-time.html`）。
///
/// 口径（工单 §4g 产品四条）：
/// ① 池全局唯一，**只有这一页能增删改**（日记/笔记页只做选择）；
/// ② 每个标签带「适用模块」多选，新建默认三个全勾；
/// ③ 各功能页选标签只列本模块启用的（日记侧见 `diaryTagPoolProvider`）；
/// ④ 跨模块搜索 + 改名 / 合并 / 删除（删除＝解绑，内容不删）。
///
/// 实现落位说明：原型把本屏放在时间专版（因为「分类管理」的家在那儿、我的页两个
/// 入口相邻）；实现侧没有专版概念，而标签的读写主战场是日记/笔记，故落在
/// `features/journal`——同 feature 内 import 不触架构 R1（跨 feature 只经 shared）。
class TagManagePage extends ConsumerStatefulWidget {
  const TagManagePage({super.key});

  @override
  ConsumerState<TagManagePage> createState() => _TagManagePageState();
}

class _TagManagePageState extends ConsumerState<TagManagePage> {
  String _scene = 'all';
  bool _foldAll = false;
  final Set<String> _folded = {};
  int _sortMode = 0; // 0＝池序（默认）· 1＝引用数降序
  final _qCtrl = TextEditingController();
  String _q = '';
  ({List<Tag> tags, List<TagSearchHit> rows})? _search;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    // 进页即刷新池：引用计数会被**其他模块**（日记保存/笔记/时间块）改写，
    // 而 `tagPoolProvider` 是常驻 FutureProvider（不 autoDispose）。真机实测
    // （批2b 6199）：给日记打上标签后回本页仍显示「0 条」，就是吃了旧缓存。
    Future.microtask(() => ref.invalidate(tagPoolProvider));
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String v) async {
    final seq = ++_searchSeq;
    setState(() => _q = v);
    if (v.trim().isEmpty) {
      setState(() => _search = null);
      return;
    }
    final r = await ref.read(tagDaoProvider).search(v);
    if (!mounted || seq != _searchSeq) return;
    setState(() => _search = r);
  }

  Future<void> _refresh() async => ref.invalidate(tagPoolProvider);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final pool = ref.watch(tagPoolProvider).valueOrNull ?? const <Tag>[];
    final shown = _sorted(pool);
    final scenes = _sections(shown);

    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
        actions: [
          IconButton(
            key: const ValueKey('tg-add'),
            tooltip: '添加标签',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await context.push('/tags/add');
              await _refresh();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: _TopBtn(
                  key: const ValueKey('tg-fold-all'),
                  label: _foldAll ? '全部展开' : '全部折叠',
                  onTap: () => setState(() {
                    _foldAll = !_foldAll;
                    _folded.clear();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TopBtn(
                  key: const ValueKey('tg-sort'),
                  label: _sortMode == 0 ? '排序 · 默认' : '排序 · 引用数',
                  onTap: () {
                    setState(() => _sortMode = _sortMode == 0 ? 1 : 0);
                    AppToast.show(context,
                        _sortMode == 1 ? '按引用条数从多到少' : '按标签池默认顺序', ms: 1200);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('tg-add-top'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    minimumSize: const Size.fromHeight(38),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    await context.push('/tags/add');
                    await _refresh();
                  },
                  child: const Text('＋ 添加标签'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 跨模块搜索（口径④）：搜标签名 + 三模块内容，**忽略作用域**。
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.search, size: 16, color: tokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('tg-search'),
                  controller: _qCtrl,
                  onChanged: _runSearch,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '跨模块搜标签或内容',
                    hintStyle: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              if (_q.isNotEmpty)
                TextButton(
                  key: const ValueKey('tg-search-clear'),
                  style: TextButton.styleFrom(
                      minimumSize: const Size(36, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: () {
                    _qCtrl.clear();
                    _runSearch('');
                  },
                  child: const Text('清空', style: TextStyle(fontSize: 12)),
                ),
            ]),
          ),
          if (_q.trim().isNotEmpty) _searchCard(tokens, scheme),
          const SizedBox(height: 10),
          _rail(shown, tokens),
          const SizedBox(height: 2),
          for (final s in scenes) _segment(s, tokens, scheme),
          const SizedBox(height: 10),
          Text(
            '计数 = 引用条数（三模块合计）· 同一标签可同时适用多个模块 · 删除只解绑不删内容',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.5, color: tokens.text2),
          ),
        ],
      ),
    );
  }

  /// 池排序：默认按池序（`sort,id`）；引用数档按条数降序（同数回落到池序，保证稳定）。
  List<Tag> _sorted(List<Tag> pool) {
    if (_sortMode == 0) return pool;
    final copy = [...pool];
    copy.sort((a, b) {
      final c = b.useCount.compareTo(a.useCount);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return copy;
  }

  /// 分区（**视图不是数据**：同一标签可同时出现在日记与笔记两段）。
  List<({String key, List<Tag> list})> _sections(List<Tag> pool) {
    final order = [...kTagScopes, 'public'];
    return [
      for (final k in order)
        if (_scene == 'all' || _scene == k)
          (
            key: k,
            list: k == 'public'
                ? [for (final t in pool) if (t.isPublic) t]
                : [for (final t in pool) if (t.appliesTo(k)) t],
          ),
    ];
  }

  Widget _rail(List<Tag> pool, ThemeTokens tokens) {
    final tabs = <({String key, String label, int n})>[
      (key: 'all', label: '全部', n: pool.length),
      for (final k in kTagScopes)
        (key: k, label: tagSceneName(k), n: pool.where((t) => t.appliesTo(k)).length),
      (
        key: 'public',
        label: '公共',
        n: pool.where((t) => t.isPublic).length,
      ),
    ];
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tabs[i];
          final on = _scene == t.key;
          return GestureDetector(
            key: ValueKey('tg-rail-${t.key}'),
            onTap: () => setState(() => _scene = t.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? tokens.accent.withValues(alpha: .12) : tokens.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: on
                        ? tokens.accent.withValues(alpha: .55)
                        : tokens.cardBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(t.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? tokens.accent : tokens.text1)),
                const SizedBox(width: 4),
                Text('${t.n}',
                    style: TextStyle(fontSize: 11, color: tokens.text2)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _segment(
      ({String key, List<Tag> list}) seg, ThemeTokens tokens, ColorScheme scheme) {
    final folded = _foldAll || _folded.contains(seg.key);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            key: ValueKey('tg-seg-${seg.key}'),
            onTap: () => setState(() {
              if (_folded.contains(seg.key)) {
                _folded.remove(seg.key);
              } else {
                _folded.add(seg.key);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(_sceneIcon(seg.key), size: 16, color: tokens.accent),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(tagSceneName(seg.key),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700))),
                Text('${seg.list.length} 个',
                    style: TextStyle(fontSize: 11, color: tokens.text2)),
                const SizedBox(width: 6),
                Icon(folded ? Icons.expand_more : Icons.expand_less,
                    size: 16, color: tokens.text2),
              ]),
            ),
          ),
          if (!folded)
            if (seg.list.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('这一段还没有标签',
                      style: TextStyle(fontSize: 11, color: tokens.text2)),
                ),
              )
            else
              for (final t in seg.list) _row(t, tokens, scheme),
        ],
      ),
    );
  }

  Widget _row(Tag t, ThemeTokens tokens, ColorScheme scheme) {
    return InkWell(
      key: ValueKey('tg-row-${t.name}'),
      onTap: () async {
        await showTagEditSheet(context, ref, t);
        await _refresh();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.cardBorder)),
        ),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: tagToneColor(tagToneAt(t.id), tokens),
                shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text(
            t.isPublic
                ? '三处通用'
                : [for (final k in kTagScopes) if (t.appliesTo(k)) tagSceneName(k)].join('·'),
            style: TextStyle(fontSize: 11, color: tokens.text2),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text('${t.useCount} 条',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    color: tokens.text2,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Icon(Icons.chevron_right, size: 16, color: tokens.text2),
        ]),
      ),
    );
  }

  Widget _searchCard(ThemeTokens tokens, ColorScheme scheme) {
    final r = _search;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in r.tags)
                  GestureDetector(
                    key: ValueKey('tg-hit-${t.name}'),
                    onTap: () async {
                      await showTagEditSheet(context, ref, t);
                      await _refresh();
                      await _runSearch(_qCtrl.text);
                    },
                    child: TagChip(name: t.name, toneIndex: t.id),
                  ),
              ]),
            ),
          if (r.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Text('三个模块里都没有含「${_q.trim()}」的内容',
                  style: TextStyle(fontSize: 11, color: tokens.text2)),
            )
          else
            for (final row in r.rows)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(children: [
                  Icon(_sceneIcon(row.module), size: 14, color: tokens.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        if (row.sub.isNotEmpty)
                          Text(
                              row.tags.isEmpty
                                  ? row.sub
                                  : '${row.sub} · ${row.tags}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: tokens.text2)),
                      ],
                    ),
                  ),
                  Text(tagSceneName(row.module),
                      style: TextStyle(fontSize: 11, color: tokens.text2)),
                ]),
              ),
        ],
      ),
    );
  }

  IconData _sceneIcon(String key) => switch (key) {
        'diary' => Icons.menu_book_outlined,
        'note' => Icons.sticky_note_2_outlined,
        'time' => Icons.schedule,
        'public' => Icons.public,
        _ => Icons.label_outline,
      };
}

class _TopBtn extends StatelessWidget {
  const _TopBtn({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.cardBorder),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: tokens.text1)),
      ),
    );
  }
}

/// 删除确认（口径④：三模块一律解绑，内容本身不删）。
Future<bool> confirmTagDelete(BuildContext context, Tag t) => lhConfirm(
      context,
      '删除标签「${t.name}」？三个模块里所有引用都会解除，内容本身不删。',
    );
