part of 'shelf_page.dart';

// 治理G7d1a：年度目标环 CustomPainter 自 shelf_page 尾随块整块外提（行为零改动）。
class _GoalRingPainter extends CustomPainter {
  _GoalRingPainter({required this.frac, required this.color});
  final double frac;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color.withValues(alpha: .26),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5708,
      6.2832 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) => old.frac != frac;
}
