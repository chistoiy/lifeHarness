part of 'mindmap_canvas_page.dart';

/// 画布页的**连接器操作面**（part 件，批P 抽出 · 2026-10-19）。
///
/// 为什么又是 part：这几段全要读写画布页的私有状态（`_nodes`/`_dao`/`_undo`/
/// `_layout`/`_pan`/`_selectedId`），抽独立 widget 得把十几条参数穿过边界；
/// 主文件已 1200 线上下，再塞必顶破 `size_budget` 默认面（同 `mindmap_canvas_ops`
/// 的抽出动机）。
///
/// 本 part 的口径（＝原型批P 已过门的那一套）：
/// · **连接＝改 `parent_id`**，零新列、零迁移；摘除＝置 null 回根层级；
/// · 成环在**入口**杜绝（自己的整枝不可点），不做「点了再报错」；
/// · 一次挂接＝撤销栈一步，label 用「连接到「X」／并入「X」／断开到根层级」；
/// · 目标处于折叠态时**自动展开**（否则「连了什么也看不见」）；
/// · 收起整枝/展开全部是**纯视图态**，不入命令栈。
extension _MmConnectOps on _MindmapCanvasPageState {
  /// 目标节点下的下一个兄弟序（挂到末尾；不重排既有兄弟）。
  int _nextSortOf(int? parentId) {
    var max = -1;
    for (final n in _nodes) {
      if (n.parentId == parentId && n.sort > max) max = n.sort;
    }
    return max + 1;
  }

  bool _hasChildrenOf(int id) => _nodes.any((n) => n.parentId == id);

  /// 进入连接态。根节点的动作语义是「整枝并入」（它没有父可挂，只能成为
  /// 别人的子级），文案与 label 都跟着变——与原型 `mmStartConnect` 同款。
  void _startConnect(MindmapNode n) {
    // ignore: invalid_use_of_protected_member
    setState(() {
      _connectFrom = n.id;
      _connectMerge = n.parentId == null;
    });
    _connectPulse.repeat(reverse: true);
    _makeRoomForConnectBar();
  }

  /// 退出连接态。呼吸相位**归零**（停住不回零＝下次进连接态第一帧是静态高亮，
  /// 看着像「只有这个能连」）。
  void _stopConnectPulse() {
    _connectPulse.stop();
    _connectPulse.value = 0;
  }

