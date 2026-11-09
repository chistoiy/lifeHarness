part of 'mindmap_canvas_page.dart';

/// 画布页的**选中态贴点气泡**（批P5 · 2026-10-20 落地，独立 part 件）。
///
/// 动因：§5 第 7 条——底部悬浮工具条离手指远、还挡画布内容。产品拍板后
/// 工具条**整条撤掉**，选中主操作整组搬成贴在节点上沿外侧的小气泡：
/// 「加子节点」（主色）＋「更多」（次色，原作仍在那个贴点菜单里）。
///
/// 落位口径（与原型 `mmSyncBubble` 同构，逐条对应）：
/// - 首选贴节点**上沿外侧 10dp**、整块水平对齐节点中心；
/// - 上方放不下时按「节点**右侧** → **左侧** → 最后才压下方」三级让位
///   ——纵向树里节点下方紧挨子级，压上去会挡字；
/// - 四边一律夹在画布内 10dp。
///
/// 两侧各留一档的取舍：气泡高 36dp、节点行高 40dp，而画布顶部还要让开
/// 连接提示条与缩放标签，最顶上那枚节点（多半是根）上方常常只剩 20~30dp
/// ——固定「上沿外侧」在同屏根节点上必然压住它的第一个子级（原型截图实证）。
extension _MmBubbleOps on _MindmapCanvasPageState {
  /// 气泡锚点（画布局部坐标）＝节点左上角 + 尺寸。节点屏幕位＝基线过一遍视口变换。
  /// 口径与 `_menuAnchorOf` 完全一致（同一条变换链，不另算一套）。
  ({
    Offset origin,
    Size size,
  })? _bubbleAnchorOf(MindmapNode n) {
    final id = n.id;
    final l = _layout;
    if (id == null || l == null) return null;
    final b = l.baseline[id];
    if (b == null) return null;
    final s = l.sizes[id] ?? const Size(120, _nodeH);
    return (origin: (b + Offset(_dxOf(n), _dyOf(n))) * _scale + _pan, size: s);
  }

  /// 该节点第一个**可见**子级在节点上沿之下的净空（让位时的下沿天花板）。
  ///
  /// **相对量**，不是屏幕绝对 y：气泡锚点用的是画布局部坐标（`_viewport` 高，
  /// 不含 AppBar），子级的屏幕 y 含 AppBar 偏移——两套坐标系直接相减会把
  /// 天花板算到节点上方去（首次实现就踩了，气泡纹丝不动）。故这里只返回
  /// 「子级上沿 − 节点上沿」，委托里再加回 nodeTop，坐标系就对齐了。
  ///
  /// 取「可见」而不是「第一个」：折叠枝里的子级画布上不画，拿它当天花板会
  /// 把气泡顶到莫名其妙的高度。没有可见子级＝null（正居中）。
  double? _firstChildGapOf(MindmapNode n) {
    final l = _layout;
    final nid = n.id;
    if (l == null || nid == null) return null;
    final b = l.baseline[nid];
    if (b == null) return null;
    final nodeTopLocal = (b + Offset(_dxOf(n), _dyOf(n))).dy * _scale + _pan.dy;
    final vis = _visibleIds();
    double? best;
    for (final c in _nodes) {
      if (c.parentId != nid || c.id == null || !vis.contains(c.id)) continue;
      final cb = l.baseline[c.id];
      if (cb == null) continue;
      final t = (cb + Offset(_dxOf(c), _dyOf(c))).dy * _scale + _pan.dy;
      if (best == null || t < best) best = t;
    }
    return best == null ? null : best - nodeTopLocal;
  }

