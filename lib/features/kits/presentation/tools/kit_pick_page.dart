// 工具屏 · 取色盘（原型 `TOOLS.pick` / `cpk*` 同源 · 批2）。
//
// 红线：禁用系统取色器（选色一律走应用内 `kitShowColorSheet`）；图片取色
// 全程本机解码（`KitPick.imagePicker` / `KitPick.decoder` 两个可注入缝，
// widget 测试注入假实现，禁真实异步 I/O）。数据落 `kit_tool_data.tool='pick'`。
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_color.dart';
import '../../domain/kit_models.dart';
import '../kit_color_sheet.dart';
import '../kit_providers.dart';
import 'kit_tools_kit.dart';

/// 一张已解码图片（宽高 + RGBA 逐像素）。
class KitDecodedImage {
  const KitDecodedImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  /// 取 (x, y) 像素 hex；越界返回 null。
  String? hexAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    final i = (y * width + x) * 4;
    if (i + 2 >= rgba.length) return null;
    return kitRgbToHex(KitRgb(rgba[i], rgba[i + 1], rgba[i + 2]));
  }
}

class KitPick {
  KitPick._();

  /// 取图缝：默认走 image_picker；测试注入返回固定路径的假实现。
  static Future<String?> Function() imagePicker = _defaultPicker;

  /// 解码缝：默认 `ui.instantiateImageCodec`；测试注入直接返回构造好的像素。
  static Future<KitDecodedImage?> Function(String path) decoder = _defaultDecoder;

  static Future<String?> _defaultPicker() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
      return f?.path;
    } catch (_) {
      return null;
    }
  }

  static Future<KitDecodedImage?> _defaultDecoder(String path) async {
    final bytes = readImageBytes(path);
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return null;
    return KitDecodedImage(
      width: img.width,
      height: img.height,
      rgba: data.buffer.asUint8List(),
    );
  }

  /// 同步读盘（FakeAsync widget 测试里异步 readAsBytes 永不完成 —— 既有踩坑）。
  static Uint8List? readImageBytes(String path) {
    try {
      return io.File(path).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }
}

/// 取色盘屏主体。
class KitPickBody extends ConsumerStatefulWidget {
  const KitPickBody({super.key});

  @override
  ConsumerState<KitPickBody> createState() => _KitPickBodyState();
}

class _KitPickBodyState extends ConsumerState<KitPickBody> {
  static const double _baseWidth = 300;

  String _hex = '#6366f1';
  List<String> _recent = const [];
  bool _loaded = false;
  bool _tabImg = true;
  final TextEditingController _parse = TextEditingController();
  String _hint = '';

