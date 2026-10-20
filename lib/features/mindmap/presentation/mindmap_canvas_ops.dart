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

  /// 同级表（与布局引擎同一份序：sort 升序、同值按 id——`nodesOf` 的
  /// `sort ASC, id ASC` 落到内存后的等价物）。
  List<MindmapNode> _siblingsOf(MindmapNode n) {
    final out = _nodes.where((x) => x.parentId == n.parentId).toList();
    out.sort((a, b) {
      final c = a.sort.compareTo(b.sort);
      return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return out;
  }

  /// 节点在**屏幕**上的锚点（节点盒底边中点）。浮层贴点用。
  ///
  /// 换算链与读屏语义层同一份：`(baseline + 拖拽偏移) * scale + pan` 得画布
  /// 局部坐标，再加画布区左上角的全局位移。算不出来（布局未就绪/节点被裁）
  /// 时返回 null，调用侧退到屏心——宁可位置保守，也不要菜单飞出屏幕。
  Offset? _menuAnchorOf(MindmapNode n) {
    final id = n.id;
    final l = _layout;
    if (id == null || l == null) return null;
    final b = l.baseline[id];
    if (b == null) return null;
    final s = l.sizes[id] ?? const Size(120, _nodeH);
    final local = (b + Offset(_dxOf(n), _dyOf(n))) * _scale + _pan;
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final origin =
        (box != null && box.hasSize) ? box.localToGlobal(Offset.zero) : Offset.zero;
    return origin + local + Offset(s.width * _scale / 2, s.height * _scale);
  }

  Future<void> _showNodeMenu(MindmapNode n) async {
    // 批P：连接/摘除两项紧随「加子节点/加同级」（原型同序）；摘除只对
    // 非根节点有意义（根节点没有父，置它就是空操作，直接 disable 并给理由）。
    // 批P3：换序与剪贴板五枚接进同一份菜单——上移/下移按同级位次置灰，
    // 粘贴按剪贴板态置灰（没有内容时点它只会得到一句「剪贴板为空」）。
    final id = n.id;
    final sibs = _siblingsOf(n);
    final i = id == null ? -1 : sibs.indexWhere((x) => x.id == id);
    final canUp = i > 0;
    final canDown = i >= 0 && i < sibs.length - 1;
    final canPaste = MmClipboard.hasContent;
    final anchor = _menuAnchorOf(n) ??
        Offset(MediaQuery.sizeOf(context).width / 2,
            MediaQuery.sizeOf(context).height * .32);
    final key = await showMmMenuAt(
      context,
      anchor,
      headline: '${n.parentId == null ? '根节点' : '节点'} · ${_displayTitle(n)}',
      groups: [
        [
          (key: 'child', icon: Icons.account_tree_outlined, label: '添加子节点', enabled: true, inline: false),
          (key: 'sibling', icon: Icons.linear_scale, label: '添加同级节点', enabled: true, inline: false),
        ],
        [
          (
            key: 'connect',
            icon: Icons.account_tree_outlined,
            label: n.parentId == null ? '并入到…' : '连接到…',
            enabled: true,
            inline: false,
          ),
          (
            key: 'detach',
            icon: Icons.call_split,
            label: '断开并移到根层级',
            enabled: n.parentId != null,
            inline: false,
          ),
        ],
        [
          (key: 'edit', icon: Icons.edit_outlined, label: '编辑节点', enabled: true, inline: false),
          (
            key: 'bind',
            icon: Icons.link_outlined,
            label: n.noteId == null ? '挂载笔记' : '更换挂载笔记',
            enabled: true,
            inline: false,
          ),
          (
            key: 'fold',
            icon: n.folded ? Icons.unfold_more : Icons.unfold_less,
            label: n.folded ? '展开子节点' : '折叠子节点',
            enabled: true,
            inline: false,
          ),
          // 树内导航是纯视图态、两枚互斥，并排一行（原型 `.nm-row`）。
          (key: 'collapse', icon: Icons.compress, label: '收起整枝', enabled: true, inline: true),
          (key: 'expand', icon: Icons.expand, label: '展开全部', enabled: true, inline: true),
        ],
        [
          (
            key: 'reset',
            icon: Icons.center_focus_strong_outlined,
            label: '归位到自动布局',
            enabled: n.hasOffset || _liveDx.containsKey(n.id) || _liveDy.containsKey(n.id),
            inline: false,
          ),
        ],
        [
          (key: 'up', icon: Icons.arrow_upward, label: '上移', enabled: canUp, inline: true),
          (key: 'down', icon: Icons.arrow_downward, label: '下移', enabled: canDown, inline: true),
        ],
        [
          (key: 'copy', icon: Icons.content_copy, label: '复制（含子级）', enabled: true, inline: false),
          (key: 'cut', icon: Icons.content_cut, label: '剪切（含子级）', enabled: true, inline: false),
          (key: 'pasteSib', icon: Icons.content_paste, label: '粘贴同级', enabled: canPaste, inline: true),
          (key: 'pasteChild', icon: Icons.content_paste_go, label: '粘贴子级', enabled: canPaste, inline: true),
        ],
        [
          (key: 'del', icon: Icons.delete_outlined, label: '删除节点', enabled: true, inline: false),
        ],
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
      case 'up':
        await _moveSibling(n, -1);
      case 'down':
        await _moveSibling(n, 1);
      case 'copy':
        await _copyBranch(n);
      case 'cut':
        await _cutBranch(n);
      case 'pasteSib':
        await _pasteBranch(n, asChild: false);
      case 'pasteChild':
        await _pasteBranch(n, asChild: true);
      case 'del':
        await _deleteNode(n);
    }
  }

  /// 同级换序（原型 `mmMoveSibling`）：**只动兄弟之间的先后，父子关系一律不碰**。
  ///
  /// 常规档只写两行的 `sort`（交换值）；历史数据 `sort` 撞值时交换等于没换
  /// （布局按 sort 稳定排序，两行仍并列）——此时整组按新序重编号 0..n-1 兜底。
  /// 整组都在一条撤销步里，撤销即整组复原。到头的方向只给一句人话、不写历史。
  Future<void> _moveSibling(MindmapNode n, int dir) async {
    if (n.id == null) return;
    final sibs = _siblingsOf(n);
    final i = sibs.indexWhere((x) => x.id == n.id);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= sibs.length) {
      _toast(dir < 0 ? '已经是同级里的第一个' : '已经是同级里的最后一个');
      return;
    }
    final a = sibs[i];
    final b = sibs[j];
    final List<(MindmapNode, MindmapNode)> pairs;
    if (a.sort != b.sort) {
      pairs = [
        (a, a.copyWith(sort: b.sort, updatedAt: _now())),
        (b, b.copyWith(sort: a.sort, updatedAt: _now())),
      ];
    } else {
      final order = [...sibs];
      order[i] = b;
      order[j] = a;
      pairs = [
        for (var k = 0; k < order.length; k++)
          if (order[k].sort != k)
            (order[k], order[k].copyWith(sort: k, updatedAt: _now())),
      ];
    }
    if (pairs.isEmpty) return;
    _undo.push(MmCommands.updateRows(pairs, '调整同级顺序'));
    for (final (_, after) in pairs) {
      await _dao.updateNode(after);
    }
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member — extension 不在 State 子类体内
    setState(() {
      for (final (_, after) in pairs) {
        final k = _nodes.indexWhere((x) => x.id == after.id);
        if (k >= 0) _nodes[k] = after;
      }
    });
    _relayout();
    _toast(dir < 0 ? '已上移' : '已下移');
  }

  /// 整枝取数（含自己与全部后代），按**根在前、父先子后**排好。
  Future<List<MindmapNode>> _branchRows(MindmapNode n) async {
    final id = n.id!;
    final ids = await _dao.descendantIdsOf(id);
    final rows = await _dao.nodesOfIds(ids);
    return mmOrderSubtree(rows, id);
  }

  Future<void> _copyBranch(MindmapNode n) async {
    if (n.id == null) return;
    final rows = await _branchRows(n);
    if (!mounted) return;
    MmClipboard.put(rows, cut: false);
    _toast('已复制该枝（${rows.length} 个节点，含子级）');
  }

  /// 剪切＝「进剪贴板 ＋ 可撤销的整枝删除」。原型不给二次确认（剪切本身就是
  /// 可撤销动作，再问一遍等于同一件事问两次），这里跟随。
  Future<void> _cutBranch(MindmapNode n) async {
    if (n.id == null) return;
    final ids = await _dao.descendantIdsOf(n.id!);
    final rows = await _dao.nodesOfIds(ids);
    if (!mounted) return;
    MmClipboard.put(mmOrderSubtree(rows, n.id!), cut: true);
    await _dao.deleteNodeCascade(n.id!);
    _undo.push(MmCommands.deleteRows(rows, '剪切「${_displayTitle(n)}」'));
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member — extension 不在 State 子类体内
    setState(() {
      _nodes = _nodes.where((x) => !ids.contains(x.id)).toList();
      if (_selectedId != null && ids.contains(_selectedId)) _selectedId = null;
    });
    _relayout();
    _toast('已剪切该枝（${rows.length} 个节点）');
  }

  /// 粘贴（原型 `mmPasteNode`）。
  ///
  /// **默认同级**：落到选中节点的父下（选中是根＝贴成新根）；**粘贴子级**才挂进
  /// 选中节点——复制 A、选 B、粘贴，A 不再莫名变成 B 的子级。
  ///
  /// 根行的 `sort` 重算成目标父下「末尾 +1」：剪贴板里的 sort 是原位置的，
  /// 直接沿用会和目标父下现有兄弟撞值，粘出来的位置就不可预期。
  Future<void> _pasteBranch(MindmapNode n, {required bool asChild}) async {
    final rows = MmClipboard.peek();
    if (rows == null || rows.isEmpty) {
      _toast('剪贴板为空');
      return;
    }
    if (_nodes.length + rows.length > mmMaxNodes) {
      _toast('已达节点上限（$mmMaxNodes）');
      return;
    }
    final parentId = asChild ? n.id : n.parentId;
    if (asChild && parentId == null) {
      _toast('先选中要粘贴到的节点');
      return;
    }
    var siblingMax = -1;
    for (final x in _nodes) {
      if (x.parentId == parentId && x.sort > siblingMax) siblingMax = x.sort;
    }
    rows[0] = rows[0].copyWith(sort: siblingMax + 1);
    // 新 id 必须**先于插入**定好（父子映射要两趟补，见 pasteRemap）⇒ 取表内
    // 最大 id 后连续递增；单线程 UI 顺序执行不会撞。
    var seq = await _dao.maxNodeId();
    final (root, out) = await pasteRemap(
      rows: rows,
      targetMapId: widget.mapId,
      newRootParent: parentId,
      nextId: () => ++seq,
      now: _now(),
    );
    MmClipboard.take(); // 剪切语义在此清空；复制语义读而不清
    for (final r in out) {
      await _dao.insertNodeFull(r);
    }
    _undo.push(MmCommands.addSubtree(root, out));
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member — extension 不在 State 子类体内
    setState(() {
      _nodes = [..._nodes, ...out];
      _selectedId = root.id;
    });
    _textSizeCache.clear();
    _relayout();
    _toast('已粘贴 ${out.length} 个节点');
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
