import 'package:flutter/material.dart';

import '../../../shared/widgets/ui_kit.dart' show SegRow;
import '../domain/mindmap_layout_preset.dart';

/// 布局家族弹层（批4 F4-8 · 原型 `sheetMm-layout`）。
///
/// 两段照抄原型顺序：**结构与方向**（四张预设卡 `lay-grid`）＋**容器比例**
/// （`竖屏友好 / 横向预览` 分段）。底部说明卡＝原型那句承诺文：
/// 横向预览是**画布内重排，App 不转屏**，导出 HTML 自带横向预设。
///
/// **改预设即时生效**：点卡即回调 [onChanged]（画布重算基线并 fit），
/// 不设「应用/保存」钮——原型 `mmApplyPreset` 同款语义。
/// 关闭弹层不做任何回滚：关掉即定稿。
Future<void> showMmLayoutSheet(
  BuildContext context, {
  required MmLayoutPreset initial,
  required ValueChanged<MmLayoutPreset> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _MmLayoutSheet(initial: initial, onChanged: onChanged),
  );
}

class _MmLayoutSheet extends StatefulWidget {
  const _MmLayoutSheet({required this.initial, required this.onChanged});

  final MmLayoutPreset initial;
  final ValueChanged<MmLayoutPreset> onChanged;

  @override
  State<_MmLayoutSheet> createState() => _MmLayoutSheetState();
}

class _MmLayoutSheetState extends State<_MmLayoutSheet> {
  late MmLayoutPreset _st = widget.initial;

  void _set(MmLayoutPreset next) {
    if (next == _st) return;
    setState(() => _st = next);
    widget.onChanged(next);
  }

  /// 容器比例切换：只改 `ratio` 一维（原型 `mmPickRatio`）。
  /// 注意 `tree/right` 切到 `landscape` 会让引擎从纵向树换成横向树——
  /// 这是原型口径（横向预览不是第四套算法，而是横向列排）。
  void _setRatio(String ratio) =>
      _set(_st.copyWith(ratio: ratio));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          key: const ValueKey('mm-layout-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('布局与横向预览',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('结构 × 方向 正交两维；点预设即时生效（改布局只重算基线，节点拖拽偏移仍保留）',
                            style: TextStyle(
                                fontSize: 11.5, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('mm-layout-close'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_outlined, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('结构与方向',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              // 四张预设卡 2×2（原型 `.lay-grid`）。
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.55,
                children: [
                  for (final c in mmLayoutCards) _card(c),
                ],
              ),
              const SizedBox(height: 14),
              const Text('容器比例',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegRow<String>(
                keyPrefix: 'mm-layout-ratio',
                value: _st.ratio,
                items: const [
                  (id: MmLayoutPreset.rPortrait, label: '竖屏友好'),
                  (id: MmLayoutPreset.rLandscape, label: '横向预览'),
                ],
                onChanged: _setRatio,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '横向预览＝按横向比例重排画布，App 内不转屏（不改全局方向、退出无还原残留）；'
                  '导出 HTML 自带横向预设。',
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.8,
                      color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(MmLayoutCard c) {
    final cs = Theme.of(context).colorScheme;
    final on = c.preset == _st;
    return GestureDetector(
      key: ValueKey('mm-layout-card-${c.preset.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _set(c.preset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: on
              ? cs.primary.withValues(alpha: .10)
              : cs.surfaceContainerHighest.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: on ? cs.primary : Colors.transparent, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: Center(
                    child: SizedBox(
                        height: 42,
                        width: 60,
                        child: CustomPaint(
                            painter: _ThumbPainter(
                                kind: c.icon, cs: cs, on: on))))),
            Text(c.title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w700)),
            Text(c.sub,
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant.withValues(alpha: .7))),
          ],
        ),
      ),
    );
  }
}

