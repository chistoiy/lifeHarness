/// 小工具合集 · 尺子纯计算（批3）。
///
/// 量程按**实测 DPI**换算：Android 面板密度 `densityDpi ≈ devicePixelRatio×160`，
/// 逻辑像素先乘 dpr 到物理像素、再按密度折毫米（dpr 相消，见 [kitRulerMmPerPx]）；
/// 真机面板与假设的偏差由银行卡校准吸收，A4 校准项仍在验收清单里。
/// 倍率 [cal] 参与换算——这是与原型唯一的口径差别：
/// 原型 `KITS.cal` 只显示不参与，实现里让它真的改变读数。
library;

/// 参考像素密度（Android `densityDpi ≈ devicePixelRatio × 160`；mdpi=160dpi）。
const double kKitRulerRefDensity = 160;

/// 倍率滑杆区间（原型 `min=0.85 max=1.15 step=0.002`）。
const double kKitRulerCalMin = .85;
const double kKitRulerCalMax = 1.15;
const double kKitRulerCalStep = .002;

/// 银行卡短边标准 85.60mm（ISO/IEC 7810 ID-1 长边）。
const double kKitRulerBankCardMm = 85.6;

/// 刻度线三级长度（原型 major 56 / mid 34 / minor 18）。
const double kKitRulerTickMajor = 56;
const double kKitRulerTickMid = 34;
const double kKitRulerTickMinor = 18;

/// 1 **逻辑**像素对应的毫米数（含倍率）。
///
/// 走一遍真实换算链：逻辑像素 × dpr = 物理像素，物理像素 ÷（dpr×[refDensity]）
/// × 25.4 = 毫米 —— dpr 在分子分母相消，结果只由参考密度决定。
/// 这不是冗余：它把「Android 用 densityDpi≈dpr×160 描述面板」这一假设写进了
/// 公式，真机面板实际 ppi 与该假设的偏差正是银行卡校准要吸收的部分。
double kitRulerMmPerPx({
  required double devicePixelRatio,
  double cal = 1,
  double refDensity = kKitRulerRefDensity,
}) {
  final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final physicalPerMm = dpr * refDensity / 25.4;
  return dpr / physicalPerMm * cal;
}

/// 尺边（长边/短边）对应的像素长度。
double kitRulerEdgePx({
  required double widthPx,
  required double heightPx,
  required bool longEdge,
}) => longEdge
    ? (widthPx > heightPx ? widthPx : heightPx)
    : (widthPx < heightPx ? widthPx : heightPx);

/// 量程（毫米，取整；= 尺边像素 × mm/px）。
int kitRulerTargetMm({
  required double widthPx,
  required double heightPx,
  required double devicePixelRatio,
  required bool longEdge,
  double cal = 1,
}) =>
    (kitRulerEdgePx(widthPx: widthPx, heightPx: heightPx, longEdge: longEdge) *
            kitRulerMmPerPx(devicePixelRatio: devicePixelRatio, cal: cal))
        .round();

/// 每毫米占多少屏幕像素（画刻度与游标定位用；量程 0 时回落 1）。
double kitRulerPxPerMm({required double tapePx, required int targetMm}) =>
    targetMm <= 0 ? 1 : tapePx / targetMm;

/// 游标/零点钳位（原型 `rsClamp`：零点 ≤ 量程-1，游标 ≥ 零点+1 且 ≤ 量程）。
class KitRulerMarks {
  const KitRulerMarks({required this.zero, required this.cur});

  final int zero;
  final int cur;

  /// 游标读数（毫米）。
  int get mm => cur - zero;
}

KitRulerMarks kitRulerClamp({
  required int zero,
  required int cur,
  required int targetMm,
}) {
  final z = zero.clamp(0, targetMm - 1);
  return KitRulerMarks(zero: z, cur: cur.clamp(z + 1, targetMm));
}

/// 键盘/按钮微调一档（±1mm，仍守零点与量程）。
KitRulerMarks kitRulerNudge(
  KitRulerMarks m, {
  required int delta,
  required int targetMm,
}) => kitRulerClamp(zero: m.zero, cur: m.cur + delta, targetMm: targetMm);

/// 大读数（cm 单位显示 mm，in 单位按 25.4 换算两位小数）。
String kitRulerReadout({required String unit, required int mm}) =>
    unit == 'in' ? '${(mm / 25.4).toStringAsFixed(2)} in' : '$mm mm';

/// 副读数行（原型 `#rulerSpan`）。
String kitRulerSpanText({required bool longEdge, required int mm}) =>
    '${longEdge ? '长边' : '短边'} 游标 $mm mm ≈ ${(mm / 10).toStringAsFixed(1)} cm';

/// 零点/量程说明行（原型 `#rsZeroPos`；键盘微调在触屏上换成 ±1mm 钮）。
String kitRulerZeroText({required int zero, required int targetMm}) =>
    '零点 $zero mm · 量程 $targetMm mm · ±1mm 微调';

