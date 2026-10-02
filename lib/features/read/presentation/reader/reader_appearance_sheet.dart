import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/reader_cfg.dart';
import './reader_bg.dart';

part 'reader_appearance_subs.dart';

/// 阅读外观草稿制面板（V1.50 批4 · R3-7 微信读书式单层主面板 + 二级页）。
///
/// 口径：改动只进草稿、实时预览；「取消」丢弃、「保存应用」按作用域落库
/// （本书专属＝逐书补丁 kv `reader.cfg.<id>` · 全部书籍＝全局 kv `reader.cfg`）。
/// R3-7（原型 sheetBrAppearance + sheetBrApSub）：主面板自上而下＝固定预览样张 →
/// 字号行（行尾「仅当前书籍」开关）→ 边距/行距/字距三列分段 → 两行三入口卡 →
/// 开关行（两端对齐/常亮/自动翻页）→ 亮度滑杆；字体样式/首行缩进/翻页方式/纸色
/// 主题/背景图片/简繁收进**同一弹层内部页面栈**的二级页（见 part 文件），
/// 不再嵌套第二个 showModalBottomSheet（自动翻页间隔滚轮是既有嵌套先例，保留）。
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

/// 分段映射（R3-7 · 原型 BR_AP_MAR/LH/LS）：s/m/l → 数值，当前值就近命中档位。
const kApSegMar = {'s': 12.0, 'm': 22.0, 'l': 34.0};
const kApSegLh = {'s': 1.45, 'm': 1.62, 'l': 1.9};
const kApSegLs = {'s': 0.0, 'm': 0.4, 'l': 1.0};

/// 首行缩进 / 简繁三档文案（原型 BR_IND_N / BR_S2T_N，key＝cfg 值）。
const kApIndNames = {'auto': '跟随原书', '2': '两全角', 'none': '无缩进'};
const kApS2TNames = {'orig': '跟随原书', 's': '简体', 't': '繁体'};

