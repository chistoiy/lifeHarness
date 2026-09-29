// 提词器全屏舞台（原型 `#tpStage` / LH-KIT-LED · 批3）。
//
// 滚动=定时器按 px/s 推进（与原型 rAF 同款 80ms 单帧上限），越尾回卷到视口上方；
// 横向方向用 RotatedBox 把整块内容转 90°（原型 `rotate(90deg)` 同义，字号行距
// 跟着转）；LED 点阵=6px 间距的暗颗粒平铺（原型 radial-gradient 30% 实心）+
// 3px 扫描线按 3.6s 周期下移。舞台内改的参数即时回传屏侧落库。
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

class _KitTeleStageState extends State<KitTeleStage> {
  static const Duration _tick = Duration(milliseconds: 16);

  late KitTeleState _s = widget.state;
  Timer? _t;
  double _y = 0;
  int _scanMs = 0;
  bool _play = false;

  // 由 build 里的 LayoutBuilder 写入，供下一步滚动回卷判定。
  double _bodyH = 0;
  double _viewH = 0;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _set(KitTeleState next) {
    setState(() => _s = next);
    widget.onState(next);
  }

  void _togglePlay() {
    if (_play) {
      _t?.cancel();
      _t = null;
      setState(() => _play = false);
      AppToast.show(context, '已暂停 · 停在当前行');
      return;
    }
    if (_s.text.trim().isEmpty) {
      AppToast.show(context, '先填讲稿再提词');
      return;
    }
    setState(() => _play = true);
    _t = Timer.periodic(_tick, (_) => _step());
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

  @override
  Widget build(BuildContext context) {
    final fg = kitColor(_s.fg);
    final bg = kitColor(_s.bg);
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RotatedBox(
                key: const ValueKey('kit-tele-stage'),
                quarterTurns: _s.horizontal ? 1 : 0,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth - 48;
                    _viewH = c.maxHeight;
                    _bodyH = _measure(w, fg);
                    return ClipRect(
                      child: Stack(
                        children: [
                          Positioned(
                            left: 24,
                            right: 24,
                            top: 0,
                            child: Transform.translate(
                              offset: Offset(0, -_y),
                              child: Text(
                                _s.text.isEmpty ? '（先在参数页填入讲稿）' : _s.text,
                                key: const ValueKey('kit-tele-body'),
                                style: TextStyle(
                                  color: fg,
                                  fontSize: _s.size.toDouble(),
                                  height: _s.lineHeightFactor,
                                  fontWeight: FontWeight.w800,
                                ),
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
                    );
                  },
                ),
              ),
            ),
            _controls(fg),
          ],
        ),
      ),
    );
  }

  double _measure(double width, Color fg) {
    final tp = TextPainter(
      text: TextSpan(
        text: _s.text.isEmpty ? '（先在参数页填入讲稿）' : _s.text,
        style: TextStyle(
          color: fg,
          fontSize: _s.size.toDouble(),
          height: _s.lineHeightFactor,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width < 0 ? 0 : width);
    return tp.height;
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
              label: _play ? '暂停' : '开始提词',
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
                _t?.cancel();
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
            KitToolChip(
              keyName: 'kit-tele-stage-led',
              label: 'LED：${_s.led ? '开' : '关'}',
              on: _s.led,
              onTap: () {
                final on = !_s.led;
                _set(_s.copyWith(led: on));
                AppToast.show(context, kitTeleLedToast(on));
              },
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
