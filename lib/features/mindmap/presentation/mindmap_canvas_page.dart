import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../../shared/linkage/mindmap_mounts.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers.dart' show sharedPreferencesProvider;
import '../data/mindmap_dao.dart';
import '../domain/mindmap_clipboard.dart';
import '../domain/mindmap_layout.dart';
import '../domain/mindmap_layout_preset.dart';
import '../domain/mindmap_measure.dart';
import '../domain/mindmap_models.dart';
import '../domain/mindmap_node_meta.dart';
import '../domain/mindmap_style.dart';
import '../domain/mindmap_undo.dart';
import '../domain/mindmap_viewport.dart';
import '../domain/mindmap_tree.dart';
import 'mindmap_export_actions.dart';
import 'mindmap_layout_sheet.dart';
import 'mindmap_node_sheet.dart';
import 'mindmap_painter.dart';
import 'mindmap_sheets.dart';
import 'mindmap_style_sheet.dart';

/// 节点操作面（长按菜单/读屏语义/构件/**批5 三段**＋**批P3 剪贴板与换序**）；part 件＝同库私有可见（动机＝体量守线，见该件头段注）。
part 'mindmap_canvas_ops.dart';

/// 连接器操作面（批P：挂接/摘除 · 连接态 · 树内导航）。
part 'mindmap_connect_ops.dart';

/// 画布绘制面接线（批P 抽出：绘制层那一棵子树＋painter 构造）。
part 'mindmap_canvas_paint.dart';
part 'mindmap_canvas_layout.dart';

/// 画布主屏（原型 mm-canvas · push 路由 `/mindmap/canvas?id=`）。
///
/// 渲染层七条（冻结方案 §6.3，批 1 硬要求）：
/// `CustomPainter`＋单 `RepaintBoundary`；可视区裁剪（[cullVisibleNodes]）；
/// `TextPainter` 缓存量宽（键＝标题文本）；拖拽局部重画；连线批量 `drawPath`；
/// 手势帧内只更 Transform。**禁用 `InteractiveViewer`**（壳内页禁令·V1.65
/// 底栏双指共存面）——手势在 [GestureDetector.onTapDown] 之下走
/// `Listener` 原始指针**自行三分仲裁**（拖节点/拖空白平移/双指捏合，§4.1）。
/// 节点盒高下限（触点 ≥44 的下沿由节点渲染自己保证，布局只管不重叠）。
const double _nodeH = 40;

/// 节点盒左右内边距。
const double _nodePad = 12;

/// 批5：任务勾选框宽（原型 `.mm-task` 15px）。**画布坐标**——命中判定与
/// painter 占位都吃它；提到顶层是因为 part extension 里也要读（extension
/// 不可直呼被扩展类型的 static 成员）。
const double _taskBoxW = 15;

/// B9 单图节点硬上限。
const int mmMaxNodes = 2000;

enum _MmGestureMode { idle, pending, dragNode, dragLink, pan, pinch, done }

/// 批P2 右缘拖拽连接点的一次拖动（指针坐标一律画布局部坐标）。
///
/// 为什么不复用 `_connectFrom`：连接态是「点一下起点、再点落点」的两段式，
/// 起点进态后就常驻；拖拽是「按住就接上（起点高亮、目标呼吸）、松手即结束」
/// 的一段式——两者共用同一套目标集与 `_connectTo`，但生命周期不同，混一起
/// 会出现「松手了还在连接态」。故单开一个轻对象，只在拖动期间存在。
class _MmLinkDrag {
  _MmLinkDrag({
    required this.fromId,
    required this.merge,
    required this.blocked,
  });

  /// 起点节点 id。
  final int fromId;

  /// 起点即根＝「整枝并入」文案（与长按菜单同口径）。
  final bool merge;

  /// 不可作目标的集合＝起点的整棵子树（含自己）——挂进去就成环。
  final Set<int> blocked;

  /// 当前指针位置（画布局部）。
  Offset at = Offset.zero;
}
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

