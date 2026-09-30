// 提词器全屏舞台（原型 `#tpStage` / LH-KIT-LED · 批3 · 反馈轮4 效果组）。
//
// 两种显示方式：滚动=定时器按 px/s 推进（与原型 rAF 同款 80ms 单帧上限，越尾
// 回卷）；静止=内容按视口垂直居中铺屏（图2/3 那类手持大字展示）。横向方向用
// RotatedBox 把整块内容转 90°（原型 `rotate(90deg)` 同义）。
// 效果组（原型 `tp-blink / tp-bold / tp-shake / tp-g-*`）：闪烁与抖动共用一条
// 1.1s 周期的时钟（[AnimationController.repeat]），闪烁取前半亮后半暗、抖动按
// 四角关键帧轮转；多彩渐变背景盖过纯色底色。LED 点阵=6px 间距的暗颗粒平铺 +
// 3px 扫描线按 3.6s 周期下移。
// 展示态只留左上角淡返回箭头（图3 口径）：进入时控制条浮出 1.8s 后收起，
// 点按屏幕随时唤回。舞台内改的参数即时回传屏侧落库。
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_tele.dart';
import 'kit_tools_kit.dart';

/// 提词舞台。
class KitTeleStage extends StatefulWidget {
  const KitTeleStage({super.key, required this.state, required this.onState});

  final KitTeleState state;

  /// 舞台内任何参数改动都回传（屏侧负责落库）。
  final ValueChanged<KitTeleState> onState;

  @override
  State<KitTeleStage> createState() => _KitTeleStageState();
}

