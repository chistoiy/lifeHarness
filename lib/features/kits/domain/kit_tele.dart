/// 小工具合集 · 提词器纯计算（批3）。
///
/// 参数五项（方向 / 速度 / 字号 / 行距 / 前景底色）+ LED 点阵开关 + 讲稿，全部
/// 落 `kit_tool_data.tool='tele'`（键名同原型 `KITS.tp*`）。滚动与扫描线只算
/// 「该移动多少像素」，时钟由屏侧注入（[kitTeleAdvance] 的 dt 与原型 rAF 同款
/// 80ms 上限，防止切后台回来一次性跳到底）。
/// 拍板口径：不做语音跟随 / 自动停顿 / 反向滚动（V1.47 §0）。
library;

import 'dart:math' as math;

/// 显示方向（原型 `KITS.tpOri`，默认横向=把手机横过来看）。
const String kKitTeleDirLand = 'land';
const String kKitTeleDirPort = 'port';

/// 速度 px/s（原型 `min=10 max=300 step=5`）。
const int kKitTeleSpeedMin = 10;
const int kKitTeleSpeedMax = 300;
const int kKitTeleSpeedStep = 5;
const int kKitTeleSpeedDefault = 60;

/// 字号 px（原型 `min=18 max=96`）。
const int kKitTeleSizeMin = 18;
const int kKitTeleSizeMax = 96;
const int kKitTeleSizeDefault = 40;

/// 行距百分比（原型 `min=110 max=220 step=5`）。
const int kKitTeleLhMin = 110;
const int kKitTeleLhMax = 220;
const int kKitTeleLhStep = 5;
const int kKitTeleLhDefault = 155;

/// 默认前景 / 底色（原型 `#ffffff` on `#000000`）。
const String kKitTeleFgDefault = '#ffffff';
const String kKitTeleBgDefault = '#000000';

/// LED 点阵与扫描线（原型 `background-size:6px 6px` · 30% 颗粒 · 3px 扫描线 ·
/// `tpScan 3.6s linear infinite`）。
const double kKitTeleDotPitch = 6;
const double kKitTeleDotRatio = .3;
const double kKitTeleScanHeight = 3;
const int kKitTeleScanPeriodMs = 3600;

/// 单帧最大推进时长（原型 `Math.min(80, t-last)`）。
const int kKitTeleMaxStepMs = 80;

/// 越过稿尾后的回卷余量（原型 `+40` / `-40`）。
const double kKitTeleOverrun = 40;

/// 方向 chip 文案。
String kitTeleDirLabel(String dir) =>
    dir == kKitTeleDirLand ? '横向（手机横过来）' : '竖向';

String kitTeleDirToast(String dir) =>
    dir == kKitTeleDirLand ? '显示方向：手机横过来看（内容转 90°）' : '显示方向：竖向滚动';

String kitTeleSpeedText(int pxPerSec) => '$pxPerSec px/s';

String kitTeleSizeText(int px) => '$px px';

String kitTeleLhText(int pct) => '$pct%';

String kitTeleLedNote(bool on) => on ? '点阵颗粒 + 扫描线已同步' : '普通文字模式';

String kitTeleLedToast(bool on) =>
    on ? 'LED 点阵屏已开 · 扫描线同步运行' : 'LED 已关 · 普通文字模式';

/// 笔记导入未接线时的口径（原型此处也只是演示提示）。
const String kKitTeleNotePending = '笔记选择器待接入 · 先把讲稿粘贴在下方';

/// 演示稿（原型 `tpDemo` 同文；复盘话术六段）。
String kitTeleDemoScript() => const [
  '各位好，欢迎参加本次产品复盘。',
  '第一件事：这个版本我们把「数据在自己手里」做到了可验证的程度——'
      '所有轻工具离线可用、抓包零请求。',
  '第二件事：插件化不是炫技，而是让不需要的模块不打扰你；'
      '安装要过哈希与签名两道门，卸载保留数据三十天。',
  '第三件事：我知道大家最在意稳定性。所以下面这三条，'
      '是我给自己定的验收红线，不是给团队的。',
  '讲到这里可以停三秒，等一等提问。',
  '最后一句话：工具应该让人更自由，而不是让人更忙。谢谢大家。',
].join('\n\n');

