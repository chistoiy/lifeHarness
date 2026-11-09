// V1.53.2 选区放大镜（loupe）：拖动手柄微调时跟随手指，圆形放大正文，避开手指遮挡。
// 实现：正文包 RepaintBoundary，拖动每帧 toImageSync 抓帧 → CustomPaint 用
// drawImageRect 把手指下的小方块放大画进圆内（真·复制内容，非坐标跟随）。
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class ReaderLoupe extends StatelessWidget {
  const ReaderLoupe({
    super.key,
    required this.image,
    required this.focal,
    required this.contentLogicalSize,
    required this.stackSize,
    this.diameter = 96,
    this.magnification = 2.0,
    this.gap = 72,
    this.ringColor, // F3-3：不传＝吃主题 accent（原固定靛蓝退役）
  });

  /// 抓到的正文快照（null 时不画内容，仅留圈）。
  final ui.Image? image;

  /// 手柄/手指在正文 Stack 局部逻辑坐标下的落点（放大镜要对准放大的点）。
  final Offset focal;

  /// RepaintBoundary 的逻辑尺寸，用于把 focal 映射到 image 像素。
  final Size contentLogicalSize;

  /// 正文 Stack 尺寸，用于边缘 clamp。
  final Size stackSize;

  final double diameter;
  final double magnification;

  /// 放大镜底部到手指的垂直间距。
  final double gap;

  /// F3-3：null＝吃主题 accent（build 内解析）。
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final ring = ringColor ?? context.tokens.accent;
    // 默认浮在手指正上方；上方空间不足则翻到手指下方。
    final aboveTop = focal.dy - gap - diameter;
    final below = aboveTop < 8;
    final top = below ? focal.dy + gap : aboveTop;
    final left = (focal.dx - diameter / 2).clamp(
      8.0,
      (stackSize.width - diameter - 8).clamp(0.0, double.infinity),
    );

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: ring, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 12,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: CustomPaint(
              size: Size.square(diameter),
              painter: _LoupePainter(
                image: image,
                focal: focal,
                contentLogicalSize: contentLogicalSize,
                diameter: diameter,
                magnification: magnification,
                crossColor: ring,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoupePainter extends CustomPainter {
  const _LoupePainter({
    required this.image,
    required this.focal,
    required this.contentLogicalSize,
    required this.diameter,
    required this.magnification,
    required this.crossColor,
  });

  final ui.Image? image;
  final Offset focal;
  final Size contentLogicalSize;
  final double diameter;
  final double magnification;
  final Color crossColor;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null || contentLogicalSize.width <= 0) return;

    // image 像素 / 逻辑像素 比。
    final dpr = img.width / contentLogicalSize.width;
    final fx = focal.dx * dpr;
    final fy = focal.dy * dpr;

    // 源方块：以 focal 为中心，边长 = 圆径 / 倍率（逻辑）× dpr。
    final srcSide = (diameter / magnification) * dpr;
    var src = Rect.fromCenter(
      center: Offset(fx, fy),
      width: srcSide,
      height: srcSide,
    );
    // clamp 到 image 边界，避免 drawImageRect 断言。
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    src = Rect.fromLTRB(
      src.left.clamp(0.0, iw - srcSide).clamp(0.0, double.infinity),
      src.top.clamp(0.0, ih - srcSide).clamp(0.0, double.infinity),
      (src.left + srcSide).clamp(srcSide, iw),
      (src.top + srcSide).clamp(srcSide, ih),
    );
    if (src.width <= 0 || src.height <= 0) return;

    final dst = Offset.zero & size;
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );

    // 中心准星：一条短竖线，指准 focal 落点。
    final c = Paint()
      ..color = crossColor
      ..strokeWidth = 1.75; // F3-9：图标线宽收敛 1.7~1.8 档（原 1.5）
    final cx = size.width / 2;
    canvas.drawLine(
      Offset(cx, size.height / 2 - 9),
      Offset(cx, size.height / 2 + 9),
      c,
    );
  }

  @override
  bool shouldRepaint(covariant _LoupePainter old) =>
      old.image != image ||
      old.focal != focal ||
      old.magnification != magnification ||
      old.diameter != diameter;
}
