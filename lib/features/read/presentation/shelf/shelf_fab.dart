part of 'shelf_page.dart';

// 治理G7d1a：书架 FAB（＋ 新书）自 shelf_page 尾随块整块外提（行为零改动）。
/// 书架 FAB（＋ 新书）。
class GradShelfFab extends StatelessWidget {
  const GradShelfFab({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      key: const ValueKey('sh-add'),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: tokens.gradient,
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: .35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}
