// 治理G7b1：选区浮层三件自 reader_page.dart 提件（行为零改动·State 依赖全参数化·ValueKey 保留）。
// R14-6（2026-09-30 确认）：不透明卡片底衬（原型 #brSelBar var(--card)＋描边）＋让位规则
// （原型 brSelBarPlace 三规则）＋首尾手柄放大（圆钮 15px · 茎 2.5×18）。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter/gestures.dart';

import '../../domain/book_quote.dart';

/// R14-6：工具条高度基准（原型量纲：让位判定的可用空间按 offsetHeight 计，
/// `||46` 为其兜底值）。本实现栏高约 40±2px，取 42 只影响临界 1~2px 的档位选择。
const kBrSelBarH = 42.0;

/// V1.53.4⑤ 选区工具条默认名单（顺序＝默认排布；名称即 read.brSelBar 逗号串词元）。
const kBrSelDefaultTools = [
  '复制',
  '划线',
  '写想法',
  '书摘',
  '查询',
  '听当前',
  'AI 解读',
  '分享',
];

/// read.brSelBar 解码：只保留在册名称；未配置/全非法→默认全量。
List<String> brSelToolsDecode(String? raw) {
  final list = (raw ?? '')
      .split(',')
      .map((e) => e.trim())
      .where(kBrSelDefaultTools.contains)
      .toList();
  return list.isEmpty ? kBrSelDefaultTools : list;
}

/// R14-6 · 选区工具条/色环配色（原型 #brSelBar、#brColorPop：var(--card) 卡底＋描边）。
class BrSelSkin {
  const BrSelSkin({required this.card, required this.border, required this.fg});
  final Color card;
  final Color border;
  final Color fg;
}

/// 与 brBarOf 同一条亮度线：浅底 → 白卡深字；深底 → 深卡浅字（原型 html.dark 口径）。
BrSelSkin brSelSkinOf(Color stageBg) {
  final l =
      0.299 * (stageBg.r * 255) + 0.587 * (stageBg.g * 255) + 0.114 * (stageBg.b * 255);
  if (l > 150) {
    return const BrSelSkin(
      card: Color(0xFFFFFFFF),
      border: Color(0xFFF1F5F9),
      fg: Color(0xFF334155),
    );
  }
  return const BrSelSkin(
    card: Color(0xFF0F172A),
    border: Color(0xFF1E293B),
    fg: Color(0xFFCBD5E1),
  );
}

/// 选区浮层（划线弹出色环 + 工具条 + 指向气泡 + 首尾手柄槽位）。
///
/// [place]：R14-6 让位结果（`top`＝工具条顶边坐标；`flip`＝下压型、箭头翻上）。
/// [skin]：不透明底衬配色。
/// [tools]：V1.53.4⑤ 工具条顺序与显隐（read.brSelBar 逗号串解码结果；
/// 只渲染名单内的工具，按名单顺序排布；缺键回落到 [kBrSelDefaultTools]）。
List<Widget> brSelLayer({
  required Size size,
  required bool hlPop,
  required ({double top, bool flip}) place,
  required BrSelSkin skin,
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
  required List<String> tools,
}) {
// 选区层（原型 brSelBar + brHStart/brHEnd）：浮条 + 首尾可拖动手柄。
// 轮5①：工具条不再放「前扩/后扩」，扩选改由手柄拖动完成（系统复制手感）。

    Widget chip(String k, String label, IconData icon, VoidCallback? onTap) =>
        InkWell(
          key: ValueKey(k),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: skin.fg),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: skin.fg,
                  ),
                ),
              ],
            ),
          ),
        );
    // V1.53.4⑤：工具名→既有 chip（key/label/图标/回调全部沿用原硬编码顺序版本）。
    Widget? toolChip(String name) => switch (name) {
      '复制' => chip('brSelCopy', '复制', Icons.copy_rounded, onCopy),
      '划线' => chip('brSelHl', '划线', Icons.format_color_text_rounded,
          () => onToggleHl()),
      '写想法' => chip('brSelThink', '写想法', Icons.edit_outlined,
          () => onQuote(true)),
      '书摘' => chip('brSelQuote', '书摘', Icons.note_alt_outlined,
          () => onQuote(false)),
      '查询' => chip('brSelDict', '查询', Icons.search_rounded, onDict),
      // 听当前＝TTS：按拍板延后，入口先占位提示。
      '听当前' => chip('brSelTts', '听当前', Icons.volume_up_rounded,
          () => onTts()),
      'AI 解读' => chip('brSelAi', 'AI 解读', Icons.auto_awesome_rounded, onAi),
      '分享' => chip('brSelShare', '分享', Icons.ios_share, onShare),
      _ => null,
    };
    final bar = Container(
      key: const ValueKey('brSelBar'),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: skin.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.border),
        // 原型 box-shadow:0 8px 24px rgba(15,23,42,.28)。
        boxShadow: const [
          BoxShadow(
            color: Color(0x470F172A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final name in tools)
              toolChip(name) ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
    return [
      // 工具条＋指向三角：上贴型（默认）三角在条下朝下；flip 型条在选区下方、
      // 三角翻到条上朝上（原型 #brSelBar.flip::after）。
      Positioned(
        top: place.flip ? place.top - 7 : place.top,
        left: 0,
        right: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (place.flip)
              CustomPaint(
                size: const Size(14, 7),
                painter: BrTriPainter(skin.card, up: true),
              ),
            bar,
            if (!place.flip)
              CustomPaint(
                size: const Size(14, 7),
                painter: BrTriPainter(skin.card),
              ),
          ],
        ),
      ),
      if (hlPop)
        // 色环浮条（原型 brColorShow）：上贴型在条上方 6px；flip 型在条下 8px。
        Positioned(
          top: place.flip ? place.top + kBrSelBarH + 8 : null,
          bottom: place.flip ? null : size.height - place.top + 6,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              key: const ValueKey('brColorPop'),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: skin.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: skin.border),
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
                  // 原型 bg-slate-700 圆角胶囊＋白字（白卡底衬上仍压得住）。
                  TextButton(
                    key: const ValueKey('brDelHl'),
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      '删划线',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      // 轮5①：首尾手柄（长按只给一句，扩不扩由拖动决定＝系统复制手感）。
      ?handle(false),
      ?handle(true),
    ];
  }

