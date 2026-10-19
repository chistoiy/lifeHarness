
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart';

import '../domain/mindmap_layout.dart';
import '../domain/mindmap_models.dart';
import '../domain/mindmap_style.dart';
import '../domain/mindmap_tree.dart' show mmTierOf;

/// 画布绘制器（批1 画布与批2 PNG 导出共用一份——导出即所见）。
///
/// 画布绘制器：网点底纹＋连线（批量 drawPath）＋节点（RRect＋TextPainter）。
/// 只画 [nodes] 里已裁剪过的可见节点（cull 在 build 侧算好）。
///
/// 批3 样式层：绘制面整体收进 [style]（一份 `MmPaintStyle`）——画布页与
/// PNG 导出调同一个工厂，导出即所见；「未设样式」时工厂返回批2 基线值
/// （逐值相等＝默认态零视觉变化）。
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
    required this.style,
    this.taskIds = const <int>{},
    this.doneTaskIds = const <int>{},
    this.imageIds = const <int>{},
    this.extraWidths = const <int, double>{},
    this.tagsOf = const <int, List<String>>{},
    this.depths = const <int, int>{},
    this.focusIds = const <int>{},
    this.connectTargetIds = const <int>{},
    this.connectBlockedIds = const <int>{},
    this.connectPulse = 0,
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

  /// 批3 样式层解析结果（档位 → 令牌实际色，含连线粗细/字号/网点开关）。
  final MmPaintStyle style;

  /// 批5：任务节点 / 已完成任务 / 已挂图节点的 id 集（由画布页按节点字段
  /// 整出来传进来）——**painter 不回头读节点对象**，与 `nodeTitles` 同款口径，
  /// 免得同一件事在两层各判一次。
  final Set<int> taskIds;
  final Set<int> doneTaskIds;
  final Set<int> imageIds;

  /// 批5：逐节点三段占位宽与标签表（**与度量同源**，画布页把同一份算好的值
  /// 传进来；painter 自己再猜一遍宽度＝标题压到 chip 上的经典洞）。
  final Map<int, double> extraWidths;
  final Map<int, List<String>> tagsOf;

  /// 批P L1：id → 深度（根＝0）。绘制按层分级：根＝主色描边＋淡底＋加粗，
  /// 二三级起描边降一档透明度。**由画布页算好传进来**（与连接态/聚焦态同一份
  /// 判定，painter 不自己再走一遍树）。
  final Map<int, int> depths;

  /// 批P L5：聚焦态保留集（自己＋祖先＋后代）。**空集＝不聚焦**（默认态零变化）。
  final Set<int> focusIds;

  /// 批P P1 连接态：可点目标（描边闪烁）与成环目标（置灰）。
  final Set<int> connectTargetIds;
  final Set<int> connectBlockedIds;

  /// 连接态呼吸值 0~1（页面侧 AnimationController 驱动；静态时 0）。
  final double connectPulse;

  /// 勾选框边长（原型 `.mm-task` 15px）。
  static const double taskBox = 15;

  /// 图片缩略占位边长（原型 `.mm-thumb` 22px）。
  static const double thumbBox = 22;

  Color get bg => style.bg;
  Color get grid => style.grid;
  Color get nodeBg => style.nodeBg;
  Color get nodeBorder => style.nodeBorder;
  Color get nodeText => style.nodeText;
  Color get edge => style.edge;
  Color get accent => style.accent;
  Color get accentSoft => style.accentSoft;

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
    // 网点底纹（§5.1：--mm-canvas 令牌对应物）。批3 样式层：画布背景档
    // 非「网点」时整层不画（对应原型 `cv.style.background` 覆盖底纹）。
    const gap = 22.0;
    if (style.dots) {
      final gp = Paint()..color = grid..strokeWidth = 1.4;
      final startX = pan.dx % gap;
      final startY = pan.dy % gap;
      for (var x = startX; x < size.width; x += gap) {
        for (var y = startY; y < size.height; y += gap) {
          canvas.drawCircle(Offset(x, y), 1, gp);
        }
      }
    }
    final l = layout;
    if (l == null || nodes.isEmpty) return;

    // ── 连线：贝塞尔批量进同一 Path（渲染层七条之五）。
    // **画法由布局形态决定**（批4：`layout.edgeKind` 声明、painter 只照办）：
    // · 纵向大纲（`stair`）＝**保持批2 既有横向贝塞尔**（真机 6113 实锤修形、
    //   6115 已装机验证）——本批不动默认形态的连线，一个像素都不改
    //   （批4 验收项②「默认态零视觉变化」的实现手段）。
    // · 横向树/放射（`branch`/`radial`）＝父中心 → 子中心直线：父左子右或
    //   根居中发散，套纵向阶梯公式会斜穿节点（6113 实锤同族坑：阶梯公式套
    //   横向布局＝连线斜穿＋折点越界出悬空 V）。
    // 父子连线只在**两端都可见**时画（裁剪口径：视口外节点不进 draw 列表，
    // 单端可见的边也一并省略——树布局下行相邻，端点成对裁剪足够）。
    // 批P L1/L3：主干（从根出发的边）单独一条 path——主色、加粗，与细枝分开画；
    // 两条 path 都画在节点之下，节点盒不透明底把穿盒处盖住（连线不再像断线）。
    final childPath = Path();
    final rootPath = Path();
    var hasRootEdge = false;
    for (final route in mmEdgeRoutes(
      nodes: nodes,
      edgeKind: l.edgeKind,
      assignedSides: l.assignedSides,
      rectOf: _nodeRect,
    )) {
      final pts = route.points;
      final p = route.fromRoot ? rootPath : childPath;
      if (route.fromRoot) hasRootEdge = true;
      p.moveTo(pts.first.dx, pts.first.dy);
      if (pts.length == 2) {
        p.lineTo(pts.last.dx, pts.last.dy);
      } else {
        // 阶梯贝塞尔的控制点镜像（批2 口径：两端切线全水平）。
        p.cubicTo(pts[1].dx, pts[1].dy, pts[2].dx, pts[2].dy,
            pts[3].dx, pts[3].dy);
      }
    }
    canvas.drawPath(
        childPath,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.lineW);
    if (hasRootEdge) {
      canvas.drawPath(
          rootPath,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.lineW + 0.9 * scale.clamp(.8, 1.4)
            ..strokeCap = StrokeCap.round);
    }

    // ── 节点（批P：按「置灰 / 降噪 / 正常」三组画，见下方分组）。
    void paintNode(MindmapNode n) {
      final r = _nodeRect(n);
      final sel = n.id == selectedId;
      final tier = mmTierOf(depths[n.id] ?? 0);
      // 批P L1 层级分级：根＝主色描边 2px＋9% 淡底＋加粗；二三级起描边降一档透明度。
      // 淡底用 alphaBlend 预先合成到节点底色上（Canvas 直接画半透明会透出连线）。
      final fill = tier == 0
          ? Color.alphaBlend(accent.withValues(alpha: .09), nodeBg)
          : nodeBg;
      final baseBorder = switch (tier) {
        0 => accent,
        2 => nodeBorder.withValues(alpha: nodeBorder.a * .72),
        3 => nodeBorder.withValues(alpha: nodeBorder.a * .52),
        _ => nodeBorder,
      };
      final bw = sel ? 1.6 : (tier == 0 ? 2.0 : 0.8);
      final radius = Radius.circular((10 * scale.clamp(0.6, 1.4)).toDouble());
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(sel ? 2 : 0), radius),
          Paint()..color = fill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(sel ? 2 : 0), radius),
          Paint()
            ..color = sel ? accent : baseBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = bw);
      if (sel) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                r.inflate(2), const Radius.circular(10)),
            Paint()..color = accentSoft);
      }
      // 标题（TextPainter 缓存量宽在 build 侧已算好尺寸；此处重排文本本身
      // 的成本由裁剪兜住——视口外节点不进本循环）。批2 F4-6：多行
      //（\n 换行、宽度按节点盒封顶），垂直居中于节点盒。
      // 批3 样式层：字号走样式档（基准值来自 MmPaintStyle.fontSize，
      // 与度量 `mmNodeMeasure` 同源——档位改字号时盒宽随之重算）。
      // **批5**：标题左侧留出三段占位（勾选框/缩略块），右侧留出标签 chip；
      // 三段的横向排布从左到右＝任务框 → 图片 → 标题 → 标签（原型同款顺序）。
      final boxW = taskBox * scale.clamp(0.6, 1.4);
      final thumbW =
          imageIds.contains(n.id) ? thumbBox * scale.clamp(0.6, 1.4) : 0.0;
      final leadW = (taskIds.contains(n.id) ? boxW + 3 : 0.0) +
          (imageIds.contains(n.id) ? thumbW + 3 : 0.0);
      final tags = tagsOf[n.id] ?? const <String>[];
      final tp = TextPainter(
        text: TextSpan(
          text: nodeTitles[n.id] ?? n.title,
          style: TextStyle(
              fontSize: style.fontSize * scale.clamp(0.5, 1.6),
              fontWeight: tier == 0 ? FontWeight.w800 : FontWeight.w600,
              color: nodeText),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(20, r.width - 12 - leadW));
      // **默认态零视觉变化**（同批3/批4 口径）：**无任何批5 角标**的节点仍走
      // 批2 的标题水平居中；一旦有勾选框/缩略块/标签，才改为左起顺排
      // （原型是 flex 行内顺排，居中会让标题压在角标上）。
      final tpX = leadW == 0 && tags.isEmpty
          ? r.left + 6 + (r.width - 12 - tp.width) / 2
          : r.left + 6 + leadW;
      tp.paint(canvas, Offset(tpX, r.center.dy - tp.height / 2));
      // 批5 三段角标（在标题之后画，与原型 DOM 顺序一致：先角标后标题）。
      var markX = r.left + 6;
      if (taskIds.contains(n.id)) {
        final done = doneTaskIds.contains(n.id);
        final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(markX, r.center.dy - boxW / 2, boxW, boxW),
            Radius.circular(boxW * 0.28));
        canvas.drawRRect(
            rect,
            Paint()
              ..color = done ? style.okColor : Colors.transparent
              ..style = done ? PaintingStyle.fill : PaintingStyle.stroke
              ..strokeWidth = 1.6);
        if (done) {
          // 勾号：两笔直线（线性、无 emoji 禁令合规）。
          final p = Path()
            ..moveTo(markX + boxW * .28, r.center.dy)
            ..lineTo(markX + boxW * .44, r.center.dy + boxW * .17)
            ..lineTo(markX + boxW * .74, r.center.dy - boxW * .19);
          canvas.drawPath(
              p,
              Paint()
                ..color = style.onOkColor
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(1, boxW * .16)
                ..strokeCap = StrokeCap.round);
        }
        markX += boxW + 3;
      }
      if (imageIds.contains(n.id)) {
        final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(markX, r.center.dy - thumbW / 2, thumbW, thumbW),
            Radius.circular(thumbW * 0.24));
        canvas.drawRRect(rect, Paint()..color = style.thumbBg);
        canvas.drawRRect(
            rect,
            Paint()
              ..color = nodeBorder
              ..style = PaintingStyle.stroke
              ..strokeWidth = .8);
        markX += thumbW + 3;
      }
      // 标签 chip：跟在标题右侧，超出节点盒就截断（截断仅视觉，数据完整）。
      if (tags.isNotEmpty) {
        var tx = r.left + 6 + leadW + tp.width + 4;
        final th = math.min(14.0 * scale.clamp(.6, 1.4), r.height - 6);
        for (final t in tags) {
          final tw = t.length * 6.0 * scale.clamp(.6, 1.4) + 8;
          if (tx + tw > r.right - 4) break;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(tx, r.center.dy - th / 2, tw, th),
                  Radius.circular(th * .34)),
              Paint()..color = style.tagBg);
          final chip = TextPainter(
            text: TextSpan(
              text: t,
              style: TextStyle(
                  fontSize: 9 * scale.clamp(.6, 1.4),
                  fontWeight: FontWeight.w800,
                  color: style.tagText),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          chip.paint(canvas, Offset(tx + 4, r.center.dy - chip.height / 2));
          tx += tw + 3;
        }
      }
      // 挂载角标（尼尔森 6：挂载节点有可见角标）。
      if (mountedIds.contains(n.id)) {
        canvas.drawCircle(
            Offset(r.right - 4, r.top + 4), 3.4, Paint()..color = accent);
      }
      // 批P P1：可点目标描边（呼吸值由页面 AnimationController 驱动）；
      // 成环目标不画环——它整枚被置灰，画环反而像「可以点」。
      if (connectTargetIds.contains(n.id)) {
        final ring = 0.30 + 0.34 * connectPulse;
        final inflate = 3 * scale.clamp(.8, 1.4);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                r.inflate(inflate),
                Radius.circular(12 * scale.clamp(.8, 1.4))),
            Paint()
              ..color = accent.withValues(alpha: ring)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                r.inflate(inflate + 2),
                Radius.circular(13 * scale.clamp(.8, 1.4))),
            Paint()
              ..color = accent.withValues(alpha: ring * .45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4);
      }
    }

    // 三组画序：置灰组 → 降噪组 → 正常/聚焦组。
    // 每组最多一层 saveLayer，**不做逐节点 saveLayer**（大图聚焦态下那是上百层）。
    final blockedNodes = <MindmapNode>[];
    final dimNodes = <MindmapNode>[];
    final hotNodes = <MindmapNode>[];
    for (final n in nodes) {
      final id = n.id;
      if (id != null && connectBlockedIds.contains(id)) {
        blockedNodes.add(n);
      } else if (id != null && focusIds.isNotEmpty && !focusIds.contains(id)) {
        dimNodes.add(n);
      } else {
        hotNodes.add(n);
      }
    }

    void paintGroup(List<MindmapNode> group, double alpha) {
      if (group.isEmpty) return;
      if (alpha >= 1) {
        for (final n in group) {
          paintNode(n);
        }
        return;
      }
      canvas.saveLayer(
          Offset.zero & size,
          Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
      for (final n in group) {
        paintNode(n);
      }
      canvas.restore();
    }

    paintGroup(blockedNodes, .32);
    paintGroup(dimNodes, .4);
    paintGroup(hotNodes, 1);
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
      !identical(old.dys, dys) ||
      // 批3 样式层：换档后画布必须重画。MmPaintStyle 是不可变值对象，
      // 逐值 == 即可（漏比＝改样式不重画，与批2 dx/dy 漏比同族）。
      old.style != style ||
      // 批5：三段角标漏比＝勾选/挂图/改标签后画布不重画（用户以为没生效）。
      !setEquals(old.taskIds, taskIds) ||
      !setEquals(old.doneTaskIds, doneTaskIds) ||
      !setEquals(old.imageIds, imageIds) ||
      !mapEquals(old.extraWidths, extraWidths) ||
      !mapEquals(old.tagsOf, tagsOf) ||
      // 批P：层级/聚焦/连接态漏比＝改状态后画布不重画（与 dx/dy 漏比同族坑）。
      !mapEquals(old.depths, depths) ||
      !setEquals(old.focusIds, focusIds) ||
      !setEquals(old.connectTargetIds, connectTargetIds) ||
      !setEquals(old.connectBlockedIds, connectBlockedIds) ||
      old.connectPulse != connectPulse;
}

