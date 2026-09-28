import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/reader_cfg.dart';
import 'reader_bg.dart';

/// 阅读外观草稿制面板（V1.50 批4 · 轮5.1 扩到弹层全量：亮度/背景/取色/图片）。
///
/// 口径：改动只进草稿、实时预览；「取消」丢弃、「保存应用」按作用域落库
/// （本书专属＝逐书补丁 kv `reader.cfg.<id>` · 全部书籍＝全局 kv `reader.cfg`）。
/// 轮5.1：主题/亮度/字号三面板并到这一层（原型 sheetBrAppearance 唯一入口）；
/// 自定义颜色用**自绘色相/明度滑杆**（禁系统取色器与 input[type=color]）；
/// 图片背景可选相册图（保存时才拷进私有目录）＋淡化档。
Future<void> showReaderAppearance(
  BuildContext context, {
  required ReaderCfg current,
  required void Function(ReaderCfg draft, bool scopeBook, String? pickedImage)
  onSave,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (sc) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .86,
    maxChildSize: .92,
    builder: (_, scrollCtl) => _ApSheet(
      initial: current,
      scrollCtl: scrollCtl,
      onSave: (d, book, img) {
        Navigator.of(sc).pop();
        onSave(d, book, img);
      },
    ),
  ),
);

/// 主题键 → 生效 (名称, 底色, 字色)。custom 走 cfg.bg/fg，其余查内置表。
(String, Color, Color) brThemeResolved(ReaderCfg c) => c.theme == 'custom'
    ? ('自定义', c.bgColor, c.textColor)
    : (kBrThemes[c.theme] ?? kBrThemes['day']!);

class _ApSheet extends StatefulWidget {
  const _ApSheet({
    required this.initial,
    required this.scrollCtl,
    required this.onSave,
  });
  final ReaderCfg initial;
  final ScrollController scrollCtl;
  final void Function(ReaderCfg, bool, String?) onSave;

  @override
  State<_ApSheet> createState() => _ApSheetState();
}

class _ApSheetState extends State<_ApSheet> {
  late ReaderCfg _d = widget.initial;
  bool _scopeBook = true;

  // 自绘取色（原型 brApPick：色相 0~360 + 明度 0~100，底色提亮、字色压暗）。
  String _pickTgt = 'bg';
  int _hue = 32;
  int _lite = 96;

  /// 本次从相册选的图（草稿期用临时路径预览，保存时才落私有目录）。
  String? _pickedImg;
  String _pickErr = '';

  void _set(ReaderCfg next) => setState(() => _d = next);

  (String, Color, Color) get _th => brThemeResolved(_d);

  void _pickColor() {
    setState(() {
      _d = _pickTgt == 'bg'
          ? _d.copyWith(
              theme: 'custom',
              bg: brPickHex(_hue, _lite, bg: true),
              bgImg: '',
            )
          : _d.copyWith(
              theme: 'custom',
              fg: brPickHex(_hue, _lite, bg: false),
            );
    });
  }

  Future<void> _pickImage() async {
    String err = '';
    try {
      final XFile? f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (f != null) _pickedImg = f.path;
    } catch (_) {
      // 无相册权限/桌面/测试环境：就地提示，不炸面板。
      err = '未能取得图片 · 请检查相册权限后重试';
    }
    setState(() {
      _pickErr = err;
      if (_pickedImg != null) _d = _d.copyWith(theme: 'custom', bgTex: '');
    });
  }

