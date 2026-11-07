import 'dart:math' as math;
import 'dart:ui';

/// 视口裁剪（渲染层七条之二 · 冻结方案 §6.3）：只画与可视区相交的节点与边。
///
/// 纯函数、零 Flutter 依赖（`dart:ui` 的 Size/Offset 除外）——
/// 常驻用例直接喂数据断言「视口外节点不进待绘集合」，变异刀 3 也钉这里
/// （摘掉裁剪＝无脑全量返回＝用例红）。
///
/// 坐标口径：`baseline`＝布局基线（画布坐标），渲染绝对位＝基线＋节点 `dx/dy`；
/// `scale`/`pan` 是画布→屏幕的视口变换（screen = canvas*scale + pan）。
/// 可视区（画布坐标）＝矩形 (−pan)/scale 到 ((viewport−pan))/scale，外扩 8px 容差。
List<int> cullVisibleNodes({
  required Map<int, Offset> baseline,
  required Map<int, Size> sizes,
  required Map<int, double> dxs,
  required Map<int, double> dys,
  required double scale,
  required Offset pan,
  required Size viewport,
  Set<int>? candidates,
}) {
  // 画布坐标下的可视矩形（随缩小而变大——缩得越小看得越多，天然正确）。
  final tl = Offset(-pan.dx / scale, -pan.dy / scale);
  final visible = Rect.fromPoints(
    tl - const Offset(8, 8),
    tl.translate(viewport.width / scale, viewport.height / scale) +
        const Offset(8, 8),
  );
  final out = <int>[];
  for (final id in candidates ?? baseline.keys) {
    final b = baseline[id];
    if (b == null) continue;
    final s = sizes[id] ?? const Size(120, 36);
    final pos = b + Offset(dxs[id] ?? 0, dys[id] ?? 0);
    if (visible.overlaps(Rect.fromLTWH(pos.dx, pos.dy, s.width, s.height))) {
      out.add(id);
    }
  }
  out.sort((a, b) {
    final ya = (baseline[a]!.dy + (dys[a] ?? 0));
    final yb = (baseline[b]!.dy + (dys[b] ?? 0));
    return ya.compareTo(yb);
  });
  return out;
}

/// fit 计算：给定内容包围盒与视口，返回 scale/pan 使全图可见且居中（C11：
/// 进图 fit 到内容；scale 钳在 [minScale, 1]——fit 不放大超原尺寸）。
(double, Offset) fitTransform({
  required Rect contentBounds,
  required Size viewport,
  double minScale = 0.25,
}) {
  if (contentBounds.isEmpty) return (1.0, Offset.zero);
  final s = math
      .min(1.0, math.min(viewport.width / contentBounds.width,
          viewport.height / contentBounds.height))
      .clamp(minScale, 1.0);
  final pan = Offset(
    (viewport.width - contentBounds.width * s) / 2 - contentBounds.left * s,
    (viewport.height - contentBounds.height * s) / 2 - contentBounds.top * s,
  );
  return (s, pan);
}

/// 缩放钳位（F1-3 口径 25%~400%）。三处缩放入口（双击 / 滚轮 / 捏合）共用一份，
/// 免得各写一遍把上下限写岔。
const double mmMinScale = 0.25;
const double mmMaxScale = 4.0;

/// 以画布上某点为锚缩放：该点缩放前后落在屏幕同一点（`screen = canvas*scale + pan`）。
///
/// 为什么单拎出来：按钮「放大/缩小」原先只改 `_scale`、不动 `_pan`，观感是
/// 「从左上角往外撑」——内容中心会往右下飘，连点几次就找不到刚看的那一枝。
/// 屏中心 / 双指中点 / 鼠标位置都走这一条，只有锚点不同。
(double, Offset) zoomAround({
  required double scale,
  required Offset pan,
  required double nextScale,
  required Offset anchor,
}) {
  final s = nextScale.clamp(mmMinScale, mmMaxScale);
  final canvas = (anchor - pan) / scale;
  return (s, anchor - canvas * s);
}