class _MindmapCanvasPageState extends ConsumerState<MindmapCanvasPage>
    with SingleTickerProviderStateMixin {
  late final MindmapDao _dao =
      widget.dao ?? MindmapDao(AppDatabase.instance.db);
  Database? get _mmDb => widget.db;

  Mindmap? _map;
  List<MindmapNode> _nodes = const [];
  late final TreeLayoutEngine _engine = TreeLayoutEngine()..measure = _measure;
  MmLayoutResult? _layout;

  /// 批4 布局家族：当前预设（null ＝未设过，走 [MmLayoutPreset.defaults]
  /// ＝纵向树，**默认态零视觉变化**）。每图一套，存 prefs。
  MmLayoutPreset? _preset;

  /// 当前预设（未设回落默认）。
  MmLayoutPreset get _view => _preset ?? MmLayoutPreset.defaults;

  /// 撤销/重做命令栈（批2 F4-1：增删改移折叠各一步·本图一份，切图即弃）。
  final MmUndoStack _undo = MmUndoStack();

  /// 挂载节点的笔记标题实时映射（C4：显示层取笔记标题；返回画布/改名后刷新）。
  final Map<int, String> _noteTitles = {};

  // 视口（帧内只更这两个值＝手势节流口径；布局计算不进手势帧）。
  double _scale = 1;
  Offset _pan = Offset.zero;
  Size _viewport = Size.zero;

  int? _selectedId;

  // ── 批P 连接态 ──
  /// 连接起点（null＝不在连接态）。在连接态里：点目标＝挂接、点自己/空白＝取消、
  /// 点节点不排拖拽（否则「想去点目标」变成「把起点拖走」）。
  int? _connectFrom;

  /// 「整枝并入」语义位：起点本身是根时它没有父可挂，动作＝成为别人的子级。
  bool _connectMerge = false;

  /// 批P L5：聚焦态保留集（自己＋祖先＋后代）。空集＝不聚焦＝默认态零视觉变化。
  /// 建成 getter 而非 build 局部量：绘制 part 每帧构造 painter 时直接读。
  Set<int> get _focusIds =>
      _selectedId == null ? const <int>{} : mmBranchOf(_nodes, _selectedId!);

  /// 批P P1：连接态置灰集（起点的整棵子树——挂进去就成环）。
  Set<int> get _connectBlockedIds => _connectFrom == null
      ? const <int>{}
      : mmSubtreeOf(_nodes, _connectFrom!);

  /// 批P P1：连接态可点目标（可见集减掉置灰集）。**入口置灰**，不做「点了再报错」。
  Set<int> get _connectTargetIds => _connectFrom == null
      ? const <int>{}
      : _visibleIds().difference(_connectBlockedIds);

  /// 目标节点的呼吸相位（0~1）。**只驱动 painter 的双环**，不参与任何判定；
  /// 用 [AnimatedBuilder] 只重建 CustomPaint 那一层（整页 setState 每帧太重）。
  late final AnimationController _connectPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// 批P2 右缘拖拽连接点：正在拖的那根连线（null＝没在拖）。
  /// 起手＝按住选中节点右缘那枚 16dp 圆点；松手落点命中合法目标＝挂接，
  /// 落空白/自己整枝＝取消（与长按菜单「连接到…」殊途同归，同一个 `_connectTo`）。
  /// 拖动中**不排长按、不排节点拖拽**——靠 [_dragLinkHover] 每帧高亮落点。
  _MmLinkDrag? _linkDrag;

  /// 拖动中悬停的落点（null＝空白）。**是否可挂接由 [_linkDrag] 的整枝集判定**
  /// （拖拽入口天然可能落在自己整枝上，故这里不预先置灰，落点时才给理由）。
  MindmapNode? _linkHover;

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


  /// 批5：节点三段的**逐节点附加宽**（标签 chip ＋ 任务框 ＋ 图片占位）。
  /// 与 painter 吃同一份节点字段 ⇒ 盒宽与画出来的角标永远一致。
  double _extraWidthOf(MindmapNode n) {
    if (!n.isTask && !n.hasImage && n.tags.isEmpty) return 0;
    return mmNodeExtraWidth(
      tags: n.tags,
      isTask: n.isTask,
      hasImage: n.hasImage,
      tagWidth: n.tags.isEmpty
          ? 0
          : mmTagWidthEstimate(n.tags.first) + 6 * (n.tags.length - 1),
    );
  }

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
    final prefs = ref.read(sharedPreferencesProvider);
    final style = MmStyleStore(prefs).load(widget.mapId);
    final preset = MmLayoutStore(prefs).load(widget.mapId);
    if (!mounted) return;
    setState(() {
      _map = map;
      _nodes = nodes;
      _style = style;
      _preset = preset;
      _loading = false;
    });
    _relayout();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  /// 重算布局（不 fit——fit 只在进图/按 fit 钮/切布局时发生）。
  ///
  /// **换预设只重算基线，拖拽偏移 `dx/dy` 原样保留**（2d 冻结口径：偏移存的是
  /// 相对基线的量，基线变了偏移直接叠加上去；「归位到自动布局」才清零）。
  void _relayout() {
    setState(() => _layout = _layoutFor(_view));
  }

  /// 按当前预设算基线。**纵向树走批1 那个引擎实例**（默认形态逐值不变＝
  /// 默认态零视觉变化），其余预设走预设工厂。
  MmLayoutResult _layoutFor(MmLayoutPreset preset) {
    if (preset == MmLayoutPreset.defaults) return _engine.layout(_nodes);
    return mmLayoutOf(preset, _nodes, measure: _measure);
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
    // 批5：三段占宽也进缓存键（改标签/任务/图片后盒宽必须重算）。
    final extra = _extraWidthOf(n);
    final cached = _textSizeCache['$fs|$extra|$title'];
    if (cached != null) return cached;
    final s = mmNodeMeasure(
      title,
      style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600),
      hPad: _nodePad,
      minH: _nodeH,
      extraWidth: extra,
    );
    _textSizeCache['$fs|$extra|$title'] = s;
    return s;
  }

  // ==================== 手势三分仲裁（§4.1） ====================

  Offset _toCanvas(Offset screen) => (screen - _pan) / _scale;

  /// 批P2：选中节点右缘那枚连接点的**画布坐标中心**（null＝当前没选中/不可见）。
  /// 与绘制层同一份基线数据 ⇒ 画在哪、点哪就一定对得上。
  Offset? _linkKnobCenter() {
    final id = _selectedId;
    final l = _layout;
    if (id == null || l == null || !_visibleIds().contains(id)) return null;
    final n = _byId(id);
    final b = l.baseline[id];
    if (n == null || b == null) return null;
    final size = l.sizes[id] ?? const Size(120, _nodeH);
    return b + Offset(_dxOf(n) + size.width, _dyOf(n) + size.height / 2);
  }

  /// 连接点命中半径：**屏幕上**取 22（触点 ≥44 的一半，但它是附属小点，
  /// 不需要整 44 见方——否则会把节点右缘的拖拽手势全吞掉）。
  static const double _linkKnobR = 22;

  bool _hitLinkKnob(Offset canvas) {
    final c = _linkKnobCenter();
    if (c == null) return false;
    return (canvas - c).distance * _scale <= _linkKnobR;
  }

  /// 起手拖连线（只在非连接态、有选中时成立）。
  void _startLinkDrag(PointerDownEvent e) {
    final id = _selectedId!;
    final n = _byId(id)!;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _linkDrag = _MmLinkDrag(
        fromId: id,
        merge: n.parentId == null,
        blocked: mmSubtreeOf(_nodes, id),
      )..at = _toCanvas(_localOf(e.position));
      _linkHover = null;
    });
    _connectPulse.repeat(reverse: true);
  }

  void _updateLinkDrag(Offset local) {
    final d = _linkDrag;
    if (d == null) return;
    final canvas = _toCanvas(local);
    final hit = _hitNode(canvas);
    // ignore: invalid_use_of_protected_member
    setState(() {
      d.at = canvas;
      // 点选与拖放共用一份判定：命中区（放宽到 44 行高）＋盒内，两者取并。
      // 只认 `_hitNode` 会在「指针压在盒的上下沿外扩区」时松手挂不上；
      // 只认盒内则要另写一份几何，与点击口径逐渐漂开。
      final over = hit != null && _linkOverNode(hit);
      _linkHover = (hit != null && hit.id != d.fromId && over) ? hit : null;
    });
  }

  /// 松手：命中且合法＝挂接（复用连接态同一条 `_connectTo`），否则静默取消。
  /// 取消**不弹 toast**——拖错了松手就散了，比「已取消」更轻（尼尔森 9 的
  /// 「别为可预期的操作报错」）。成环原因走 `_connectTo` 的既有提示。
  Future<void> _endLinkDrag() async {
    final d = _linkDrag;
    if (d == null) return;
    final target = _linkHover;
    _connectPulse.stop();
    _connectPulse.value = 0;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _linkDrag = null;
      _linkHover = null;
    });
    if (target == null) return;
    final src = _byId(d.fromId);
    if (src == null) return;
    // `_connectTo` 读 `_connectMerge` 决定 label 文案：拖拽路径没走连接态，
    // 这里临时按起手时算好的语义位摆正，结束后复位（不改连接态本身的生命周期）。
    _connectMerge = d.merge;
    await _connectTo(src, target);
    _connectMerge = false;
  }

  void _cancelLinkDrag() {
    if (_linkDrag == null) return;
    _connectPulse.stop();
    _connectPulse.value = 0;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _linkDrag = null;
      _linkHover = null;
    });
  }

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
      final local = _localOf(e.position);
      // 批P2：按住「右缘连接点」＝起手拖连线。**先于**勾选框与节点命中判
      // （它在节点盒右缘之外，但离盒很近，不先判会被当成点空白取消选中）。
      if (_connectFrom == null && _hitLinkKnob(_toCanvas(local))) {
        _dragNodeId = null;
        _mode = _MmGestureMode.dragLink;
        _startLinkDrag(e);
        return;
      }
      // 批P 连接态：点节点＝选目标。**不排拖拽也不排长按**（否则「想去点目标」
      // 变成「把起点拖走」/「弹自己的菜单」）；平移仍可（_panStart 照常记）。
      if (_connectFrom != null) {
        _dragNodeId = null;
        _panStart = _pan;
        return;
      }
      // 批5：按下落在勾选框上＝**不排拖拽也不排长按**（原型对 `.mm-task`
      // 在 pointerdown 就 stopPropagation 同款）。否则一勾就变成拖节点。
      if (_hitTaskBox(_toCanvas(local)) != null) {
        _dragNodeId = null;
        _panStart = _pan;
        return;
      }
      final hit = _hitNode(_toCanvas(local));
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
      case _MmGestureMode.dragLink:
        _updateLinkDrag(_localOf(e.position));
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
      } else if (wasMode == _MmGestureMode.dragLink) {
        // 松手即落位：命中合法目标＝挂接，其余＝静默散掉。
        _endLinkDrag();
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
      _cancelLinkDrag();
      _mode = _MmGestureMode.idle;
      _dragNodeId = null;
    }
  }

  /// 单击（<4dp）：命中节点＝选中（双击间隔内同节点且已挂笔记＝进笔记）；
  // 命中空白＝取消选中（B5），工具条随选中态显隐。入参＝画布局部坐标。
  ///
  /// 批P：连接态下这一支**整体改语义**——点目标＝挂接、点自己/空白＝取消，
  /// 且不参与双击进笔记（连接态里双击＝两次点目标，别混）。
  Future<void> _handleTap(Offset local) async {
    final canvas = _toCanvas(local);
    final from = _connectFrom;
    if (from != null) {
      final target = _hitNode(canvas);
      if (target == null || target.id == from) {
        _cancelConnect();
        return;
      }
      final src = _byId(from);
      if (src != null) await _connectTo(src, target);
      return;
    }
    // 批5：**勾选框先判**——它在节点盒最左 15px 内，与节点命中区重叠；
    // 不先判就会「点勾选框＝选中节点」，勾选永远点不中。
    final taskNode = _hitTaskBox(canvas);
    if (taskNode != null) {
      _longPressTimer?.cancel();
      _toggleTaskDone(taskNode);
      return;
    }
    final hit = _hitNode(canvas);
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
      preset: _view,
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

  Future<void> _addChild(int? parentId) => _createNode(
      parentId: parentId, headline: '添加子节点', continueOnSubmit: true);

  Future<void> _addSibling(MindmapNode n) =>
      // 在根节点上加同级＝新增根（C7/F1-6）。批P2：同级是速录主战场。
      _createNode(
          parentId: n.parentId,
          headline: '添加同级节点',
          continueOnSubmit: true);

  Future<void> _addRoot() => _createNode(parentId: null, headline: '加根节点');

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

  // ==================== 批5 F4-9 · 三段接线 ====================

  /// 把弹层草稿落成一行（**加节点与改节点共用这一份**——批4 教训：
  /// 同一份字段映射写两遍必漏一处，表现为「编辑能存、撤销重做丢字段」）。
  Future<void> _applyDraftNew(MindmapNode base, MmNodeDraft d) async {
    final u = base.copyWith(
      title: d.title,
      note: d.note,
      tags: d.tags,
      isTask: d.isTask,
      imagePath: d.imagePath,
      clearImage: d.imagePath == null,
      updatedAt: _now(),
    );
    await _dao.updateNode(u);
    _textSizeCache.clear(); // 标签/任务/图片都改盒宽 ⇒ 度量缓存整体失效
    setState(() {
      final i = _nodes.indexWhere((x) => x.id == u.id);
      if (i >= 0) _nodes[i] = u;
    });
    _relayout();
  }

  /// 新建节点（加子/加同级/加根三处共用）。
  ///
  /// 批P2 同级速录：回车提交且 [MmNodeSubmit.again] 时**弹层不关**，
  /// 循环回到这里再开一次同名同级弹层（弹层内部已把标题等清空，
  /// 这里只需重新走一遍插入），直到用户点保存/取消或到连录上限。
  Future<void> _createNode(
      {required int? parentId,
      required String headline,
      bool continueOnSubmit = false}) async {
    if (_nodes.length >= mmMaxNodes) {
      _toast('已达节点上限（$mmMaxNodes）');
      return;
    }
    var again = true;
    while (again && mounted) {
      final r = await showMmNodeSheet(
        // ignore: use_build_context_synchronously
        context,
        headline: headline,
        continueOnSubmit: continueOnSubmit,
      );
      if (r == null) break; // 取消＝收手（已录的都已落库，不撤）
      final d = r.draft;
      final created = await _dao.addNode(
        mapId: widget.mapId,
        parentId: parentId,
        title: d.title,
        note: d.note,
        tags: d.tags,
        isTask: d.isTask,
        imagePath: d.imagePath,
      );
      setState(() => _nodes = [..._nodes, created]);
      _undo.push(MmCommands.addSubtree(created, [created]));
      _textSizeCache.clear();
      _relayout();
      setState(() => _selectedId = created.id);
      again = r.again;
      if (again && _nodes.length >= mmMaxNodes) {
        _toast('已达节点上限（$mmMaxNodes）');
        break;
      }
    }
  }

  /// 编辑节点（H2：标题＋备注读回改写；批5：再加三段）。
  Future<void> _editNode(MindmapNode n) async {
    final r = await showMmNodeSheet(
      context,
      headline: '编辑节点',
      initialTitle: n.title,
      initialNote: n.note,
      initialTags: n.tags,
      initialTask: n.isTask,
      initialImagePath: n.imagePath,
    );
    if (r == null || n.id == null) return;
    final d = r.draft;
    final u = n.copyWith(
      title: d.title,
      note: d.note,
      tags: d.tags,
      isTask: d.isTask,
      imagePath: d.imagePath,
      clearImage: d.imagePath == null,
      updatedAt: _now(),
    );
    if (u.title != n.title ||
        u.note != n.note ||
        !listEquals(u.tags, n.tags) ||
        u.isTask != n.isTask ||
        u.imagePath != n.imagePath) {
      _undo.push(MmCommands.editNode(n, u));
    }
    await _applyDraftNew(n, d);
  }

  /// 勾选框命中判定（画布局部坐标 → 该点是否落在某节点的勾选框内）。
  ///
  /// **独立于 [_hitNode]**：勾选框在节点盒**最左 15px**，与节点命中区重叠；
  /// 若不先判勾选，点勾选框会先选中节点（原型的 `stopPropagation` 双保险
  /// 在 DOM 里天然成立，Flutter 侧要自己在这里做等价的事）。
  MindmapNode? _hitTaskBox(Offset canvas) {
    final l = _layout;
    if (l == null) return null;
    for (final n in _nodes) {
      if (!n.isTask || n.id == null) continue;
      final b = l.baseline[n.id];
      if (b == null) continue;
      final pos = b + Offset(_dxOf(n), _dyOf(n));
      final s = l.sizes[n.id] ?? const Size(120, _nodeH);
      final box = Rect.fromLTWH(pos.dx, pos.dy, _taskBoxW, s.height);
      if (box.contains(canvas)) return n;
    }
    return null;
  }

  /// 勾选完成/取消（**入撤销栈一步**，原型 `mmPushHistory` 同款语义）。
  Future<void> _toggleTaskDone(MindmapNode n) async {
    if (n.id == null) return;
    final u = n.copyWith(taskDone: !n.taskDone, updatedAt: _now());
    _undo.push(MmCommands.editNode(n, u,
        label: u.taskDone ? '完成任务' : '取消完成'));
    await _dao.updateNode(u);
    setState(() {
      _nodes[_nodes.indexWhere((x) => x.id == u.id)] = u;
    });
    // 联动待办统计：只发事件不写待办表（导出＝通知，不是替用户建条目）。
    mmCompleteNodeTask(
      ref,
      mapId: widget.mapId,
      nodeId: n.id!,
      nodeTitle: _displayTitle(n),
      done: u.taskDone,
    );
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
    // 批P 三个输入集（聚焦/连接目标/置灰）是状态派生量，改成 State 上的 getter
    // ——绘制 part 直接吃，build 里不再各留一份。
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
                        child: _canvasPaintLayer(painterNodes),
                      ),
                    ),
                    // 批P：连接态提示条（顶部）。条会盖住最顶那枚节点（多半是根，
                    // 而根正是合法目标）⇒ _makeRoomForConnectBar 已把画布下移。
                    if (_connectFrom != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 12,
                        child: _connectBar(context),
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
                    // 右下缩放条（＋/－/fit）＋布局/样式直达（原型 mmZoomBar 同款顺序：
                    // 放大·缩小·fit·**布局**·**样式**——两者都是画布高频项，
                    // 先于「更多」直达）。
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
                          _zoomBtn(context, Icons.center_focus_weak, _fit,
                              key: 'mm-layout-open'),
                          const SizedBox(height: 6),
                          _zoomBtn(
                              context, Icons.account_tree_outlined, _openLayout,
                              key: 'mm-layout-btn'),
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
          // 批P §5 第 1 条：原 `SafeArea(top:false)`＋底部 10dp 只到手势条上沿，
          // Android 手势导航下按钮仍贴死屏幕最底。bottom 抬到 18dp＋安全区
          // ⇒ 与原型 `bottom:82`（≈41dp）对齐，热区不再正对手势条。
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
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

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _saveDebounce?.cancel();
    _connectPulse.dispose();
    // PopScope flush（B4）：退出前把未落库偏移写库（不依赖 context，dispose 安全）。
    _commitLiveOffsets(immediate: true);
    super.dispose();
  }
}

