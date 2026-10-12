
import 'package:flutter/material.dart';

import '../domain/mindmap_layout.dart';
import '../domain/mindmap_models.dart';

/// 画布绘制器（批1 画布与批2 PNG 导出共用一份——导出即所见）。
///
/// 画布绘制器：网点底纹＋连线（批量 drawPath）＋节点（RRect＋TextPainter）。
/// 只画 [nodes] 里已裁剪过的可见节点（cull 在 build 侧算好）。
class MmCanvasPainter extends CustomPainter {
  MmCanvasPainter({
    required this.nodes,
    required this.layout,
    required this.scale,
    required this.pan,
    required this.selectedId,
    required this.nodeTitles,
    required this.mountedIds,
    required this.dxs,
    required this.dys,
    required this.bg,
    required this.grid,
    required this.nodeBg,
    required this.nodeBorder,
    required this.nodeText,
    required this.edge,
    required this.accent,
    required this.accentSoft,
  });

  final List<MindmapNode> nodes;
  final MmLayoutResult? layout;
  final double scale;
  final Offset pan;
  final int? selectedId;
  final Map<int, String> nodeTitles;
  final Set<int> mountedIds;
  final Map<int, double> dxs;
  final Map<int, double> dys;
  final Color bg, grid, nodeBg, nodeBorder, nodeText, edge, accent, accentSoft;

  Rect _nodeRect(MindmapNode n) {
    final l = layout!;
    final b = l.baseline[n.id!]!;
    final s = l.sizes[n.id!] ?? const Size(120, 36);
    final pos = (b + Offset(dxs[n.id!] ?? 0, dys[n.id!] ?? 0)) * scale + pan;
    return Rect.fromLTWH(pos.dx, pos.dy, s.width * scale, s.height * scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    // 网点底纹（§5.1：--mm-canvas 令牌对应物）。
    const gap = 22.0;
    final gp = Paint()..color = grid..strokeWidth = 1.4;
    final startX = pan.dx % gap;
    final startY = pan.dy % gap;
    for (var x = startX; x < size.width; x += gap) {
      for (var y = startY; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1, gp);
      }
    }
    final l = layout;
    if (l == null || nodes.isEmpty) return;

    // ── 连线：贝塞尔批量进同一 Path（渲染层七条之五）。
    // 横向树画法（真机 6113 实锤：旧纵向阶梯公式套横向布局＝斜穿节点＋
    // 子低于父时折点越界出悬空 V）：从父**侧边**中点水平切线出弧、进子
    // 侧边中点，两端切线全水平——子在上/下/平任何方位都平滑不穿节点。
    // 父子连线只在**两端都可见**时画（裁剪口径：视口外节点不进 draw 列表，
    // 单端可见的边也一并省略——树布局下行相邻，端点成对裁剪足够）。
    final byId = {for (final n in nodes) n.id!: n};
    final path = Path();
    for (final n in nodes) {
      final p = n.parentId;
      if (p == null || !byId.containsKey(p)) continue;
      final a = _nodeRect(byId[p]!);
      final b = _nodeRect(n);
      final childLeft = (l.assignedSides[n.id!] ?? 'r') == 'l';
      final ox = childLeft ? a.left : a.right;
      final ix = childLeft ? b.right : b.left;
      final midX = (ox + ix) / 2;
      path.moveTo(ox, a.center.dy);
      path.cubicTo(midX, a.center.dy, midX, b.center.dy, ix, b.center.dy);
    }
    canvas.drawPath(
        path, Paint()..color = edge..style = PaintingStyle.stroke..strokeWidth = 1.2);

    // ── 节点。
    for (final n in nodes) {
      final r = _nodeRect(n);
      final sel = n.id == selectedId;
      final paint = Paint()..color = nodeBg;
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(sel ? 2 : 0),
              Radius.circular((10 * scale.clamp(0.6, 1.4)).toDouble())),
          paint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              r.inflate(sel ? 2 : 0),
              Radius.circular((10 * scale.clamp(0.6, 1.4)).toDouble())),
          Paint()
            ..color = sel ? accent : nodeBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 1.6 : 0.8);
      if (sel) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                r.inflate(2), const Radius.circular(10)),
            Paint()..color = accentSoft);
      }
      // 标题（TextPainter 缓存量宽在 build 侧已算好尺寸；此处重排文本本身
      // 的成本由裁剪兜住——视口外节点不进本循环）。批2 F4-6：多行
      //（\n 换行、宽度按节点盒封顶），垂直居中于节点盒。
      final tp = TextPainter(
        text: TextSpan(
          text: nodeTitles[n.id] ?? n.title,
          style: TextStyle(
              fontSize: 13.5 * scale.clamp(0.5, 1.6),
              fontWeight: FontWeight.w600,
              color: nodeText),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width - 12);
      tp.paint(
          canvas,
          Offset(
              r.left + 6 + (r.width - 12 - tp.width) / 2,
              r.center.dy - tp.height / 2));
      // 挂载角标（尼尔森 6：挂载节点有可见角标）。
      if (mountedIds.contains(n.id)) {
        canvas.drawCircle(
            Offset(r.right - 4, r.top + 4), 3.4, Paint()..color = accent);
      }
    }
  }

  @override
  bool shouldRepaint(MmCanvasPainter old) =>
      old.scale != scale ||
      old.pan != pan ||
      old.selectedId != selectedId ||
      !identical(old.layout, layout) ||
      !identical(old.nodes, nodes) ||
      // 拖拽偏移走旁路 map（build 侧每次新字面量）——漏比＝拖拽帧不重画。
      !identical(old.dxs, dxs) ||
      !identical(old.dys, dys);
}
