part of 'mindmap_canvas_page.dart';

/// 画布手势补强（批P6 · 2026-10-21）。
///
/// 三条一起进：**滚轮/触控板缩放**（桌面与投屏场景原本完全没反应）、
/// **按钮缩放锚点改成屏中心**（原先只改 `_scale` 不动 `_pan`，观感是
/// 「从左上角往外撑」，连点几次刚看的那一枝就跑出屏了）、
/// **缩得很小时节点最小可点面**（25% 档下 40dp 行高只剩 10dp，
/// 手指根本点不中，而 25% 恰恰是大图唯一能看全局的档）。
///
/// **不引入 `InteractiveViewer`**（壳内页禁令，见画布页头段注）：滚轮走
/// `Listener.onPointerSignal`，其余仍由三分仲裁管。
extension _MmGestureOps on _MindmapCanvasPageState {
  /// 以某点（画布局部坐标）为锚缩放一档。屏中心 / 鼠标位置都走这里。
  void _zoomAt(Offset anchor, double factor) {
    final (s, p) = zoomAround(
      scale: _scale,
      pan: _pan,
      nextScale: _scale * factor,
      anchor: anchor,
    );
    if (s == _scale) return; // 已顶到上下限：不白刷一帧
    // ignore: invalid_use_of_protected_member
    setState(() {
      _scale = s;
      _pan = p;
    });
  }

  /// 按钮缩放：锚点＝画布中心（与原型 `mmZoomBy` 同口径）。
  void _zoomCenter(double factor) =>
      _zoomAt(Offset(_viewport.width / 2, _viewport.height / 2), factor);

  /// 滚轮 / 触控板双指滑动。
  ///
  /// 折算口径：`exp(-dy/300)`——鼠标滚轮一格（~100）约 1.4 倍，触控板
  /// 一格（~30）约 1.1 倍；指数形式天然对称（往上滚与往下滚互逆），
  /// 不像加减法在顶到上下限后回不来。
  ///
  /// **不做累计**（原想攒到几像素才动，结果触控板那种每帧 8~15 的小量
  /// 会被攒成「先不动、突然跳一下」）：单次滚动哪怕只有 3%，`zoomAround`
  /// 也照样算得出来；只有钳位顶死时它才返回原值，那时本来就该不动。
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    // 触控板「横向滚动」也走同一事件；只有纵向量才算缩放（横向上系统里
    // 是翻页手势，画布没有横向可翻的东西，直接忽略）。
    if (e.scrollDelta.dy == 0) return;
    _zoomAt(_localOf(e.position), math.exp(-e.scrollDelta.dy / 300));
  }

  /// 缩到很小时给节点「最小可点面」：屏幕上的命中盒不小于 44dp 见方
  /// （`_nodeH` 40 是 100% 时的行高下限，25% 只剩 10dp）。
  ///
  /// 只在**命中判定**里放宽，不动绘制尺寸——放大了画反而失真；放宽命中区
  /// 的风险是相邻节点互抢，故只在纵向（行距方向）适度放宽、横向仍按盒宽
  /// （横向节点之间隔着缩进与连线，空得更多）。重叠时取**中心最近**的那个，
  /// 而不是列表里第一个，否则缩小时点到的是旁边那枚。
  MindmapNode? hitNodeWithMinTouch(Offset canvas) {
    final l = _layout;
    if (l == null) return null;
    final vis = _visibleIds();
    // 目标屏幕尺寸（逐边）→ 换算回画布坐标要除的缩放比。
    final wantW = 44 / _scale;
    final wantH = 44 / _scale;
    MindmapNode? best;
    var bestDist = double.infinity;
    for (final id in vis) {
      final b = l.baseline[id];
      if (b == null) continue;
      final n = _byId(id);
      if (n == null) continue;
      final pos = b + Offset(_dxOf(n), _dyOf(n));
      final s = l.sizes[id] ?? const Size(120, _nodeH);
      final w = math.max(s.width, wantW);
      final h = math.max(s.height, wantH);
      // 放大到最小可点面时以中心为基准往外涨，节点盒本身仍完整覆盖。
      final rect = Rect.fromCenter(
        center: Offset(pos.dx + s.width / 2, pos.dy + s.height / 2),
        width: w,
        height: h,
      );
      if (!rect.contains(canvas)) continue;
      final d = (canvas - rect.center).distance;
      if (d < bestDist) {
        bestDist = d;
        best = n;
      }
    }
    return best;
  }
}