  void _cancelConnect({bool silent = false}) {
    if (_connectFrom == null) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _connectFrom = null;
      _connectMerge = false;
    });
    _stopConnectPulse();
    if (!silent) _toast('已取消连接');
  }

  /// 顶部提示条会盖住最上面那枚节点（多半就是根，而根是合法目标）：
  /// 进场时把画布整体下移让开。只动 `_pan`，不动任何节点数据。
  void _makeRoomForConnectBar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _connectFrom == null) return;
      final l = _layout;
      if (l == null) return;
      var minTop = double.infinity;
      for (final n in _nodes) {
        final id = n.id;
        if (id == null) continue;
        final b = l.baseline[id];
        if (b == null) continue;
        final top = (b + Offset(_dxOf(n), _dyOf(n))) * _scale + _pan;
        if (top.dy < minTop) minTop = top.dy;
      }
      const barH = 52.0;
      if (minTop.isFinite && minTop < barH + 8) {
        // ignore: invalid_use_of_protected_member
        setState(() => _pan = _pan + Offset(0, barH + 8 - minTop));
      }
    });
  }

  /// 把 [from] 挂到 [to] 下（mode 只影响文案与 label，数据动作同一条）。
  Future<void> _connectTo(MindmapNode from, MindmapNode to) async {
    final reason =
        mmConnectBlockReason(_nodes, child: from.id!, parent: to.id!);
    if (reason != null) {
      _toast(reason);
      return;
    }
    final merge = _connectMerge;
    final after = from.copyWith(
      parentId: to.id,
      sort: _nextSortOf(to.id),
      updatedAt: _now(),
    );
    await _dao.updateNode(after);
    // 目标折叠着就连进去也看不见——自动展开（原型同款）。
    if (to.folded) {
      await _dao.updateNode(to.copyWith(folded: false, updatedAt: _now()));
    }
    _undo.push(MmCommands.editNode(
      from,
      after,
      label: '${merge ? '并入' : '连接到'}「${to.title}」',
    ));
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _connectFrom = null;
      _connectMerge = false;
      _selectedId = from.id;
    });
    _stopConnectPulse();
    await _reloadNodes();
    _centerOnNode(to.id!);
    _toast(merge
        ? '已把「${from.title}」整枝并入「${to.title}」'
        : '已把「${from.title}」连接到「${to.title}」');
  }

  /// 摘除：只摘父子关系，节点与它自己的子级都保留（回根层级）。
  Future<void> _detachNode(MindmapNode n) async {
    if (n.parentId == null) {
      _toast('该节点已在根层级');
      return;
    }
    final after = n.copyWith(
      clearParent: true,
      sort: _nextSortOf(null),
      updatedAt: _now(),
    );
    await _dao.updateNode(after);
    _undo.push(MmCommands.editNode(n, after, label: '断开到根层级'));
    await _reloadNodes();
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() => _selectedId = n.id);
    _toast('已断开「${n.title}」· 现为根层级');
  }

  /// 收起整枝：只留当前这一枝。**祖先链必须保持展开**——把根也折了＝整屏空
  ///（原型轮探针抓到的真缺陷，实现侧同一坑）。
  Future<void> _collapseBranch(MindmapNode n) async {
    final keep = mmBranchOf(_nodes, n.id!);
    var changed = false;
    for (final x in _nodes) {
      final id = x.id;
      if (id == null) continue;
      final want = !keep.contains(id) && _hasChildrenOf(id);
      if (x.folded != want) {
        await _dao.updateNode(x.copyWith(folded: want, updatedAt: _now()));
        changed = true;
      }
    }
    if (!changed) {
      _toast('当前已经只剩这一枝');
      return;
    }
    await _reloadNodes();
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() => _selectedId = n.id);
    _toast('已收起其余枝，只留当前枝');
  }

  /// 展开全部（纯视图态，不入命令栈）。
  Future<void> _expandAll() async {
    var changed = false;
    for (final x in _nodes) {
      if (!x.folded) continue;
      await _dao.updateNode(x.copyWith(folded: false, updatedAt: _now()));
      changed = true;
    }
    if (!changed) {
      _toast('没有折叠着的节点');
      return;
    }
    await _reloadNodes();
    _toast('已展开全部节点');
  }

  /// 把视口挪到某节点（连接落位后「滚到落点」的实现；与 `_fit` 同坐标系）。
  void _centerOnNode(int id) {
    final l = _layout;
    final n = _byId(id);
    if (l == null || n == null) return;
    final b = l.baseline[id];
    if (b == null) return;
    final size = l.sizes[id] ?? const Size(120, _nodeH);
    final pos = (b + Offset(_dxOf(n), _dyOf(n))) * _scale;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _pan = Offset(
        _viewport.width / 2 - pos.dx - size.width * _scale / 2,
        _viewport.height / 2 - pos.dy - size.height * _scale / 2,
      );
    });
  }

  /// 连接态提示条（原型 `#mmConnectBar`：顶部一条＋取消）。
  Widget _connectBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final from = _connectFrom == null ? null : _byId(_connectFrom!);
    final title = from?.title ?? '';
    return Material(
      key: const ValueKey('mm-connect-bar'),
      color: cs.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: cs.primary.withValues(alpha: .34)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _connectMerge
                    ? '点一个目标节点，把「$title」整枝并入它下面'
                    : '点一个目标节点，把「$title」挂到它下面',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('mm-connect-cancel'),
              onPressed: _cancelConnect,
              style: TextButton.styleFrom(
                minimumSize: const Size(56, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                backgroundColor: cs.primary.withValues(alpha: .12),
                foregroundColor: cs.primary,
              ),
              child: const Text('取消',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
