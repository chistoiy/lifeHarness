import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'note_tree_drawer.dart';

/// 开侧阈值（轮4 由 56 下调到 24＝更早入树；起手面＝整屏口径同轮4）。
const double kNoteTreeOpenTriggerPx = 24;

/// 甩速腿：横向甩速过此值即算开/关（真机反馈轮4「速度优先」口径）。
const double kNoteTreeFlingVx = 500; // px/s

/// 笔记树·常驻叠层（常驻叠层批·2026-10-11 工单 §1/§2）：树面板不再走 Navigator，
/// 作为 `NoteTab` body 之上的 Stack 层常驻，由本件自持的 [AnimationController] 驱动。
///
/// **为什么必须是常驻叠层（轮4 定位结论，勿再回路由式）**：`NavigatorState` 在路由插入时
/// 把在场指针逐个 cancel（flutter/lib/src/widgets/navigator.dart:5822）——拖拽中途 push
/// ＝这一路指针当场作废，「面板随指推出／遮罩同帧变淡」在路由式弹层上架构性不成立。
/// 叠层形态下拖拽期间不往 Navigator 插任何东西，指针一路留在本件的 `Listener` 里。
///
/// 形态＝同型参照 Flutter `Scaffold` 的 `_DrawerController`：
/// - 整屏起手右滑，累计 24px 且横>纵才入树（竖滚不误开，判据沿革轮4）；
/// - 入树后 `p＝净位移/面板宽` 逐帧钉控制器值，遮罩透明度＝`p*0.54` 同帧；
/// - 抬手判定＝**位置腿 p>0.4 或 速度腿 甩速>500px/s** 补间全开，否则反向补间回弹；
/// - 面板上左滑收起＝同一条 controller 反向跟手（判定回本件 [_settlePanel]）；
/// - 遮罩只在**全开**时参与命中（`IgnorePointer` 钉 value==1），中途态手指仍归列表，
///   卡片左滑回收站/竖滚不被叠层抢走；返回键＝`PopScope` 收起而不是退出模块。
class NoteTreeOverlay extends StatefulWidget {
  const NoteTreeOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<NoteTreeOverlay> createState() => NoteTreeOverlayState();
}

