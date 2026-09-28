import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/reader_cfg.dart';

/// 轮5.1 · 背景层（原型 brStageBgCss 的 Flutter 等价）。
///
/// 叠放顺序与 CSS 背景层一致：底色 → 图片/纹理 → 白幕淡化 → 内容。
/// 纹理不存 CSS 串，按 [kBrTex] 的键现画（[BrTexPainter]）；自选图片
/// 由外观面板在保存时拷进应用私有目录，这里只存/读文件路径。
class BrBackdrop extends StatelessWidget {
  const BrBackdrop({
    super.key,
    required this.cfg,
    required this.base,
    required this.child,
    this.thumb = false,
  });

  final ReaderCfg cfg;

  /// 生效底色（主题解析后的舞台背景色）。
  final Color base;
  final Widget child;

  /// 缩略图模式（外观面板的纹理小样）：只画纹理本身，不叠白幕。
  final bool thumb;

  bool get _hasLayer => cfg.bgTex.isNotEmpty || cfg.bgImg.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasLayer) return ColoredBox(color: base, child: child);
    final a = thumb ? 0.0 : ((100 - cfg.dim) / 100).clamp(0.0, 1.0);
    return ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cfg.bgImg.isNotEmpty)
            IgnorePointer(
              child: Image.file(
                File(cfg.bgImg),
                key: const ValueKey('brBgImg'),
                fit: BoxFit.cover,
                // 图被系统清理/换机导入丢文件：回落到纯色，不影响阅读。
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            )
          else
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: BrTexPainter(cfg.bgTex)),
              ),
            ),
          if (a > 0)
            IgnorePointer(
              child: ColoredBox(
                key: const ValueKey('brBgDim'),
                color: Colors.white.withValues(alpha: a),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// 纹理绘制（原型 BR_TEX 三种 repeating-linear-gradient 的等价实现）。/// 线条数按逻辑像素步进（一屏数百条，且在 RepaintBoundary 内只画一次）。
class BrTexPainter extends CustomPainter {
  const BrTexPainter(this.tex);
  final String tex;

  static const _cPaper = Color(0x12785A28); // rgba(120,90,40,.07)
  static const _cKraft = Color(0x1F785014); // rgba(120,80,20,.12)
  static const _cGrid = Color(0x1A3C5078); // rgba(60,80,120,.10)

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    switch (tex) {
      case 'paper':
        _bands(canvas, r, period: 4, w: 1, color: _cPaper);
      case 'kraft':
        canvas.save();
        canvas.clipRect(r);
        final d = size.width + size.height;
        canvas.translate(size.width / 2, size.height / 2);
        canvas.rotate(math.pi / 4);
        _bands(
          canvas,
          Rect.fromCenter(center: Offset.zero, width: d, height: d),
          period: 6,
          w: 2,
          color: _cKraft,
        );
        canvas.restore();
      case 'grid':
        _bands(canvas, r, period: 12, w: 1, color: _cGrid, vertical: true);
        _bands(canvas, r, period: 12, w: 1, color: _cGrid);
      default:
        break;
    }
  }

  /// 等距平行线：vertical=false 画横线（沿 y 步进），true 画竖线。
  void _bands(
    Canvas canvas,
    Rect area, {
    required double period,
    required double w,
    required Color color,
    bool vertical = false,
  }) {
    final p = Paint()..color = color;
    if (vertical) {
      for (var x = area.left; x < area.right; x += period) {
        canvas.drawRect(Rect.fromLTWH(x, area.top, w, area.height), p);
      }
    } else {
      for (var y = area.top; y < area.bottom; y += period) {
        canvas.drawRect(Rect.fromLTWH(area.left, y, area.width, w), p);
      }
    }
  }

  @override
  bool shouldRepaint(BrTexPainter old) => old.tex != tex;
}

/// 轮5.4 · 顶栏/底栏配色（原型 brBarTheme）：浅底＝同色浅栏深字，
/// 深底＝深色栏浅字。不再固定黑底，避免与阅读主题割裂。
/// 真机反馈（2026-09-28）：栏底改不透明——阅读页顶/底栏已摘掉 BackdropFilter
/// （毛玻璃在弹层/选区重合成时会把整页正文卷进模糊），半透明底会直接透出正文。
class BrBar {
  const BrBar({
    required this.bg,
    required this.fg,
    required this.line,
    required this.chip,
  });
  final Color bg, fg, line, chip;
}

BrBar brBarOf(Color stageBg, Color textFg) {
  final c = stageBg;
  final l =
      0.299 * (c.r * 255) + 0.587 * (c.g * 255) + 0.114 * (c.b * 255);
  if (l > 150) {
    return BrBar(
      bg: c,
      fg: textFg,
      line: Colors.black.withValues(alpha: .10),
      chip: Colors.black.withValues(alpha: .06),
    );
  }
  return const BrBar(
    bg: Color(0xFF0F172A),
    fg: Color(0xFFE2E8F0),
    line: Color(0x1AFFFFFF),
    chip: Color(0x1FFFFFFF),
  );
}
