// 治理G7b1：选区浮层三件自 reader_page.dart 提件（行为零改动·State 依赖全参数化·ValueKey 保留）。
import 'package:flutter/material.dart';

import 'package:flutter/gestures.dart';

import '../../domain/book_quote.dart';

/// 选区浮层（划线弹出色环 + 工具条 + 指向气泡 + 首尾手柄槽位）。
List<Widget> brSelLayer({
  required Size size,
  required bool hlPop,
  required VoidCallback onCopy,
  required VoidCallback onToggleHl,
  required void Function(bool) onQuote,
  required VoidCallback onDict,
  required VoidCallback onTts,
  required VoidCallback onAi,
  required VoidCallback onShare,
  required void Function(String) onColor,
  required VoidCallback onDelete,
  required Widget? Function(bool end) handle,
}) {
// 选区层（原型 brSelBar + brHStart/brHEnd）：浮条 + 首尾可拖动手柄。
// 轮5①：工具条不再放「前扩/后扩」，扩选改由手柄拖动完成（系统复制手感）。

    const dark = Color(0xE60F172A);
    const brand = Color(0xFFA5B4FC);
    Widget chip(String k, String label, IconData icon, VoidCallback? onTap, {bool accent = false}) =>
        InkWell(
          key: ValueKey(k),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: accent ? brand : Colors.white),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: accent ? brand : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
    return [
      Positioned(
        top: size.height * .15,
        left: 0,
        right: 0,
        child: Column(
          children: [
            if (hlPop)
              Container(
                key: const ValueKey('brColorPop'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: dark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tg in BookQuote.colorTags)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          key: ValueKey('brColor-$tg'),
                          onTap: () => onColor(tg),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Color(
                                0xFF000000 |
                                    (BookQuote.hexToInt(
                                          BookQuote.colorHex[tg],
                                        ) ??
                                        0xFDE047),
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white38),
                            ),
                          ),
                        ),
                      ),
                    TextButton(
                      key: const ValueKey('brDelHl'),
                      onPressed: onDelete,
                      child: const Text(
                        '删划线',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              key: const ValueKey('brSelBar'),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color: dark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    chip('brSelCopy', '复制', Icons.copy_rounded, onCopy),
                    chip(
                      'brSelHl',
                      '划线',
                      Icons.format_color_text_rounded,
                      () => onToggleHl(),
                    ),
                    chip(
                      'brSelThink',
                      '写想法',
                      Icons.edit_outlined,
                      () => onQuote(true),
                    ),
                    chip(
                      'brSelQuote',
                      '书摘',
                      Icons.note_alt_outlined,
                      () => onQuote(false),
                    ),
                    chip('brSelDict', '查询', Icons.search_rounded, onDict),
                    // 听当前＝TTS：按拍板延后，入口先占位提示。
                    chip(
                      'brSelTts',
                      '听当前',
                      Icons.volume_up_rounded,
                      () => onTts(),
                    ),
                    chip('brSelAi', 'AI 解读', Icons.auto_awesome_rounded, onAi),
                    chip('brSelShare', '分享', Icons.ios_share, onShare),
                  ],
                ),
              ),
            ),
            // 指向气泡（参考图4：工具条下沿小三角指向选中段落方向）。
            CustomPaint(size: const Size(16, 8), painter: BrTriPainter(dark)),
          ],
        ),
      ),
      // 轮5①：首尾手柄（长按只给一句，扩不扩由拖动决定＝系统复制手感）。
      ?handle(false),
      ?handle(true),
    ];
  }

/// 选区端点手柄：锚点算不出（段落未渲染/快照缺段）就不画，也不拦事件。


  Widget? brHandleWidget(bool end, Offset? p, void Function(Offset g) onDrag) {
    if (p == null) return null;
    final stemUp = !end; // 首端：枝在点上方；尾端：枝在点下方
    return Positioned(
      key: ValueKey(end ? 'brHEnd' : 'brHStart'),
      left: p.dx - 13,
      top: p.dy - (stemUp ? 26 : 0),
      width: 26,
      height: 37,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 起点即判定：拖动一开始就认领手势，避免与父级识别器争抢。
        dragStartBehavior: DragStartBehavior.down,
        onPanUpdate: (d) => onDrag(d.globalPosition),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: stemUp ? 0 : null,
              bottom: stemUp ? null : 0,
              child: Container(
                width: 2,
                height: 15,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x660F172A),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

class BrTriPainter extends CustomPainter {
  const BrTriPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant BrTriPainter old) => old.color != color;
}