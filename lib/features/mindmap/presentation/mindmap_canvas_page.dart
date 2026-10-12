import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../../shared/linkage/mindmap_mounts.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers.dart' show sharedPreferencesProvider;
import '../data/mindmap_dao.dart';
import '../domain/mindmap_layout.dart';
import '../domain/mindmap_measure.dart';
import '../domain/mindmap_models.dart';
import '../domain/mindmap_style.dart';
import '../domain/mindmap_undo.dart';
import '../domain/mindmap_viewport.dart';
import 'mindmap_export_actions.dart';
import 'mindmap_painter.dart';
import 'mindmap_sheets.dart';
import 'mindmap_style_sheet.dart';

/// 画布主屏（原型 mm-canvas · push 路由 `/mindmap/canvas?id=`）。
///
/// 渲染层七条（冻结方案 §6.3，批 1 硬要求）：
/// `CustomPainter`＋单 `RepaintBoundary`；可视区裁剪（[cullVisibleNodes]）；
/// `TextPainter` 缓存量宽（键＝标题文本）；拖拽局部重画；连线批量 `drawPath`；
/// 手势帧内只更 Transform。**禁用 `InteractiveViewer`**（壳内页禁令·V1.65
/// 底栏双指共存面）——手势在 [GestureDetector.onTapDown] 之下走
/// `Listener` 原始指针**自行三分仲裁**（拖节点/拖空白平移/双指捏合，§4.1）。
enum _MmGestureMode { idle, pending, dragNode, pan, pinch, done }
class MindmapCanvasPage extends ConsumerStatefulWidget {
  const MindmapCanvasPage({
    super.key,
    required this.mapId,
    this.onOpenNote,
    this.dao,
    this.db,
  });

  final int mapId;

  /// 双击进笔记的跳转出口（生产＝[mmOpenNote]；测试注入 fake 断言被调用）。
  final Future<void> Function(BuildContext, int)? onOpenNote;

  /// 测试注入缝（生产 null＝走 AppDatabase.instance）；挂载标题刷新经 [db]。
  final MindmapDao? dao;
  final Database? db;

  @override
  ConsumerState<MindmapCanvasPage> createState() => _MindmapCanvasPageState();
}

class _MindmapCanvasPageState extends ConsumerState<MindmapCanvasPage> {
  late final MindmapDao _dao =
      widget.dao ?? MindmapDao(AppDatabase.instance.db);
  Database? get _mmDb => widget.db;

  Mindmap? _map;
  List<MindmapNode> _nodes = const [];
  late final TreeLayoutEngine _engine = TreeLayoutEngine()..measure = _measure;
  MmLayoutResult? _layout;

  /// 撤销/重做命令栈（批2 F4-1：增删改移折叠各一步·本图一份，切图即弃）。
  final MmUndoStack _undo = MmUndoStack();

  /// 挂载节点的笔记标题实时映射（C4：显示层取笔记标题；返回画布/改名后刷新）。
  final Map<int, String> _noteTitles = {};

  // 视口（帧内只更这两个值＝手势节流口径；布局计算不进手势帧）。
  double _scale = 1;
  Offset _pan = Offset.zero;
  Size _viewport = Size.zero;

  int? _selectedId;

  // ── 手势仲裁状态 ──
  final Map<int, Offset> _pointers = {};
  _MmGestureMode _mode = _MmGestureMode.idle;
  int? _dragNodeId;
  Offset _dragStartCanvas = Offset.zero;
  double _dragStartDx = 0, _dragStartDy = 0;
  Offset _panStart = Offset.zero;
  double _pinchStartDist = 0, _pinchStartScale = 1;
  Offset _pinchStartMid = Offset.zero, _panAtPinch = Offset.zero;
  Offset _downGlobal = Offset.zero;
  /// 画布区 RenderBox 钥匙：指针事件是全局坐标，_pan/_viewport 是画布局部
  /// 坐标，进 _toCanvas 前必须 globalToLocal（漏转＝命中测试整体错位 AppBar 高）。
  final GlobalKey _canvasKey = GlobalKey();

