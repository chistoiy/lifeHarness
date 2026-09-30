/// 小工具合集 · 提词器纯计算（批3 · 反馈轮4 吸收手持弹幕效果组）。
///
/// 参数（方向 / 显示方式 / 速度 / 字号 / 行距 / 前景底色 / 多彩背景 / 闪烁 /
/// 加粗 / 抖动 / LED）+ 讲稿，全部落 `kit_tool_data.tool='tele'`
/// （键名同原型 `KITS.tp*`）。滚动与扫描线只算「该移动多少像素」，时钟由屏侧
/// 注入（[kitTeleAdvance] 的 dt 与原型 rAF 同款 80ms 上限，防止切后台回来一次
/// 性跳到底）。
/// 拍板口径：不做语音跟随 / 自动停顿 / 反向滚动（V1.47 §0）。
/// 反馈轮4 定位：长文本提词能力保留（滚动态），同时吸收图2 的单屏大字展示
/// （静止态 + 闪烁 / 加粗 / 抖动 / 多彩渐变背景）。
library;

import 'dart:math' as math;

/// 显示方向（原型 `KITS.tpOri`，默认横向=把手机横过来看）。
const String kKitTeleDirLand = 'land';
const String kKitTeleDirPort = 'port';

/// 显示方式（原型 `KITS.tpMode`）：滚动=提词；静止=铺屏大字。
const String kKitTeleModeScroll = 'scroll';
const String kKitTeleModeStatic = 'static';

/// 速度 px/s（原型 `min=10 max=300 step=5`）。
const int kKitTeleSpeedMin = 10;
const int kKitTeleSpeedMax = 300;
const int kKitTeleSpeedStep = 5;
const int kKitTeleSpeedDefault = 60;

/// 字号 px（原型 `min=18 max=160`：图2 那类手持展示需要铺屏大字）。
const int kKitTeleSizeMin = 18;
const int kKitTeleSizeMax = 160;
const int kKitTeleSizeDefault = 40;

/// 行距百分比（原型 `min=110 max=220 step=5`）。
const int kKitTeleLhMin = 110;
const int kKitTeleLhMax = 220;
const int kKitTeleLhStep = 5;
const int kKitTeleLhDefault = 155;

/// 文字抖动幅度 px（原型 `min=0 max=8 step=1`；0=不抖）。
const int kKitTeleShakeMin = 0;
const int kKitTeleShakeMax = 8;
const int kKitTeleShakeStep = 1;
const int kKitTeleShakeDefault = 0;

/// 多彩背景档位（原型 `TP_GRADS`；none=用所选背景色）。
const List<({String id, String label, List<int> colors})> kKitTeleGrads = [
  (id: 'none', label: '纯色', colors: []),
  (id: 'candy', label: '糖果', colors: [0xFFA78BFA, 0xFFF472B6]),
  (id: 'dusk', label: '落日', colors: [0xFFFB923C, 0xFFF43F5E]),
  (id: 'mint', label: '薄荷', colors: [0xFF34D399, 0xFF0EA5E9]),
  (id: 'sea', label: '海盐', colors: [0xFF6366F1, 0xFF22D3EE]),
  (id: 'grape', label: '葡萄', colors: [0xFF8B5CF6, 0xFF6366F1]),
];

/// 脏值回落：库里存了不认识的档位时按 none 处理。
({String id, String label, List<int> colors}) kitTeleGrad(Object? id) {
  final v = id is String ? id : 'none';
  return kKitTeleGrads.firstWhere((g) => g.id == v, orElse: () => kKitTeleGrads.first);
}

/// 点一行换一档（原型 `tpGradNext`：按表序循环）。
String kitTeleGradNext(String cur) {
  final ids = [for (final g in kKitTeleGrads) g.id];
  return ids[(ids.indexOf(kitTeleGrad(cur).id) + 1) % ids.length];
}

/// 闪烁半周期占比（原型 `tpBlink 1.1s steps(1)`：前半亮、后半暗）。
const double kKitTeleBlinkHalf = .5;
const double kKitTeleBlinkDim = .12;

/// 闪烁透明度（[phase] 0~1，原型 keyframes 同构）。
double kitTeleBlinkOpacity(double phase) =>
    phase < kKitTeleBlinkHalf ? 1.0 : kKitTeleBlinkDim;

/// 抖动位移（原型 `tpShake .28s`：四角轮转，[phase] 0~1 落在 4 个关键帧上）。
///
/// 返回 `(dx, dy)` 记录而非 `Offset`：域层保持不引 `dart:ui`，与其余
/// `kit_*.dart` 同口径（屏侧自己 `Offset($1, $2)`）。
(double, double) kitTeleShakeOffset({required double phase, required int px}) {
  if (px <= 0) return (0, 0);
  final step = (phase * 4).floor() % 4;
  const signs = [(0.0, 0.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)];
  final s = signs[step];
  return (s.$1 * px, s.$2 * px);
}

