import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book_dict.dart';
import 'read_providers.dart';
import 'read_sheets.dart';

/// 书架资料五类管理器（原型 p-bkmgr · §3.4 资料管理器行）：
/// 来源 / 分组 / 作者 / 出版社 / 标签横向 tab；新增、就地改名（事务回写 books）、
/// 删除前按引用计数守卫。入口＝阅读设置 → 数据与存储「书架资料」。
class BookMgrPage extends ConsumerStatefulWidget {
  const BookMgrPage({super.key, this.kind = DictEntry.kSource});

  final String kind;

  @override
  ConsumerState<BookMgrPage> createState() => _BookMgrPageState();
}

class _BookMgrPageState extends ConsumerState<BookMgrPage> {
  late String _kind = widget.kind;
  final _addCtl = TextEditingController();
  int? _renamingId;
  final _renameCtl = TextEditingController();

  @override
  void dispose() {
    _addCtl.dispose();
    _renameCtl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final repo = ref.read(readRepositoryProvider);
    final n = _addCtl.text.trim();
    // 原型 bmAdd 三态文案：空＝「先起个名字」；撞字典＝「已存在「v」」（原 ignore 会静默误报成功）。
    if (n.isEmpty) {
      readToast(context, '先起个名字');
      return;
    }
    final exist = await repo.dictOf(_kind);
    if (exist.any((e) => e.name == n)) {
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
    _renamingId = null;
    if (n.isEmpty || n == e.name) {
      setState(() {});
      return;
    }
    await ref.read(readRepositoryProvider).dictRename(e, n);
    ref.read(readTickProvider.notifier).state++;
    if (mounted) readToast(context, '已改名，相关书籍同步更新');
  }

  Future<void> _delete(DictEntry e) async {
    final n = await ref.read(readRepositoryProvider).dictRefCount(e);
    if (!mounted) return;
    if (n > 0) {
      readToast(context, '还有 $n 本在用 · 先改书籍资料再删');
      return;
    }
    await ref.read(readRepositoryProvider).dictDelete(e);
    ref.read(readTickProvider.notifier).state++;
    if (mounted) readToast(context, '已删除「${e.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final entries =
        ref.watch(dictProvider(_kind)).valueOrNull ?? const <DictEntry>[];
    return Scaffold(
      appBar: AppBar(title: const Text('书架资料')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SizedBox(
            height: 32,
            child: ListView(
              key: const ValueKey('bkm-tabs'),
              scrollDirection: Axis.horizontal,
              children: [
                for (final k in DictEntry.kinds)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      key: ValueKey('bkm-k-$k'),
                      onTap: () => setState(() {
                        _kind = k;
                        _renamingId = null;
                      }),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _kind == k
                              ? tokens.accent
                              : cs.surfaceContainerHighest
                                    .withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          DictEntry.label(k),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _kind == k
                                ? Colors.white
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
                      hintText: '新增${DictEntry.label(_kind)}名称…',
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
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '还没有${DictEntry.label(_kind)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final e in entries)
                        _row(cs, tokens, e),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, ThemeTokens tokens, DictEntry e) {
    final renaming = _renamingId == e.id;
    return Container(
      key: ValueKey('bkm-row-${e.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      key: ValueKey('bkm-rn-inp-${e.id}'),
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
                : Text(
                    e.name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          if (!renaming)
            TextButton(
              key: ValueKey('bkm-rename-${e.id}'),
              onPressed: () => setState(() {
                _renamingId = e.id;
                _renameCtl.text = e.name;
              }),
              child: const Text('改名', style: TextStyle(fontSize: 11.5)),
            ),
          if (renaming)
            TextButton(
              key: ValueKey('bkm-rn-ok-${e.id}'),
              onPressed: () => _rename(e),
              child: const Text('保存', style: TextStyle(fontSize: 11.5)),
            ),
          IconButton(
            key: ValueKey('bkm-del-${e.id}'),
            tooltip: '删除',
            icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
            onPressed: () => _delete(e),
          ),
        ],
      ),
    );
  }
}