  /// 全局 → 画布局部。
  Offset _localOf(Offset global) {
    final ctx = _canvasKey.currentContext;
    final box = ctx?.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.globalToLocal(global);
    return global;
  }
  Timer? _longPressTimer;
  Timer? _saveDebounce;

  /// 双击检测（间隔 <300ms 同节点＝双击）。
  int? _lastTapId;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// TextPainter 量宽缓存（渲染层七条之三：改文字才重算；批2 多行化＝缓存整 Size）。
  final Map<String, Size> _textSizeCache = {};
  static const double _nodeH = 40;
  static const double _nodePad = 12;

  /// 批3 样式层：当前图的档位（null＝未设样式，走批2 基线绘制面）。
  /// 每图一套，存 prefs（`lh.mm_styles` 的 mapId 那一格）。
  MmStyle? _style;

  /// 绘制面（画布与 PNG 导出同源；度量也吃同一 [MmPaintStyle.fontSize]）。
  MmPaintStyle get _paintStyle =>
      MmPaintStyle.of(_style, Theme.of(context).colorScheme);

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 双击进笔记返回：视口与选中态保持（§3.3），但挂载标题可能已改名→刷新映射。
    _refreshMountedTitles();
  }

  Future<void> _load() async {
    final map = await _dao.mapById(widget.mapId);
    final nodes = await _dao.nodesOf(widget.mapId);
    await _refreshMountedTitlesData(nodes);
    final style = MmStyleStore(ref.read(sharedPreferencesProvider)).load(widget.mapId);
    if (!mounted) return;
    setState(() {
      _map = map;
      _nodes = nodes;
      _style = style;
      _loading = false;
    });
    _relayout();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  /// 重算布局（不 fit——fit 只在进图/按 fit 钮时发生）。
  void _relayout() {
    setState(() => _layout = _engine.layout(_nodes));
  }

  /// 可见节点集（折叠整枝跳过；画布绘制与命中共用一份）。
  Set<int> _visibleIds() {
    final byId = {for (final n in _nodes) if (n.id != null) n.id!: n};
    final children = <int, List<MindmapNode>>{};
    final roots = <MindmapNode>[];
    for (final n in _nodes) {
      final p = n.parentId;
      if (p != null && byId.containsKey(p)) {
        children.putIfAbsent(p, () => []).add(n);
      } else {
        roots.add(n);
      }
    }
    final out = <int>{};
    void walk(MindmapNode n) {
      out.add(n.id!);
      if (n.folded) return;
      for (final c in children[n.id!] ?? const <MindmapNode>[]) {
        walk(c);
      }
    }

    for (final r in roots) {
      walk(r);
    }
    return out;
  }

  /// 内容包围盒（fit 与缩放边界用；只算可见节点）。
  Rect _contentBounds() {
    final l = _layout;
    if (l == null || _nodes.isEmpty) return Rect.zero;
    final vis = _visibleIds();
    Rect? acc;
    for (final id in vis) {
      final b = l.baseline[id];
      if (b == null) continue;
      final n = _byId(id);
      final pos = b + Offset(n?.dx ?? 0, n?.dy ?? 0);
      final s = l.sizes[id] ?? const Size(120, _nodeH);
      final r = Rect.fromLTWH(pos.dx, pos.dy, s.width, s.height);
      acc = acc == null ? r : acc.expandToInclude(r);
    }
    return acc ?? Rect.zero;
  }

  MindmapNode? _byId(int id) {
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _fit() {
    if (!mounted || _viewport == Size.zero) return;
    final (s, pan) = fitTransform(
        contentBounds: _contentBounds(), viewport: _viewport);
    setState(() {
      _scale = s;
      _pan = pan;
    });
  }

  /// 挂载标题映射刷新（显示实时跟随的落点：进图/返回本页/动作后调用）。
  Future<void> _refreshMountedTitles() =>
      _refreshMountedTitlesData(_nodes).then((_) {
        if (mounted) setState(() {});
      });

  Future<void> _refreshMountedTitlesData(List<MindmapNode> nodes) async {
    final ids = {
      for (final n in nodes) if (n.noteId != null) n.noteId!,
    };
    _noteTitles.removeWhere((k, _) => !ids.contains(k));
    for (final id in ids) {
      // 笔记已删＝存空串（B6 占位态的判据），不保留旧快照谎报跟随。
      _noteTitles[id] = await mmNoteTitleOf(id, _mmDb) ?? '';
    }
  }

  /// 节点显示标题（C4/B6：挂载＝笔记标题实时；失效＝占位；未挂＝自身标题）。
  String _displayTitle(MindmapNode n) {
    if (n.noteId == null) return n.title;
    final t = _noteTitles[n.noteId!];
    return (t == null || t.isEmpty) ? '（已删除的笔记）' : t;
  }

  Size _measure(MindmapNode n) {
    final title = _displayTitle(n);
    // 批3 样式层：字号档进缓存键（换字号必须重算盒宽——度量与 painter 同源，
    // 否则 lg 档文字会溢出旧盒）。
    final fs = _paintStyle.fontSize;
    final cached = _textSizeCache['$fs|$title'];
    if (cached != null) return cached;
    final s = mmNodeMeasure(
      title,
      style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600),
      hPad: _nodePad,
      minH: _nodeH,
    );
    _textSizeCache['$fs|$title'] = s;
    return s;
  }

  // ==================== 手势三分仲裁（§4.1） ====================

  Offset _toCanvas(Offset screen) => (screen - _pan) / _scale;

  MindmapNode? _hitNode(Offset canvas) {
    final l = _layout;
    if (l == null) return null;
    final vis = _visibleIds();
    for (final id in vis) {
      final b = l.baseline[id];
      if (b == null) continue;
      final n = _byId(id);
      final pos = b + Offset(n?.dx ?? 0, n?.dy ?? 0);
      final s = l.sizes[id] ?? const Size(120, _nodeH);
      // 命中区放宽到行高 44（触点 ≥44 口径），宽按节点盒。
      if (Rect.fromLTWH(pos.dx, pos.dy - 2, math.max(s.width, 44), s.height + 4)
          .contains(canvas)) {
        return n;
      }
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 1) {
      _mode = _MmGestureMode.pending;
      _downGlobal = e.position;
      final hit = _hitNode(_toCanvas(_localOf(e.position)));
      if (hit != null) {
        _dragNodeId = hit.id;
        _dragStartCanvas = _toCanvas(_localOf(e.position));
        _dragStartDx = hit.dx;
        _dragStartDy = hit.dy;
        // 长按 ≥450ms 未移动 → 节点菜单（§4.1）。
        _longPressTimer = Timer(const Duration(milliseconds: 450), () {
          if (_mode == _MmGestureMode.pending && mounted) {
            _mode = _MmGestureMode.done;
            _showNodeMenu(hit);
          }
        });
      } else {
        _dragNodeId = null;
        _panStart = _pan;
      }
    } else if (_pointers.length == 2) {
      // 双指 = 缩放，抢在一切单指语义前；取消长按。
      _longPressTimer?.cancel();
      _mode = _MmGestureMode.pinch;
      final pts = _pointers.values.toList();
      _pinchStartDist = (pts[0] - pts[1]).distance;
      _pinchStartScale = _scale;
      _pinchStartMid = _localOf(Offset((pts[0].dx + pts[1].dx) / 2,
          (pts[0].dy + pts[1].dy) / 2));
      _panAtPinch = _pan;
      _dragNodeId = null;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    switch (_mode) {
      case _MmGestureMode.pending:
        final moved = (e.position - _downGlobal).distance;
        if (moved < 4) return; // <4dp 仍算按住（tap/长按窗口）
        _longPressTimer?.cancel();
        if (_dragNodeId != null) {
          _mode = _MmGestureMode.dragNode;
          final c = _toCanvas(_localOf(e.position));
          final d = c - _dragStartCanvas;
          setState(() {
            _overrideDx(_dragNodeId!, _dragStartDx + d.dx);
            _overrideDy(_dragNodeId!, _dragStartDy + d.dy);
          });
        } else {
          _mode = _MmGestureMode.pan;
          setState(() => _pan = _panStart + (e.position - _downGlobal));
        }
      case _MmGestureMode.dragNode:
        // 拖拽中只改内存偏移＋重画（不落库，B4）；帧内无布局计算。
        final c = _toCanvas(_localOf(e.position));
        final d = c - _dragStartCanvas;
        setState(() {
          _overrideDx(_dragNodeId!, _dragStartDx + d.dx);
          _overrideDy(_dragNodeId!, _dragStartDy + d.dy);
        });
      case _MmGestureMode.pan:
        setState(() => _pan = _panStart + (e.position - _downGlobal));
      case _MmGestureMode.pinch:
        final pts = _pointers.values.toList();
        if (pts.length < 2) return;
        final dist = (pts[0] - pts[1]).distance;
        final mid = Offset(
            (pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
        final k = _pinchStartDist == 0 ? 1.0 : dist / _pinchStartDist;
        final newScale =
            (_pinchStartScale * k).clamp(0.25, 4.0); // 25%~400%（F1-3）
        // 以捏合中点为锚：锚点画布坐标在缩放前后落在屏幕同一点。
        final anchor = (_pinchStartMid - _panAtPinch) / _pinchStartScale;
        setState(() {
          _scale = newScale;
          _pan = mid - anchor * newScale;
        });
      case _MmGestureMode.done:
        break;
      case _MmGestureMode.idle:
        break;
    }
  }

  /// 拖拽中的内存偏移覆写（不写 `_nodes` 列表对象——列表是 DAO 行快照，
  /// 覆写走旁路 map，松手/flush 才合回并落库）。
  final Map<int, double> _liveDx = {};
  final Map<int, double> _liveDy = {};

  void _overrideDx(int id, double v) => _liveDx[id] = v;
  void _overrideDy(int id, double v) => _liveDy[id] = v;

  double _dxOf(MindmapNode n) => _liveDx[n.id] ?? n.dx;
  double _dyOf(MindmapNode n) => _liveDy[n.id] ?? n.dy;

  /// 松手/退出：把旁路偏移合回节点并落库（防抖 300ms 合并连续操作，B4）。
  void _commitLiveOffsets({bool immediate = false}) {
    if (_liveDx.isEmpty && _liveDy.isEmpty) return;
    final updates = <MindmapNode>[];
    for (final n in _nodes) {
      if (n.id == null) continue;
      final dx = _liveDx[n.id!], dy = _liveDy[n.id!];
      if (dx == null && dy == null) continue;
      final u = n.copyWith(
          dx: dx ?? n.dx, dy: dy ?? n.dy, updatedAt: _now());
      // 「移」也是一步（F4-1）：拖拽前 n → 拖拽后 u 各为快照。
      if (u.dx != n.dx || u.dy != n.dy) {
        _undo.push(MmCommands.editNode(n, u, label: '移动节点'));
      }
      updates.add(u);
    }
    _liveDx.clear();
    _liveDy.clear();
    for (final u in updates) {
      final i = _nodes.indexWhere((x) => x.id == u.id);
      if (i >= 0) _nodes[i] = u;
    }
    void write() {
      for (final u in updates) {
        _dao.updateNode(u);
      }
    }

    if (immediate) {
      _saveDebounce?.cancel();
      write();
    } else {
      _saveDebounce?.cancel();
      _saveDebounce = Timer(const Duration(milliseconds: 300), write);
    }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    _longPressTimer?.cancel();
    final wasMode = _mode;
    if (_pointers.isEmpty) {
      if (wasMode == _MmGestureMode.pending) {
        _handleTap(_localOf(e.position));
      } else if (wasMode == _MmGestureMode.dragNode) {
        _commitLiveOffsets();
        _relayout(); // 松手整树重排（拖拽中只局部重画）
      }
      _mode = _MmGestureMode.idle;
      _dragNodeId = null;
    } else if (_pointers.length == 1 && wasMode == _MmGestureMode.pinch) {
      // 双指抬剩一指：回平移态，基准重置。
      _mode = _MmGestureMode.pan;
      _downGlobal = _pointers.values.first;
      _panStart = _pan;
      _dragNodeId = null;
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _longPressTimer?.cancel();
    if (_pointers.isEmpty) {
      _commitLiveOffsets();
      _mode = _MmGestureMode.idle;
      _dragNodeId = null;
    }
  }

  /// 单击（<4dp）：命中节点＝选中（双击间隔内同节点且已挂笔记＝进笔记）；
  // 命中空白＝取消选中（B5），工具条随选中态显隐。入参＝画布局部坐标。
  void _handleTap(Offset local) {
    final hit = _hitNode(_toCanvas(local));
    if (hit == null) {
      if (_selectedId != null) setState(() => _selectedId = null);
      return;
    }
    final now = DateTime.now();
    final isDoubleTap = _lastTapId == hit.id &&
        now.difference(_lastTapAt).inMilliseconds < 300;
    _lastTapId = hit.id;
    _lastTapAt = now;
    if (isDoubleTap && hit.noteId != null) {
      // 双击进笔记（H4/C5）：失效挂载置灰无响应（B6）——占位标题态不跳。
      final title = _noteTitles[hit.noteId!];
      if (title != null && title.isNotEmpty) {
        final cb = widget.onOpenNote ?? mmOpenNote;
        cb(context, hit.noteId!);
        return;
      }
    }
    setState(() => _selectedId = hit.id);
  }

  // ==================== 导出（批2 F4-5） ====================

  Future<void> _exportMap() async {
    await mmRunExport(
      context,
      mapTitle: _map?.title ?? '思维导图',
      rows: _nodes,
      noteTitleOf: (n) async {
        if (n.noteId == null) return null;
        final t = _noteTitles[n.noteId!];
        return (t == null || t.isEmpty) ? null : t;
      },
      noteBodyOf: (n) => mmNoteContentOf(n.noteId!, _mmDb),
      pngSnapshot: _pngSnapshot,
    );
  }

  /// PNG 离屏快照：薄封装（主体在 mmCanvasPngSnapshot·导出即所见）。
  Future<Uint8List?> _pngSnapshot() => mmCanvasPngSnapshot(
        nodes: _nodes,
        layout: _layout,
        bounds: _contentBounds(),
        displayTitleOf: _displayTitle,
        dxOf: _dxOf,
        dyOf: _dyOf,
        cs: Theme.of(context).colorScheme,
        style: _style,
      );

  // ==================== 撤销/重做（批2 F4-1） ====================

  Future<void> _undoStep() async {
    final label = await _undo.undo(_dao);
    if (label == null || !mounted) return;
    await _reloadNodes();
    _toast('已撤销：$label');
  }

  Future<void> _redoStep() async {
    final label = await _undo.redo(_dao);
    if (label == null || !mounted) return;
    await _reloadNodes();
  }

  /// undo/redo 落库后重拉整图（快照含新增/删除行，重拉最省心且正确）。
  Future<void> _reloadNodes() async {
    final nodes = await _dao.nodesOf(widget.mapId);
    await _refreshMountedTitlesData(nodes);
    if (!mounted) return;
    setState(() {
      _nodes = nodes;
      _selectedId = null;
    });
    _textSizeCache.clear();
    _relayout();
  }

  // ==================== 节点操作（F1-4~F1-12） ====================

  static const int mmMaxNodes = 2000; // B9 单图节点硬上限

  Future<void> _addChild(int? parentId) async {
    if (_nodes.length >= mmMaxNodes) {
      _toast('已达节点上限（$mmMaxNodes）');
      return;
    }
    final r = await showMmNodeSheet(context, headline: '添加子节点');
    if (r == null) return;
    final n = await _dao.addNode(
      mapId: widget.mapId,
      parentId: parentId,
      title: r.$1,
      note: r.$2,
    );
    setState(() => _nodes = [..._nodes, n]);
    _undo.push(MmCommands.addSubtree(n, [n]));
    _relayout();
    setState(() => _selectedId = n.id);
  }

  Future<void> _addSibling(MindmapNode n) async {
    // 在根节点上加同级＝新增根（C7/F1-6）。
    if (_nodes.length >= mmMaxNodes) {
      _toast('已达节点上限（$mmMaxNodes）');
      return;
    }
    final r = await showMmNodeSheet(context, headline: '添加同级节点');
    if (r == null) return;
    final created = await _dao.addNode(
      mapId: widget.mapId,
      parentId: n.parentId,
      title: r.$1,
      note: r.$2,
    );
    setState(() => _nodes = [..._nodes, created]);
    _undo.push(MmCommands.addSubtree(created, [created]));
    _relayout();
    setState(() => _selectedId = created.id);
  }

  Future<void> _addRoot() async {
    if (_nodes.length >= mmMaxNodes) {
      _toast('已达节点上限（$mmMaxNodes）');
      return;
    }
    final r = await showMmNodeSheet(context, headline: '加根节点');
    if (r == null) return;
    final created = await _dao.addNode(
        mapId: widget.mapId, parentId: null, title: r.$1, note: r.$2);
    setState(() => _nodes = [..._nodes, created]);
    _undo.push(MmCommands.addSubtree(created, [created]));
    _relayout();
    setState(() => _selectedId = created.id);
  }

  Future<void> _editNode(MindmapNode n) async {
    // H2：标题＋备注均可读回并改写（弹层同「添加」骨架，读回现值）。
    final r = await showMmNodeSheet(
      context,
      headline: '编辑节点',
      initialTitle: n.title,
      initialNote: n.note,
    );
    if (r == null || n.id == null) return;
    final u = n.copyWith(title: r.$1, note: r.$2, updatedAt: _now());
    if (u.title != n.title || u.note != n.note) {
      _undo.push(MmCommands.editNode(n, u));
    }
    await _dao.updateNode(u);
    _textSizeCache.remove(n.title); // 改文字才重算（缓存失效即重算，不是删除缓存用途）
    setState(() {
      _nodes[_nodes.indexWhere((x) => x.id == n.id)] = u;
    });
    _relayout();
  }

  Future<void> _toggleFold(MindmapNode n) async {
    if (n.id == null) return;
    final u = n.copyWith(folded: !n.folded, updatedAt: _now());
    _undo.push(MmCommands.editNode(n, u, label: u.folded ? '折叠子级' : '展开子级'));
    await _dao.updateNode(u); // 折叠态持久化（C10）
    setState(() {
      _nodes[_nodes.indexWhere((x) => x.id == n.id)] = u;
    });
    _relayout();
  }

  /// 归位到自动布局＝清偏移（2d 口径：偏移可叠加在任意基线上）。
  Future<void> _resetOffset(MindmapNode n) async {
    if (n.id == null) return;
    final u = n.copyWith(dx: 0, dy: 0, updatedAt: _now());
    _undo.push(MmCommands.editNode(n, u, label: '归位节点'));
    await _dao.updateNode(u);
    setState(() {
      _nodes[_nodes.indexWhere((x) => x.id == n.id)] = u;
      _liveDx.remove(n.id);
      _liveDy.remove(n.id);
    });
  }

  Future<void> _deleteNode(MindmapNode n) async {
    if (n.id == null) return;
    final ids = await _dao.descendantIdsOf(n.id!);
    if (!mounted) return;
    final children = ids.length - 1;
    // 取消＝零副作用（F1-11）：确认前不写任何数据。
    final ok = await mmConfirmDeleteNode(context, ids.length, children);
    if (!ok || !mounted) return;
    // 撤销快照在删除前取完整后代闭包（undo 整行重插带原 id）。
    final rows = await _dao.nodesOfIds(ids);
    await _dao.deleteNodeCascade(n.id!);
    _undo.push(MmCommands.deleteRows(rows, '删除「${_displayTitle(n)}」'));
    setState(() {
      _nodes = _nodes.where((x) => !ids.contains(x.id)).toList();
      if (_selectedId != null && ids.contains(_selectedId)) {
        _selectedId = null;
      }
    });
    _relayout();
    _toast('已删除 ${ids.length} 个节点');
  }

  Future<void> _bindNote(MindmapNode n) async {
    final r = await showMmBindSheet(context, currentNoteId: n.noteId);
    if (r == null || n.id == null) return;
    final MindmapNode u;
    if (r == -1) {
      u = n.copyWith(clearNote: true, updatedAt: _now());
    } else {
      u = n.copyWith(noteId: r, updatedAt: _now());
    }
    if (u.noteId != n.noteId) {
      _undo.push(MmCommands.editNode(n, u,
          label: u.noteId == null ? '解绑笔记' : '挂载笔记'));
    }
    await _dao.updateNode(u);
    if (u.noteId != null && !_noteTitles.containsKey(u.noteId)) {
      _noteTitles[u.noteId!] = await mmNoteTitleOf(u.noteId!, _mmDb) ?? '';
    }
    _textSizeCache.remove(n.title);
    setState(() {
      _nodes[_nodes.indexWhere((x) => x.id == n.id)] = u;
    });
    _relayout();
  }

  Future<void> _showNodeMenu(MindmapNode n) async {
    final key = await showMmMenu(context, [
      (key: 'child', icon: Icons.account_tree_outlined, label: '添加子节点', enabled: true),
      (key: 'sibling', icon: Icons.linear_scale, label: '添加同级节点', enabled: true),
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
    ]);
    if (key == null || !mounted) return;
    switch (key) {
      case 'child':
        await _addChild(n.id);
      case 'sibling':
        await _addSibling(n);
      case 'edit':
        await _editNode(n);
      case 'bind':
        await _bindNote(n);
      case 'fold':
        await _toggleFold(n);
      case 'reset':
        await _resetOffset(n);
      case 'del':
        await _deleteNode(n);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1600)));
  }

  // ==================== 样式层（批3 F4-7） ====================

  /// 打开样式弹层（原型 `mmOpenStyle`：画布高频直达）。改档即时生效并入
  /// 撤销栈（原型 `mmSetStyle` 走 `mmPushHistory`，同款语义）。
  /// 打开样式弹层（原型 `mmOpenStyle`：画布高频直达）。改档**即时生效**并
  /// 入撤销栈（原型 `mmSetStyle` 走 `mmPushHistory`，同款语义）——所以关闭
  /// 弹层不做任何回滚：关掉即定稿（含「恢复默认」＝显式写默认档）。
  Future<void> _openStyle() async {
    final store = MmStyleStore(ref.read(sharedPreferencesProvider));
    await showMmStyleSheet(
      context,
      initial: _style ?? MmStyle.defaults,
      onChanged: (next) => _applyStyle(store, next),
    );
  }

  /// 应用一份样式档：改状态 → 清度量缓存（字号变则盒宽重算）→ 落 prefs。
  /// 每次改档入撤销栈一步（原型 `mmPushHistory('调整样式')` 同款语义）。
  Future<void> _applyStyle(MmStyleStore store, MmStyle next) async {
    final before = _style;
    if (before == next) return;
    setState(() => _style = next);
    _textSizeCache.clear();
    _relayout();
    _undo.push(MmCommand(
      label: '调整样式',
      redo: (_) async {
        await store.save(widget.mapId, next);
        if (!mounted) return;
        setState(() => _style = next);
        _textSizeCache.clear();
        _relayout();
      },
      undo: (_) async {
        if (before == null) {
          await store.reset(widget.mapId);
        } else {
          await store.save(widget.mapId, before);
        }
        if (!mounted) return;
        setState(() => _style = before);
        _textSizeCache.clear();
        _relayout();
      },
    ));
    await store.save(widget.mapId, next);
  }

  // ==================== build ====================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      // B10 大图加载指示（1000+ 节点开图 ≤1.5s 消失；不阻塞返回）。
      return Scaffold(
        appBar: AppBar(title: Text(_map?.title ?? '思维导图')),
        body: const Center(
            key: ValueKey('mm-canvas-loading'),
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final selected = _selectedId == null ? null : _byId(_selectedId!);
    final visIds = _visibleIds();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _map?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const ValueKey('mm-undo-btn'),
            tooltip: '撤销',
            onPressed: _undo.canUndo ? _undoStep : null,
            icon: const Icon(Icons.undo_outlined, size: 21),
          ),
          IconButton(
            key: const ValueKey('mm-redo-btn'),
            tooltip: '重做',
            onPressed: _undo.canRedo ? _redoStep : null,
            icon: const Icon(Icons.redo_outlined, size: 21),
          ),
          IconButton(
            key: const ValueKey('mm-export-btn'),
            tooltip: '导出',
            onPressed: _exportMap,
            icon: const Icon(Icons.ios_share_outlined, size: 21),
          ),
          IconButton(
            key: const ValueKey('mm-add-root'),
            tooltip: '加根节点',
            onPressed: _addRoot,
            icon: const Icon(Icons.add_circle_outline, size: 22),
          ),
          IconButton(
            key: const ValueKey('mm-fit-btn'),
            tooltip: '全图可见',
            onPressed: _fit,
            icon: const Icon(Icons.center_focus_weak, size: 22),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _viewport = box.biggest;
                final painterNodes = <MindmapNode>[];
                final l = _layout;
                if (l != null) {
                  final culled = cullVisibleNodes(
                    baseline: l.baseline,
                    sizes: l.sizes,
                    dxs: {
                      for (final n in _nodes)
                        if (n.id != null) n.id!: _dxOf(n),
                    },
                    dys: {
                      for (final n in _nodes)
                        if (n.id != null) n.id!: _dyOf(n),
                    },
                    scale: _scale,
                    pan: _pan,
                    viewport: _viewport,
                    candidates: visIds,
                  );
                  for (final id in culled) {
                    final n = _byId(id);
                    if (n != null) painterNodes.add(n);
                  }
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Listener(
                        key: _canvasKey,
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: _onPointerUp,
                        onPointerCancel: _onPointerCancel,
                        child: RepaintBoundary(
                          child: CustomPaint(
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
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                    // 读屏语义层（§4.7）：Canvas 节点对读屏不可见 ⇒ 叠透明 Semantics。
                    for (final id in visIds)
                      _buildSemantics(context, id),
                    // 缩放比例标签（尼尔森 1 系统状态可见性）。
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        key: const ValueKey('mm-scale-label'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: .85),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${(_scale * 100).round()}% · ${_nodes.length} 节点',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    // 右下缩放条（＋/－/fit）＋样式层直达（原型 mmZoomBar 同款：
// 样式是画布高频项，先于「更多」菜单直达）。
                    Positioned(
                      right: 10,
                      bottom: 72,
                      child: Column(
                        children: [
                          _zoomBtn(context, Icons.add_outlined, () {
                            setState(() {
                              _scale = (_scale * 1.25).clamp(0.25, 4.0);
                            });
                          }),
                          const SizedBox(height: 6),
                          _zoomBtn(context, Icons.remove_outlined, () {
                            setState(() {
                              _scale = (_scale / 1.25).clamp(0.25, 4.0);
                            });
                          }),
                          const SizedBox(height: 6),
                          _zoomBtn(context, Icons.center_focus_weak, _fit),
                          const SizedBox(height: 6),
                          _zoomBtn(
                              context, Icons.palette_outlined, _openStyle),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // 悬浮工具条（贴画布底部、不占壳底栏——本模块不进 ShellRoute 底栏）。
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _toolBtn(
                    context,
                    key: const ValueKey('mm-tool-bind'),
                    icon: Icons.link_outlined,
                    label: '挂笔记',
                    enabled: selected != null,
                    onTap: () => _bindNote(selected!),
                  ),
                  const SizedBox(width: 8),
                  _toolBtn(
                    context,
                    key: const ValueKey('mm-tool-addchild'),
                    icon: Icons.account_tree_outlined,
                    label: '加子节点',
                    enabled: selected != null,
                    onTap: () => _addChild(selected!.id),
                  ),
                  const SizedBox(width: 8),
                  _toolBtn(
                    context,
                    key: const ValueKey('mm-tool-more'),
                    icon: Icons.more_horiz,
                    label: '更多',
                    enabled: selected != null,
                    onTap: () => _showNodeMenu(selected!),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _zoomBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40, // 触点 ≥44 视觉含 padding
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
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

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _saveDebounce?.cancel();
    // PopScope flush（B4）：退出前把未落库偏移写库（不依赖 context，dispose 安全）。
    _commitLiveOffsets(immediate: true);
    super.dispose();
  }
}