/// 量程卡文案（原型 `#rulerSpanCard`）。
String kitRulerSpanCard(int targetMm) => '$targetMm mm';

/// 倍率文案（`1.000×`）。
String kitRulerCalText(double cal) => '${cal.toStringAsFixed(3)}×';

/// 银行卡校准：按住游标量过一张真实银行卡后，把当前读数（含现有倍率）
/// 折算回未校准毫米，再反算出新倍率（夹在滑杆区间内）。
double kitRulerBankCal({required double currentCal, required int readingMm}) {
  if (readingMm <= 0) return currentCal.clamp(kKitRulerCalMin, kKitRulerCalMax);
  final rawMm = readingMm / (currentCal <= 0 ? 1 : currentCal);
  return (kKitRulerBankCardMm / rawMm).clamp(kKitRulerCalMin, kKitRulerCalMax);
}

/// 一枚刻度线（位置毫米 + 线长 + 可选主刻度标注）。
class KitRulerTick {
  const KitRulerTick({required this.mm, required this.len, this.label});

  final double mm;
  final double len;
  final String? label;
}

/// 刻度序列（cm：逐毫米，整厘米标数字、半厘米加长；
/// in：按 1/4 英寸分档，整英寸标数字、半英寸加长 —— 原型 rulerDrawScale 同构）。
List<KitRulerTick> kitRulerTicks({
  required int targetMm,
  required String unit,
}) {
  if (targetMm <= 0) return const [];
  if (unit != 'in') {
    return [
      for (var i = 0; i <= targetMm; i++)
        KitRulerTick(
          mm: i.toDouble(),
          len: i % 10 == 0
              ? kKitRulerTickMajor
              : (i % 5 == 0 ? kKitRulerTickMid : kKitRulerTickMinor),
          label: i % 10 == 0 ? '${i ~/ 10}' : null,
        ),
    ];
  }
  final n = (targetMm / 25.4 * 4).round();
  final out = <KitRulerTick>[];
  for (var i = 0; i <= n; i++) {
    final v = i * 25.4 / 4;
    if (v > targetMm) break;
    out.add(
      KitRulerTick(
        mm: v,
        len: i % 4 == 0
            ? kKitRulerTickMajor
            : (i % 2 == 0 ? kKitRulerTickMid : kKitRulerTickMinor),
        label: i % 4 == 0 ? '${i ~/ 4}' : null,
      ),
    );
  }
  return out;
}

/// 单位说明 toast（原型 `rulerUnit`）。
String kitRulerUnitToast(String unit) =>
    unit == 'in' ? '刻度单位：英寸 · 1in=25.4mm 换算' : '刻度单位：厘米 · 逻辑毫米基准';

/// 方向说明 toast（原型 `rulerDir` · 反馈轮4：换尺边会真的转屏）。
String kitRulerDirToast(bool longEdge) =>
    longEdge ? '尺边：长边 · 尺面转为横向（手机横过来量）' : '尺边：短边 · 尺面回到竖向';

/// 分享文案（原型 `KIT_SHARE_TXT`）。
String kitRulerShare({
  required KitRulerMarks m,
  required bool longEdge,
  required int targetMm,
  required double cal,
}) =>
    '尺子 · 游标读数 ${m.mm} mm（${longEdge ? '长边' : '短边'} · 零点 ${m.zero} mm）'
    '· 量程 $targetMm mm · 校准 ${cal.toStringAsFixed(3)}×';

/// 尺子私有数据（`kit_tool_data.tool='ruler'`；键名与原型 `KITS.*` 一致）。
Map<String, Object?> kitRulerEncode({
  required String unit,
  required String dir,
  required double cal,
  required int zero,
  required int? cur,
}) => {'unit': unit, 'dir': dir, 'cal': cal, 'zero': zero, 'cur': cur};

/// 已恢复的尺子参数（[cur]=null 表示还没落过游标，屏侧按量程 40% 给初值）。
class KitRulerState {
  const KitRulerState({
    required this.unit,
    required this.dir,
    required this.cal,
    required this.zero,
    this.cur,
  });

  final String unit;
  final String dir;
  final double cal;
  final int zero;
  final int? cur;

  bool get longEdge => dir != 'short';

  /// 损坏数据一律回默认（原型 `KITS.cal=.995` 的兜底思路）。
  static KitRulerState decode(Map<String, Object?> d) {
    final cal = (d['cal'] as num?)?.toDouble() ?? 1.0;
    return KitRulerState(
      unit: d['unit'] == 'in' ? 'in' : 'cm',
      dir: d['dir'] == 'short' ? 'short' : 'long',
      cal: cal.clamp(kKitRulerCalMin, kKitRulerCalMax),
      zero: ((d['zero'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      cur: (d['cur'] as num?)?.toInt(),
    );
  }
}
