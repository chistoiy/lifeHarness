// 工具屏 · 互补色方案（原型 `TOOLS.comp` / `cmpShow` / `cmpWheel` 同源 · 批2）。
//
// 色环为自绘 CustomPainter（60 段弧 + 方案色标记），支持按住拖动实时换主色
// （V1.47 真机轮2 拍板）；选色入口走应用内弹层，禁用系统取色器。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/kit_color.dart';
import '../../domain/kit_models.dart';

import '../kit_color_sheet.dart';
import '../kit_providers.dart';
import 'kit_tools_kit.dart';

class KitCompBody extends ConsumerStatefulWidget {
  const KitCompBody({super.key});

  @override
  ConsumerState<KitCompBody> createState() => _KitCompBodyState();
}

class _KitCompBodyState extends ConsumerState<KitCompBody> {
  String _hex = '#6366f1';
  int _mode = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final d = await ref.read(kitRepositoryProvider).toolData(kitToolKeyComp);
    if (!mounted) return;
    final hex = d['hex'];
    final mode = d['mode'];
    setState(() {
      if (hex is String && kitHexToRgb(hex) != null) _hex = hex;
      if (mode is int && mode >= 0 && mode < kKitSchemes.length) _mode = mode;
    });
  }

  Future<void> _persist() => ref.read(kitRepositoryProvider).setToolData(
        kitToolKeyComp,
        {'hex': _hex, 'mode': _mode},
      );

  KitScheme get _scheme => kKitSchemes[_mode];

  List<KitSchemeColor> get _colors => kitSchemeColors(_hex, _scheme);

  void _cycle() {
    setState(() => _mode = (_mode + 1) % kKitSchemes.length);
    _persist();
  }

  /// 色环拖动/点选：把局部坐标换算成角度，保留当前 S/L 只换色相。
  void _steer(Offset local, Size box) {
    final dx = local.dx - box.width / 2;
    final dy = local.dy - box.height / 2;
    final next = kitHueFromAngle(dx: dx, dy: dy, keep: kitHexToHsl(_hex));
    if (next == _hex) return;
    setState(() => _hex = next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = _colors;
    final base = kitHexToHsl(_hex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KitColorSwatchButton(hex: _hex, onChanged: (v) {
              setState(() => _hex = v);
              _persist();
            }),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '主色 ${_hex.toUpperCase()} · ${_scheme.name}',
                key: const ValueKey('kit-comp-main'),
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: LayoutBuilder(
            builder: (context, c) {
              final box = Size(c.maxWidth, c.maxWidth);
              return GestureDetector(
                key: const ValueKey('kit-comp-wheel'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => setState(() => _dragging = true),
                onPanUpdate: (d) => _steer(d.localPosition, box),
                onPanEnd: (_) => setState(() => _dragging = false),
                onPanCancel: () => setState(() => _dragging = false),
                onTapDown: (d) => _steer(d.localPosition, box),
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: CustomPaint(
                    painter: _CompWheelPainter(
                      segments: kitWheelSegments(base),
                      colors: colors,
                      base: base,
                      modeName: _scheme.name,
                      dragging: _dragging,
                      card: tokens.card,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        kitToolNote(
          _dragging ? '拖动中 · 主色随角度实时重算' : '按住色环拖动可换主色（保留饱和与明度）',
          key: const ValueKey('kit-comp-drag-hint'),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < colors.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                GestureDetector(
                  key: ValueKey('kit-comp-dot-${i.toString()}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => kitToolCopy(context, colors[i].hex.toUpperCase()),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: kitColor(colors[i].hex),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i == 0 ? '原色 · ${colors[i].name}' : colors[i].name,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${colors[i].hex.toUpperCase()} · H ${colors[i].deg.round()}°',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                kitToolBtn(
                  context,
                  '复制',
                  () => kitToolCopy(context, colors[i].hex.toUpperCase()),
                  keyName: 'kit-comp-copy-$i',
                  small: true,
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        kitToolNote(
          '${_scheme.name} · ${_scheme.desc} · S ${base.s.round()}% / L ${base.l.round()}% 随主色保持',
          key: const ValueKey('kit-comp-desc'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: kitToolBtn(
                context,
                '一键复制全套 HEX',
                () => kitToolCopy(
                  context,
                  colors.map((c) => c.hex.toUpperCase()).join('  '),
                  msg: '全套 ${colors.length} 色已复制',
                ),
                keyName: 'kit-comp-copy-all',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: kitToolBtn(
                context,
                '切换方案 · ${_scheme.name}',
                _cycle,
                keyName: 'kit-comp-cycle',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 色环（原型 `cmpWheel`：60 段环带 + 每色刻度弧与圆点 + 中心方案名/主色串）。
class _CompWheelPainter extends CustomPainter {
  _CompWheelPainter({
    required this.segments,
    required this.colors,
    required this.base,
    required this.modeName,
    required this.dragging,
    required this.card,
  });

  final List<String> segments;
  final List<KitSchemeColor> colors;
  final KitHsl base;
  final String modeName;
  final bool dragging;

  /// 环带内孔与中心圆底色（取当前主题卡片色）。
  final Color card;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 176;
    double R(double v) => v * scale;

    for (var i = 0; i < segments.length; i++) {
      final a0 = (i * 6 - 90) * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: R(84)),
        a0,
        6 * math.pi / 180,
        true,
        Paint()
          ..color = kitColor(segments[i]).withValues(alpha: .9),
      );
    }
    // 内孔掏空成环带
    canvas.drawCircle(c, R(62), Paint()..color = card);
    for (var k = 0; k < colors.length; k++) {
      final a = (colors[k].deg - 90) * math.pi / 180;
      final stroke = Paint()
        ..color = k == 0 ? const Color(0xFF0F172A) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = R(2.5);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: R(72)),
        a - 5 * math.pi / 180,
        10 * math.pi / 180,
        false,
        stroke,
      );
      final dot = Offset(c.dx + R(72) * math.cos(a), c.dy + R(72) * math.sin(a));
      canvas.drawCircle(dot, R(7), Paint()..color = Colors.white);
      canvas.drawCircle(dot, R(6), Paint()..color = kitColor(colors[k].hex));
    }
    canvas.drawCircle(c, R(34), Paint()..color = const Color(0xFFFFFFFF));
    _text(canvas, modeName, c.translate(0, -R(6)), 9, Colors.black54, false);
    _text(canvas, colors.isEmpty ? '' : colors.first.hex.toUpperCase(),
        c.translate(0, R(6)), 8, kitColor(colors.isEmpty ? '#000000' : colors.first.hex), true);
  }


  void _text(Canvas canvas, String s, Offset at, double size, Color color, bool bold) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CompWheelPainter old) =>
      old.segments != segments ||
      old.colors != colors ||
      old.modeName != modeName ||
      old.dragging != dragging;
}
