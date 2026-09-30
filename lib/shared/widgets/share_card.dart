import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_log.dart';
import '../../core/theme/app_theme.dart';
import 'ui_kit.dart';

/// G1 分享长图公共通道（需求 V1.57 A 批 · 原型 sheetShareCard 同一套语言）。
///
/// 口径（拍板记录 §五~§六）：弹层＝标题「分享长图」＋右上「预览」＋圆角预览框＋
/// 底部「复制文字版／保存图片」两钮；卡片＝渐变头（eyebrow·标题·一行口径·大数字+单位·
/// 三格）＋白底分段列表（左名右值；值空则整段文本行）＋脚注「数据仅存本机」。
/// 保存图片＝落 `<文档目录>/share/<名>.png`（1080 宽 PNG），回执给真实绝对路径；
/// 失败落 warn 日志并弹失败提示，不谎报成功。「保存到相册」说法作废。

/// 文件名清洗：去 `\/:*?"<>|` 与首尾空格（Windows/macOS/Linux 全安全）。
String sanitizeShareName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();

/// 三格小 tile（渐变头底部一行）。
class ShareCardTile {
  const ShareCardTile(this.label, this.value);

  final String label;
  final String value;
}

/// 分段列表一行：value 非空＝左名右值；空＝整段文本行。
class ShareCardRow {
  const ShareCardRow(this.label, [this.value = '']);

  final String label;
  final String value;
}

/// 一个白底分段（标题 + 行列表 + 可选柱图）。
class ShareCardSection {
  const ShareCardSection({
    required this.head,
    this.rows = const [],
    this.bars,
    this.barLabels,
  });

  final String head;
  final List<ShareCardRow> rows;

  /// 月度柱图（记账年度卡用；文字版不输出柱图，站点自带 textVersion）。
  final List<double>? bars;
  final List<String>? barLabels;
}

/// 分享长图卡数据快照（纯值对象，各站点自行装配）。
class ShareCardModel {
  const ShareCardModel({
    required this.file,
    required this.eyebrow,
    required this.title,
    required this.line,
    required this.big,
    required this.unit,
    required this.tiles,
    required this.sections,
    this.textVersion,
  });

  /// 落盘文件名（清洗前）。
  final String file;
  final String eyebrow;
  final String title;
  final String line;
  final String big;
  final String unit;
  final List<ShareCardTile> tiles;
  final List<ShareCardSection> sections;

  /// 文字版覆盖（记账年度卡原型 yrShareText 与通用版不同）；null＝按通用算法生成。
  final String? textVersion;

  /// 通用文字版（原型 scText 同构）：标题·大数字+单位·口径·〔段名〕+行。
  String get copyText {
    if (textVersion != null) return textVersion!;
    final l = <String>[title, '$big $unit', line];
    for (final s in sections) {
      if (s.rows.isEmpty) continue;
      l
        ..add('')
        ..add('〔${s.head}〕');
      for (final r in s.rows) {
        l.add(r.value.isEmpty ? r.label : '${r.label}：${r.value}');
      }
    }
    return l.join('\n');
  }
}

/// 把 [boundary] 处的预览层渲染成 1080 宽 PNG，落 `<文档目录>/share/<名>.png`。
/// 成功返回真实绝对路径；任何失败（渲染对象未就绪 / 编码 / 写盘）落 warn 日志
/// 并返回 null——调用方据 null 弹失败提示，不得回执「已保存」。
Future<String?> captureShareCard(
  GlobalKey boundary, {
  required String name,
  String? src,
}) async {
  try {
    final ro = boundary.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      AppLog.add('分享长图生成失败：预览层未就绪（$name）',
          level: LhLevel.warn, src: src ?? '分享长图');
      return null;
    }
    // 预览按屏宽缩放显示；像素比按实际布局宽反推，恒得 1080 宽成品。
    final w = ro.paintBounds.width;
    if (w <= 0) return null;
    final img = await ro.toImage(pixelRatio: 1080 / w);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (bytes == null) {
      AppLog.add('分享长图生成失败：PNG 编码为空（$name）',
          level: LhLevel.warn, src: src ?? '分享长图');
      return null;
    }
    final dir = await getApplicationDocumentsDirectory();
    final f = File(
        '${dir.path}${Platform.pathSeparator}share${Platform.pathSeparator}'
        '${sanitizeShareName(name)}.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes.buffer.asUint8List());
    return f.path;
  } catch (e) {
    AppLog.add('分享长图生成失败：$e',
        level: LhLevel.warn, src: src ?? '分享长图');
    return null;
  }
}