class NoteTreeOverlayState extends State<NoteTreeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: kNoteTreeAnimDur);

  /// 树在场（含回弹动画期间）＝返回键要拦、开侧监听要让位。
  bool _treeVisible = false;

  /// 全开闸（遮罩参与命中/返回键拦截都钉这一位）。
  bool _openAll = false;

  // ---- 开侧跟手（Listener 只观察、不进竞技场；沿革 EdgeSwipeToOpen 旧头注） ----
  int? _pid;
  bool _tracking = false, _following = false;
  double _dx = 0, _dy = 0, _p = 0;
  VelocityTracker? _vt;
  Offset _lastPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    // 值变化即重建（跟手段无动画也要刷），落定 0/1 时翻命中态与面板挂载。
    _c.addListener(_onTick);
  }

  void _onTick() {
    final v = _c.value;
    final vis = v > 0, openAll = v >= 1;
    // 只在命中/挂载两个布尔闸翻转时重建；纯位移帧交给 AnimatedBuilder。
    if (vis != _treeVisible || openAll != _openAll) {
      setState(() {
        _treeVisible = vis;
        _openAll = openAll;
      });
    }
  }

  double _panelW(BuildContext c) => MediaQuery.sizeOf(c).width * .62;

  void _backTo0() =>
      _c.animateBack(0, curve: Curves.easeOutCubic);

  /// 文件夹钮复用同一条开合动画。
  void open() {
    if (_treeVisible) return;
    setState(() => _treeVisible = true);
    _c.animateTo(1, curve: Curves.easeOutCubic);
  }

  /// 六处「收起自己」入口统一走这条（不许再 Navigator.pop）。
  void close() {
    if (!_treeVisible) return;
    _backTo0();
  }

  void _onDown(PointerDownEvent e) {
    // 树在场（打开中/打开后/回弹中）＝面板有自己的左滑收起，这里不再观察开侧。
    if (_treeVisible || _c.isAnimating) return;
    _pid = e.pointer;
    _tracking = true;
    _following = false;
    _dx = 0;
    _dy = 0;
    _lastPos = e.position;
    (_vt ??= VelocityTracker.withKind(e.kind))
        .addPosition(e.timeStamp, e.position);
  }

  void _onMove(PointerMoveEvent e) {
    if (!_tracking || e.pointer != _pid) return;
    _dx += e.delta.dx;
    _dy += e.delta.dy.abs();
    _lastPos = e.position;
    _vt!.addPosition(e.timeStamp, e.position);
    if (!_following) {
      // 轮4 判据照留：累计右移过阈 24 且横>纵（竖滚不误开）。
      if (_dx >= kNoteTreeOpenTriggerPx && _dx > _dy) {
        _following = true; // 面板挂载与命中闸交给 _c 监听（_onTick）
      } else {
        return;
      }
    }
    // 真跟手：p 逐帧钉控制器＝面板位移与遮罩淡入同帧（摘掉这两行＝中途态例红＝刀①）。
    final p = _dx / _panelW(context);
    _p = p.clamp(0.0, 1.0);
    _c.value = _p;
  }

  void _onUp(PointerUpEvent e) => _settle(e.pointer, e.timeStamp);

  void _onCancel(PointerCancelEvent e) => _settle(e.pointer, e.timeStamp);

  void _settle(int pid, Duration ts) {
    if (!_tracking || pid != _pid) return;
    _tracking = false;
    if (!_following) {
      _pid = null;
      return;
    }
    _following = false;
    _pid = null;
    // 速度腿按抬手时刻补一个点，否则末段位移没有样本＝甩速被低估成 0（轮4 实伤成因之一）。
    _vt!.addPosition(ts, _lastPos);
    final vx = _vt!.getVelocity().pixelsPerSecond.dx;
    _vt = null;
    // 抬手判定（轮4 撤下的三条判定在本架构下全部恢复）：位置腿 .4 或速度腿 500 → 全开。
    if (_p > .4 || vx > kNoteTreeFlingVx) {
      _c.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _backTo0();
    }
  }

  @override
  void dispose() {
    _vt = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = _panelW(context);
    return PopScope(
      canPop: !_treeVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _treeVisible) close();
      },
      child: Listener(
        key: const ValueKey('note-edge-follow'),
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            // 中途态整层不吃命中（未全开）；全开＝遮罩参与命中、点树外收起（同旧 barrier）。
            IgnorePointer(
              ignoring: !_openAll,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 遮罩：透明度＝p*0.54 同帧（全开＝与旧路由 barrier black54 等值）。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: close,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, sc) => ColoredBox(
                        key: const ValueKey('nt-barrier'),
                        color: Colors.black.withValues(alpha: .54 * _c.value),
                      ),
                    ),
                  ),
                  // 面板：Transform 逐帧位移（子级不包 Offstage——transform 要内容在场才跟手）。
                  AnimatedBuilder(
                    animation: _c,
                    builder: (_, ch) => Transform.translate(
                      offset: Offset(((_c.value - 1) * w).clamp(-w, 0.0), 0),
                      child: ch,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: w,
                        height: double.infinity,
                        child: _treeVisible
                            ? NoteTreePanel(
                                onClose: close,
                                follow: (p) => _c.value = p.clamp(0.0, 1.0),
                                settleClose: _settlePanel,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 面板左滑松手判定（工单 §1：剩开度 p<0.6 或左甩即关，否则补间回全开）。
  void _settlePanel(double p, double vx) {
    if (vx < -kNoteTreeFlingVx || p < .6) {
      close();
    } else {
      _c.animateTo(1, curve: Curves.easeOutCubic);
    }
  }
}
