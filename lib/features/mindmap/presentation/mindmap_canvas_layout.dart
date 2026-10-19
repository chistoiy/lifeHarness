part of 'mindmap_canvas_page.dart';

/// 版式选择面（实现批 P 从 mindmap_canvas_page.dart 原样抽出：块内逐字未改）。
extension _MmLayoutOps on _MindmapCanvasPageState {
  // ==================== 布局家族（批4 F4-8） ====================

  /// 打开布局弹层（原型 `mmOpenLayout`：画布高频直达，缩放条上布局钮）。
  /// 点预设**即时生效并入撤销栈一步**（原型 `mmApplyPreset` 走
  /// `mmPushHistory('切换布局')`，同款语义）——关闭弹层不回滚。
  Future<void> _openLayout() async {
    final store = MmLayoutStore(ref.read(sharedPreferencesProvider));
    await showMmLayoutSheet(
      context,
      initial: _view,
      onChanged: (next) => _applyPreset(store, next),
    );
  }

  /// 应用一份布局预设：重算基线 → fit 全图可见 → 落 prefs → 入撤销栈。
  ///
  /// **不清 `dx/dy`**（批4 验收项③）：切布局只重算基线，用户拖过的节点仍在
  /// 相对原位——否则「换个布局看看」会把用户摆好的位置全丢掉。
  Future<void> _applyPreset(
      MmLayoutStore store, MmLayoutPreset next) async {
    final before = _preset;
    if (before == next) return;
    // ignore: invalid_use_of_protected_member
    setState(() => _preset = next);
    _relayout();
    _fit();
    _undo.push(MmCommand(
      label: '切换布局',
      redo: (_) async {
        await store.save(widget.mapId, next);
        if (!mounted) return;
        // ignore: invalid_use_of_protected_member
        setState(() => _preset = next);
        _relayout();
        _fit();
      },
      undo: (_) async {
        if (before == null) {
          await store.reset(widget.mapId);
        } else {
          await store.save(widget.mapId, before);
        }
        if (!mounted) return;
        // ignore: invalid_use_of_protected_member
        setState(() => _preset = before);
        _relayout();
        _fit();
      },
    ));
    await store.save(widget.mapId, next);
    if (mounted) _toast('布局＝${_presetLabel(next)}');
  }

  String _presetLabel(MmLayoutPreset p) {
    for (final c in mmLayoutCards) {
      if (c.preset == p) return c.title;
    }
    return p.key;
  }
}