/// 本帧推进像素（[dtMs] 超上限按上限算，避免切后台回来一次跳完）。
double kitTeleAdvance({required int pxPerSec, required int dtMs}) =>
    pxPerSec * math.min(dtMs, kKitTeleMaxStepMs) / 1000;

/// 越过稿尾回卷到视口上方（原型 `TP_Y = -(clientHeight-40)`）。
double kitTeleWrap({
  required double y,
  required double bodyHeight,
  required double viewportHeight,
}) =>
    y > bodyHeight + kKitTeleOverrun ? -(viewportHeight - kKitTeleOverrun) : y;

/// 扫描线在视口中的比例位置（0~1，周期 [kKitTeleScanPeriodMs]）。
double kitTeleScanFraction(int elapsedMs) =>
    (elapsedMs % kKitTeleScanPeriodMs) / kKitTeleScanPeriodMs;

/// LED 颗粒半径（原型 30% 实心 + 6px 间距）。
double kitTeleDotRadius({double cell = kKitTeleDotPitch}) =>
    cell * kKitTeleDotRatio;

/// 状态（屏侧持有；色值只接受 `#rrggbb`，非法回落默认）。
class KitTeleState {
  const KitTeleState({
    required this.dir,
    required this.speed,
    required this.size,
    required this.lh,
    required this.fg,
    required this.bg,
    required this.led,
    required this.text,
  });

  final String dir;
  final int speed;
  final int size;
  final int lh;
  final String fg;
  final String bg;
  final bool led;
  final String text;

  bool get horizontal => dir == kKitTeleDirLand;

  /// 行距倍数（`TextStyle.height` 直接用）。
  double get lineHeightFactor => lh / 100;

  static String _hex(Object? v, String fallback) =>
      (v is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v))
      ? v.toLowerCase()
      : fallback;

  static KitTeleState decode(Map<String, Object?> d) => KitTeleState(
    dir: d['tpOri'] == kKitTeleDirPort ? kKitTeleDirPort : kKitTeleDirLand,
    speed: _clamp(
      d['tpSpeed'],
      kKitTeleSpeedDefault,
      kKitTeleSpeedMin,
      kKitTeleSpeedMax,
      kKitTeleSpeedStep,
    ),
    size: _clamp(
      d['tpSize'],
      kKitTeleSizeDefault,
      kKitTeleSizeMin,
      kKitTeleSizeMax,
      1,
    ),
    lh: _clamp(
      d['tpLh'],
      kKitTeleLhDefault,
      kKitTeleLhMin,
      kKitTeleLhMax,
      kKitTeleLhStep,
    ),
    fg: _hex(d['tpFg'], kKitTeleFgDefault),
    bg: _hex(d['tpBg'], kKitTeleBgDefault),
    led: d['tpLed'] == true,
    text: d['tpText'] as String? ?? '',
  );

  /// 落到区间并对齐步长（库里存脏值时读数仍可用）。
  static int _clamp(Object? v, int dflt, int min, int max, int step) {
    final n = (v as num?)?.round() ?? dflt;
    final c = n.clamp(min, max);
    return step <= 1
        ? c
        : (min + ((c - min) / step).round() * step).clamp(min, max);
  }

  KitTeleState copyWith({
    String? dir,
    int? speed,
    int? size,
    int? lh,
    String? fg,
    String? bg,
    bool? led,
    String? text,
  }) => KitTeleState(
    dir: dir ?? this.dir,
    speed: speed ?? this.speed,
    size: size ?? this.size,
    lh: lh ?? this.lh,
    fg: fg ?? this.fg,
    bg: bg ?? this.bg,
    led: led ?? this.led,
    text: text ?? this.text,
  );
}

/// 落库结构（`kit_tool_data.tool='tele'`）。
Map<String, Object?> kitTeleEncode(KitTeleState s) => {
  'tpOri': s.dir,
  'tpSpeed': s.speed,
  'tpSize': s.size,
  'tpLh': s.lh,
  'tpFg': s.fg,
  'tpBg': s.bg,
  'tpLed': s.led,
  'tpText': s.text,
};
