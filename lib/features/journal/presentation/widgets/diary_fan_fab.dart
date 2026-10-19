import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/grad_fab.dart' show GradFab, kFabOpenRotation;

/// 日记页 FAB 的「单击新建 / 长按展开扇形」（对齐 `prototype/index-journal.html` 的 `fabFan*`）。
///
/// ## 原型口径（逐条照搬）
/// - **呼吸环**：`inset:-8px` 的 2px 主色描边圆环，4s 一来回，scale 1→1.28、opacity .42→.18；
///   `prefers-reduced-motion` 下停动画（静置 opacity .3）。
/// - **长按 380ms** 展开扇形；弧线 **-168°..-102°**（正左偏上 → 正上偏左）、半径 **74**。
///   向右上会顶屏幕右缘（FAB 距右仅 16px），所以一律向左上。
/// - 扇形**只两枚**：筛选 / 设置。**只出图标不出文字**，`tooltip` 兼作无障碍名。
/// - 44px 圆钮、`--card` 底 + `--card-bd` 描边 + 阴影；展开曲线 `cubic-bezier(.2,.8,.2,1)` 220ms。
/// - 展开后球转 45°、图标变 ×；再点球 / 点环外 / 返回键 都收起。
///
/// ## 为什么用 OverlayEntry（两次实测踩坑记录）
/// 1. **`OverflowBox` 撑成 400×400 放在 FAB 槽里**（8191 装机体）：球体被跟着挤到屏幕中央
///    ——FAB 槽按子节点尺寸定位，撑大画布＝挪走球。
/// 2. **槽内 Stack 里负偏移挂全屏**：球不挪了，但**扇形项点不中**。FAB 槽只有 56×56、原点在
///    球左上角，槽内 Stack 的 `Positioned(left: -全局x)` 是双重偏移，项画到页面别处、
///    命中测试落到 Scaffold 布局盒上（F6/F7/F8 实测 `would not hit test on the specified widget`）。
/// 3. **正解＝`OverlayEntry` 插到页面最顶层**：坐标即全屏，球与扇形各在各的坐标系里，
///    既不改球布局、也不受槽裁剪，scrim 还能真的盖住全屏。
class DiaryFanFab extends StatefulWidget {
  const DiaryFanFab({
    super.key,
    required this.onNewDiary,
    required this.onFilter,
    required this.onSettings,
  });

  /// 单击＝新建日记。
  final VoidCallback onNewDiary;
  final VoidCallback onFilter;
  final VoidCallback onSettings;

  /// 长按判定时长（原型 380ms）。
  static const Duration longPress = Duration(milliseconds: 380);

  /// 扇形项圆心到球心的距离（原型 `R=74`）。
  static const double radius = 74;

  static const double angleStart = -168;
  static const double angleEnd = -102;

  /// 扇形项直径（原型 44px）。
  static const double itemSize = 44;

  /// 球体直径（FAB 槽同尺寸）。
  static const double ballSize = 56;

  @override
  State<DiaryFanFab> createState() => _DiaryFanFabState();
}