/// 就近命中分段档位（原型 brApSegCol 的 near 同式：绝对值最小档）。
String apSegNear(Map<String, double> bucket, double cur) {
  var near = bucket.keys.first;
  for (final e in bucket.entries) {
    if ((e.value - cur).abs() < (bucket[near]! - cur).abs()) near = e.key;
  }
  return near;
}

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

  /// R3-7 二级页栈（同一弹层内部）：null＝主面板；否则 font/ind/turn/theme/bg/s2t。
  String? _sub;

  /// 字体二级页当前分类 chip（原型 brApFontCat，'全部' 起）。
  String _fontCat = '全部';

  // 自绘取色（原型 brApPick：色相 0~360 + 明度 0~100，底色提亮、字色压暗）。
  String _pickTgt = 'bg';
  int _hue = 32;
  int _lite = 96;

  /// 本次从相册选的图（草稿期用临时路径预览，保存时才落私有目录）。
  String? _pickedImg;
  String _pickErr = '';

  void _set(ReaderCfg next) => setState(() => _d = next);

  /// 二级页（part 扩展）统一走宿主这两个口，扩展体内免碰 protected setState。
  void _rebuild(VoidCallback f) => setState(f);
  void _openSub(String k) => setState(() => _sub = k);
  void _closeSub() => setState(() => _sub = null);

  (String, Color, Color) get _th => brThemeResolved(_d);

  // 入口卡/子页副标题的当前值回显（原型 brApFontLbl/IndLbl/TurnLbl/ThemeLbl/BgLbl/S2TLbl）。
  String get _fontLbl => kBrFonts[_d.font] ?? kBrFonts['system']!;
  String get _indLbl => kApIndNames[_d.indMode] ?? kApIndNames['auto']!;
  String get _turnLbl => _d.mode == 'scroll' ? '滚动' : '翻页';
  String get _themeLbl => _d.theme == 'custom' ? '自定义' : _th.$1;
  String get _bgLbl =>
      _d.bgTex.isEmpty && (_d.bgImg.isNotEmpty || _pickedImg != null)
      ? '自选图片'
      : (kBrTex[_d.bgTex] ?? '无');
  String get _s2tLbl => kApS2TNames[_d.s2t] ?? kApS2TNames['orig']!;

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
        children: _sub == null ? _apMain(cs, tokens) : _apSub(cs),
      ),
    );
  }

  // ---------- 主面板（原型 sheetBrAppearance 单层） ----------

  List<Widget> _apMain(ColorScheme cs, ThemeTokens tokens) => [
    Row(
      children: [
        const Text(
          '阅读外观',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        Text(
          '草稿制 · 保存后生效',
          style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
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
              textAlign: _d.just ? TextAlign.justify : TextAlign.left,
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
          // ① 字号行：小A 滑杆 大A ＋ 行尾「仅当前书籍」开关（开＝本书专属）。
          Row(
            key: const ValueKey('brApFs'),
            children: [
              Text(
                'A',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('brApFsSlider'),
                  min: 14,
                  max: 30,
                  divisions: 16,
                  value: _d.fs.clamp(14, 30),
                  label: '${_d.fs.round()}',
                  onChanged: (v) => _set(_d.copyWith(fs: v.roundToDouble())),
                ),
              ),
              const Text(
                'A',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              Text(
                '${_d.fs.round()}',
                key: const ValueKey('brApFsV'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '仅当前书籍',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Switch(
                key: const ValueKey('brApScopeTgl'),
                value: _scopeBook,
                onChanged: (v) => setState(() {
                  _scopeBook = v;
                  _sub = null;
                }),
              ),
            ],
          ),
          // ② 三列分段：边距（小/中/大）· 行距（紧/中/松）· 字距（密/标准/疏）。
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _segCol(
                    'mar',
                    '边距',
                    const [('s', '小'), ('m', '中'), ('l', '大')],
                    kApSegMar,
                    _d.mar,
                    (k) => _set(_d.copyWith(mar: kApSegMar[k])),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _segCol(
                    'lh',
                    '行距',
                    const [('s', '紧'), ('m', '中'), ('l', '松')],
                    kApSegLh,
                    _d.lh,
                    (k) => _set(_d.copyWith(lh: kApSegLh[k])),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _segCol(
                    'ls',
                    '字距',
                    const [('s', '密'), ('m', '标准'), ('l', '疏')],
                    kApSegLs,
                    _d.ls,
                    (k) => _set(_d.copyWith(ls: kApSegLs[k])),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ③④ 两行三入口卡（卡内小字回显当前值 · 点开二级页）。
          Row(
            children: [
              _entryCard('font', '字体样式', _fontLbl, 'brApFontLbl'),
              const SizedBox(width: 8),
              _entryCard('ind', '首行缩进', _indLbl, 'brApIndLbl'),
              const SizedBox(width: 8),
              _entryCard('turn', '翻页方式', _turnLbl, 'brApTurnLbl'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _entryCard('theme', '纸色主题', _themeLbl, 'brApThemeLbl'),
              const SizedBox(width: 8),
              _entryCard('bg', '背景图片', _bgLbl, 'brApBgLbl'),
              const SizedBox(width: 8),
              _entryCard('s2t', '简繁', _s2tLbl, 'brApS2TLbl'),
            ],
          ),
          // ⑤ 开关行（自动翻页沿用既有间隔滚轮弹层）。
          SwitchListTile(
            key: const ValueKey('brApJust'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('两端对齐', style: TextStyle(fontSize: 12.5)),
            value: _d.just,
            onChanged: (v) => _set(_d.copyWith(just: v)),
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
            title: const Text('自动翻页', style: TextStyle(fontSize: 12.5)),
            subtitle: Text(
              _d.auto ? '${_d.autoSecs} 秒/页' : '关',
              key: const ValueKey('brApAutoLbl'),
              style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
            ),
            value: _d.auto,
            onChanged: (_) => _autoToggle(),
          ),
          // ⑥ 亮度滑杆行。
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
          const SizedBox(height: 4),
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
            style: FilledButton.styleFrom(backgroundColor: tokens.accent),
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
  ];

  /// 一列分段（原型 brApSegCol：小标题 + 三档 pill · 当前值就近命中）。
  Widget _segCol(
    String tag,
    String label,
    List<(String, String)> names,
    Map<String, double> bucket,
    double cur,
    ValueChanged<String> onPick,
  ) {
    final near = apSegNear(bucket, cur);
    return Column(
      key: ValueKey('brApSeg-$tag'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            label,
            style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final (i, e) in names.indexed) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: _segPill(
                  keyTag: 'brApSeg-$tag-${e.$1}',
                  label: e.$2,
                  on: e.$1 == near,
                  padH: 4,
                  onTap: () => onPick(e.$1),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 二级页入口卡（原型 .card 三列：标题 + 当前值小字）。
  Widget _entryCard(String k, String title, String value, String valKey) =>
    Expanded(
      child: GestureDetector(
        key: ValueKey('brApSubBtn-$k'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openSub(k),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                key: ValueKey(valKey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

  /// 预览用配置：图片未落私有目录前，用临时路径直接渲染。
  ReaderCfg _perviewCfg() => _pickedImg == null
      ? _d
      : _d.copyWith(bgImg: _pickedImg!, bgTex: '');

  Widget _segPill({
    required String keyTag,
    required String label,
    required bool on,
    required VoidCallback onTap,
    double padH = 10,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey(keyTag),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: 5),
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
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: on ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
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
  }) => Column(
    key: ValueKey('brAp$keyTag'),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
