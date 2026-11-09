import 'package:flutter/material.dart';

import '../../domain/media_item.dart';

/// 2A · 实物卡材质皮肤（可选皮肤，`media.cardSkin` 默认关）。
///
/// 边界（产品 2026-11-08 过门口径）：**只换卡面材质与双层阴影**——桌面底
/// 仍吃 `--page`/scheme、四类扁平主色与统计色令牌一律不动、卡片结构不变。
/// 这不是把 2026-09-23 已否决的「桌面微拟物／亚麻底」搬回来；默认关时
/// 扁平卡逐像素零变化，开启后才叠这一层。与原型
/// `prototype/index-media.html` 的 `<style id="mclab-skin">` 同源四态。
///
/// 阴影两档对应原型 `--mds-skin-contact`／`--mds-skin-ambient`：
/// 浅档 `rgba(15,23,42,.20)/(..14)`，深档加厚为 `rgba(0,0,0,.55)/(..48)`。
const List<BoxShadow> kMdsSkinShadowLight = [
  BoxShadow(color: Color(0x330F172A), offset: Offset(0, 2), blurRadius: 4),
  BoxShadow(color: Color(0x240F172A), offset: Offset(0, 10), blurRadius: 24),
];

const List<BoxShadow> kMdsSkinShadowDark = [
  BoxShadow(color: Color(0x8C000000), offset: Offset(0, 2), blurRadius: 4),
  BoxShadow(color: Color(0x7A000000), offset: Offset(0, 12), blurRadius: 28),
];

/// 双层阴影唯一出口：接触影＋环境影，深档整套加厚（不混搭两档）。
List<BoxShadow> mdsSkinShadows(bool dark) =>
    dark ? kMdsSkinShadowDark : kMdsSkinShadowLight;

/// 四类卡面材质层：铺满整卡、不吃命中；默认关时整层不进树。
/// [surface] 给电影卷角用（随主题走，不写死白色，深色棘轮闸同口径）。
class MdsSkinPainter extends CustomPainter {
  const MdsSkinPainter({
    required this.kind,
    required this.dark,
    required this.surface,
  });

  final String kind;
  final bool dark;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    // 材质层挂在 Container 外层（foregroundPainter）＝自己按卡体圆角收边，
    // 卷角/书脊/金手指都不会画出 14dp 圆角之外。
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(14),
      ),
    );
    switch (kind) {
      case MediaItem.kMovie:
        _movie(canvas, size);
      case MediaItem.kSeries:
        _series(canvas, size);
      case MediaItem.kMusic:
        _music(canvas, size);
      case MediaItem.kGame:
        _game(canvas, size);
    }
  }

  /// 电影＝卡纸海报：1px matte 内框＋右上 15dp 卷角（角面吃主题 surface）。
  void _movie(Canvas canvas, Size size) {
    final frame = Paint()
      ..color = Colors.white.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(13),
      ),
      frame,
    );
    const fold = 15.0;
    canvas.drawPath(
      Path()
        ..moveTo(size.width - fold, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, fold)
        ..close(),
      Paint()..color = surface,
    );
    canvas.drawLine(
      Offset(size.width - fold, 0),
      Offset(size.width, fold),
      Paint()
        ..color = const Color(0x4D000000)
        ..strokeWidth = 1,
    );
  }

  /// 剧集＝蓝光 BOX：左侧 8dp 书脊＋顶盖 9dp 高光。
  void _series(Canvas canvas, Size size) {
    const spine = 8.0;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, spine, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xA60F172A), Color(0x380F172A)],
        ).createShader(Rect.fromLTWH(0, 0, spine, size.height)),
    );
    canvas.drawLine(
      const Offset(spine, 0),
      Offset(spine, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: .18)
        ..strokeWidth = 1,
    );
    canvas.drawRect(
      Rect.fromLTWH(spine, 0, size.width - spine, 9),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
        ).createShader(Rect.fromLTWH(spine, 0, size.width - spine, 9)),
    );
  }

  /// 音乐＝黑胶径向纹：右上 52% 宽、上沿 16% 起的一圈同心纹（每 3dp 一道）。
  void _music(Canvas canvas, Size size) {
    final d = size.width * .52;
    final c = Offset(
      size.width * .98 - d / 2,
      size.height * .16 + d / 2,
    );
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: dark ? .09 : .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = d / 2; r > 1; r -= 3) {
      canvas.drawCircle(c, r, ring);
    }
  }

  /// 游戏＝FC 卡带：上沿 9dp 凸棱＋底部 7dp 金手指。
  void _game(Canvas canvas, Size size) {
    const ridge = 9.0;
    final ridgePaint = Paint()
      ..color = Colors.white.withValues(alpha: .14)
      ..strokeWidth = 2;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset(x, ridge), ridgePaint);
    }
    const fingers = 7.0;
    final left = size.width * .09;
    final right = size.width * .91;
    canvas.drawRect(
      Rect.fromLTWH(left, size.height - fingers, right - left, fingers),
      Paint()..color = const Color(0x4D0F172A),
    );
    final gold = Paint()
      ..color = const Color(0xFFC9A227)
      ..strokeWidth = 3;
    for (var x = left; x < right; x += 5) {
      canvas.drawLine(
        Offset(x, size.height - fingers),
        Offset(x, size.height),
        gold,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MdsSkinPainter old) =>
      old.kind != kind || old.dark != dark || old.surface != surface;
}

/// 材质层挂件：IgnorePointer 保证不抢卡片点击/长按，`SizedBox.expand`
/// 让 CustomPaint 在 `Positioned.fill` 的紧约束里拿到整卡尺寸。
Widget mdsSkinOverlay({
  required String kind,
  required bool dark,
  required Color surface,
}) =>
    IgnorePointer(
      child: CustomPaint(
        painter: MdsSkinPainter(kind: kind, dark: dark, surface: surface),
        child: const SizedBox.expand(),
      ),
    );
