import 'package:flutter/material.dart';

import '../../../shared/widgets/ui_kit.dart' show SegRow;
import '../domain/mindmap_style.dart';

/// 样式层弹层（批3 F4-7 · 原型 `sheetMm-style`）。
///
/// 六段照抄原型顺序：文字色 / 字号 / 节点背景色 / 连线颜色 / 连线粗细 /
/// 画布背景，末尾「恢复默认样式」。副标沿用原型那句承诺文（令牌跟随）。
///
/// **改档即时生效**：弹层内每点一下即回调 [onChanged]（画布重画），
/// 不设「应用/保存」钮——原型 `mmSetStyle` 同款语义。
/// 返回 null＝未改或取消；返回 [MmStyle.defaults]＝点了恢复默认。
Future<MmStyle?> showMmStyleSheet(
  BuildContext context, {
  required MmStyle initial,
  required ValueChanged<MmStyle> onChanged,
}) {
  return showModalBottomSheet<MmStyle>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _MmStyleSheet(initial: initial, onChanged: onChanged),
  );
}

class _MmStyleSheet extends StatefulWidget {
  const _MmStyleSheet({required this.initial, required this.onChanged});

  final MmStyle initial;
  final ValueChanged<MmStyle> onChanged;

  @override
  State<_MmStyleSheet> createState() => _MmStyleSheetState();
}

class _MmStyleSheetState extends State<_MmStyleSheet> {
  late MmStyle _st = widget.initial;

  void _set(MmStyle next) {
    if (next == _st) return;
    setState(() => _st = next);
    widget.onChanged(next);
  }

  void _reset() {
    final next = MmStyle.defaults;
    if (next == _st) return;
    setState(() => _st = next);
    widget.onChanged(next);
  }

  /// 连线粗细步进（原型 `mmStepLineW`：0.8~4.0，步进 0.4，越界或等值不动作）。
  void _stepLineW(double d) {
    final v = ((_st.lineW + d) * 10).round() / 10;
    final clamped = v.clamp(0.8, 4.0);
    if ((clamped - _st.lineW).abs() < 0.01) return;
    _set(_st.copyWith(lineW: clamped));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          key: const ValueKey('mm-style-sheet'),
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
                        const Text('样式',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('文字色 / 字号 / 节点背景 / 线条 / 画布背景；自动跟随主题与深浅色',
                            style: TextStyle(
                                fontSize: 11.5, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('mm-style-close'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_outlined, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _swatches('文字色', 'text', _st.text, cs),
              const SizedBox(height: 14),
              const Text('字号',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegRow<String>(
                keyPrefix: 'mm-style-size',
                value: _st.size,
                items: [
                  for (final lv in MmStyle.levelDomain['size']!)
                    (id: lv, label: MmStyle.label('size', lv)),
                ],
                onChanged: (v) => _set(_st.copyWith(size: v)),
              ),
              const SizedBox(height: 14),
              _swatches('节点背景色', 'bg', _st.bg, cs),
              const SizedBox(height: 14),
              _swatches('连线颜色', 'line', _st.line, cs),
              const SizedBox(height: 14),
              const Text('连线粗细',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  _stepBtn(context, 'mm-style-linew-dec', Icons.remove, () => _stepLineW(-0.4)),
                  Expanded(
                    child: Center(
                      key: const ValueKey('mm-style-linew-val'),
                      child: Text('${_st.lineW.toStringAsFixed(1)} px',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  _stepBtn(context, 'mm-style-linew-inc', Icons.add, () => _stepLineW(0.4)),
                ],
              ),
              const SizedBox(height: 14),
              _swatches('画布背景', 'canvas', _st.canvas, cs),
              const SizedBox(height: 18),
              OutlinedButton(
                key: const ValueKey('mm-style-reset'),
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('恢复默认样式',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 档位色板行：每档一枚「色点 ＋ 中文标签」按钮（原型 `.swatches`）。
  /// 色点取该档**解析出的实际色**——所见即所得，也顺带证明是解析非存值。
  Widget _swatches(String title, String kind, String value, ColorScheme cs) {
    final paint = MmPaintStyle.of(_st, cs);
    final preview = switch (kind) {
      'text' => mmResolveTextColor(value, cs) ?? paint.nodeText,
      'line' => mmResolveLineColor(value, cs) ?? paint.edge,
      'bg' => mmResolveNodeBg(value, cs) ?? paint.nodeBg,
      _ => mmResolveCanvasBg(value, cs) ?? paint.bg,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final lv in MmStyle.levelDomain[kind]!)
              _swatchBtn(kind, lv, value == lv, preview, cs),
          ],
        ),
      ],
    );
  }

  Widget _swatchBtn(String kind, String level, bool on, Color fallback, ColorScheme cs) {
    final color = switch (kind) {
      'text' => mmResolveTextColor(level, cs) ?? fallback,
      'line' => mmResolveLineColor(level, cs) ?? fallback,
      'bg' => mmResolveNodeBg(level, cs) ?? fallback,
      _ => mmResolveCanvasBg(level, cs) ?? fallback,
    };
    return GestureDetector(
      key: ValueKey('mm-style-$kind-$level'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _set(_switch(kind, level)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? cs.primary.withValues(alpha: .12) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? cs.primary : Colors.transparent, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              MmStyle.label(kind, level),
              style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                color: on ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  MmStyle _switch(String kind, String level) => switch (kind) {
        'text' => _st.copyWith(text: level),
        'size' => _st.copyWith(size: level),
        'bg' => _st.copyWith(bg: level),
        'line' => _st.copyWith(line: level),
        _ => _st.copyWith(canvas: level),
      };

  Widget _stepBtn(BuildContext context, String key, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}