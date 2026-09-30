// 尺子全屏舞台（原型 `#rulerStage` / `rs*` · 批3 · V1.47 验收轮2 口径）。
//
// 一条铺满屏幕的尺面 + 可拖动的**零点**与**红色游标**：按住游标滑到被测物
// 末端即自动读数。量程由屏侧按实测 DPI 算好后注入（本文件不碰仓储与落库，
// 只在拖动结束时经 [KitRulerController.setMarks] 提交一次）。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_ruler.dart';
import 'kit_ruler_page.dart';
import 'kit_tools_kit.dart';

class KitRulerStage extends StatefulWidget {
  const KitRulerStage({super.key, required this.controller});

  final KitRulerController controller;

  @override
  State<KitRulerStage> createState() => _KitRulerStageState();
}

class _KitRulerStageState extends State<KitRulerStage> {
  final GlobalKey _tapeKey = GlobalKey();
  late int _zero = widget.controller.zero;
  late int _cur = widget.controller.curOrDefault(_target);

  KitRulerController get _c => widget.controller;

  /// 量程随视口现算：舞台里点「长边/短边」会转屏，冻结进入时的值会算错刻度。
  int get _target => kitRulerTargetOf(context, widget.controller);

  /// ±1mm 微调（触屏上没有方向键，读数仍要能精调）。
  void _move(KitRulerMarks m) {
    setState(() {
      _zero = m.zero;
      _cur = m.cur;
    });
    _c.setMarks(_zero, _cur, targetMm: _target);
  }

  /// 全局 X → 毫米（尺面左边缘为零点）。
  int _mmAt(double globalX) {
    final box = _tapeKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final px = globalX - box.localToGlobal(Offset.zero).dx;
    final ppmm = kitRulerPxPerMm(tapePx: box.size.width, targetMm: _target);
    return (px / ppmm).round().clamp(0, _target);
  }

  void _dragTo(double globalX, {required bool isZero}) {
    final mm = _mmAt(globalX);
    setState(() {
      if (isZero) {
        _zero = mm;
      } else {
        _cur = mm;
      }
      final m = kitRulerClamp(zero: _zero, cur: _cur, targetMm: _target);
      _zero = m.zero;
      _cur = m.cur;
    });
  }

