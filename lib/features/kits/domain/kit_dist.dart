/// 小工具合集 · 测距纯计算（批3）。
///
/// 两模（原型 `KITS.distMode`）：
/// - `map`：离线地图比例尺，自绘网格画布上点选，距离 = 像素欧氏距离 × m/px；
/// - `gps`：轻点采集定位点，距离走**大圆（Haversine）**，点由画布坐标反算经纬度。
/// 全程本机几何计算，零出站。
library;

import 'dart:math' as math;

/// 两种模式取值（与原型 `KITS.distMode` 字面量一致——键即数据）。
const String kKitDistModeMap = 'map';
const String kKitDistModeGps = 'gps';

/// 比例尺滑杆（原型 `min=0.5 max=10 step=0.5`，单位 m/px）。
const double kKitDistScaleMin = .5;
const double kKitDistScaleMax = 10;
const double kKitDistScaleStep = .5;
const double kKitDistScaleDefault = 2.5;

/// GPS 模拟行走：14 步 × 260ms（原型 `distGpsWalk`）。
const int kKitGpsWalkSteps = 14;
const int kKitGpsWalkTickMs = 260;

/// 一个轨迹点（[x]/[y] 为画布内逻辑像素；gps 模式带经纬度）。
class KitDistPoint {
  const KitDistPoint({required this.x, required this.y, this.lat, this.lng});

  final double x;
  final double y;
  final double? lat;
  final double? lng;
}

/// 轻点落点：map 只记画布坐标；gps 按原型线性映射反算经纬度
/// （纬度每像素 -0.00002、经度每像素 +0.000022，锚点 30.28 / 120.02）。
KitDistPoint kitDistPointAt(double x, double y, {required String mode}) =>
    mode == kKitDistModeGps
    ? KitDistPoint(
        x: x,
        y: y,
        lat: 30.28 - y * .00002,
        lng: 120.02 + x * .000022,
      )
    : KitDistPoint(x: x, y: y);

/// 大圆距离（米，原型 `distHav`，R=6371000）。
double kitHaversineMeters(KitDistPoint a, KitDistPoint b) {
  const r = 6371000.0;
  const deg = math.pi / 180;
  final la1 = (a.lat ?? 0) * deg;
  final la2 = (b.lat ?? 0) * deg;
  final dLat = ((b.lat ?? 0) - (a.lat ?? 0)) * deg;
  final dLng = ((b.lng ?? 0) - (a.lng ?? 0)) * deg;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// 轨迹总长（米）：gps 用大圆，map 用像素距离 × 比例尺。
double kitDistTotalMeters(
  List<KitDistPoint> pts, {
  required String mode,
  required double scaleMPerPx,
}) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    d += mode == kKitDistModeGps && pts[i].lat != null && pts[i - 1].lat != null
        ? kitHaversineMeters(pts[i - 1], pts[i])
        : math.sqrt(
                math.pow(pts[i].x - pts[i - 1].x, 2) +
                    math.pow(pts[i].y - pts[i - 1].y, 2),
              ) *
              scaleMPerPx;
  }
  return d;
}

/// 总长文案（原型 `#distTotal`：≥1km 走 km 两位小数，否则米取整）。
String kitDistTotalText(double meters, int count) {
  final len = meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(2)} km'
      : '${meters.round()} m';
  return '总长 $len · $count 个点';
}

/// 画布左上角提示（原型 `distHint`）。
String kitDistHintText(String mode, double scaleMPerPx) =>
    mode == kKitDistModeGps
    ? 'GPS 轨迹 · 轻点采集定位点 · 大圆距离'
    : '模拟地图 · 轻点落点 · 1px≈${scaleMPerPx}m';

/// 画布右下角经纬度浮标（gps 且有轨迹点时才有值；原型 `#distTrail`）。
String? kitDistTrailText(List<KitDistPoint> pts, {required String mode}) {
  if (mode != kKitDistModeGps || pts.isEmpty) return null;
  final l = pts.last;
  return '${(l.lat ?? 0).toStringAsFixed(5)}, ${(l.lng ?? 0).toStringAsFixed(5)}';
}

/// 模拟行走第 k 步的落点（原型 `distGpsWalk` 的螺旋增量，全部实算）。
KitDistPoint kitGpsWalkStep(KitDistPoint start, int k) => KitDistPoint(
  x: start.x + k * 5 * math.cos(k / 2),
  y: start.y + k * 3 * math.sin(k / 3),
  lat: (start.lat ?? 30.28) - k * .00004,
  lng: (start.lng ?? 120.02) + k * .00003,
);

/// GPS 模式空轨迹时的种子点（原型 `distSeedGps`）。
const KitDistPoint kKitGpsSeed = KitDistPoint(
  x: 30,
  y: 150,
  lat: 30.279998,
  lng: 120.02066,
);

/// 撤销一步（原型 `distUndo` 直接 pop）。
List<KitDistPoint> kitDistUndo(List<KitDistPoint> pts) =>
    pts.isEmpty ? pts : pts.sublist(0, pts.length - 1);

/// 测距私有数据（`kit_tool_data.tool='dist'`；原型 `KITS.distMode` / `distScale`，
/// 轨迹本身按原型口径只存内存、不落库）。
Map<String, Object?> kitDistEncode({
  required String mode,
  required double scale,
}) => {'distMode': mode, 'distScale': scale};

class KitDistState {
  const KitDistState({required this.mode, required this.scale});

  final String mode;
  final double scale;

  bool get isGps => mode == kKitDistModeGps;

  static KitDistState decode(Map<String, Object?> d) => KitDistState(
    mode: d['distMode'] == kKitDistModeGps ? kKitDistModeGps : kKitDistModeMap,
    scale: ((d['distScale'] as num?)?.toDouble() ?? kKitDistScaleDefault).clamp(
      kKitDistScaleMin,
      kKitDistScaleMax,
    ),
  );
}