  /// 选中态气泡。未选中 / 连接中 / 拖线中一律不渲染——连接态下点节点是
  /// 「选目标」不是「改这一枝」，此时给操作气泡只会误导。
  ///
  /// `debugBubblePos` 只在测试里传（`@visibleForTesting` 的静态钩子），用来把
  /// 落位结果与几何解耦：节点被挤到贴顶那几格时，「屏幕几何反推分支」既脆弱
  /// 又容易被视口留白骗成假绿——直接读委托算出的落位才认得出走了哪一档。
  Widget? _selectedBubble(BuildContext context) {
    final sel = _selectedId == null ? null : _byId(_selectedId!);
    if (sel == null || _connectFrom != null) return null;
    final a = _bubbleAnchorOf(sel);
    if (a == null) return null;
    final vp = _viewport;
    if (vp.width <= 0 || vp.height <= 0) return null;

    const gap = 10.0; // 与节点的最小净距
    const inset = 10.0; // 与画布四边的最小净距
    final box = a.size * _scale;
    final origin = a.origin;

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, _) {
          // 先在无约束下量一遍尺寸（气泡随文案变宽，写死会截字）。
          final delegate = _MmBubbleDelegate(
            nodeLeft: origin.dx,
            nodeTop: origin.dy,
            nodeW: box.width,
            nodeH: box.height,
            gap: gap,
            inset: inset,
            ceiling: _firstChildGapOf(sel),
          );
          MmBubbleProbe.last = delegate;
          return CustomSingleChildLayout(
            delegate: delegate,
            child: _bubbleRow(context, sel),
          );
        },
      ),
    );
  }

  Widget _bubbleRow(BuildContext context, MindmapNode n) {
    final cs = Theme.of(context).colorScheme;
    Widget chip({
      required ValueKey<String> key,
      required IconData icon,
      required String label,
      required bool primary,
      required VoidCallback onTap,
    }) {
      final fg = primary ? cs.onPrimary : cs.onSurface;
      // key 钉在**内层 InkWell**（与旧底部条 `_toolBtn` 同口径）——用例一律
      // `tester.widget<InkWell>(find.byKey(...))` 取触点，钉在 Material 上会类型错。
      return Material(
        color: primary ? cs.primary : cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: primary
              ? BorderSide.none
              : BorderSide(color: cs.outlineVariant.withValues(alpha: .6)),
        ),
        elevation: primary ? 3 : 0,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fg)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip(
            key: const ValueKey('mm-bubble-child'),
            icon: Icons.add,
            label: '加子节点',
            primary: true,
            onTap: () => _addChild(n.id),
          ),
          const SizedBox(width: 4),
          chip(
            key: const ValueKey('mm-bubble-more'),
            icon: Icons.more_horiz,
            label: '更多',
            primary: false,
            onTap: () => _showNodeMenu(n),
          ),
        ],
      ),
    );
  }
}

/// 气泡落位委托：贴在节点上沿外侧／放不下时三级让位／四边夹取。
///
/// 让位档位记在 [tier] 里（`top`／`right`／`left`／`below`）——测试要断的正是
/// 「上方放不下时走了哪一档」，而屏幕几何会被视口留白与夹取搅浑。
class _MmBubbleDelegate extends SingleChildLayoutDelegate {
  _MmBubbleDelegate({
    required this.nodeLeft,
    required this.nodeTop,
    required this.nodeW,
    required this.nodeH,
    required this.gap,
    required this.inset,
    this.ceiling,
  });

  final double nodeLeft;
  final double nodeTop;
  final double nodeW;
  final double nodeH;
  final double gap;
  final double inset;

  /// 让位时的「下沿天花板」＝该节点**第一个可见子级的屏幕上沿**。
  /// 纵向树里节点正下方就是子级，正居中会把气泡压在子级顶边上；
  /// 有天花板就往上收。没有子级（或子级在视口外）时为 null＝正居中。
  final double? ceiling;

  /// 实际走的那一档（`top`＝贴节点上沿，其余三档都是让位）。
  String tier = 'top';

  /// 上次算出来的天花板（诊断用；null＝没有可见子级）。
  double? ceilingSeen;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(c.biggest);

