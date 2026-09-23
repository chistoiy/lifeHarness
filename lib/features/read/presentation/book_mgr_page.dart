import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/book_dict.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'shelf_page.dart' show shelfUiProvider, ShelfUI, kShelfDimDict;

/// 书架资料管理页（原型 p-bkmgr + renderBm + bmSwitch 五类切换）：
/// kind 初始由路由 ?kind= 决定（书架维度行「管理X」/ 阅读设置「书架资料」入口），
/// 页内五类 chips 可互切（来源/分组/作者/出版社/标签的增删改都在这一项）；
/// 页头卡＝图标+标题+概述+回书架；行点按＝回书架并按该维度筛选（原型 bmFilter）；
/// 就地改名事务回写 books（原型 bmEditOk）；删除按引用计数守卫（原型 bmDel）。
class BookMgrPage extends ConsumerStatefulWidget {
  const BookMgrPage({super.key, this.kind = DictEntry.kSource});

  final String kind;

  @override
  ConsumerState<BookMgrPage> createState() => _BookMgrPageState();
}

class _BookMgrPageState extends ConsumerState<BookMgrPage> {
  final _addCtl = TextEditingController();
  String? _renamingName;
  final _renameCtl = TextEditingController();

  late String _kind = widget.kind;

  /// 五类切换序（原型 bmKindChips：来源/分组/作者/出版社/标签）。
  static const _kOrder = [
    DictEntry.kSource,
    DictEntry.kGroup,
    DictEntry.kAuthor,
    DictEntry.kPublisher,
    DictEntry.kTag,
  ];

  /// kind → 书架维度键（kShelfDimDict 反查：行点进书架筛选用）。
  String get _dim =>
      kShelfDimDict.entries
          .firstWhere((e) => e.value == _kind, orElse: () => const MapEntry('none', ''))
          .key;

  @override
  void dispose() {
    _addCtl.dispose();
    _renameCtl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final repo = ref.read(readRepositoryProvider);
    final n = _addCtl.text.trim();
    // 原型 bmAdd 三态文案：空＝「先起个名字」；撞值域（dict ∪ books）＝「已存在「v」」。
    if (n.isEmpty) {
      readToast(context, '先起个名字');
      return;
    }
    final inDict = (await repo.dictOf(_kind)).any((e) => e.name == n);
    final inBooks = (await repo.dictRefCounts(_kind)).containsKey(n);
    if (inDict || inBooks) {
      if (mounted) readToast(context, '已存在「$n」');
      return;
    }
    await repo.dictAdd(_kind, n);
    _addCtl.clear();
    ref.read(readTickProvider.notifier).state++;
    if (mounted) {
      readToast(context, '已新增${DictEntry.label(_kind)}「$n」');
    }
  }

  Future<void> _rename(DictEntry e) async {
    final n = _renameCtl.text.trim();
    _renamingName = null;
    if (n.isEmpty || n == e.name) {
      setState(() {});
      return;
    }
    await ref.read(readRepositoryProvider).dictRename(e, n);
    ref.read(readTickProvider.notifier).state++;
    if (mounted) readToast(context, '已改名为「$n」');
  }

  Future<void> _delete(DictEntry e) async {
    final n = await ref.read(readRepositoryProvider).dictRefCount(e);
    if (!mounted) return;
    if (n > 0) {
      // 原型 bmDel 守卫：被引用不可删，先去书里改掉该维度值。
      readToast(context, '还有 $n 本书在用，请先在这些书里改掉${DictEntry.label(_kind)}');
      return;
    }
    await ref.read(readRepositoryProvider).dictDelete(e);
    ref.read(readTickProvider.notifier).state++;
    if (mounted) readToast(context, '已删除「${e.name}」');
  }

  /// 行点按（原型 bmFilter 5291）：书架按该维度筛选 + 回书架 + toast。
  void _filterShelf(String name) {
    ref.read(shelfUiProvider.notifier).state = ShelfUI(
      dim: _dim,
      dimVal: name,
    );
    if (mounted) {
      readToast(context, '书架已筛选：${DictEntry.label(_kind)} = $name');
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/read/shelf');
    }
  }