  KitDecodedImage? _img;
  Uint8List? _imgBytes;
  double _zoom = 1;
  int _tapX = 0;
  int _tapY = 0;
  bool _mag = true;
  String? _picked;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _parse.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final d = await ref.read(kitRepositoryProvider).toolData(kitToolKeyPick);
    if (!mounted) return;
    final hex = d['hex'];
    final recent = d['recent'];
    setState(() {
      if (hex is String && kitHexToRgb(hex) != null) _hex = hex;
      _recent = [
        if (recent is List)
          for (final e in recent)
            if (e is String && kitHexToRgb(e) != null) e,
      ];
      _loaded = true;
    });
  }

  Future<void> _persist() => ref.read(kitRepositoryProvider).setToolData(
        kitToolKeyPick,
        {'hex': _hex, 'recent': _recent},
      );

  void _apply(String hex, {bool toRecent = true}) {
    setState(() {
      _hex = hex;
      if (toRecent) _recent = kitTouchRecent(_recent, hex);
      _hint = '';
    });
    _persist();
  }

  void _parseInput() {
    final v = kitParseColor(_parse.text);
    if (v == null) {
      setState(() => _hint = '无法解析 · 支持 #RRGGBB / rgb() / hsl()');
      return;
    }
    _parse.clear();
    _apply(v);
    setState(() => _hint = '已解析为 ${v.toUpperCase()}');
  }

  Future<void> _loadImage() async {
    final path = await KitPick.imagePicker();
    if (path == null || !mounted) return;
    setState(() => _decoding = true);
    final img = await KitPick.decoder(path);
    if (!mounted) return;
    final bytes = KitPick.readImageBytes(path);
    if (!mounted) return;
    setState(() {
      _decoding = false;
      _img = img;
      _imgBytes = bytes;
      _picked = null;
      _zoom = 1;
      _tabImg = true;
      _hint = img == null ? '这张图读不出来 · 换一张试试' : '轻点图片取样';
    });
  }

  void _pickAt(Offset local) {
    final img = _img;
    if (img == null) {
      AppToast.show(context, '先导入一张图片');
      return;
    }
    final w = _baseWidth * _zoom;
    final h = img.height / img.width * w;
    final x = (local.dx / w * img.width).floor();
    final y = (local.dy / h * img.height).floor();
    final hex = img.hexAt(x.clamp(0, img.width - 1), y.clamp(0, img.height - 1));
    setState(() {
      _picked = hex;
      _tapX = x;
      _tapY = y;
    });
  }

  Future<void> _dropRecent(String c) async {
    setState(() => _recent = kitDropRecent(_recent, c));
    await _persist();
    if (mounted) AppToast.show(context, '已从最近取色移除 ${c.toUpperCase()}');
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = const []);
    await _persist();
    if (mounted) AppToast.show(context, '最近取色已清空 · 随备份导出');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final readouts = kitColorReadouts(_hex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KitColorSwatchButton(
              hex: _hex,
              onChanged: (v) => _apply(v),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _readout(readouts[0], 'kit-pick-hex', 13, true),
                  _readout(readouts[1], 'kit-pick-rgb', 10.5, false),
                  _readout(readouts[2], 'kit-pick-hsl', 10.5, false),
                ],
              ),
            ),
            Container(
              key: const ValueKey('kit-pick-big'),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: kitColor(_hex),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('kit-pick-parse-in'),
                controller: _parse,
                style: const TextStyle(fontSize: 11.5),
                onSubmitted: (_) => _parseInput(),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '粘贴 HEX / rgb() / hsl() 解析',
                  hintStyle: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 4),
            kitToolBtn(context, '解析', _parseInput, keyName: 'kit-pick-parse'),
            kitToolBtn(
              context,
              '屏上取色',
              () => AppToast.show(context, '屏上取色需在系统能力开放后接入 · 当前请用图片取色'),
              keyName: 'kit-pick-eye',
            ),
          ],
        ),
        if (_hint.isNotEmpty) kitToolNote(_hint, key: const ValueKey('kit-pick-hint')),
        const SizedBox(height: 8),
        Row(
          children: [
            KitToolChip(
              keyName: 'kit-pick-tab-img',
              label: '图片取色',
              on: _tabImg,
              onTap: () => setState(() => _tabImg = true),
            ),
            const SizedBox(width: 6),
            KitToolChip(
              keyName: 'kit-pick-tab-recent',
              label: '最近取色',
              on: !_tabImg,
              onTap: () => setState(() => _tabImg = false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_tabImg) _imgTab(tokens) else _recentTab(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            kitToolBtn(context, '复制 HEX', () => kitToolCopy(context, readouts[0]),
                keyName: 'kit-pick-copy-hex', small: true),
            kitToolBtn(context, '复制 RGB', () => kitToolCopy(context, readouts[1]),
                keyName: 'kit-pick-copy-rgb', small: true),
            kitToolBtn(context, '复制 HSL', () => kitToolCopy(context, readouts[2]),
                keyName: 'kit-pick-copy-hsl', small: true),
            kitToolBtn(
              context,
              '存为配色笔记',
              () => kitToolCopy(context, '配色 · ${readouts.join(' / ')}',
                  msg: '配色串已复制 · 可到笔记页粘贴'),
              keyName: 'kit-pick-to-note',
              small: true,
            ),
          ],
        ),
        if (!_loaded) kitToolNote('正在读本机取色记录…'),
      ],
    );
  }

  Widget _readout(String text, String key, double size, bool strong) => Text(
        text,
        key: ValueKey(key),
        style: TextStyle(
          fontSize: size,
          fontWeight: strong ? FontWeight.w800 : FontWeight.normal,
          color: strong ? null : Colors.grey,
        ),
      );

  Widget _imgTab(ThemeTokens tokens) {
    final img = _img;
    if (img == null) {
      return GestureDetector(
        key: const ValueKey('kit-pick-import'),
        behavior: HitTestBehavior.opaque,
        onTap: _decoding ? null : _loadImage,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: context.cardDecoration,
          child: Column(
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 30, color: Colors.grey),
              const SizedBox(height: 6),
              Text(
                _decoding ? '正在解码…' : '导入图片取色',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    final w = _baseWidth * _zoom;
    final h = img.height / img.width * w;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: GestureDetector(
              key: const ValueKey('kit-pick-canvas'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pickAt(d.localPosition),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    SizedBox(
                      width: w,
                      height: h,
                      child: _imgBytes == null
                          ? _PixelGrid(img: img)
                          : Image.memory(
                              _imgBytes!,
                              fit: BoxFit.fill,
                              width: w,
                              height: h,
                              gaplessPlayback: true,
                            ),
                    ),
                    if (_mag && _picked != null)
                      Positioned(
                        left: (_tapX / img.width * w) - 8,
                        top: (_tapY / img.height * h) - 8,
                        child: IgnorePointer(
                          child: CustomPaint(
                            size: const Size(16, 16),
                            painter: _CrosshairPainter(tokens.accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('缩放', style: TextStyle(fontSize: 10, color: Colors.grey)),
            Expanded(
              child: Slider(
                key: const ValueKey('kit-pick-zoom'),
                value: _zoom,
                min: 1,
                max: 4,
                divisions: 6,
                label: '${(_zoom * 100).round()}%',
                onChanged: (v) => setState(() => _zoom = v),
              ),
            ),
            Text('${(_zoom * 100).round()}%',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(width: 6),
            kitToolBtn(context, '全屏', () => _openStage(img),
                keyName: 'kit-pick-fs', small: true),
            kitToolBtn(context, '复位', () => setState(() => _zoom = 1),
                keyName: 'kit-pick-reset', small: true),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              key: const ValueKey('kit-pick-swatch'),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _picked == null ? tokens.card : kitColor(_picked!),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: tokens.cardBorder),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _picked?.toUpperCase() ?? '—',
                    key: const ValueKey('kit-pick-picked-hex'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    _picked == null ? '轻点图片取样' : '十字准星已${_mag ? '开启' : '关闭'}',
                    style: const TextStyle(fontSize: 9.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
            kitToolBtn(
              context,
              '复制',
              _picked == null ? null : () => kitToolCopy(context, _picked!.toUpperCase()),
              keyName: 'kit-pick-picked-copy',
              small: true,
            ),
            const SizedBox(width: 4),
            kitToolBtn(
              context,
              '加入取色盘',
              _picked == null ? null : () => _apply(_picked!),
              keyName: 'kit-pick-picked-use',
              small: true,
            ),
            const SizedBox(width: 4),
            kitToolBtn(
              context,
              _mag ? '准星开' : '准星关',
              () => setState(() => _mag = !_mag),
              keyName: 'kit-pick-mag',
              small: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _recentTab() => kitToolSubCard(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            kitToolSection(
              '点击复用 · 长按移除 · 随备份持久化',
              trailing: [
                kitToolBtn(context, '清空', _recent.isEmpty ? null : _clearRecent,
                    keyName: 'kit-pick-recent-clear', small: true, color: Colors.redAccent),
              ],
            ),
            const SizedBox(height: 8),
            if (_recent.isEmpty)
              kitToolNote('还没有取色记录')
            else
              Wrap(
                key: const ValueKey('kit-pick-recent'),
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in _recent)
                    GestureDetector(
                      key: ValueKey('kit-pick-recent-$c'),
                      onTap: () => _apply(c),
                      onLongPress: () => _dropRecent(c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: kitColor(c),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.tokens.cardBorder),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );

  /// 全屏舞台（原型 `#cpkFs`：整屏看图取色，退出后主屏状态不变）。
  Future<void> _openStage(KitDecodedImage img) async {
    final hex = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _KitPickStage(
          img: img,
          bytes: _imgBytes,
          initialZoom: _zoom,
        ),
      ),
    );
    if (hex != null && mounted) _apply(hex);
  }
}

/// 全屏取色舞台。
class _KitPickStage extends StatefulWidget {
  const _KitPickStage({required this.img, required this.bytes, required this.initialZoom});

  final KitDecodedImage img;
  final Uint8List? bytes;
  final double initialZoom;

  @override
  State<_KitPickStage> createState() => _KitPickStageState();
}

class _KitPickStageState extends State<_KitPickStage> {
  late double _zoom = widget.initialZoom;
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = (size.width - 32) * _zoom;
    final h = widget.img.height / widget.img.width * w;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1120),
        foregroundColor: Colors.white,
        title: const Text('图片取色 · 全屏', style: TextStyle(fontSize: 13)),
        actions: [
          IconButton(
            key: const ValueKey('kit-pick-fs-minus'),
            onPressed: () => setState(() => _zoom = (_zoom - .5).clamp(1, 4)),
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            key: const ValueKey('kit-pick-fs-plus'),
            onPressed: () => setState(() => _zoom = (_zoom + .5).clamp(1, 4)),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            key: const ValueKey('kit-pick-fs-ok'),
            onPressed: () => Navigator.of(context).pop(_picked),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: GestureDetector(
            key: const ValueKey('kit-pick-fs-canvas'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final x = (d.localPosition.dx / w * widget.img.width).floor();
              final y = (d.localPosition.dy / h * widget.img.height).floor();
              setState(() => _picked = widget.img.hexAt(
                    x.clamp(0, widget.img.width - 1),
                    y.clamp(0, widget.img.height - 1),
                  ));
            },
            child: SizedBox(
              width: w,
              height: h,
              child: widget.bytes == null
                  // 测试注入的解码器可能只给像素不给字节；此处按像素画出色块网格。
                  ? _PixelGrid(img: widget.img)
                  : Image.memory(widget.bytes!, fit: BoxFit.fill, width: w, height: h),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: kitColor(_picked ?? '#000000'),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _picked == null ? '轻点图片取样' : _picked!.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 无原始字节时（测试注入）按像素渲染简化色块网格。
class _PixelGrid extends StatelessWidget {
  const _PixelGrid({required this.img});

  final KitDecodedImage img;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PixelGridPainter(img),
        size: Size.infinite,
      );
}

class _PixelGridPainter extends CustomPainter {
  _PixelGridPainter(this.img);

  final KitDecodedImage img;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 8;
    for (var y = 0; y < img.height; y += step) {
      for (var x = 0; x < img.width; x += step) {
        final hex = img.hexAt(x, y);
        if (hex == null) continue;
        final rgb = kitHexToRgb(hex);
        if (rgb == null) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            x / img.width * size.width,
            y / img.height * size.height,
            size.width / (img.width / step),
            size.height / (img.height / step),
          ),
          Paint()..color = Color(0xFF000000 | (rgb.r << 16) | (rgb.g << 8) | rgb.b),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelGridPainter old) => old.img != img;
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), p);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) => old.color != color;
}
