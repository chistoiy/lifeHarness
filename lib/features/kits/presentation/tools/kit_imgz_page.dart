// 工具屏 · 图片体积缩小（原型 `TOOLS.imgz` / `imgz*` 同源 · 批3）。
//
// 全程本机：image_picker 取图 → `dart:ui` 真解码 → 画布等比缩放（+右下角水印）
// → 纯 Dart JPEG 内核（`kit_jpeg.dart`）真编码 → 界面上的每个字节数都来自真实产物。
// 取图/解码/压缩/另存四个环节都留了静态缝，widget 测试注入假实现（禁真实异步 I/O）。
// 参数落 `kit_tool_data.tool='imgz'`；WebP 无纯 Dart 编码器，选中只给「待接入」口径，
// 不谎报格式。
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_calc.dart' show kitBytesText;
import '../../domain/kit_imgz.dart';
import '../../domain/kit_models.dart';
import '../kit_providers.dart';
import 'kit_pick_page.dart' show KitPick;
import 'kit_tools_kit.dart';

/// 一张已取到本机的原图（真实字节 + 解码尺寸；preview 可缺省=降级路径）。
class KitImgzSource {
  const KitImgzSource({
    required this.width,
    required this.height,
    required this.bytes,
    this.preview,
  });

  final int width;
  final int height;
  final Uint8List bytes;

  /// 解码后的句柄，null 表示只做尺寸级验证（测试注入的假源）。
  final ui.Image? preview;
}

/// 一次真实压缩的产物。
class KitImgzResult {
  const KitImgzResult({
    required this.outW,
    required this.outH,
    required this.bytes,
  });

  final int outW;
  final int outH;
  final Uint8List bytes;
}

/// 四个可注入缝（默认实现走真机通道；测试一律替换）。
class KitImgz {
  KitImgz._();

  static Future<List<String>?> Function() pathPicker = _defaultPathPicker;
  static Future<KitImgzSource?> Function(String path) loader = _defaultLoader;
  static Future<KitImgzResult?> Function(
    KitImgzSource src,
    int maxEdge,
    int quality,
    bool watermark,
  )
  compress = _defaultCompress;
  static Future<String?> Function(String fileName, Uint8List bytes) save =
      _defaultSave;

  static Future<List<String>?> _defaultPathPicker() async {
    try {
      final files = await ImagePicker().pickMultiImage();
      return files.isEmpty ? null : files.map((e) => e.path).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<KitImgzSource?> _defaultLoader(String path) async {
    final bytes = KitPick.readImageBytes(path);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return KitImgzSource(
        width: frame.image.width,
        height: frame.image.height,
        bytes: bytes,
        preview: frame.image,
      );
    } catch (_) {
      return null;
    }
  }

  /// 缩放（+水印）后交给 JPEG 内核；内核是 CPU 密集段，放隔离区跑免得卡界面。
  static Future<KitImgzResult?> _defaultCompress(
    KitImgzSource src,
    int maxEdge,
    int quality,
    bool watermark,
  ) async {
    final img = src.preview;
    if (img == null) return null;
    final plan = kitImgzPlan(
      srcW: src.width,
      srcH: src.height,
      maxEdge: maxEdge,
    );
    final dst = Rect.fromLTWH(0, 0, plan.outW.toDouble(), plan.outH.toDouble());
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, dst);
    // 透明图压 JPEG 必须铺底，否则 alpha 直接变黑块（原型同款白底）。
    canvas.drawRect(dst, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
    if (watermark) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'LifeHarness · 本地压缩',
          style: TextStyle(
            color: Color(0xC0FFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (plan.outW - 10).toDouble() - tp.width,
          (plan.outH - 8).toDouble() - tp.height,
        ),
      );
    }
    final scaled = await rec.endRecording().toImage(plan.outW, plan.outH);
    final rgba = await scaled.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    scaled.dispose();
    if (rgba == null) return null;
    final px = rgba.buffer.asUint8List();
    final rgb = Uint8List(plan.outW * plan.outH * 3);
    for (var i = 0, j = 0; j < px.length; i += 3, j += 4) {
      rgb[i] = px[j];
      rgb[i + 1] = px[j + 1];
      rgb[i + 2] = px[j + 2];
    }
    final w = plan.outW, h = plan.outH;
    final bytes = await Isolate.run(
      () => kitJpegEncode(width: w, height: h, rgb: rgb, quality: quality),
    );
    return KitImgzResult(outW: w, outH: h, bytes: bytes);
  }