/// 预设卡缩略图（原型 `LAY_SVG` 的四个分支的 Flutter 版）。
///
/// **线性绘制、只用现有令牌色**——不写 `Color(0x…)` 字面量（色值棘轮零增长）。
/// 画法与原型逐条同形：outline＝父在上子竖排缩进（**勿画成横向树**）、
/// hright＝父左子右、hboth＝子分列两侧、radial＝根居中四面发散。
class _ThumbPainter extends CustomPainter {
  const _ThumbPainter({required this.kind, required this.cs, required this.on});

  final String kind;
  final ColorScheme cs;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    // 60×42 逻辑坐标系按实际尺寸缩放（原型 viewBox="0 0 60 42"）。
    final s = size.width / 60.0;
    canvas.save();
    canvas.scale(s, size.height / 42.0);
    final line = Paint()
      ..color = (on ? cs.primary : cs.onSurfaceVariant)
          .withValues(alpha: on ? .95 : .8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = on ? cs.primary : cs.onSurfaceVariant
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = on ? cs.primary : cs.onSurfaceVariant
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke;

    switch (kind) {
      case 'radial':
        for (final p in const [
          [30.0, 21.0, 12.0, 9.0],
          [30.0, 21.0, 48.0, 9.0],
          [30.0, 21.0, 12.0, 33.0],
          [30.0, 21.0, 48.0, 33.0],
        ]) {
          canvas.drawLine(Offset(p[0], p[1]), Offset(p[2], p[3]), line);
        }
        _box(canvas, fill, 24, 16.5, 12, 9);
        _box(canvas, stroke, 6, 4.5, 12, 9);
        _box(canvas, stroke, 42, 4.5, 12, 9);
        _box(canvas, stroke, 6, 28.5, 12, 9);
        _box(canvas, stroke, 42, 28.5, 12, 9);
      case 'hboth':
        for (final p in const [
          [30.0, 21.0, 10.0, 11.0],
          [30.0, 21.0, 10.0, 31.0],
          [30.0, 21.0, 50.0, 11.0],
          [30.0, 21.0, 50.0, 31.0],
        ]) {
          canvas.drawLine(Offset(p[0], p[1]), Offset(p[2], p[3]), line);
        }
        _box(canvas, fill, 24, 16.5, 12, 9);
        _box(canvas, stroke, 3, 6.5, 12, 9);
        _box(canvas, stroke, 3, 26.5, 12, 9);
        _box(canvas, stroke, 45, 6.5, 12, 9);
        _box(canvas, stroke, 45, 26.5, 12, 9);
      case 'hright':
        canvas.drawLine(const Offset(14, 21), const Offset(26, 21), line);
        canvas.drawLine(const Offset(38, 21), const Offset(46, 11), line);
        canvas.drawLine(const Offset(38, 21), const Offset(46, 31), line);
        _box(canvas, fill, 2, 16.5, 12, 9);
        _box(canvas, stroke, 26, 16.5, 12, 9);
        _box(canvas, stroke, 46, 6.5, 12, 9);
        _box(canvas, stroke, 46, 26.5, 12, 9);
      default:
        // 纵向大纲：父在上、子竖排缩进（上中下三层示意）。
        final path = Path()
          ..moveTo(14, 13.5)
          ..lineTo(14, 33.5)
          ..moveTo(14, 21.5)
          ..lineTo(24, 21.5)
          ..moveTo(14, 31.5)
          ..lineTo(24, 31.5);
        canvas.drawPath(path, line);
        _box(canvas, fill, 4, 4, 20, 9.5);
        _box(canvas, stroke, 24, 17, 20, 9.5);
        _box(canvas, stroke, 24, 27, 20, 9.5);
    }
    canvas.restore();
  }

  void _box(Canvas canvas, Paint p, double x, double y, double w, double h) {
    // 实心/描边靠传入的 paint 区分（fill 实心、stroke 描边）。
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h), const Radius.circular(2.6)),
        p);
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.kind != kind || old.on != on || old.cs != cs;
}