/// 分享长图卡视图（640 设计宽；预览层保持 1:1 布局、横向滚动查看，
/// [captureShareCard] 挂在直接包裹它的 RepaintBoundary 上，恒得 1080 宽）。
class ShareCardView extends StatelessWidget {
  const ShareCardView({super.key, required this.model});

  final ShareCardModel model;

  static const double designWidth = 640;

  @override
  Widget build(BuildContext context) {
    final g = context.tokens.gradient.colors;
    return Container(
      key: const ValueKey('sc-img'),
      width: designWidth,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: g,
              ),
            ),
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(model.eyebrow,
                    style: const TextStyle(fontSize: 15, color: Colors.white70)),
                const SizedBox(height: 5),
                Text(model.title,
                    style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
                const SizedBox(height: 5),
                Text(model.line,
                    style: const TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(model.big,
                        style: const TextStyle(
                            fontSize: 42,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(model.unit,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white70)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final t in model.tiles)
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.symmetric(
                              horizontal: model.tiles.length > 1 ? 4 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              Text(t.value,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              const SizedBox(height: 3),
                              Text(t.label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in model.sections)
                  if (s.rows.isNotEmpty || s.bars != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(s.head,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF64748B))),
                    ),
                    if (s.bars != null) _bars(s),
                    for (final r in s.rows) _row(r),
                    const SizedBox(height: 16),
                  ],
                const _ShareFootnote(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ShareCardRow r) {
    if (r.value.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(r.label,
            style: const TextStyle(fontSize: 15, height: 1.5)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(r.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 8),
          Text(r.value,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D9488))),
        ],
      ),
    );
  }

  Widget _bars(ShareCardSection s) {
    final bars = s.bars!;
    final mx = bars.fold<double>(1, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: bars[i] > 0 ? (bars[i] / mx * 62).clamp(3.0, 62.0) : 2,
                      decoration: BoxDecoration(
                        color: bars[i] > 0
                            ? const Color(0xFFFB7185)
                            : const Color(0xFFE2E8F0),
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(s.barLabels?[i] ?? '${i + 1}',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareFootnote extends StatelessWidget {
  const _ShareFootnote();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
            child: SizedBox(
                height: 1, child: ColoredBox(color: Color(0xFFE2E8F0)))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('数据仅存本机',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ),
        const Expanded(
            child: SizedBox(
                height: 1, child: ColoredBox(color: Color(0xFFE2E8F0)))),
      ],
    );
  }
}

/// 统一的「分享长图」预览弹层（四站共用；习惯站保有自己的弹层，只复用 [captureShareCard]）。
/// 保存图片成功＝关弹层后 toast 真实路径；失败＝关弹层后 toast 失败文案（日志已留痕）。
Future<void> showShareCardSheet(BuildContext context, ShareCardModel model,
    {String? src}) async {
  final messenger = ScaffoldMessenger.of(context);
  final boundaryKey = GlobalKey();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) {
      final scheme = Theme.of(bc).colorScheme;
      return SafeArea(
        child: Padding(
          key: const ValueKey('sc-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('分享长图',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                  Text('预览',
                      style: TextStyle(
                          fontSize: 10.5, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    // 卡片按 640 设计宽真实布局（禁祖先缩放变换——toImage 会把
                    // 变换算进光栅尺寸导致宽度失控），窄屏靠横向滚动预览。
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: RepaintBoundary(
                        key: boundaryKey,
                        child: ShareCardView(model: model),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('sc-copy'),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: model.copyText));
                        if (bc.mounted) AppToast.show(bc, '文字版已复制');
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurface,
                        backgroundColor:
                            scheme.onSurface.withValues(alpha: .05),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('复制文字版',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('sc-save'),
                      onPressed: () async {
                        final path = await captureShareCard(boundaryKey,
                            name: model.file, src: src);
                        if (bc.mounted) Navigator.of(bc).pop();
                        messenger.showSnackBar(SnackBar(
                            content: Text(path == null
                                ? '分享长图生成失败 · 详见日志'
                                : '分享长图已保存：$path')));
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: context.tokens.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('保存图片',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
