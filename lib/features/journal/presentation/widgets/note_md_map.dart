import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../shared/linkage/mindmap_api.dart';
import '../../domain/note_outline.dart';

/// 笔记「导图」视图（md 结构 → 横向树，只读）。
///
/// 复用导图模块的布局引擎与画布绘制器：节点度量、列宽、父居中、连线画法、
/// 层级描边全部与导图页同一份实现——两处各写一套必然漂移（同族坑见
/// `mindmap_layout.dart` 的三引擎共用 `MmTreeIndex` 注释）。
///
/// **只读**：不给选中态、不给拖拽偏移、不给连接点；手势只有缩放/平移/双击归位。
/// 编辑仍回写作或源码视图——导图是「看结构」的第三只眼，不是第二个编辑器。
class NoteMdMapView extends StatefulWidget {
  const NoteMdMapView({
    super.key,
    required this.source,
    required this.title,
    required this.fg,
    required this.bg,
  });

  /// 正文 md 原文（`_bodyCtl.text`）。
  final String source;

  /// 中心主题＝笔记标题（空则「未命名笔记」，由解析层兜）。
  final String title;

  /// 纸面前景色/背景色（跟随笔记纸色，不跟主题色板——导图铺在纸上）。
  final Color fg;
  final Color bg;

  @override
  State<NoteMdMapView> createState() => _NoteMdMapViewState();
}

class _NoteMdMapViewState extends State<NoteMdMapView> {
  static const double _minScale = .25;
  static const double _maxScale = 2.4;

  /// 节点标题基准字号（与 `mmNodeMeasure` 的度量字号必须同源，否则盒子量宽
  /// 与实际排版不一致：多行标题会溢出盒子）。
  static const double _fontSize = 13.5;

  List<MindmapNode> _nodes = const <MindmapNode>[];
  Map<int, String> _titles = const <int, String>{};
  MmLayoutResult? _layout;

  double _scale = 1;
  Offset _pan = Offset.zero;

  /// 首帧（或内容变化后）按视口做一次 fit；用户动过手势后不再自动 fit。
  bool _fitted = false;

  double _startScale = 1;
  Offset _startPan = Offset.zero;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant NoteMdMapView old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source || old.title != widget.title) {
      _rebuild();
      _fitted = false;
    }
  }

  /// 解析 → 扁平节点表（id 按先序自增，parentId 串树）→ 横向树布局。
  void _rebuild() {
    final root = parseNoteOutline(widget.source, rootTitle: widget.title);
    final nodes = <MindmapNode>[];
    final titles = <int, String>{};
    var seq = 0;

    void walk(NoteOutlineNode n, int? parent, int sort) {
      final id = ++seq;
      nodes.add(MindmapNode(
        id: id,
        mapId: 0,
        parentId: parent,
        title: n.title,
        sort: sort,
        createdAt: 0,
        updatedAt: 0,
      ));
      titles[id] = n.title;
      for (var i = 0; i < n.children.length; i++) {
        walk(n.children[i], id, i);
      }
    }

    walk(root, null, 0);

    final engine = HorizontalTreeEngine(
      both: false,
      colGap: 34,
      rowGap: 8,
      // 根用 w800（painter 里根也是 w800）——度量与绘制不同权重会让根标题
      // 换行、盒子高度对不上。
      measure: (n) => mmNodeMeasure(
        n.title,
        style: TextStyle(
            fontSize: _fontSize,
            fontWeight:
                n.parentId == null ? FontWeight.w800 : FontWeight.w600),
        maxWidth: 240,
      ),
    );

    _nodes = nodes;
    _titles = titles;
    _layout = engine.layout(nodes);
  }

  /// 全图包围盒（布局基线坐标，未乘缩放）。
  Rect? _bounds() {
    final l = _layout;
    if (l == null || l.baseline.isEmpty) return null;
    Rect? out;
    for (final e in l.baseline.entries) {
      final s = l.sizes[e.key] ?? const Size(120, 36);
      final r = Rect.fromLTWH(e.value.dx, e.value.dy, s.width, s.height);
      out = out == null ? r : out.expandToInclude(r);
    }
    return out;
  }

  /// 缩放到整图可见并居中（双击空白＝归位）。
  void _applyFit(Size view) {
    final b = _bounds();
    if (b == null || b.width <= 0 || b.height <= 0) {
      _scale = 1;
      _pan = Offset.zero;
      return;
    }
    const pad = 22.0;
    final s = math
        .min((view.width - pad * 2) / b.width, (view.height - pad * 2) / b.height)
        .clamp(_minScale, 1.25)
        .toDouble();
    _scale = s;
    _pan = Offset(
        view.width / 2 - b.center.dx * s, view.height / 2 - b.center.dy * s);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startPan = _pan;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final next = (_startScale * d.scale).clamp(_minScale, _maxScale).toDouble();
    final k = next / _startScale;
    // 锚点公式：内容点 c 的屏幕位置＝c·s＋pan。让起始焦点在缩放中钉住，
    // 手指移动同时平移（`d.scale==1` 时退化为纯拖动）。
    final f = d.localFocalPoint;
    setState(() {
      _scale = next;
      _pan = f - (_startFocal - _startPan) * k;
    });
  }

  /// 纸面配色（不跟导图页的样式档：笔记导图铺在纸上，底色必须与纸一致）。
  MmPaintStyle _style(ColorScheme cs) => MmPaintStyle(
        bg: widget.bg,
        grid: widget.fg.withValues(alpha: .06),
        nodeBg: Color.alphaBlend(widget.fg.withValues(alpha: .035), widget.bg),
        nodeBorder: widget.fg.withValues(alpha: .22),
        nodeText: widget.fg,
        edge: widget.fg.withValues(alpha: .42),
        accent: cs.primary,
        accentSoft: cs.primary.withValues(alpha: .14),
        lineW: 1.2,
        fontSize: _fontSize,
        dots: false,
        okColor: cs.tertiary,
        onOkColor: cs.onTertiary,
        thumbBg: widget.fg.withValues(alpha: .08),
        tagBg: cs.primary.withValues(alpha: .15),
        tagText: cs.primary,
      );

  @override
  Widget build(BuildContext context) {
    final style = _style(Theme.of(context).colorScheme);
    return LayoutBuilder(builder: (ctx, c) {
      final view = Size(c.maxWidth, c.maxHeight);
      // 首帧 fit：直接改字段本帧即生效（不 setState——build 内改状态会触发
      // 额外一帧；这里只是把「还没定过视角」补上）。
      if (!_fitted && view.width > 8 && view.height > 8) {
        _applyFit(view);
        _fitted = true;
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onDoubleTap: () => setState(() => _applyFit(view)),
        child: ClipRect(
          child: CustomPaint(
            size: Size.infinite,
            painter: MmCanvasPainter(
              nodes: _nodes,
              layout: _layout,
              scale: _scale,
              pan: _pan,
              selectedId: null,
              nodeTitles: _titles,
              mountedIds: const <int>{},
              dxs: const <int, double>{},
              dys: const <int, double>{},
              style: style,
              // 笔记导图＝无框（只画文字＋S 形连线），与产品给的参考图一致；
              // 导图模块自身的画布仍是带框视觉（默认 false）。
              frameless: true,
            ),
          ),
        ),
      );
    });
  }
}
