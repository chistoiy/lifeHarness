import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ledger_kit.dart';

/// 分类占比环（原型 finRing：SVG r30 strokeWidth11 · 段间 1.5 空隙 · butt 端点 · -90° 起）。
class LRing extends StatelessWidget {
  const LRing({
    super.key,
    required this.segs,
    this.size = 76,
    this.center,
  });

  /// (颜色 hex, 占比 0..1)，按序顺时针排布。
  final List<(String, double)> segs;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(painter: _RingPainter(segs)),
          ?center,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.segs);

  final List<(String, double)> segs;

  static const _stroke = 11.0 / 12.0; // 原型 11/84 viewBox 比例

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - _stroke;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final total = segs.fold<double>(0, (a, s) => a + s.$2);
    if (total <= 0) {
      canvas.drawCircle(
        size.center(Offset.zero),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..color = const Color(0xFFE2E8F0),
      );
      return;
    }
    final gap = 1.5 / (2 * math.pi * r); // 原型 len-1.5 固定间隙 → 弧度
    var off = -math.pi / 2;
    for (final (hex, ratio) in segs) {
      final sweep = ratio / total * 2 * math.pi;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.butt
        ..color = lColor(hex);
      final s = math.max(0.0, sweep - gap);
      canvas.drawArc(rect, off, s, false, p);
      off += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}
