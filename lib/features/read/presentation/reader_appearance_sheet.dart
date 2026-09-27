import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/reader_cfg.dart';

/// 阅读外观草稿制面板（V1.50 批4 · 原型 sheetBrAppearance）。
///
/// 口径：改动只进草稿、实时预览；「取消」丢弃、「保存应用」按作用域落库
/// （本书专属＝逐书补丁 kv `reader.cfg.<id>` · 全部书籍＝全局 kv `reader.cfg`）。
/// 自动翻页开启时先选间隔（就地滚轮 · 原型 sheetBrAutoPage）。

/// 打开面板；保存时回调草稿与作用域（本书＝true）。
Future<void> showReaderAppearance(
  BuildContext context, {
  required ReaderCfg current,
  required void Function(ReaderCfg draft, bool scopeBook) onSave,
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
      onSave: (d, book) {
        Navigator.of(sc).pop();
        onSave(d, book);
      },
    ),
  ),
);

class _ApSheet extends StatefulWidget {
  const _ApSheet({
    required this.initial,
    required this.scrollCtl,
    required this.onSave,
  });
  final ReaderCfg initial;
  final ScrollController scrollCtl;
  final void Function(ReaderCfg draft, bool scopeBook) onSave;

  @override
  State<_ApSheet> createState() => _ApSheetState();
}

class _ApSheetState extends State<_ApSheet> {
  late ReaderCfg _d = widget.initial;
  bool _scopeBook = true;

  void _set(ReaderCfg next) => setState(() => _d = next);

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
              for (final (k, label) in const [(true, '本书专属'), (false, '全部书籍')])
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
          // 实时预览（原型 brApPrev 样张）
          Container(
            key: const ValueKey('brApPrev'),
            height: 132,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _d.theme == 'custom' ? _d.bgColor : kBrThemes[_d.theme]!.$2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
            ),
            padding: EdgeInsets.fromLTRB(_d.mar * .55, _d.mar * .4, _d.mar * .55, _d.mar * .4),
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
                color: _d.theme == 'custom'
                    ? _d.textColor
                    : kBrThemes[_d.theme]!.$3,
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
                          child: _themeCard(e.key, e.value.$1, e.value.$2, e.value.$3),
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
                if (_d.theme == 'custom') _colorRows(cs),
                const SizedBox(height: 10),
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
                                : cs.surfaceContainerHighest.withValues(alpha: .5),
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
                  title: const Text('自动翻页', style: TextStyle(fontSize: 12.5)),
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
                  onPressed: () => widget.onSave(_d, _scopeBook),
                  child: const Text('保存应用'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required String valueLabel,
    required double min,
    required double max,
    required int divisions,
    required double value,
    required String keyTag,
    required ValueChanged<double> onChanged,
  }) =>
      Column(
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
                bg: '#${(kBrThemes[key]!.$2.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
                fg: '#${(kBrThemes[key]!.$3.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
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

  /// 自定义颜色：底色/字色各一行色板（原型原生取色器的 Flutter 等价）。
  Widget _colorRows(ColorScheme cs) {
    const bgs = [
      '#faf6ee', '#f5f1e8', '#eef3f7', '#f7eef2', '#eef7ee', '#f2efe9',
      '#101317', '#1c1f26', '#0f1a14', '#241a12', '#1a1030', '#000000',
    ];
    const fgs = [
      '#3b3630', '#1f2937', '#374151', '#7c2d12', '#14532d', '#4b5563',
      '#e5e7eb', '#f3f4f6', '#9ca3af', '#fcd34d', '#a5b4fc', '#ffffff',
    ];
    Widget row(String label, List<String> palette, bool isBg) => Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final hex in palette)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      key: ValueKey('brAp${isBg ? 'Bg' : 'Fg'}-$hex'),
                      onTap: () => setState(() {
                        _d = isBg
                            ? _d.copyWith(bg: hex, theme: 'custom')
                            : _d.copyWith(fg: hex, theme: 'custom');
                      }),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: ReaderCfg(bg: hex).bgColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (isBg ? _d.bg : _d.fg) == hex
                                ? cs.primary
                                : cs.outlineVariant,
                            width: (isBg ? _d.bg : _d.fg) == hex ? 2.4 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    return Column(
      key: const ValueKey('brApColors'),
      children: [
        const SizedBox(height: 8),
        row('底色', bgs, true),
        const SizedBox(height: 8),
        row('字色', fgs, false),
      ],
    );
  }
}

/// 自动翻页间隔（原型 sheetBrAutoPage · 就地滚轮）。返回选择秒数，取消＝null。
Future<int?> showBrAutoPageSheet(BuildContext context, {required int current}) =>
    showModalBottomSheet<int>(
      context: context,
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
