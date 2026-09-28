part of 'shelf_page.dart';

// 治理G7d1d：批量管理群自 _ShelfPageState 移入同库扩展（行为零改动）。
// 浮动选择条与批量钮 / 退出多选 / 批量移书单·删除·加标签（走 shelfUiProvider + readTick）。
extension _ShelfBatchOps on _ShelfPageState {
  // ---------------- 批量管理浮动条（原型 849-855 / 4619-4628） ----------------

  Widget _batchBar(ShelfUI ui, ColorScheme cs, dynamic tokens) {
    final ids = ui.sel.toList();
    return Positioned(
      left: 16,
      right: 16,
      bottom: 22,
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const ValueKey('bat-bar'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
            boxShadow: tokens.cardShadow as List<BoxShadow>,
          ),
          child: Row(
            children: [
              Text(
                '已选 ${ids.length} 本',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              _batBtn('bat-move', '移入分区', cs, () => _batMove(ids)),
              const SizedBox(width: 6),
              _batBtn('bat-tag', '加标签', cs, () => _batTag(ids)),
              const SizedBox(width: 6),
              _batBtn(
                'bat-del',
                '删除',
                cs,
                () => _batDel(ids),
                danger: true,
              ),
              const Spacer(),
              _batBtn(
                'bat-cancel',
                '取消',
                cs,
                () => ref.read(shelfUiProvider.notifier).state =
                    ui.copyWith(batch: false, sel: const {}),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _batBtn(
    String key,
    String label,
    ColorScheme cs,
    VoidCallback onTap, {
    bool danger = false,
  }) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: danger
            ? const Color(0xFFFDBA74).withValues(alpha: .15)
            : cs.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: danger ? const Color(0xFFF43F5E) : cs.onSurfaceVariant,
        ),
      ),
    ),
  );

  void _exitBatch() => ref.read(shelfUiProvider.notifier).state = ref
      .read(shelfUiProvider)
      .copyWith(batch: false, sel: const {});

  /// 移入分区：以首本当前分区循环到下一分区（原型 shBatchMove 4619）。
  Future<void> _batMove(List<String> ids) async {
    final all = await ref.read(readRepositoryProvider).allBooks();
    final cur = all.firstWhere((b) => b.id == ids.first, orElse: () => all.first);
    final nx = Book.states[(Book.states.indexOf(cur.state) + 1) % 4];
    await ref.read(readRepositoryProvider).bulkSetState(ids, nx);
    ref.read(readTickProvider.notifier).state++;
    _exitBatch();
    if (mounted) readToast(context, '已将 ${ids.length} 本移入「$nx」');
  }

  /// 删除：软删（原型 shBatchDel 4627 的 30 天承诺＝softDeleteBooks）。
  Future<void> _batDel(List<String> ids) async {
    await ref.read(readRepositoryProvider).softDeleteBooks(ids);
    ref.read(readTickProvider.notifier).state++;
    _exitBatch();
    if (mounted) {
      readToast(context, '已移出书架 ${ids.length} 本（笔记与时长保留 30 天可恢复）');
    }
  }

  /// 加标签：选一个标签批量并集写入（原型 shBatchTag 4625 ＝ 真落库）。
  Future<void> _batTag(List<String> ids) async {
    final repo = ref.read(readRepositoryProvider);
    final tags = <String>{
      ...await repo.quoteTags(),
      ...[
        for (final b in ref.read(booksProvider).valueOrNull ?? const <Book>[])
          ...b.tags,
      ],
    }.where((t) => t.isNotEmpty).toList();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BatchTagSheet(count: ids.length, tags: tags),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final exist = await repo.dictOf(DictEntry.kTag);
    if (!exist.any((e) => e.name == picked)) {
      await repo.dictAdd(DictEntry.kTag, picked);
    }
    await repo.bulkAddTags(ids, [picked]);
    ref.read(readTickProvider.notifier).state++;
    _exitBatch();
    if (mounted) readToast(context, '已为 ${ids.length} 本加上 #$picked');
  }
}