class _KitTeleStageState extends State<KitTeleStage>
    with SingleTickerProviderStateMixin {
  static const Duration _tick = Duration(milliseconds: 16);

  /// 效果时钟周期（原型闪烁 1.1s；抖动 0.28s 由同一周期切 4 档得到）。
  static const Duration _fxPeriod = Duration(milliseconds: 1100);
  static const double _fxShakeCycles = 1100 / 280;

  /// 进入时控制条浮出多久（之后靠点按唤回）。
  static const Duration _ctlHold = Duration(milliseconds: 1800);

  late KitTeleState _s = widget.state;
  Timer? _t;
  Timer? _hideCtl;
  double _y = 0;
  int _scanMs = 0;
  bool _play = false;
  bool _ctlOn = true;

  late final AnimationController _fx = AnimationController(
    vsync: this,
    duration: _fxPeriod,
  );

  // 由 build 里的 LayoutBuilder 写入，供下一步滚动回卷判定。
  double _bodyH = 0;
  double _viewH = 0;

  @override
  void initState() {
    super.initState();
    // 滚动态进入即走字（图2 的「显示弹幕」就是按下去直接展示）；静止态不动。
    if (!_s.isStatic) _start();
    _syncFx();
    _holdCtl();
  }

  @override
  void dispose() {
    _t?.cancel();
    _hideCtl?.cancel();
    _fx.dispose();
    super.dispose();
  }

  void _set(KitTeleState next) {
    setState(() => _s = next);
    widget.onState(next);
    _syncFx();
    if (_s.isStatic) _pause();
  }

  /// 闪烁 / 抖动任一开着才让时钟跑起来，避免静止展示时无谓重绘。
  void _syncFx() {
    final need = _s.blink || _s.shake > 0;
    if (need && !_fx.isAnimating) {
      _fx.repeat();
    } else if (!need && _fx.isAnimating) {
      _fx.stop();
    }
  }

  void _holdCtl() {
    _hideCtl?.cancel();
    setState(() => _ctlOn = true);
    _hideCtl = Timer(_ctlHold, () {
      if (mounted) setState(() => _ctlOn = false);
    });
  }

  void _togglePlay() {
    if (_play) {
      _pause();
      AppToast.show(context, '已暂停 · 停在当前行');
      return;
    }
    if (_s.text.trim().isEmpty) {
      AppToast.show(context, '先填内容再提词');
      return;
    }
    _start();
  }

  void _start() {
    _t?.cancel();
    setState(() => _play = true);
    _t = Timer.periodic(_tick, (_) => _step());
  }

  void _pause() {
    _t?.cancel();
    _t = null;
    if (mounted) setState(() => _play = false);
  }

  void _step() {
    setState(() {
      _scanMs += _tick.inMilliseconds;
      _y = kitTeleWrap(
        y: _y + kitTeleAdvance(pxPerSec: _s.speed, dtMs: _tick.inMilliseconds),
        bodyHeight: _bodyH,
        viewportHeight: _viewH,
      );
    });
  }

  void _reset() {
    setState(() => _y = 0);
    AppToast.show(context, '已回到稿首');
  }

  /// 舞台主体（滚动位移 / 静止居中 + 闪烁 / 加粗 / 抖动）。
  Widget _body(BoxConstraints c, Color fg) {
    final w = c.maxWidth - 48;
    _viewH = c.maxHeight;
    final text = _s.text.isEmpty ? '（先在参数页填入内容）' : _s.text;
    final style = TextStyle(
      color: fg,
      fontSize: _s.size.toDouble(),
      height: _s.lineHeightFactor,
      fontWeight: _s.bold ? FontWeight.w900 : FontWeight.w500,
    );
    _bodyH = _measure(w, style, text);
    final offset = _s.isStatic
        ? kitTeleStaticTranslateY(bodyHeight: _bodyH, viewportHeight: c.maxHeight)
        : -_y;
    return ClipRect(
      child: ListenableBuilder(
        listenable: _fx,
        builder: (context, child) {
          final phase = _fx.value;
          final sh = kitTeleShakeOffset(phase: (phase * _fxShakeCycles) % 1, px: _s.shake);
          return Transform.translate(
            offset: Offset(sh.$1, sh.$2),
            child: Opacity(
              opacity: _s.blink ? kitTeleBlinkOpacity(phase) : 1,
              child: child,
            ),
          );
        },
        child: Stack(
          children: [
            Positioned(
              left: 24,
              right: 24,
              top: 0,
              child: Transform.translate(
                offset: Offset(0, offset),
                child: Text(
                  text,
                  key: const ValueKey('kit-tele-body'),
                  textAlign: _s.isStatic ? TextAlign.center : TextAlign.left,
                  style: style,
                ),
              ),
            ),
            if (_s.led)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const ValueKey('kit-tele-led-grid'),
                    painter: _KitTeleLedPainter(
                      fraction: kitTeleScanFraction(_scanMs),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _measure(double width, TextStyle style, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width < 0 ? 0 : width);
    return tp.height;
  }

  @override
  Widget build(BuildContext context) {
    final fg = kitColor(_s.fg);
    final colors = _s.gradColors;
    return Scaffold(
      backgroundColor: _s.gradOn ? Colors.black : kitColor(_s.bg),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _s.gradOn
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [for (final c in colors) Color(c)],
                )
              : null,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 返回箭头：展示态唯一的常驻控件（图3）。
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('kit-tele-back'),
                      onPressed: () {
                        _pause();
                        Navigator.of(context).pop();
                      },
                      icon: Icon(
                        Icons.arrow_back,
                        color: fg.withValues(alpha: .45),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('kit-tele-stage'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _ctlOn = !_ctlOn),
                  child: RotatedBox(
                    quarterTurns: _s.horizontal ? 1 : 0,
                    child: LayoutBuilder(
                      builder: (context, c) => _body(c, fg),
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                key: const ValueKey('kit-tele-ctl'),
                opacity: _ctlOn ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_ctlOn,
                  child: _controls(fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(Color fg) => Container(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: fg.withValues(alpha: .18))),
    ),
    child: Column(
      children: [
        Row(
          children: [
            KitToolChip(
              keyName: 'kit-tele-play',
              label: _play ? '暂停' : (_s.isStatic ? '静止展示' : '开始提词'),
              on: _play,
              onTap: _togglePlay,
            ),
            kitToolBtn(
              context,
              '回到稿首',
              _reset,
              keyName: 'kit-tele-reset',
              small: true,
              color: fg,
            ),
            const Spacer(),
            kitToolBtn(
              context,
              '退出',
              () {
                _pause();
                Navigator.of(context).pop();
              },
              keyName: 'kit-tele-close',
              small: true,
              color: fg,
            ),
          ],
        ),
        Row(
          children: [
            _miniSlider(
              label: '速度',
              keyName: 'kit-tele-stage-speed',
              value: _s.speed.toDouble(),
              min: kKitTeleSpeedMin,
              max: kKitTeleSpeedMax,
              step: kKitTeleSpeedStep,
              text: kitTeleSpeedText(_s.speed),
              onChanged: (v) => _set(_s.copyWith(speed: v.round())),
            ),
            _miniSlider(
              label: '字号',
              keyName: 'kit-tele-stage-size',
              value: _s.size.toDouble(),
              min: kKitTeleSizeMin,
              max: kKitTeleSizeMax,
              step: 1,
              text: kitTeleSizeText(_s.size),
              onChanged: (v) => _set(_s.copyWith(size: v.round())),
            ),
            _miniSlider(
              label: '行距',
              keyName: 'kit-tele-stage-lh',
              value: _s.lh.toDouble(),
              min: kKitTeleLhMin,
              max: kKitTeleLhMax,
              step: kKitTeleLhStep,
              text: kitTeleLhText(_s.lh),
              onChanged: (v) => _set(_s.copyWith(lh: v.round())),
            ),
          ],
        ),
        Row(
          children: [
            KitToolChip(
              keyName: 'kit-tele-stage-mode',
              label: _s.isStatic ? '方式：静止' : '方式：滚动',
              on: false,
              onTap: () =>
                    _set(_s.copyWith(mode: _s.isStatic ? kKitTeleModeScroll : kKitTeleModeStatic)),
            ),
            const SizedBox(width: 6),
            KitToolChip(
              keyName: 'kit-tele-stage-blink',
              label: '闪烁',
              on: _s.blink,
              onTap: () => _set(_s.copyWith(blink: !_s.blink)),
            ),
            const SizedBox(width: 6),
            KitToolChip(
              keyName: 'kit-tele-stage-bold',
              label: '加粗',
              on: _s.bold,
              onTap: () => _set(_s.copyWith(bold: !_s.bold)),
            ),
            const SizedBox(width: 6),
            KitToolChip(
              keyName: 'kit-tele-stage-led',
              label: 'LED：${_s.led ? '开' : '关'}',
              on: _s.led,
              onTap: () => _set(_s.copyWith(led: !_s.led)),
            ),
            const SizedBox(width: 6),
            KitToolChip(
              keyName: 'kit-tele-stage-grad',
              label: '背景：${kitTeleGrad(_s.grad).label}',
              on: _s.gradOn,
              onTap: () => _set(_s.copyWith(grad: kitTeleGradNext(_s.grad))),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _miniSlider({
    required String label,
    required String keyName,
    required double value,
    required int min,
    required int max,
    required int step,
    required String text,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    return Expanded(
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: Colors.white70)),
          Expanded(
            child: Slider(
              key: ValueKey(keyName),
              value: value.clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions < 2 ? null : divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              text,
              key: ValueKey('$keyName-v'),
              style: const TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// LED 点阵 + 扫描线（原型 `.tp-led` 的两层背景）。
class _KitTeleLedPainter extends CustomPainter {
  _KitTeleLedPainter({required this.fraction});

  final double fraction;

  static ui.Image? _tile;

  static ui.Image _tileImage() {
    final cached = _tile;
    if (cached != null) return cached;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(
      rec,
      const Rect.fromLTWH(0, 0, kKitTeleDotPitch, kKitTeleDotPitch),
    );
    canvas.drawCircle(
      const Offset(kKitTeleDotPitch / 2, kKitTeleDotPitch / 2),
      kitTeleDotRadius(),
      Paint()..color = const Color(0x99000000),
    );
    final pic = rec.endRecording();
    final img = pic.toImageSync(
      kKitTeleDotPitch.round(),
      kKitTeleDotPitch.round(),
    );
    pic.dispose();
    return _tile = img;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.ImageShader(
        _tileImage(),
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Matrix4.identity().storage,
      );
    canvas.drawRect(Offset.zero & size, paint);
    final top = fraction * (size.height - kKitTeleScanHeight);
    final scan = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, top),
        const Offset(0, kKitTeleScanHeight) + Offset(0, top),
        [
          const Color(0x00FFFFFF),
          const Color(0x52FFFFFF),
          const Color(0x00FFFFFF),
        ],
        // 三段渐变必须显式给 colorStops（dart:ui 省略时只允许两色）。
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, kKitTeleScanHeight),
      scan,
    );
  }

  @override
  bool shouldRepaint(covariant _KitTeleLedPainter old) =>
      old.fraction != fraction;
}
