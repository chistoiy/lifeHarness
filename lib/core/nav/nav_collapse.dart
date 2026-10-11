import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';

/// 底栏「收起态」批（V1.65）＝双指张开收起底栏 / 双指捏合还原。
///
/// 口径来源＝轮4 工单 §3 评估 + 产品 2026-10-11 两处拍板：
/// - **方向**（产品 2026-10-11 裁定）：**双指张开（放大）＝收起底栏**、
///   **双指捏合＝还原**（＝轮4 原始需求；原型样张文案当时写反，已回改）。
/// - **总开关默认关**（产品 2026-10-11 裁定）：装完不改变老用户行为，用户到
///   「设置 › 外观 › 底栏手势」自己开。
/// - 机理：壳 body 外套一层**只观察不消费**的 [Listener]（不进手势竞技场，与开树同手法），
///   数在场指针；≥2 时取两指间距 / 起始间距之比，>1.15 发「收起」、<0.87 发「还原」。
/// - 收起后底栏整条收走、内容通底，底部留一条**可见线索**（细握把 / 胶囊折角，设置里切），
///   距屏幕底部距离可调（档位 8–48px，常量与校验同在 `user_settings.dart`）。
/// - **悬浮球不落底**（产品拍板）：收起时壳层给「页面内锚定底边」的悬浮球一个补偿量
///   （[ShellFabInset]），把它按屏幕位置钉住。
/// - 手势不进弹层/详情页（那些路由不在壳内，天然不冲突）；壳内页不得嵌
///   `InteractiveViewer` 大图（评估 §3 代价③），本批未涉。

/// 底栏高度（原型 nav 70px；一处定义，壳层尺寸与补偿量都取这里）。
const double kShellNavHeight = 70;

/// 底栏收放动画时长（〇B 微动档 150~180ms）。
const Duration kNavCollapseDuration = Duration(milliseconds: 170);

/// 收起态内容底留白（原型 `body.tbdemo .page.safe-pb{padding-bottom:28px}`）。
const double kNavCollapsedSlack = 28;

/// 张开/捏合判定阈值（比值＝当前两指间距 ÷ 起始两指间距）。
const double kNavPinchOpenRatio = 1.15; // >它＝张开＝收起底栏
const double kNavPinchCloseRatio = 0.87; // <它＝捏合＝还原底栏

/// 双指判定结果（纯函数产出，便于守护）。
enum NavPinchAction { none, hide, show }

/// 双指比值 → 动作：>1.15 收起、<0.87 还原、之间不动。
///
/// **方向口径**：比值 >1 ＝两指张开 → 收起底栏；<1 ＝捏合 → 还原（产品 2026-10-11 裁定）。
NavPinchAction navPinchAction(double ratio) {
  if (ratio > kNavPinchOpenRatio) return NavPinchAction.hide;
  if (ratio < kNavPinchCloseRatio) return NavPinchAction.show;
  return NavPinchAction.none;
}

/// 底栏收起态（**会话内存态**：冷启动 / 重进 app 回到展开，与原型 `body.tbdemo` 同口径；
/// 不落设置项——「收没收起」不是偏好，是临时视图状态）。
class NavCollapseController extends Notifier<bool> {
  @override
  bool build() => false;

  void hide() {
    if (!state) state = true;
  }

  void show() {
    if (state) state = false;
  }

  void toggle() => state = !state;
}

final navCollapsedProvider =
    NotifierProvider<NavCollapseController, bool>(NavCollapseController.new);

/// 给「页面内锚定底边」的悬浮球用的补偿量（＝底栏收起后飘出来的那段高度）。
///
/// 为什么需要它：悬浮球是**页面级** `floatingActionButton`（锚在页面 Scaffold 底边），
/// 底栏一收，壳 body 变高 → 页面底边下移 → 球跟着往下掉（产品明确不要它落底）。
/// 壳层按屏幕位置把这段高度补回去，球就钉在原处。不在壳内的页面读不到 → 0，行为不变。
class ShellFabInset extends InheritedWidget {
  const ShellFabInset({super.key, required this.bottom, required super.child});

  final double bottom;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellFabInset>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(ShellFabInset oldWidget) => oldWidget.bottom != bottom;
}

/// 收起态「可见线索」的两条形态（原型 #tbGrab / #tbBadge）。
///
/// 壳内的全屏线索与「设置 › 外观 › 底栏手势」卡里的预览框**共用这两个件**，
/// 所以两处永远同形（原型里共用 `--tb-gap` 是同一口径）。
///
/// A · 细握把（原型 56×4 圆头细线，中灰、透明度 .7）——最素，最不像按钮。
class NavLineGrip extends StatelessWidget {
  const NavLineGrip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 4,
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

/// B · 胶囊折角（原型 44×20 胶囊 ＋ 向上折角标）——比 A 更像「可拉起」。
class NavLineCapsule extends StatelessWidget {
  const NavLineCapsule({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 44,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.cardBorder),
        // 影只用 Colors.black12（与 grad_fab 的 Colors.black26 同族）——
        // 不写 Color(0x…) 字面量，免触「色值棘轮」（doclint 守护十）。
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(Icons.keyboard_arrow_up, size: 14, color: tokens.accent),
    );
  }
}

/// 只观察不消费的双指手势层。
///
/// 关键：用 [Listener]（原始指针事件）而不是 [GestureDetector]——**不进手势竞技场**，
/// 不抢子级（列表滚动、卡片左滑、长按等）的任何手势，只在旁边数手指。
class NavPinchListener extends StatefulWidget {
  const NavPinchListener({
    super.key,
    required this.enabled,
    required this.child,
    this.onHide,
    this.onShow,
  });

  /// 手势总开关（设置项）；关＝整层不工作（也不吞事件）。
  final bool enabled;
  final Widget child;
  final VoidCallback? onHide;
  final VoidCallback? onShow;

  @override
  State<NavPinchListener> createState() => _NavPinchListenerState();
}

class _NavPinchListenerState extends State<NavPinchListener> {
  /// 在场指针（pointer id → 最新位置）。
  final Map<int, Offset> _ptrs = <int, Offset>{};

  /// 第二指落下时的两指间距（判定基准）；不足两指／抬手后置空。
  double? _startDist;

  /// 一次手势只触发一次（防抖：判定成立后一直锁到所有手指抬起）。
  bool _fired = false;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        child: widget.child,
      );

  /// 当前前两指的间距（不足两指＝null）。
  double? get _curDist {
    if (_ptrs.length < 2) return null;
    final it = _ptrs.values.toList(growable: false);
    return (it[0] - it[1]).distance;
  }

  void _onDown(PointerDownEvent e) {
    if (!widget.enabled) return;
    _ptrs[e.pointer] = e.position;
    if (_ptrs.length == 2) {
      _startDist = _curDist;
      _fired = false;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!widget.enabled) return;
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs[e.pointer] = e.position;
    if (_fired) return;
    final start = _startDist;
    final cur = _curDist;
    if (start == null || cur == null || start <= 0) return;
    switch (navPinchAction(cur / start)) {
      case NavPinchAction.hide:
        _fired = true;
        widget.onHide?.call();
      case NavPinchAction.show:
        _fired = true;
        widget.onShow?.call();
      case NavPinchAction.none:
        break;
    }
  }

  void _onUp(PointerEvent e) {
    _ptrs.remove(e.pointer);
    if (_ptrs.length < 2) _startDist = null;
    if (_ptrs.isEmpty) _fired = false;
  }
}