  static Future<String?> _defaultSave(String fileName, Uint8List bytes) async {
    try {
      final picked = await FilePicker.platform.saveFile(
        dialogTitle: '保存压缩结果',
        fileName: fileName,
        bytes: bytes,
      );
      if (picked != null) return picked;
    } catch (_) {
      // 平台不支持系统另存 → 落应用文件目录。
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = io.File('${dir.path}/$fileName');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}

/// 队列里的一项（首项=正在实时预览的那张）。
class _ImgzEntry {
  _ImgzEntry({required this.name, required this.path});

  final String name;
  final String path;
  KitImgzSource? source;
  KitImgzResult? result;
  bool failed = false;

  bool get done => result != null;

  KitImgzQueueItem get queue => KitImgzQueueItem(
    name: name,
    srcBytes: source?.bytes.length ?? 0,
    outBytes: result?.bytes.length,
  );
}

/// 图片体积缩小屏主体。
class KitImgzBody extends ConsumerStatefulWidget {
  const KitImgzBody({super.key});

  @override
  ConsumerState<KitImgzBody> createState() => _KitImgzBodyState();
}

class _KitImgzBodyState extends ConsumerState<KitImgzBody> {
  final List<_ImgzEntry> _items = <_ImgzEntry>[];
  int _edge = kKitImgzEdgeDefault;
  int _quality = kKitImgzQDefault;
  bool _mark = false;
  String _fmt = kKitImgzFmtJpeg;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    for (final e in _items) {
      e.source?.preview?.dispose();
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final d = await ref.read(kitRepositoryProvider).toolData(kitToolKeyImgz);
    if (!mounted) return;
    final s = KitImgzState.decode(d);
    setState(() {
      _edge = s.edge;
      _quality = s.quality;
      _mark = s.mark;
      _loaded = true;
    });
  }

  Future<void> _persist() => ref
      .read(kitRepositoryProvider)
      .setToolData(
        kitToolKeyImgz,
        kitImgzEncode(edge: _edge, quality: _quality, watermark: _mark),
      );

  String _baseName(String path) => path
      .split(RegExp(r'[/\\]'))
      .where((s) => s.isNotEmpty)
      .last;

  Future<void> _pick() async {
    if (_busy) return;
    final paths = await KitImgz.pathPicker();
    if (paths == null || paths.isEmpty || !mounted) return;
    for (final e in _items) {
      e.source?.preview?.dispose();
    }
    setState(() {
      _items
        ..clear()
        ..addAll(
          paths.map((p) => _ImgzEntry(name: _baseName(p), path: p)),
        );
    });
    await _run(0);
    for (var i = 1; i < _items.length; i++) {
      await _run(i);
    }
  }

  /// 压第 [idx] 张（真实字节；缝返回 null 或抛错都记为失败，不给假结果）。
  Future<void> _run(int idx) async {
    final e = _items[idx];
    setState(() => _busy = true);
    var src = e.source;
    try {
      src ??= await KitImgz.loader(e.path);
      if (src == null) {
        e.failed = true;
      } else {
        final res = await KitImgz.compress(src, _edge, _quality, _mark);
        if (res == null) {
          e.failed = true;
        } else {
          e.result = res;
        }
      }
    } catch (_) {
      e.failed = true;
    }
    if (!mounted) {
      // 页面已退出：dispose 早于这里，解码句柄只能就地释放。
      src?.preview?.dispose();
      return;
    }
    setState(() {
      e.source = src;
      _busy = false;
    });
    if (idx == 0 && src == null) {
      AppToast.show(context, '本机读不到这张图 · 换一张试试');
    }
  }

  /// 参数改动 = 首张立刻重压（原型 `oninput → imgzGo()` 同口径）。
  Future<void> _recompress() async {
    if (_items.isEmpty || _busy) return;
    _items.first.result = null;
    await _run(0);
  }

  Future<void> _save() async {
    final res = _items.isEmpty ? null : _items.first.result;
    if (res == null) {
      AppToast.show(context, '还没有可保存的结果');
      return;
    }
    final path = await KitImgz.save('compressed.jpg', res.bytes);
    if (!mounted) return;
    AppToast.show(
      context,
      path == null ? '已取消保存' : '已保存 ${kitBytesText(res.bytes.length)} → $path',
    );
  }

  void _setFmt(String fmt) {
    setState(() => _fmt = fmt);
    if (fmt == kKitImgzFmtWebp) AppToast.show(context, kKitImgzWebpNote);
    _recompress();
  }

  void _clear() {
    for (final e in _items) {
      e.source?.preview?.dispose();
    }
    setState(_items.clear);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final first = _items.isEmpty ? null : _items.first;
    final src = first?.source;
    final res = first?.result;
    // 三者同生同灭：结果行只在「已解码 + 已编码」时有数据可展示。
    final view = (src == null || res == null)
        ? null
        : (
            plan: KitImgzPlan(
              srcW: src.width,
              srcH: src.height,
              outW: res.outW,
              outH: res.outH,
            ),
            src: src,
            res: res,
          );
    final queue = _items.map((e) => e.queue).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: const ValueKey('kit-imgz-pick'),
          behavior: HitTestBehavior.opaque,
          onTap: _pick,
          child: kitToolSubCard(
            context,
            Column(
              children: [
                Icon(Icons.add_photo_alternate_outlined, size: 26, color: tokens.accent),
                const SizedBox(height: 4),
                Text(
                  _items.isEmpty
                      ? '选择图片（可多选 · 全程本机处理，不上传）'
                      : '已选 ${_items.length} 张 · ${src == null ? first!.name : '${src.width}×${src.height}'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('最长边', style: TextStyle(fontSize: 11, color: Colors.grey)),
              KitToolNumberField(
                keyName: 'kit-imgz-edge',
                value: _edge,
                min: kKitImgzEdgeMin,
                max: kKitImgzEdgeMax,
                onChanged: (v) {
                  setState(() => _edge = v);
                  _persist();
                  _recompress();
                },
              ),
              KitToolChip(
                keyName: 'kit-imgz-fmt-jpeg',
                label: 'JPEG',
                on: _fmt == kKitImgzFmtJpeg,
                onTap: () => _setFmt(kKitImgzFmtJpeg),
              ),
              KitToolChip(
                keyName: 'kit-imgz-fmt-webp',
                label: 'WebP',
                on: _fmt == kKitImgzFmtWebp,
                onTap: () => _setFmt(kKitImgzFmtWebp),
              ),
              Text('水印', style: TextStyle(fontSize: 11, color: Colors.grey)),
              SizedBox(
                key: const ValueKey('kit-imgz-mark'),
                width: 44,
                height: 30,
                child: Switch(
                  value: _mark,
                  onChanged: (v) {
                    setState(() => _mark = v);
                    _persist();
                    _recompress();
                    AppToast.show(context, '右下角水印${v ? '已加 · LifeHarness' : '已移除'}');
                  },
                ),
              ),
            ],
          ),
        ),
        if (_fmt == kKitImgzFmtWebp)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: kitToolNote(
              kKitImgzWebpNote,
              key: const ValueKey('kit-imgz-webp-note'),
            ),
          ),
        if (_items.isNotEmpty) ...[
          SizedBox(
            key: const ValueKey('kit-imgz-prev'),
            height: 132,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: src == null
                  ? kitToolSubCard(
                      context,
                      Center(
                        child: Text(
                          _busy ? '本机解码中…' : '本机读不到这张图',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    )
                  : src.preview == null
                  ? kitToolSubCard(
                      context,
                      Center(
                        child: Text(
                          '${src.width}×${src.height} · ${kitBytesText(src.bytes.length)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: RawImage(
                        image: src.preview,
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
          ),
          Row(
            children: [
              const Text(
                '质量',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('kit-imgz-q'),
                  value: _quality.toDouble(),
                  min: kKitImgzQMin.toDouble(),
                  max: kKitImgzQMax.toDouble(),
                  divisions: kKitImgzQMax - kKitImgzQMin,
                  label: '$_quality',
                  onChanged: (v) {
                    setState(() => _quality = v.round());
                    _persist();
                    _recompress();
                  },
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '$_quality',
                  // 键放 Text 上（用例按文案读数；键放 SizedBox 会 cast 失败）。
                  key: const ValueKey('kit-imgz-q-v'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: Text(
              _busy
                  ? '本机压缩中…'
                  : view == null
                  ? (first!.failed
                        ? '这张图本机处理失败（读取或编码未通过）· 换一张试试'
                        : (_loaded ? '选图后自动出结果' : '正在读本机参数…'))
                  : kitImgzInfo(
                      plan: view.plan,
                      srcBytes: view.src.bytes.length,
                      outBytes: view.res.bytes.length,
                      fmt: _fmt,
                      watermark: _mark,
                    ),
              // 键放 Text 上：用例按文案读数，键留在 SizedBox 上会 cast 成 Text 失败。
              key: const ValueKey('kit-imgz-info'),
              style: const TextStyle(fontSize: 11, height: 1.6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                kitToolBtn(
                  context,
                  '保存压缩结果',
                  res == null || _busy ? null : _save,
                  keyName: 'kit-imgz-save',
                ),
                kitToolBtn(
                  context,
                  '复制结果文案',
                  view == null
                      ? null
                      : () => kitToolCopy(
                          context,
                          kitImgzShare(
                            plan: view.plan,
                            srcBytes: view.src.bytes.length,
                            outBytes: view.res.bytes.length,
                          ),
                        ),
                  keyName: 'kit-imgz-share',
                  small: true,
                ),
                kitToolBtn(
                  context,
                  '清空',
                  _items.isEmpty ? null : _clear,
                  keyName: 'kit-imgz-clear',
                  small: true,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        kitToolSection('批量队列 · 逐张本地压缩'),
        if (_items.length <= 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: kitToolNote(
              '单选时不产生队列 · 多选后逐张本地压缩',
              key: const ValueKey('kit-imgz-single-note'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Padding(
                    key: ValueKey('kit-imgz-item-$i'),
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _items[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5),
                          ),
                        ),
                        Text(
                          _items[i].failed
                              ? '失败'
                              : kitImgzQueueText(_items[i].queue),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: _items[i].done ? tokens.accent : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (queue.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: kitToolResult(
              kitImgzBatchSummary(queue),
              tokens.accent,
              keyName: 'kit-imgz-sum',
            ),
          ),
        kitToolSubCard(
          context,
          kitToolNote(
            '最长边等比缩放 · JPEG 质量档真实编码字节 · 水印与参数随本机备份',
            key: const ValueKey('kit-imgz-note'),
          ),
        ),
      ],
    );
  }
}