class _DiaryFanFabState extends State<DiaryFanFab>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  final GlobalKey _ballKey = GlobalKey();

  /// 扇形层（挂在 Overlay 上，坐标系＝全屏）。
  OverlayEntry? _entry;

  /// **必须 `initState` 里建**：惰性 `late final ... =` 在「从没展开过」的路径上会拖到
  /// `dispose()` 才首次构造，届时 element 已 deactivated，抛
  /// 「Looking up a deactivated widget's ancestor is unsafe」。
  late final AnimationController _anim;

  static const Duration _dur = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _dur);
  }

  @override
  void dispose() {
    _removeEntry();
    _anim.dispose();
    super.dispose();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _openFan() {
    final box = _ballKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final c = box.localToGlobal(box.size.center(Offset.zero));
    setState(() => _open = true);
    _entry?.remove();
    _entry = OverlayEntry(builder: (_) => _buildFanLayer(c));
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _anim.forward(from: 0);
  }

  void _close() {
    if (!_open) return;
    _removeEntry();
    setState(() => _open = false);
    _anim.value = 0;
  }

  void _act(VoidCallback cb) {
    // 先收起再执行；不延后一帧（延后会让「展开中」多一帧空窗，也让测试拿不到弹层）。
    _close();
    cb();
  }

  @override
  Widget build(BuildContext context) {
    // 球本体：56×56，位置交给 Scaffold 的 FAB 槽（不撑大、不加 padding）。
    return _BreathingBall(
      key: _ballKey,
      open: _open,
      onTap: _open ? _close : widget.onNewDiary,
      onLongPress: _open ? null : _openFan,
    );
  }

  /// 全屏扇形层：scrim + 两枚项，全部用**全局坐标**（Overlay 的坐标系就是全屏）。
  Widget _buildFanLayer(Offset c) {
    final acts = <({IconData icon, String label, VoidCallback go})>[
      (icon: Icons.filter_alt_outlined, label: '筛选', go: widget.onFilter),
      (icon: Icons.tune, label: '设置', go: widget.onSettings),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('diary-fan-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        for (var i = 0; i < acts.length; i++)
          _fanItem(c, i, acts.length, acts[i].icon, acts[i].label,
              () => _act(acts[i].go)),
      ],
    );
  }

  /// 一枚扇形项：**圆心从球心沿角度推 74px**，`Positioned` 用圆心减半径。
  Widget _fanItem(
    Offset center,
    int i,
    int n,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final ang = (DiaryFanFab.angleStart +
            (DiaryFanFab.angleEnd - DiaryFanFab.angleStart) *
                (n == 1 ? 0 : i / (n - 1))) *
        math.pi /
        180;
    final dx = math.cos(ang) * DiaryFanFab.radius;
    final dy = math.sin(ang) * DiaryFanFab.radius;
    const r = DiaryFanFab.itemSize / 2;
    return AnimatedBuilder(
      key: ValueKey('diary-fan-$label'),
      animation: _anim,
      builder: (context, child) {
        final p = _anim.value.clamp(0.0, 1.0);
        // 原型 cubic-bezier(.2,.8,.2,1) 的近似（先快后慢的轻微回弹感）。
        final t = Curves.easeOutCubic.transform(p);
        // 逐枚 30ms 延迟：第 2 枚比第 1 枚晚起跳（原型 `transition-delay`）。
        final local = ((p - i * .06) / (1 - (n - 1) * .06)).clamp(0.0, 1.0);
        return Positioned(
          left: center.dx + dx * t - r,
          top: center.dy + dy * t - r,
          width: DiaryFanFab.itemSize,
          height: DiaryFanFab.itemSize,
          child: Opacity(opacity: local, child: child),
        );
      },
      child: _FanItemBody(icon: icon, label: label, onTap: onTap),
    );
  }
}

/// 呼吸环 + 球本体。环只缩放自身，不位移球（原型 `#fabHalo`）。
class _BreathingBall extends StatefulWidget {
  const _BreathingBall({
    super.key,
    required this.open,
    required this.onTap,
    required this.onLongPress,
  });

  final bool open;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_BreathingBall> createState() => _BreathingBallState();
}

class _BreathingBallState extends State<_BreathingBall>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4000));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `prefers-reduced-motion` 的 Flutter 对应物：系统「移除动画」。
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced != _reduced) _reduced = reduced;
    if (_reduced) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final dark =
        ThemeData.estimateBrightnessForColor(tokens.page) == Brightness.dark;
    return SizedBox(
      width: DiaryFanFab.ballSize,
      height: DiaryFanFab.ballSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 呼吸环（原型 `#fabHalo`）：`inset:-8px` ⇒ 72×72 的 2px 描边圆，只缩放不挡点击。
          // 曲率＝原型 `ease-in-out`（原来用线性，节奏生硬像心跳不像呼吸）。
          Positioned(
            key: const ValueKey('diary-fan-halo'),
            left: -8,
            top: -8,
            width: 72,
            height: 72,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final v = _reduced
                      ? 0.0
                      : Curves.easeInOut.transform(_c.value);
                  // 0..1 往返 ⇒ scale 1..1.28、opacity .42→.18（`0%,100%` .42／`50%` .18）。
                  final op = _reduced ? .30 : .42 - .24 * v;
                  return Opacity(
                    opacity: op,
                    child: Transform.scale(
                      scale: 1 + .28 * v,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: tokens.accent, width: 2),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // 本体外光晕（原型 `#fab` 的 `box-shadow: … , 0 0 0 6px rgba(99,102,241,.07)`）。
          // 这一层是「呼吸感」的另一半：只有描边环时观感是「一圈灰边在胀」，加上 6px 柔光环
          // 才像光在球周围散开。深档提高到 .10（深底需更亮）。
          Positioned(
            key: const ValueKey('diary-fan-glow'),
            left: -6,
            top: -6,
            width: 68,
            height: 68,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.accent.withValues(alpha: dark ? .10 : .07),
                ),
              ),
            ),
          ),
          GradFab(
            tooltip: widget.open ? '收起' : '写今天的日记（长按：筛选与设置）',
            rotation: widget.open ? kFabOpenRotation : 0,
            icon: Icon(widget.open ? Icons.close : Icons.add,
                color: Colors.white, size: 26),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
          ),
        ],
      ),
    );
  }
}

/// 扇形项内容（图标 + 命中区），与定位解耦以便动画缓存 child。
class _FanItemBody extends StatelessWidget {
  const _FanItemBody({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: label,
      child: Material(
        color: tokens.card,
        shape: CircleBorder(side: BorderSide(color: tokens.cardBorder)),
        elevation: 4,
        shadowColor: const Color(0x290F172A),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(child: Icon(icon, size: 19, color: tokens.ink)),
        ),
      ),
    );
  }
}