  @override
  Offset getPositionForChild(Size size, Size child) {
    double clampX(double v) =>
        math.max(inset, math.min(v, size.width - child.width - inset));
    double clampY(double v) =>
        math.max(inset, math.min(v, size.height - child.height - inset));

    // 让位时纵向怎么落：正居中优先，但**下沿不许越过子级上沿**——
    // 纵向树里节点正下方就是第一个子级，正居中会横跨它的顶边。
    //
    // 顺序很要紧：先排「不许越线」，再看画布四边。反过来（先夹取再 min 天花板）
    // 在两档都成立时会压子级；而 nodeTop 已经贴 0 时，两者的结果**恰好相同**
    // ——都被夹到同一个 top 上，看起来像没生效。故这里不夹、原样给出，
    // 越界与否交给外面判（真放不下就换第三档「压下方」）。
    double sideTop() {
      final cy = nodeTop + (nodeH - child.height) / 2;
      if (ceiling == null) return cy;
      // ceiling 是**相对节点上沿**的净空，相当于「气泡下沿的最高位置」。
      final hardMax = nodeTop + ceiling! - child.height;
      return math.min(cy, hardMax);
    }

    final nodeCx = nodeLeft + nodeW / 2;
    var left = clampX(nodeCx - child.width / 2);
    var top = nodeTop - gap - child.height;
    tier = 'top';
    ceilingSeen = ceiling;

    if (top < inset) {
      // 上方放不下：右侧 → 左侧 → 压下方（顺序同原型，理由见文件头）。
      // 「正好放得下」用 `>=` 判：夹到 `inset` 那格时按「放得下」处理，
      // 别为省 1dp 把气泡塞到节点侧面（原型同口径）。
      final right = nodeLeft + nodeW + gap;
      final leftSide = nodeLeft - gap - child.width;
      final side = sideTop();
      // 侧面放得下＝横向有位置 **且** 纵向不越界（越界就落回第三档「压下方」，
      // 那一档至少不会横跨子级的顶边——子级开始的位置就是它）。
      final sideFits = side >= inset && side <= size.height - child.height - inset;
      if (right + child.width <= size.width - inset && sideFits) {
        left = right;
        top = side;
        tier = 'right';
      } else if (leftSide >= inset && sideFits) {
        left = leftSide;
        top = side;
        tier = 'left';
      } else {
        top = nodeTop + nodeH + gap;
        tier = 'below';
      }
    }
    return Offset(clampX(left), clampY(top));
  }

  @override
  bool shouldRelayout(_MmBubbleDelegate old) =>
      old.nodeLeft != nodeLeft ||
      old.nodeTop != nodeTop ||
      old.nodeW != nodeW ||
      old.nodeH != nodeH ||
      old.gap != gap ||
      old.inset != inset ||
      old.ceiling != ceiling;
}

/// 落位探针（仅测试用）：把最近一次渲染的委托交出来，读它的 [tier] 与几何。
///
/// 为什么需要它：贴顶那几档的屏幕坐标既受视口留白影响、又被四边夹取抹平，
/// 「按坐标反推走了哪一档」会写出看着在断、其实两边恒等的假用例（本批首次
/// 跑就假绿过一次）。直接读委托算出的结果才认得出分支。
@visibleForTesting
class MmBubbleProbe {  MmBubbleProbe._();

  static SingleChildLayoutDelegate? last;

  /// 当前气泡落位档位：`top`／`right`／`left`／`below`；没渲染气泡时为 null。
  static String? get tier =>
      last is _MmBubbleDelegate ? (last as _MmBubbleDelegate).tier : null;

  static void reset() => last = null;

  /// 上次算出的下沿天花板（null＝当时没有可用子级）。
  static double? get ceiling =>
      last is _MmBubbleDelegate ? (last as _MmBubbleDelegate).ceilingSeen : null;
}

/// 落位委托的调试入口（仅测试用）：绕开 widget 树直接喂几何。
///
/// 让位那几档在真实布局里很难稳定造出来（视口留白、fit 缩放、四边夹取三者
/// 一起动），而它们的共同判据就是「气泡该落哪」。直接调它最省事也最不容易
/// 写出假用例。
@visibleForTesting
MmBubblePlacement debugBubbleDelegate({
  required double nodeLeft,
  required double nodeTop,
  required double nodeW,
  required double nodeH,
  required double gap,
  required double inset,
  double? ceiling,
  Size canvas = const Size(800, 544),
  Size childSize = const Size(168, 36),
}) =>
    _placementOf(_MmBubbleDelegate(
      nodeLeft: nodeLeft,
      nodeTop: nodeTop,
      nodeW: nodeW,
      nodeH: nodeH,
      gap: gap,
      inset: inset,
      ceiling: ceiling,
    ), canvas, childSize);

MmBubblePlacement _placementOf(
    _MmBubbleDelegate d, Size canvas, Size child) {
  final pos = d.getPositionForChild(canvas, child);
  return MmBubblePlacement(pos, d.tier);
}

/// 调试入口的返回值：落位坐标＋走了哪一档（`top`／`right`／`left`／`below`）。
@visibleForTesting
class MmBubblePlacement {
  MmBubblePlacement(this.position, this.tier);
  final Offset position;
  final String tier;
}