/// 一条连线的路由点列（[MmEdgeRoutes] 的元素）。
///
/// `points` 长度 2＝直线（父中心→子中心）；长度 4＝阶梯贝塞尔的
/// 「起点/控制点1/控制点2/终点」。做成数据而不是直接在 paint 里画，
/// 是为了让**画法分派本身可被常驻用例直接断言**（批4 变异刀3 钉位：
/// 横向树/放射必须走两点直线，套阶梯公式＝斜穿节点）。
class MmEdgeRoute {
  const MmEdgeRoute(
      {required this.childId, required this.points, this.fromRoot = false});

  final int childId;
  final List<Offset> points;

  /// 批P L1：这条边是否从根出发（主干）。主干单独一条 path，主色＋加粗。
  final bool fromRoot;

  bool get isStraight => points.length == 2;
}

/// 批量算本帧所有父子连线（批4）。**画法只由 [edgeKind] 决定**：
/// · [MmEdgeKind.stair]＝纵向大纲（批2 修形的横向贝塞尔，两端切线全水平）；
/// · [MmEdgeKind.branch]／[MmEdgeKind.radial]＝父中心 → 子中心直线。
///
/// 单端可见的边一并省略（与 paint 侧裁剪口径一致：树布局下行相邻，
/// 端点成对裁剪足够）。
List<MmEdgeRoute> mmEdgeRoutes({
  required List<MindmapNode> nodes,
  required MmEdgeKind edgeKind,
  required Map<int, String> assignedSides,
  required Rect Function(MindmapNode n) rectOf,
}) {
  final byId = {for (final n in nodes) n.id!: n};
  final out = <MmEdgeRoute>[];
  for (final n in nodes) {
    final p = n.parentId;
    if (p == null || !byId.containsKey(p)) continue;
    final parent = byId[p]!;
    final a = rectOf(parent);
    final b = rectOf(n);
    // 批P L1：父是根（自己没有父）⇒ 这条是主干，画的时候主色加粗。
    final top = parent.parentId == null || !byId.containsKey(parent.parentId!);
    if (edgeKind == MmEdgeKind.stair) {
      final childLeft = (assignedSides[n.id!] ?? 'r') == 'l';
      final ox = childLeft ? a.left : a.right;
      final ix = childLeft ? b.right : b.left;
      final midX = (ox + ix) / 2;
      out.add(MmEdgeRoute(
        childId: n.id!,
        fromRoot: top,
        points: [
          Offset(ox, a.center.dy),
          Offset(midX, a.center.dy),
          Offset(midX, b.center.dy),
          Offset(ix, b.center.dy),
        ],
      ));
    } else {
      out.add(MmEdgeRoute(
          childId: n.id!, fromRoot: top, points: [a.center, b.center]));
    }
  }
  return out;
}