/// 闪烁 / 加粗 / 抖动的开关文案（原型 chip 同名）。
String kitTeleFxLabel(String which) => switch (which) {
  'blink' => '闪烁',
  'bold' => '加粗',
  _ => 'LED 点阵',
};

/// 显示方式 toast（原型 `tpMode`）。
String kitTeleModeToast(String mode) =>
    mode == kKitTeleModeStatic ? '显示方式：静止铺屏' : '显示方式：向上滚动';

/// 多彩背景 toast（原型 `tpGradNext`）。
String kitTeleGradToast(String id) => '背景：${kitTeleGrad(id).label}';

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
String kitTeleDirLabel(String dir) => dir == kKitTeleDirLand ? '横屏' : '竖屏';

String kitTeleDirToast(String dir) =>
    dir == kKitTeleDirLand ? '显示方向：横屏（内容转 90°）' : '显示方向：竖屏';

String kitTeleSpeedText(int pxPerSec) => '$pxPerSec px/s';

String kitTeleSizeText(int px) => '$px px';

String kitTeleLhText(int pct) => '$pct%';

String kitTeleShakeText(int px) => '$px px';

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

/// 静止态的垂直居中位移（原型 `tpStatic`：`max(0,(视口高-内容高)/2)`；
/// 内容比视口高时贴顶，交给用户调字号）。
double kitTeleStaticTranslateY({
  required double bodyHeight,
  required double viewportHeight,
}) =>
    ((viewportHeight - bodyHeight) / 2).clamp(0, double.infinity);

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
    required this.mode,
    required this.speed,
    required this.size,
    required this.lh,
    required this.fg,
    required this.bg,
    required this.grad,
    required this.blink,
    required this.bold,
    required this.shake,
    required this.led,
    required this.text,
  });

  final String dir;

  /// 显示方式：滚动（提词）/ 静止（铺屏大字）。
  final String mode;
  final int speed;
  final int size;
  final int lh;
  final String fg;
  final String bg;

  /// 多彩背景档位 id（[kKitTeleGrads]，`none`=用 [bg] 纯色）。
  final String grad;
  final bool blink;
  final bool bold;

  /// 文字抖动幅度 px（0=不抖）。
  final int shake;
  final bool led;
  final String text;

  bool get horizontal => dir == kKitTeleDirLand;

  bool get isStatic => mode == kKitTeleModeStatic;

  /// 多彩背景是否生效（生效时 [bg] 只当文本底色兜底用）。
  bool get gradOn => kitTeleGrad(grad).id != 'none';

  /// 当前档位的渐变色（none 给空表）。
  List<int> get gradColors => kitTeleGrad(grad).colors;

  /// 行距倍数（`TextStyle.height` 直接用）。
  double get lineHeightFactor => lh / 100;

  static String _hex(Object? v, String fallback) =>
      (v is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v))
      ? v.toLowerCase()
      : fallback;

  static KitTeleState decode(Map<String, Object?> d) => KitTeleState(
    dir: d['tpOri'] == kKitTeleDirPort ? kKitTeleDirPort : kKitTeleDirLand,
    mode: d['tpMode'] == kKitTeleModeStatic
        ? kKitTeleModeStatic
        : kKitTeleModeScroll,
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
    grad: kitTeleGrad(d['tpGrad']).id,
    blink: d['tpBlink'] == true,
    bold: d['tpBold'] == true,
    shake: _clamp(
      d['tpShake'],
      kKitTeleShakeDefault,
      kKitTeleShakeMin,
      kKitTeleShakeMax,
      kKitTeleShakeStep,
    ),
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
    String? mode,
    int? speed,
    int? size,
    int? lh,
    String? fg,
    String? bg,
    String? grad,
    bool? blink,
    bool? bold,
    int? shake,
    bool? led,
    String? text,
  }) => KitTeleState(
    dir: dir ?? this.dir,
    mode: mode ?? this.mode,
    speed: speed ?? this.speed,
    size: size ?? this.size,
    lh: lh ?? this.lh,
    fg: fg ?? this.fg,
    bg: bg ?? this.bg,
    grad: grad ?? this.grad,
    blink: blink ?? this.blink,
    bold: bold ?? this.bold,
    shake: shake ?? this.shake,
    led: led ?? this.led,
    text: text ?? this.text,
  );
}

/// 落库结构（`kit_tool_data.tool='tele'`）。
Map<String, Object?> kitTeleEncode(KitTeleState s) => {
  'tpOri': s.dir,
  'tpMode': s.mode,
  'tpSpeed': s.speed,
  'tpSize': s.size,
  'tpLh': s.lh,
  'tpFg': s.fg,
  'tpBg': s.bg,
  'tpGrad': s.grad,
  'tpBlink': s.blink,
  'tpBold': s.bold,
  'tpShake': s.shake,
  'tpLed': s.led,
  'tpText': s.text,
};
