part of 'mindmap_canvas_page.dart';

/// 画布页的**绘制面接线**（part 件，批P 抽出 · 2026-10-19）。
///
/// 抽出动因同 `mindmap_connect_ops`：画布页抽了三段 part 后仍贴着 `size_budget`
/// 的 1200 默认面，批P 又往 build 里加东西（AnimatedBuilder 包层＋连接三集＋
/// 呼吸相位），再塞必顶线。故把「绘制层那一棵子树」整体搬来本件——
/// **行为零改动**：只是 RepaintBoundary → AnimatedBuilder → CustomPaint 这段
/// 从 build 里挪进函数，键（`mm-canvas-paint`）与 painter 参数逐值不变
/// （既有 24 个画布用例靠这个键定位画布，抽件后一个都没动）。
extension _MmCanvasPaintOps on _MindmapCanvasPageState {
  /// 批P2：拖动中指针的屏幕位置＝画布局部坐标过一遍视口变换。
  Offset _linkTipOnScreen() {
    final d = _linkDrag;
    if (d == null) return Offset.zero;
    return d.at * _scale + _pan;
  }

  /// 批P2：画布坐标下的落点是否落在该节点盒内（拖线松手判定的备用口径；
  /// 主判定仍走 `_hitNode`——它与点击同一份命中区，不会出现「看着压住了
  /// 却挂不上」）。
  bool _linkOverNode(MindmapNode n) {
    final d = _linkDrag;
    if (d == null) return false;
    final l = _layout;
    final id = n.id;
    if (l == null || id == null) return false;
    final b = l.baseline[id];
    if (b == null) return false;
    final s = l.sizes[id] ?? const Size(120, _nodeH);
    final pos = b + Offset(_dxOf(n), _dyOf(n));
    return Rect.fromLTWH(pos.dx, pos.dy, s.width, s.height).contains(d.at);
  }
  /// 绘制层子树。入参＝本帧可见节点（裁剪后）。
  Widget _canvasPaintLayer(List<MindmapNode> painterNodes) {
    return RepaintBoundary(
      // 连接态与拖拽连接点都靠这枚呼吸控制器驱动帧：
      // 帧内只重建这一层（整页 setState 每帧太重）。
      child: AnimatedBuilder(
        animation: _connectPulse,
        builder: (context, _) => CustomPaint(
          key: const ValueKey('mm-canvas-paint'),
          painter: MmCanvasPainter(
            nodes: painterNodes,
            layout: _layout,
            scale: _scale,
            pan: _pan,
            selectedId: _selectedId,
            nodeTitles: {
              for (final n in _nodes)
                if (n.id != null) n.id!: _displayTitle(n),
            },
            mountedIds: {
              for (final n in _nodes)
                if (n.noteId != null) n.id!,
            },
            dxs: {
              for (final n in _nodes)
                if (n.id != null) n.id!: _dxOf(n),
            },
            dys: {
              for (final n in _nodes)
                if (n.id != null) n.id!: _dyOf(n),
            },
            style: _paintStyle,
            // 批5 三段：id 集与占位宽由本层算好传下去
            // （painter 不回头判节点字段，两层各判一次必走偏）。
            taskIds: {
              for (final n in _nodes)
                if (n.id != null && n.isTask) n.id!
            },
            doneTaskIds: {
              for (final n in _nodes)
                if (n.id != null && n.isTask && n.taskDone) n.id!
            },
            imageIds: {
              for (final n in _nodes)
                if (n.id != null && n.hasImage) n.id!
            },
            extraWidths: {
              for (final n in _nodes)
                if (n.id != null) n.id!: _extraWidthOf(n)
            },
            tagsOf: {
              for (final n in _nodes)
                if (n.id != null && n.tags.isNotEmpty)
                  n.id!: n.tags
            },
            // 批P：层级深度 / 聚焦降噪 / 连接态三集与相位。
            depths: mmDepths(_nodes),
            focusIds: _focusIds,
            connectTargetIds: _connectTargetIds,
            connectBlockedIds: _connectBlockedIds,
            connectPulse: _connectPulse.value,
            // 批P2：右缘连接点（选中才出，连接态期间让位）＋拖动中的连线。
            linkKnobId: _connectFrom == null ? _selectedId : null,
            linkFrom: _linkDrag == null
                ? null
                : _linkKnobCenter() == null
                    ? null
                    : _linkKnobCenter()! * _scale + _pan,
            linkTo: _linkDrag == null ? null : _linkTipOnScreen(),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
