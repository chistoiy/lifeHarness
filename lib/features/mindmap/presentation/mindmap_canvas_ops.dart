part of 'mindmap_canvas_page.dart';

/// 画布页的**节点操作面**（part 件，批5 抽出）。
///
/// 为什么要 part 而不是独立 widget：这三段全都要读画布页的私有状态
/// （`_nodes`/`_layout`/`_undo`/`_dao`/`_byId`…），抽成独立件就得把十几条
/// 参数穿过边界；part 是同库私有可见（治理 G7c 族口径，reader_page 同样做法）。
///
/// **抽出动机＝体积**：画布页批4 后 1180 行，`size_budget` 默认面 1200，
/// 批5 要往里加任务勾选命中/三段接线，再塞就顶破预算线。故把
/// 「节点长按菜单 ＋ 读屏语义块 ＋ 两枚按钮构件」整段搬进本 part，
/// 主文件回落到默认面以下（按口径**不登记**）。
///
/// 本 part 另含**批5 F4-9 的三段接线**：
/// · [MmNodeDraft] → DAO 的四列写入（加/改节点都走这一份）；
/// · 画布点勾选框 → [mmCompleteNodeTask] 发事件（**不触发选中/拖拽**，
///   原型 `stopPropagation` 双保险在命中层做：勾选区先于节点命中判定）；
/// · 度量加宽（标签 chip/任务框/图片占位）——与 painter 同一份数据源。

extension _MmCanvasOps on _MindmapCanvasPageState {

  Future<void> _showNodeMenu(MindmapNode n) async {
    // 批P：连接/摘除两项紧随「加子节点/加同级」（原型同序）；摘除只对
    // 非根节点有意义（根节点没有父，置它就是空操作，直接 disable 并给理由）。
    final key = await showMmMenu(
      context,
      [
        (key: 'child', icon: Icons.account_tree_outlined, label: '添加子节点', enabled: true),
        (key: 'sibling', icon: Icons.linear_scale, label: '添加同级节点', enabled: true),
        (
          key: 'connect',
          icon: Icons.account_tree_outlined,
          label: n.parentId == null ? '并入到…' : '连接到…',
          enabled: true
        ),
        (
          key: 'detach',
          icon: Icons.call_split,
          label: '断开并移到根层级',
          enabled: n.parentId != null
        ),
        (key: 'edit', icon: Icons.edit_outlined, label: '编辑节点', enabled: true),
        (
          key: 'bind',
          icon: Icons.link_outlined,
          label: n.noteId == null ? '挂载笔记' : '更换挂载笔记',
          enabled: true
        ),
        (
          key: 'fold',
          icon: n.folded ? Icons.unfold_more : Icons.unfold_less,
          label: n.folded ? '展开子节点' : '折叠子节点',
          enabled: true
        ),
        (
          key: 'reset',
          icon: Icons.center_focus_strong_outlined,
          label: '归位到自动布局',
          enabled: n.hasOffset || _liveDx.containsKey(n.id) || _liveDy.containsKey(n.id)
        ),
        (key: 'del', icon: Icons.delete_outlined, label: '删除节点', enabled: true),
      ],
      // 树内导航是纯视图态、两枚互斥，并排一行（原型 `.nm-row`）。
      row: [
        (key: 'collapse', icon: Icons.compress, label: '收起整枝', enabled: true),
        (key: 'expand', icon: Icons.expand, label: '展开全部', enabled: true),
      ],
    );
    if (key == null || !mounted) return;
    switch (key) {
      case 'child':
        await _addChild(n.id);
      case 'sibling':
        await _addSibling(n);
      case 'connect':
        _startConnect(n);
      case 'detach':
        await _detachNode(n);
      case 'edit':
        await _editNode(n);
      case 'bind':
        await _bindNote(n);
      case 'fold':
        await _toggleFold(n);
      case 'reset':
        await _resetOffset(n);
      case 'collapse':
        await _collapseBranch(n);
      case 'expand':
        await _expandAll();
      case 'del':
        await _deleteNode(n);
    }
  }



  /// 读屏语义块（label＝标题＋挂载态；button＝可双击进笔记）。
  Widget _buildSemantics(BuildContext context, int id) {
    final l = _layout;
    if (l == null) return const SizedBox.shrink();
    final b = l.baseline[id];
    final n = _byId(id);
    if (b == null || n == null) return const SizedBox.shrink();
    final s = l.sizes[id] ?? const Size(120, _nodeH);
    final pos = (b + Offset(_dxOf(n), _dyOf(n))) * _scale + _pan;
    final mounted = n.noteId != null;
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IgnorePointer(
        child: SizedBox(
          width: s.width * _scale,
          height: s.height * _scale,
          child: Semantics(
            label: '${_displayTitle(n)}${mounted ? ' · 已挂载笔记' : ''}',
            button: mounted,
          ),
        ),
      ),
    );
  }

  Widget _zoomBtn(BuildContext context, IconData icon, VoidCallback onTap,
      {String? key}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40, // 触点 ≥44 视觉含 padding
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key == null ? null : ValueKey(key),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Icon(icon, size: 20, color: cs.onSurface),
        ),
      ),
    );
  }

  Widget _toolBtn(
    BuildContext context, {
    required ValueKey<String> key,
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : .42,
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: cs.onSurface),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
