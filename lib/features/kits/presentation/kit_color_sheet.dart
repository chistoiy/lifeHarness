// 应用内选色弹层（原型 `sheetKitColor` / `kcc*` 函数族同源 · V1.47 真机轮2 拍板：
// 禁用系统取色器，全 app 四处取色入口共用本弹层）。
//
// 口径：预设与解析路径保留精确 HEX；只有拖动滑杆才由 HSL 回算。
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/kit_color.dart';

/// 打开选色弹层；确认返回小写 hex，取消返回 null。
Future<String?> kitShowColorSheet(BuildContext context, String current) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _KitColorSheet(initial: current),
    );

class _KitColorSheet extends StatefulWidget {
  const _KitColorSheet({required this.initial});

  final String initial;

  @override
  State<_KitColorSheet> createState() => _KitColorSheetState();
}

class _KitColorSheetState extends State<_KitColorSheet> {
  /// 精确 hex（预设/解析路径写入；滑杆改动后置空，改由 HSL 回算）。
  String? _exact;
  late KitHsl _hsl;
  final TextEditingController _hex = TextEditingController();
  String _hint = '';

  @override
  void initState() {
    super.initState();
    _load(widget.initial);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  /// 原型 `kccLoad`：记住精确串并把滑杆摆到对应 HSL。
  void _load(String v) {
    final hex = kitParseColor(v) ?? '#6366f1';
    setState(() {
      _exact = hex;
      final c = kitHexToHsl(hex);
      _hsl = KitHsl(c.h.roundToDouble(), c.s.roundToDouble(), c.l.roundToDouble());
      _hex.text = hex.toUpperCase();
      _hint = '';
    });
  }

  String get _hexNow => _exact ?? kitHslToHex(_hsl);

  void _slide(double h, double s, double l) {
    setState(() {
      _exact = null;
      _hsl = KitHsl(h, s, l);
      _hex.text = _hexNow.toUpperCase();
      _hint = '';
    });
  }

  void _parse() {
    final v = kitParseColor(_hex.text);
    if (v == null) {
      setState(() => _hint = '无法解析该色串 · 支持 #RRGGBB / rgb() / hsl()');
      return;
    }
    _load(v);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hex = _hexNow;
    final rgb = kitHexToRgb(hex) ?? const KitRgb(0, 0, 0);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: tokens.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    key: const ValueKey('kit-cc-prev'),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(0xFF000000 |
                          (rgb.r << 16) |
                          (rgb.g << 8) |
                          rgb.b),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tokens.cardBorder),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '选择颜色',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${hex.toUpperCase()} · H${_hsl.h.round()}° · '
                          'S${_hsl.s.round()}% · L${_hsl.l.round()}%',
                          key: const ValueKey('kit-cc-cur'),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                key: const ValueKey('kit-cc-presets'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kKitColorPresets)
                    GestureDetector(
                      key: ValueKey('kit-cc-dot-$c'),
                      onTap: () => _load(c),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _colorOf(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.toLowerCase() == hex
                                ? tokens.accent
                                : tokens.cardBorder,
                            width: c.toLowerCase() == hex ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _slider(
                key: 'kit-cc-h',
                label: '色相',
                value: _hsl.h,
                maxValue: 359,
                display: '${_hsl.h.round()}°',
                onChanged: (v) => _slide(v, _hsl.s, _hsl.l),
              ),
              _slider(
                key: 'kit-cc-s',
                label: '饱和',
                value: _hsl.s,
                maxValue: 100,
                display: '${_hsl.s.round()}%',
                onChanged: (v) => _slide(_hsl.h, v, _hsl.l),
              ),
              _slider(
                key: 'kit-cc-l',
                label: '明度',
                value: _hsl.l,
                maxValue: 100,
                display: '${_hsl.l.round()}%',
                onChanged: (v) => _slide(_hsl.h, _hsl.s, v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('kit-cc-hex'),
                      controller: _hex,
                      onSubmitted: (_) => _parse(),
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '#RRGGBB / rgb() / hsl()',
                        hintStyle: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const ValueKey('kit-cc-parse'),
                    onPressed: _parse,
                    child: const Text('解析', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
              if (_hint.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _hint,
                    key: const ValueKey('kit-cc-hint'),
                    style: const TextStyle(fontSize: 11.5, color: Color(0xE6F43F5E)),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: tokens.cardBorder),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('取消', style: TextStyle(fontSize: 13.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('kit-cc-ok'),
                      onPressed: () => Navigator.of(context).pop(_hexNow),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('确定', style: TextStyle(fontSize: 13.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider({
    required String key,
    required String label,
    required double value,
    required double maxValue,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          ),
          Expanded(
            child: Slider(
              key: ValueKey(key),
              value: value.clamp(0, maxValue),
              max: maxValue,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

Color _colorOf(String hex) {
  final rgb = kitHexToRgb(hex) ?? const KitRgb(0, 0, 0);
  return Color(0xFF000000 | (rgb.r << 16) | (rgb.g << 8) | rgb.b);
}

/// 供各工具屏复用的色板入口按钮（原型 `.kcc-sw`：圆角色块，点击开弹层）。
class KitColorSwatchButton extends StatelessWidget {
  const KitColorSwatchButton({
    super.key,
    required this.hex,
    required this.onChanged,
    this.size = 44,
  });

  final String hex;
  final ValueChanged<String> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      key: ValueKey('kit-sw-$hex'),
      onTap: () async {
        final v = await kitShowColorSheet(context, hex);
        if (v != null) onChanged(v);
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _colorOf(hex),
          borderRadius: BorderRadius.circular(size / 4),
          border: Border.all(color: tokens.cardBorder),
        ),
      ),
    );
  }
}
