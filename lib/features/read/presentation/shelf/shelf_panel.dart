part of 'shelf_page.dart';

// 治理G7d1b：排序与筛选面板群自 _ShelfPageState 移入同库扩展（行为零改动）。
// 半屏面板（_openPanel）+ 面板胶囊（_panelChip）；读写走 shelfUiProvider。
extension _ShelfPanel on _ShelfPageState {
  // ---------------- 排序与筛选面板 ----------------

  void _openPanel(BuildContext context, ShelfUI ui) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true, // F3-10 弹层骨架
      isScrollControlled: true,
      // ConstrainedBox 包 builder 会破坏 sheet 布局（按钮 hit-test 被 barrier 吸收）；限高走 constraints。
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            24,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // 轮3：键盘弹出时面板上移且限高，「清空筛选/完成」双钮不再被输入法遮挡。
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
        child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: Consumer(
                    builder: (_, ref2, _) {
                      // watch 当前 UI 态：面板内即时刷新选中态（不重开也对）
                      final ui = ref2.watch(shelfUiProvider);
                      void setUi(ShelfUI Function(ShelfUI) f) =>
                          ref2.read(shelfUiProvider.notifier).state = f(
                            ref2.read(shelfUiProvider),
                          );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '书架排序与筛选',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(sheetCtx).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 原型 2341：排序＝6 行竖排全宽按钮，选中显 ✓
                    for (final (k, t) in kShelfSorts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GestureDetector(
                          key: ValueKey('panel-sort-$k'),
                          onTap: () {
                            setUi((u) => u.copyWith(sort: k));
                            Navigator.of(sheetCtx).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: ui.sort == k
                                  ? context.tokens.accent.withValues(
                                      alpha: .12,
                                    )
                                  : Theme.of(
                                      sheetCtx,
                                    ).colorScheme.surfaceContainerHighest
                                      .withValues(alpha: .5),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: ui.sort == k
                                          ? context.tokens.accent
                                          : Theme.of(
                                              sheetCtx,
                                            ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (ui.sort == k)
                                  Icon(
                                    BsIcons.check,
                                    size: 14,
                                    color: context.tokens.accent,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      '分组方式',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (k, t) in kShelfDims)
                          _panelChip(
                            sheetCtx,
                            'panel-dim-$k',
                            t,
                            ui.dim == k,
                            () => setUi((u) => u.copyWith(dim: k, dimVal: '')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // 原型 2344：清空筛选 / 完成 双钮
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('panel-reset'),
                            onTap: () {
                              _kwCtl.clear();
                              setUi((u) => u.cleared);
                              readToast(context, '筛选与维度已清空');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              alignment: Alignment.center,
                              decoration: _cardDeco(context),
                              child: Text(
                                '清空筛选',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      Theme.of(
                                        sheetCtx,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('panel-done'),
                            onTap: () => Navigator.of(sheetCtx).pop(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: context.tokens.gradient,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text(
                                '完成',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _panelChip(
    BuildContext context,
    String key,
    String label,
    bool on,
    VoidCallback onTap,
  ) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: on
            ? context.tokens.accent.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: on ? context.tokens.accent : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: on ? context.tokens.accent : null,
        ),
      ),
    ),
  );
}