/// R14-6：首尾手柄（原型 brHandlePlace / .br-h：圆钮 15px 中心≈字符盒边，
/// 茎 2.5×18 外挑 17px；命中区按视觉簇外扩 8px 保证拖动可靠）。
/// 锚点算不出（段落未渲染/快照缺段）就不画，也不拦事件。
  Widget? brHandleWidget(
    bool end,
    Offset? p,
    void Function(Offset g) onDrag, {
    void Function(Offset g)? onDragStart,
    VoidCallback? onDragEnd,
  }) {
    if (p == null) return null;
    final stemUp = !end; // 首端：枝在点上方；尾端：枝在点下方
    const w = 31.0, h = 48.0, knob = 15.0;
    final anchorY = stemUp ? 32.5 : 15.5; // 锚点在命中区内的纵坐标
    final knobTop = anchorY - knob / 2;
    final stemTop = stemUp ? knobTop - 17 : knobTop + knob - 1;
    return Positioned(
      key: ValueKey(end ? 'brHEnd' : 'brHStart'),
      left: p.dx - w / 2,
      top: p.dy - anchorY,
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 起点即判定：拖动一开始就认领手势，避免与父级识别器争抢。
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) => onDragStart?.call(d.globalPosition),
        onPanUpdate: (d) => onDrag(d.globalPosition),
        onPanEnd: (d) => onDragEnd?.call(),
        onPanCancel: () => onDragEnd?.call(),
        child: Stack(
          children: [
            Positioned(
              left: w / 2 - 1.25,
              top: stemTop,
              child: Container(
                width: 2.5,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              left: w / 2 - knob / 2,
              top: knobTop,
              child: Container(
                width: knob,
                height: knob,
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
            ),
          ],
        ),
      ),
    );
  }

/// R14-6：栏体尺寸实测（原型 offsetHeight 口径）。仅在尺寸变化时经 postFrame 回调，
/// 供选区工具条让位拿到真实顶/底栏高度（顶栏检索行、底栏显隐都会改变高度）。
class BrSizeProbe extends SingleChildRenderObjectWidget {
  const BrSizeProbe({super.key, required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _BrSizeProbeRender(onSize);

  @override
  // ignore: library_private_types_in_public_api
  void updateRenderObject(BuildContext context, _BrSizeProbeRender renderObject) {
    renderObject.onSize = onSize;
  }
}

class _BrSizeProbeRender extends RenderProxyBox {
  _BrSizeProbeRender(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final v = size;
    if (v == _last) return;
    _last = v;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(v));
  }
}

/// 选区工具条指向小三角（原型 #brSelBar::after：14×7；flip 时翻上）。
class BrTriPainter extends CustomPainter {
  const BrTriPainter(this.color, {this.up = false});
  final Color color;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    if (up) {
      p
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height);
    } else {
      p
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0);
    }
    p.close();
    // 原型 filter:drop-shadow(0 ±1px 1px rgba(15,23,42,.22))。
    canvas.drawPath(
      Path.from(p).shift(Offset(0, up ? -1 : 1)),
      Paint()
        ..color = const Color(0x380F172A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant BrTriPainter old) =>
      old.color != color || old.up != up;
}