  void _bank() {
    final m = kitRulerClamp(zero: _zero, cur: _cur, targetMm: _target);
    _c.setCal(kitRulerBankCal(currentCal: _c.cal, readingMm: m.mm));
    AppToast.show(
      context,
      '已按银行卡 ${kKitRulerBankCardMm}mm 对齐 · 倍率 ${kitRulerCalText(_c.cal)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.page,
      // 参数（单位/尺边/倍率）由页面与舞台共享，控制器一变两边同时刷新。
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final m = kitRulerClamp(zero: _zero, cur: _cur, targetMm: _target);
          final mm = m.mm;
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      const Text(
                        '尺子',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      KitToolChip(
                        keyName: 'kit-ruler-fs-cm',
                        label: 'cm',
                        on: _c.unit == 'cm',
                        onTap: () => _c.setUnit('cm'),
                      ),
                      const SizedBox(width: 4),
                      KitToolChip(
                        keyName: 'kit-ruler-fs-in',
                        label: 'in',
                        on: _c.unit == 'in',
                        onTap: () => _c.setUnit('in'),
                      ),
                      const Spacer(),
                      KitToolChip(
                        keyName: 'kit-ruler-fs-long',
                        label: '长边',
                        on: _c.longEdge,
                        onTap: () => _c.setDir('long'),
                      ),
                      const SizedBox(width: 4),
                      KitToolChip(
                        keyName: 'kit-ruler-fs-short',
                        label: '短边',
                        on: !_c.longEdge,
                        onTap: () => _c.setDir('short'),
                      ),
                      const SizedBox(width: 6),
                      kitToolBtn(
                        context,
                        '校准',
                        _bank,
                        keyName: 'kit-ruler-fs-bank',
                        small: true,
                      ),
                      kitToolBtn(
                        context,
                        '退出',
                        () => Navigator.of(context).pop(),
                        keyName: 'kit-ruler-fs-close',
                        small: true,
                      ),
                    ],
                  ),
                ),
                // ---- 尺面（LayoutBuilder 宽度=尺面实宽，刻度与命中公式同源） ----
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final tapePx = cons.maxWidth;
                      final ppmm = kitRulerPxPerMm(
                        tapePx: tapePx,
                        targetMm: _target,
                      );
                      final ticks = kitRulerTicks(
                        targetMm: _target,
                        unit: _c.unit,
                      );
                      return GestureDetector(
                        key: const ValueKey('kit-ruler-fs-tape'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          _dragTo(d.globalPosition.dx, isZero: false);
                          _c.setMarks(_zero, _cur, targetMm: _target);
                        },
                        onHorizontalDragUpdate: (d) =>
                            _dragTo(d.globalPosition.dx, isZero: false),
                        onHorizontalDragEnd: (_) =>
                            _c.setMarks(_zero, _cur, targetMm: _target),
                        child: Container(
                          key: _tapeKey,
                          height: 92,
                          decoration: BoxDecoration(
                            color: tokens.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: tokens.cardBorder),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _KitTapePainter(
                                    ticks: ticks,
                                    ppmm: ppmm,
                                    ink:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ),
                              // 零点把手
                              Positioned(
                                left: (_zero * ppmm - 10).clamp(0, tapePx - 20),
                                top: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  key: const ValueKey('kit-ruler-fs-zero'),
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragUpdate: (d) => _dragTo(
                                    d.globalPosition.dx,
                                    isZero: true,
                                  ),
                                  onHorizontalDragEnd: (_) => _c.setMarks(
                                    _zero,
                                    _cur,
                                    targetMm: _target,
                                  ),
                                  child: SizedBox(
                                    width: 20,
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 20,
                                          height: 14,
                                          color: const Color(0xFF0EA5E9),
                                          child: const Center(
                                            child: Text(
                                              '0',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            width: 1.6,
                                            color: const Color(0xFF0EA5E9),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // 红色游标
                              Positioned(
                                left: (_cur * ppmm - 1).clamp(0, tapePx - 2),
                                top: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  key: const ValueKey('kit-ruler-fs-cursor'),
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragUpdate: (d) => _dragTo(
                                    d.globalPosition.dx,
                                    isZero: false,
                                  ),
                                  onHorizontalDragEnd: (_) => _c.setMarks(
                                    _zero,
                                    _cur,
                                    targetMm: _target,
                                  ),
                                  child: SizedBox(
                                    width: 2,
                                    child: Container(
                                      width: 2,
                                      color: const Color(0xFFF43F5E),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // ---- 读数 ----
                Text(
                  kitRulerReadout(unit: _c.unit, mm: mm),
                  key: const ValueKey('kit-ruler-fs-big'),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kitRulerSpanText(longEdge: _c.longEdge, mm: mm),
                  key: const ValueKey('kit-ruler-fs-span'),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  kitRulerZeroText(zero: _zero, targetMm: _target),
                  key: const ValueKey('kit-ruler-fs-zero-pos'),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: kitToolBtn(
                          context,
                          '−1mm',
                          () => _move(
                            kitRulerNudge(m, delta: -1, targetMm: _target),
                          ),
                          keyName: 'kit-ruler-fs-minus',
                          small: true,
                        ),
                      ),
                      Expanded(
                        child: kitToolBtn(
                          context,
                          '+1mm',
                          () => _move(
                            kitRulerNudge(m, delta: 1, targetMm: _target),
                          ),
                          keyName: 'kit-ruler-fs-plus',
                          small: true,
                        ),
                      ),
                      Expanded(
                        child: kitToolBtn(
                          context,
                          '复制读数',
                          () => kitToolCopy(
                            context,
                            kitRulerShare(
                              m: m,
                              longEdge: _c.longEdge,
                              targetMm: _target,
                              cal: _c.cal,
                            ),
                            msg: '读数已复制 · 正式版走系统分享面板',
                          ),
                          keyName: 'kit-ruler-fs-copy',
                          small: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Text(
                        '倍率',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Expanded(
                        child: Slider(
                          key: const ValueKey('kit-ruler-fs-cal'),
                          value: _c.cal,
                          min: kKitRulerCalMin,
                          max: kKitRulerCalMax,
                          divisions:
                              ((kKitRulerCalMax - kKitRulerCalMin) /
                                      kKitRulerCalStep)
                                  .round(),
                          label: kitRulerCalText(_c.cal),
                          onChanged: (v) => setState(() => _c.setCal(v)),
                        ),
                      ),
                      SizedBox(
                        key: const ValueKey('kit-ruler-fs-cal-v'),
                        width: 56,
                        child: Text(
                          kitRulerCalText(_c.cal),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: kitToolNote(
                    '把要量的东西贴着上方尺条 · 按住红线滑到末端即自动读数'
                    ' · 零点钮单独拖动可设起点',
                    key: const ValueKey('kit-ruler-fs-tip'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 尺面刻度（原型 `rulerDrawScale`：线长按三档，主刻度下方标数字）。
class _KitTapePainter extends CustomPainter {
  _KitTapePainter({required this.ticks, required this.ppmm, required this.ink});

  final List<KitRulerTick> ticks;
  final double ppmm;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ink
      ..strokeWidth = 1;
    for (final t in ticks) {
      final x = t.mm * ppmm;
      canvas.drawLine(Offset(x, 0), Offset(x, t.len), line);
      final label = t.label;
      if (label == null) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 9,
            color: ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, t.len + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _KitTapePainter old) =>
      old.ppmm != ppmm || old.ticks.length != ticks.length || old.ink != ink;
}