  /// 回书架（原型 navTo('p-bookshelf')）：不设筛选、不 toast。
  void _backToShelf() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/read/shelf');
    }
  }

  /// 值域合并（原型 bmVals：dict ∪ books distinct），键＝名称、值＝引用计数。
  Map<String, DictEntry> _values() {
    final dict = ref.watch(dictProvider(_kind)).valueOrNull ??
        const <DictEntry>[];
    final counts =
        ref.watch(dictCountsProvider(_kind)).valueOrNull ??
        const <String, int>{};
    final out = {for (final e in dict) e.name: e};
    for (final v in counts.keys) {
      out.putIfAbsent(v, () => DictEntry(kind: _kind, name: v));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final values = _values();
    final counts = ref.watch(dictCountsProvider(_kind)).valueOrNull ??
        const <String, int>{};
    final bookTotal =
        (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
            .where((b) => !b.isDeleted)
            .length;
    return Scaffold(
      appBar: AppBar(title: Text(DictEntry.title(_kind))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            key: const ValueKey('bkm-head'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    DictEntry.icon(_kind),
                    size: 18,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DictEntry.title(_kind),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${values.length} 个${DictEntry.label(_kind)} · 覆盖 $bookTotal 本书',
                        key: const ValueKey('bkm-sum'),
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('bkm-back'),
                  onPressed: _backToShelf,
                  child: const Text(
                    '回书架',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 五类切换（原型 bmKindChips/bmSwitch）：来源/分组/作者/出版社/标签互切。
          Wrap(
            key: const ValueKey('bkm-kinds'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in _kOrder)
                GestureDetector(
                  key: ValueKey('bkm-k-$k'),
                  onTap: () => setState(() {
                    _kind = k;
                    _renamingName = null;
                    _addCtl.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _kind == k
                          ? tokens.accent.withValues(alpha: .12)
                          : cs.surfaceContainerHighest.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _kind == k ? tokens.accent : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      DictEntry.label(k),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _kind == k
                            ? tokens.accent
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    key: ValueKey('bkm-add-inp-$_kind'),
                    controller: _addCtl,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: '新增名称…',
                      hintStyle: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: cs
                          .surfaceContainerHighest
                          .withValues(alpha: .35),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: ValueKey('bkm-add-$_kind'),
                onPressed: _add,
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: values.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '还没有条目，先在下方添加',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final e in values.values)
                        _row(cs, e, counts[e.name] ?? 0),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, DictEntry e, int n) {
    final rk = '${e.id ?? e.name}';
    final renaming = _renamingName == e.name;
    return GestureDetector(
      key: ValueKey('bkm-row-$rk'),
      behavior: HitTestBehavior.opaque,
      onTap: renaming ? null : () => _filterShelf(e.name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: .3),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: renaming
                  ? SizedBox(
                      height: 36,
                      child: TextField(
                        key: ValueKey('bkm-rn-inp-$rk'),
                        controller: _renameCtl,
                        autofocus: true,
                        style: const TextStyle(fontSize: 12.5),
                        onSubmitted: (_) => _rename(e),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '$n 本${n > 0 ? ' · 点行进书架筛选' : ' · 暂无书引用，可删除'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
            if (!renaming)
              TextButton(
                key: ValueKey('bkm-rename-$rk'),
                onPressed: () => setState(() {
                  _renamingName = e.name;
                  _renameCtl.text = e.name;
                }),
                child: const Text('改名', style: TextStyle(fontSize: 11.5)),
              ),
            if (renaming)
              TextButton(
                key: ValueKey('bkm-rn-ok-$rk'),
                onPressed: () => _rename(e),
                child: const Text('确定', style: TextStyle(fontSize: 11.5)),
              ),
            Opacity(
              opacity: n > 0 ? .3 : 1,
              child: IconButton(
                key: ValueKey('bkm-del-$rk'),
                tooltip: '删除',
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                onPressed: () => _delete(e),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
