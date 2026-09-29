/// 小工具合集 · 图片体积缩小纯计算（批3）。
///
/// 只算「该怎么压」与「压完省了多少」：缩放尺寸、体积百分比、批量队列汇总、
/// 文案与落库结构。真正的解码/缩放/编码在屏侧经注入缝完成
/// （`dart:ui` + [kitJpegEncode]），保证界面上的每个数字都来自真实字节。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'kit_calc.dart' show kitBytesText;
import 'kit_jpeg.dart' show kitJpegEncode;

export 'kit_jpeg.dart' show kitJpegEncode, kitJpegScale;

/// 格式取值（原型 `IMGZ_FMT`）。webp 在当前纯 Dart 内核无编码器，见
/// [kitImgzWebpNote]——按批2「屏上取色」的既有处置方式给「待接入」提示。
const String kKitImgzFmtJpeg = 'jpeg';
const String kKitImgzFmtWebp = 'webp';

/// 最长边区间（原型 `#imgzEdge` 默认 1600）。
const int kKitImgzEdgeDefault = 1600;
const int kKitImgzEdgeMin = 64;
const int kKitImgzEdgeMax = 8192;

/// 质量区间（原型 `#imgzQ` min=20 max=90，默认 60）。
const int kKitImgzQMin = 20;
const int kKitImgzQMax = 90;
const int kKitImgzQDefault = 60;

/// 一张图的压缩计划（只算尺寸，不碰像素）。
class KitImgzPlan {
  const KitImgzPlan({
    required this.srcW,
    required this.srcH,
    required this.outW,
    required this.outH,
  });

  final int srcW;
  final int srcH;
  final int outW;
  final int outH;

  /// 是否真的缩了（等比 1:1 时界面上不提「缩至」）。
  bool get scaled => outW != srcW || outH != srcH;

  /// 缩放比例（1=不变）。
  double get ratio => srcW == 0 ? 1 : outW / srcW;
}

/// 按最长边等比缩放计划（原型 `Math.min(1, edge/Math.max(w,h))`；放大一律拒绝）。
KitImgzPlan kitImgzPlan({
  required int srcW,
  required int srcH,
  required int maxEdge,
}) {
  final edge = maxEdge.clamp(kKitImgzEdgeMin, kKitImgzEdgeMax);
  final longest = math.max(srcW, srcH);
  if (longest <= 0) {
    return KitImgzPlan(srcW: srcW, srcH: srcH, outW: 0, outH: 0);
  }
  final sc = (edge / longest).clamp(0.0, 1.0);
  return KitImgzPlan(
    srcW: srcW,
    srcH: srcH,
    outW: math.max(1, (srcW * sc).round()),
    outH: math.max(1, (srcH * sc).round()),
  );
}

/// 节省百分比（原型 `(1-b/size)*100`，一位小数；负数=反而变大，照实显示）。
double kitImgzSavedPct(int srcBytes, int outBytes) => srcBytes <= 0
    ? 0
    : double.parse(((1 - outBytes / srcBytes) * 100).toStringAsFixed(1));

/// 结果说明行（原型 `#imgzInfo`）。
String kitImgzInfo({
  required KitImgzPlan plan,
  required int srcBytes,
  required int outBytes,
  required String fmt,
  required bool watermark,
}) {
  final pct = kitImgzSavedPct(srcBytes, outBytes);
  final buf = StringBuffer(
    '原图 ${plan.srcW}×${plan.srcH} · ${kitBytesText(srcBytes)}　→　'
    '${kitBytesText(outBytes)}',
  );
  if (plan.scaled) buf.write(' · 缩至 ${plan.outW}×${plan.outH}');
  buf.write(' · 体积减少 ${pct.toStringAsFixed(1)}%');
  buf.write(' · ${fmt.toUpperCase()} 质量档已生效');
  if (watermark) buf.write(' · 已加右下角水印');
  return buf.toString();
}

/// 分享文案（原型 `KIT_SHARE_TXT`）。
String kitImgzShare({
  required KitImgzPlan plan,
  required int srcBytes,
  required int outBytes,
}) =>
    '图片压缩 ${plan.srcW}×${plan.srcH} ${kitBytesText(srcBytes)} → '
    '${plan.outW}×${plan.outH} ${kitBytesText(outBytes)} · '
    '−${kitImgzSavedPct(srcBytes, outBytes).toStringAsFixed(1)}%';

/// 队列里的一张待压/已压图片。
class KitImgzQueueItem {
  const KitImgzQueueItem({
    required this.name,
    required this.srcBytes,
    this.outBytes,
  });

  final String name;
  final int srcBytes;

  /// null=还在队列里等待本机压缩。
  final int? outBytes;

  bool get done => outBytes != null;
}

/// 批量汇总行（原型 `#imgzBatchSum`：全部真实字节，无演示值）。
String kitImgzBatchSummary(List<KitImgzQueueItem> items) {
  final done = items.where((e) => e.done).toList();
  if (done.isEmpty) return '';
  final tot = items.fold<int>(0, (a, e) => a + e.srcBytes);
  final after = items.fold<int>(0, (a, e) => a + (e.outBytes ?? e.srcBytes));
  final saved = tot == 0 ? 0.0 : (1 - after / tot) * 100;
  return '批量合计 ${items.length} 张 · 已压 ${done.length} 张 · '
      '${kitBytesText(tot)} → ${kitBytesText(after)} · 节省 ${saved.toStringAsFixed(0)}%'
      '（每张都为本机真实编码）';
}

/// 单张队列行文案（原型 `#imgzBatch`）。
String kitImgzQueueText(KitImgzQueueItem e) => e.done
    ? '${kitBytesText(e.srcBytes)} → ${kitBytesText(e.outBytes!)} · '
          '−${kitImgzSavedPct(e.srcBytes, e.outBytes!).toStringAsFixed(0)}%'
    : '排队中…';

/// WebP 在当前内核不可用的提示（保留入口，不给假结果）。
const String kKitImgzWebpNote =
    'WebP 编码器需系统原生通道 · 本机 Dart 内核暂不支持 · 已按 JPEG 真实压缩';

/// 图片私有数据（`kit_tool_data.tool='imgz'`；键名同原型 `KITS.imgzEdge` 等）。
Map<String, Object?> kitImgzEncode({
  required int edge,
  required int quality,
  required bool watermark,
}) => {'imgzEdge': edge, 'imgzQ': quality, 'imgzMk': watermark};

class KitImgzState {
  const KitImgzState({
    required this.edge,
    required this.quality,
    required this.mark,
  });

  final int edge;
  final int quality;
  final bool mark;

  static KitImgzState decode(Map<String, Object?> d) => KitImgzState(
    edge: ((d['imgzEdge'] as num?)?.toInt() ?? kKitImgzEdgeDefault).clamp(
      kKitImgzEdgeMin,
      kKitImgzEdgeMax,
    ),
    quality: ((d['imgzQ'] as num?)?.toInt() ?? kKitImgzQDefault).clamp(
      kKitImgzQMin,
      kKitImgzQMax,
    ),
    mark: d['imgzMk'] == true,
  );
}

/// 屏侧经本别名调用编码器（域层内部再依赖 [kit_jpeg]，保持屏侧只认一个入口）。
Uint8List kitImgzEncodeJpeg({
  required int width,
  required int height,
  required Uint8List rgb,
  int quality = 75,
}) => kitJpegEncode(width: width, height: height, rgb: rgb, quality: quality);