  Future<void> _autoToggle() async {
    if (_d.auto) {
      _set(_d.copyWith(auto: false));
      return;
    }
    final secs = await showBrAutoPageSheet(context, current: _d.autoSecs);
    if (secs != null) _set(_d.copyWith(auto: true, autoSecs: secs));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        key: const ValueKey('sheetBrAppearance'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '阅读外观',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              for (final (k, label) in const [
                (true, '本书专属'),
                (false, '全部书籍'),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: TextButton(
                    key: ValueKey('brApScope-${k ? 'book' : 'global'}'),
                    onPressed: () => setState(() => _scopeBook = k),
                    style: TextButton.styleFrom(
                      backgroundColor: _scopeBook == k
                          ? cs.primary.withValues(alpha: .12)
                          : Colors.transparent,
                      foregroundColor: _scopeBook == k
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 实时预览（原型 brApPrev 样张 · 含图片/纹理/淡化层）
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              key: const ValueKey('brApPrev'),
              height: 132,
              child: BrBackdrop(
                cfg: _perviewCfg(),
                base: _th.$2,
                thumb: true,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    _d.mar * .55,
                    _d.mar * .4,
                    _d.mar * .55,
                    _d.mar * .4,
                  ),
                  child: Text(
                    '系统 2 是一种更为自动自发的功能，与系统 1 的规范有关。无论你是否有实施意图，都会在时间行为直接而迅速生成。',
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.justify,
                    style: TextStyle(
                      fontSize: _d.fs * .62,
                      height: _d.lh,
                      letterSpacing: _d.ls,
                      fontFamily: _d.fontFamily,
                      color: _th.$3,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: widget.scrollCtl,
              children: [
                _slider(
                  label: '字号',
                  valueLabel: '${_d.fs.round()}',
                  min: 14,
                  max: 30,
                  divisions: 16,
                  value: _d.fs,
                  keyTag: 'Fs',
                  onChanged: (v) => _set(_d.copyWith(fs: v.roundToDouble())),
                ),
                _slider(
                  label: '行距',
                  valueLabel: _d.lh.toStringAsFixed(2),
                  min: 1.3,
                  max: 2.4,
                  divisions: 22,
                  value: _d.lh,
                  keyTag: 'Lh',
                  onChanged: (v) => _set(
                    _d.copyWith(lh: (v * 20).roundToDouble() / 20),
                  ),
                ),
                _slider(
                  label: '字间距',
                  valueLabel: _d.ls.toStringAsFixed(1),
                  min: 0,
                  max: 3,
                  divisions: 15,
                  value: _d.ls,
                  keyTag: 'Ls',
                  onChanged: (v) => _set(
                    _d.copyWith(ls: (v * 5).roundToDouble() / 5),
                  ),
                ),
                _slider(
                  label: '页边距（上下左右）',
                  valueLabel: brMarLabel(_d.mar),
                  min: 8,
                  max: 40,
                  divisions: 16,
                  value: _d.mar,
                  keyTag: 'Mar',
                  onChanged: (v) => _set(_d.copyWith(mar: v.roundToDouble())),
                ),
                _slider(
                  label: '亮度',
                  valueLabel: '${_d.lum}',
                  min: 30,
                  max: 100,
                  divisions: 70,
                  value: _d.lum.toDouble(),
                  keyTag: 'Lum',
                  onChanged: (v) => _set(_d.copyWith(lum: v.round())),
                ),
                const SizedBox(height: 6),
                const Text(
                  '主题',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final e in kBrThemes.entries)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _themeCard(
                            e.key,
                            e.value.$1,
                            e.value.$2,
                            e.value.$3,
                          ),
                        ),
                      ),
                    Expanded(
                      child: _themeCard(
                        'custom',
                        '自定义',
                        _d.bgColor,
                        _d.textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '背景色',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  key: const ValueKey('brApBgs'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hex in kBrBgs)
                      GestureDetector(
                        key: ValueKey('brApBg-$hex'),
                        onTap: () => _set(
                          _d.copyWith(
                            theme: 'custom',
                            bg: hex,
                            bgImg: '',
                          ),
                        ),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: ReaderCfg(bg: hex).bgColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  _d.theme == 'custom' &&
                                      _d.bg == hex &&
                                      _d.bgImg.isEmpty
                                  ? cs.primary
                                  : cs.outlineVariant,
                              width:
                                  _d.theme == 'custom' &&
                                          _d.bg == hex &&
                                          _d.bgImg.isEmpty
                                  ? 2
                                  : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '自定义颜色',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      key: const ValueKey('brApSwBg'),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _d.bgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      key: const ValueKey('brApSwFg'),
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _d.bgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        'A',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _d.textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          _hueSlider(cs),
                          const SizedBox(height: 6),
                          _liteSlider(cs),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  key: const ValueKey('brApPickTgt'),
                  children: [
                    for (final (k, l) in const [('bg', '改底色'), ('fg', '改字色')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _segPill(
                          keyTag: 'brApTgt-$k',
                          label: l,
                          on: _pickTgt == k,
                          onTap: () => setState(() => _pickTgt = k),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      _pickTgt == 'bg' ? '底色 ${_d.bg}' : '字色 ${_d.fg}',
                      key: const ValueKey('brApHex'),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '图片背景',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  key: const ValueKey('brApTex'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in kBrTex.entries)
                      Builder(
                        builder: (_) {
                          // 「无」只有在既无纹理也无图片时才算选中（原型同式）。
                          final on =
                              _d.bgTex == e.key &&
                              (e.key.isNotEmpty ||
                                  (_d.bgImg.isEmpty && _pickedImg == null));
                          return GestureDetector(
                            key: ValueKey(
                              'brApTex-${e.key.isEmpty ? 'none' : e.key}',
                            ),
                            onTap: () => _set(_d.copyWith(bgTex: e.key)),
                            child: SizedBox(
                              width: 56,
                              height: 44,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  BrBackdrop(
                                    cfg: ReaderCfg(
                                      bg: _d.bg,
                                      fg: _d.fg,
                                      theme: 'custom',
                                      bgTex: e.key,
                                    ),
                                    base: _d.bgColor,
                                    thumb: true,
                                    child: const SizedBox.expand(),
                                  ),
                                  Center(
                                    child: Text(
                                      e.value,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: _d.textColor,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: on
                                            ? cs.primary
                                            : cs.outlineVariant,
                                        width: on ? 2 : 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    if (_pickedImg != null || _d.bgImg.isNotEmpty)
                      GestureDetector(
                        key: const ValueKey('brApTex-img'),
                        onTap: () => setState(() {
                          _pickedImg = null;
                          _d = _d.copyWith(bgImg: '');
                        }),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 56,
                            height: 44,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(_pickedImg ?? _d.bgImg),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => ColoredBox(
                                    color: cs.surfaceContainerHighest,
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: cs.primary,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                const Positioned(
                                  bottom: 2,
                                  right: 0,
                                  left: 0,
                                  child: Text(
                                    '清除',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      backgroundColor: Color(0x99000000),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('brApPickImg'),
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: const Text(
                          '从相册选择图片',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_pickErr.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _pickErr,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                _slider(
                  label: '淡化',
                  valueLabel: '${_d.dim}',
                  min: 0,
                  max: 90,
                  divisions: 18,
                  value: _d.dim.toDouble(),
                  keyTag: 'Dim',
                  onChanged: (v) => _set(_d.copyWith(dim: v.round())),
                ),
                const SizedBox(height: 6),
                const Text(
                  '字体（系统字体 · 可扩展下载，控制包体积）',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final e in kBrFonts.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TextButton(
                          key: ValueKey('brApFont-${e.key}'),
                          onPressed: () => _set(_d.copyWith(font: e.key)),
                          style: TextButton.styleFrom(
                            backgroundColor: _d.font == e.key
                                ? cs.primary.withValues(alpha: .12)
                                : cs.surfaceContainerHighest.withValues(
                                  alpha: .5,
                                ),
                            foregroundColor: _d.font == e.key
                                ? cs.primary
                                : cs.onSurface,
                          ),
                          child: Text(
                            e.value,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              fontFamily: ReaderCfg(
                                font: e.key,
                              ).fontFamily,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  key: const ValueKey('brApIndent'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '首行缩进',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  value: _d.indent,
                  onChanged: (v) => _set(_d.copyWith(indent: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('brApBright'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('屏幕常亮', style: TextStyle(fontSize: 12.5)),
                  value: _d.bright,
                  onChanged: (v) => _set(_d.copyWith(bright: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('brApAuto'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '自动翻页',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  subtitle: Text(
                    _d.auto ? '${_d.autoSecs} 秒/页' : '关',
                    key: const ValueKey('brApAutoLbl'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  value: _d.auto,
                  onChanged: (_) => _autoToggle(),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('brApCancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const ValueKey('brApSave'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                  ),
                  onPressed: () {
                    final img = _pickedImg;
                    final out = img == null
                        ? _d
                        : _d.copyWith(bgImg: img, theme: 'custom');
                    widget.onSave(out, _scopeBook, img);
                  },
                  child: const Text('保存应用'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 预览用配置：图片未落私有目录前，用临时路径直接渲染。
  ReaderCfg _perviewCfg() => _pickedImg == null
      ? _d
      : _d.copyWith(bgImg: _pickedImg!, bgTex: '');

  Widget _segPill({
    required String keyTag,
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey(keyTag),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? cs.primary.withValues(alpha: .12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? cs.primary : cs.outlineVariant,
            width: on ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: on ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 色相滑杆（自绘彩虹轨道 · 禁系统取色器）。
  Widget _hueSlider(ColorScheme cs) => Container(
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      gradient: const LinearGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ),
    ),
    child: Slider(
      key: const ValueKey('brApHue'),
      min: 0,
      max: 360,
      divisions: 360,
      value: _hue.toDouble().clamp(0, 360),
      activeColor: Colors.white,
      inactiveColor: Colors.transparent,
      onChanged: (v) {
        setState(() => _hue = v.round());
        _pickColor();
      },
    ),
  );

  /// 明度滑杆（黑→白轨道）。
  Widget _liteSlider(ColorScheme cs) => Container(
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      gradient: const LinearGradient(
        colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
      ),
    ),
    child: Slider(
      key: const ValueKey('brApLite'),
      min: 0,
      max: 100,
      divisions: 100,
      value: _lite.toDouble().clamp(0, 100),
      activeColor: Colors.transparent,
      inactiveColor: Colors.transparent,
      onChanged: (v) {
        setState(() => _lite = v.round());
        _pickColor();
      },
    ),
  );

  Widget _slider({
    required String label,
    required String valueLabel,
    required double min,
    required double max,
    required int divisions,
    required double value,
    required String keyTag,
    required ValueChanged<double> onChanged,
  }) => Column(
    key: ValueKey('brAp$keyTag'),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            valueLabel,
            key: ValueKey('brAp${keyTag}V'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      Slider(
        key: ValueKey('brAp${keyTag}Slider'),
        min: min,
        max: max,
        divisions: divisions,
        value: value.clamp(min, max),
        onChanged: onChanged,
      ),
    ],
  );

  Widget _themeCard(String key, String name, Color bg, Color fg) {
    final on = _d.theme == key;
    return GestureDetector(
      key: ValueKey('brApTheme-$key'),
      onTap: () => setState(() {
        _d = key == 'custom'
            ? _d.copyWith(theme: 'custom')
            : _d.copyWith(
                theme: key,
                bg:
                    '#${(kBrThemes[key]!.$2.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
                fg:
                    '#${(kBrThemes[key]!.$3.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
              );
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: fg,
              ),
            ),
            Text(
              'Aa 阅读示例',
              style: TextStyle(
                fontSize: 7.5,
                color: fg.withValues(alpha: .7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自绘取色（原型 brApPick 同式）：色相 + 明度两滑杆 → #rrggbb。
/// 底色限高亮档（L 78~99）、字色限深暗档（L 8~45），保证正文可读。
String brPickHex(int hue, int lite, {required bool bg}) {
  final l = bg
      ? math.max(78.0, math.min(99.0, lite.toDouble()))
      : math.max(8.0, math.min(45.0, 100.0 - lite));
  final s = bg ? (hue == 0 ? 0.0 : math.min(60.0, 38.0)) : 30.0;
  final c = hslToColor(hue.toDouble(), s, l);
  return '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// HSL → Color（h 0~360，s/l 0~100）。
Color hslToColor(double h, double s, double l) {
  final ss = s / 100, ll = l / 100;
  final c = (1 - (2 * ll - 1).abs()) * ss;
  final hp = (h % 360) / 60;
  final x = c * (1 - (hp % 2 - 1).abs());
  final (r1, g1, b1) = switch (hp.floor().clamp(0, 5)) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  final m = ll - c / 2;
  return Color.fromARGB(
    255,
    (((r1 + m) * 255).round().clamp(0, 255)),
    (((g1 + m) * 255).round().clamp(0, 255)),
    (((b1 + m) * 255).round().clamp(0, 255)),
  );
}

/// 自动翻页间隔（原型 sheetBrAutoPage · 就地滚轮）。返回选择秒数，取消＝null。
Future<int?> showBrAutoPageSheet(
  BuildContext context, {
  required int current,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (sc) => _AutoPageSheet(current: current, sc: sc),
);

class _AutoPageSheet extends StatefulWidget {
  const _AutoPageSheet({required this.current, required this.sc});
  final int current;
  final BuildContext sc;
  @override
  State<_AutoPageSheet> createState() => _AutoPageSheetState();
}

class _AutoPageSheetState extends State<_AutoPageSheet> {
  late int _i = kBrAutos.contains(widget.current)
      ? kBrAutos.indexOf(widget.current)
      : 3;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          key: const ValueKey('sheetBrAutoPage'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '自动翻页间隔',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: ListWheelScrollView.useDelegate(
                key: const ValueKey('wBrAuto'),
                controller: FixedExtentScrollController(initialItem: _i),
                itemExtent: 30,
                squeeze: 1.05,
                diameterRatio: 2.4,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) => setState(() => _i = i),
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: kBrAutos.length,
                  builder: (_, i) => Center(
                    child: Text(
                      '${kBrAutos[i]} 秒',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '滚动模式下为逐屏下滚 · 触摸正文即暂停',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('brAutoOk'),
              onPressed: () => Navigator.of(widget.sc).pop(kBrAutos[_i]),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 逐书补丁 kv 编解码（坏值回空补丁）。
Map<String, dynamic> brDecodePatch(String? raw) {
  try {
    final v = raw == null ? null : jsonDecode(raw);
    return v is Map ? v.cast<String, dynamic>() : {};
  } catch (_) {
    return {};
  }
}
