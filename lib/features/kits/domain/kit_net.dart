/// 小工具合集 · 网络类工具纯计算（Ping / 网络测速 · 批3）。
///
/// 口径（计划 §4 红线）：这两件都是**模拟网络层**——与原型 `pingGo` / `spdGo`
/// 同源，逐条复刻其发包节奏、丢包概率、延迟与抖动分布，**不发真实请求**；
/// 真出站只发生在 AI API 验证屏。随机源一律参数注入，用例用
/// `math.Random(seed)` 复现，禁真实异步 I/O。
library;

import 'dart:math' as math;

/// 发包节奏：每 420ms 一行（原型 `setInterval(..., 420)`）。
const int kKitPingTickMs = 420;

/// 丢包概率 7%（原型 `roll<.07`）。
const double kKitPingLossRate = .07;

/// 次数区间（原型 `Math.max(1,Math.min(50,...))`）。
const int kKitPingMinTimes = 1;
const int kKitPingMaxTimes = 50;

/// 超时区间（秒，原型 `min=1 max=10`）。
const int kKitPingMinTimeout = 1;
const int kKitPingMaxTimeout = 10;

/// 一次发包结果（[ok]=false 即请求超时）。
class KitPingLine {
  const KitPingLine({
    required this.seq,
    required this.ok,
    required this.ms,
    required this.ttl,
    required this.timeoutS,
  });

  final int seq;
  final bool ok;

  /// 往返毫秒（超时时为 0，不参与统计）。
  final double ms;
  final int ttl;
  final int timeoutS;

  /// 终端行文案（原型 `seq=1  ttl=57  time=23.4ms` / `seq=2 请求超时（>2s）`）。
  String get text => ok
      ? 'seq=$seq  ttl=$ttl  time=${ms.toStringAsFixed(1)}ms'
      : 'seq=$seq 请求超时（>${timeoutS}s）';
}

/// 基准延迟（原型 `12+Math.random()*40`，整轮共用一个基准）。
double kitPingBase(math.Random rnd) => 12 + rnd.nextDouble() * 40;

/// 探测一次（**按固定顺序**消耗随机数：丢包骰 → 延迟抖动 → TTL）。
KitPingLine kitPingProbe({
  required int seq,
  required int timeoutS,
  required double base,
  required math.Random rnd,
}) {
  if (rnd.nextDouble() < kKitPingLossRate) {
    return KitPingLine(seq: seq, ok: false, ms: 0, ttl: 0, timeoutS: timeoutS);
  }
  final ms = math.max(1.0, base + (rnd.nextDouble() - .5) * base * 1.1);
  return KitPingLine(
    seq: seq,
    ok: true,
    ms: ms,
    ttl: 54 + rnd.nextInt(8),
    timeoutS: timeoutS,
  );
}

/// 模拟解析出的 IPv4（原型只在 `39.156.` / `110.242.` 两段里凑后两节）。
String kitPingIp(math.Random rnd) {
  final head = rnd.nextDouble() < .5;
  return '${head ? '39.156' : '110.242'}.${10 + rnd.nextInt(200)}.${10 + rnd.nextInt(200)}';
}

/// 首行（原型 `PING host · 模拟解析 → ip · 56 字节包 · 超时 2s`）。
String kitPingHead(String host, String ip, int timeoutS) =>
    'PING $host · 模拟解析 → $ip · 56 字节包 · 超时 ${timeoutS}s';

/// 累计统计（不可变；[kitPingApply] 逐行累加，min/max 只记成功样本）。
class KitPingStats {
  const KitPingStats({
    this.sent = 0,
    this.recv = 0,
    this.lost = 0,
    this.sumMs = 0,
    this.minMs = 0,
    this.maxMs = 0,
    this.jitMs = 0,
    this.lastMs = 0,
  });

  final int sent;
  final int recv;
  final int lost;
  final double sumMs;
  final double minMs;
  final double maxMs;

  /// 相邻 RTT 差值之和（抖动 = 该和 ÷ (recv-1)，原型同口径）。
  final double jitMs;
  final double lastMs;

  bool get empty => sent == 0;
  double get avgMs => recv == 0 ? 0 : sumMs / recv;
  double get jitterMs => recv > 1 ? jitMs / (recv - 1) : 0;
  int get lossPct => sent == 0 ? 0 : (lost * 100 / sent).round();

  /// 丢包率是否该标红（原型 `lossPct>10` 用玫红）。
  bool get lossWarn => lossPct > 10;
}

/// 把一行结果并进统计（[s] 原样返回不参与计数的行不存在：每行必计 sent）。
KitPingStats kitPingApply(KitPingStats s, KitPingLine l) {
  if (!l.ok) {
    return KitPingStats(
      sent: s.sent + 1,
      recv: s.recv,
      lost: s.lost + 1,
      sumMs: s.sumMs,
      minMs: s.minMs,
      maxMs: s.maxMs,
      jitMs: s.jitMs,
      lastMs: s.lastMs,
    );
  }
  return KitPingStats(
    sent: s.sent + 1,
    recv: s.recv + 1,
    lost: s.lost,
    sumMs: s.sumMs + l.ms,
    minMs: s.recv == 0 ? l.ms : math.min(s.minMs, l.ms),
    maxMs: math.max(s.maxMs, l.ms),
    jitMs: s.lastMs > 0 ? s.jitMs + (l.ms - s.lastMs).abs() : s.jitMs,
    lastMs: l.ms,
  );
}

/// 四格统计（值 + 标签，顺序=原型 收/发 · 平均 ms · min/max · 丢包率；
/// 未发过包时四格一律占位（原型 `pingStatSeed` 的「—」）。
List<(String, String)> kitPingCells(KitPingStats s) {
  if (s.empty) {
    return const [
      ('—', '收/发'),
      ('—', '平均 ms'),
      ('— / —', 'min / max'),
      ('—', '丢包率'),
    ];
  }
  return [
    ('${s.recv}/${s.sent}', '收/发'),
    (s.recv == 0 ? '—' : s.avgMs.toStringAsFixed(1), '平均 ms'),
    (
      s.recv == 0
          ? '— / —'
          : '${s.minMs.toStringAsFixed(1)} / ${s.maxMs.toStringAsFixed(1)}',
      'min / max',
    ),
    ('${s.lossPct}%', '丢包率'),
  ];
}

/// 分享文案（原型 `KIT_SHARE_TXT`）。
String kitPingShare(String host, KitPingStats s) =>
    'PING $host · 发 ${s.sent} 收 ${s.recv} · 平均 ${s.avgMs.toStringAsFixed(1)}ms'
    ' · 丢包 ${s.lossPct}% · 抖动 ${s.jitterMs.toStringAsFixed(1)}ms';

// ============================ 网络测速（模拟） ============================

/// 测速节点（原型三枚 chips，切换即记入结果）。
const List<String> kKitSpeedNodes = ['电信·杭州', '联通·北京', '移动·广州'];

/// 爬坡时长与刷新节奏（原型 3200ms / 70ms）。
const int kKitSpeedRampMs = 3200;
const int kKitSpeedTickMs = 70;

/// 仪表满量程（原型 `target/200*360`）。
const double kKitSpeedGaugeMax = 200;

/// 历史留档上限 5 次（原型 `KITS.spd.slice(0,5)`）。
const int kKitSpeedHistMax = 5;

/// 一次测速结果（[down]/[up]=Mbps，[pingMs]/[jitterMs] 取整口径同原型）。
class KitSpeedResult {
  const KitSpeedResult({
    required this.node,
    required this.down,
    required this.up,
    required this.pingMs,
    required this.jitterMs,
    required this.ts,
  });

  final String node;
  final double down;
  final double up;
  final int pingMs;
  final int jitterMs;
  final int ts;

  Map<String, Object?> toJson() => {
    'n': node,
    'd': down,
    'u': up,
    'p': pingMs,
    'j': jitterMs,
    'ts': ts,
  };

  static KitSpeedResult? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = j['n'];
    final d = j['d'];
    if (n is! String || d is! num) return null;
    return KitSpeedResult(
      node: n,
      down: d.toDouble(),
      up: (j['u'] as num?)?.toDouble() ?? 0,
      pingMs: (j['p'] as num?)?.round() ?? 0,
      jitterMs: (j['j'] as num?)?.round() ?? 0,
      ts: (j['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 目标下载速率（原型 `40+Math.random()*160`，即 40~200 Mbps）。
double kitSpeedTarget(math.Random rnd) => 40 + rnd.nextDouble() * 160;

/// 爬坡过程中仪表显示值（原型 `target*p*(.82+rnd*.36)`，夹到 ≥0）。
double kitSpeedRampValue({
  required double progress,
  required double target,
  required math.Random rnd,
}) => math.max(0.0, target * progress * (.82 + rnd.nextDouble() * .36));

/// 收尾：上传 ≈ 下载 ×(0.12~0.22)、延迟 8~48ms、抖动 0~20ms（原型同分布）。
KitSpeedResult kitSpeedFinish({
  required String node,
  required double target,
  required int ts,
  required math.Random rnd,
}) => KitSpeedResult(
  node: node,
  down: double.parse(target.toStringAsFixed(1)),
  up: double.parse((target * (.12 + rnd.nextDouble() * .1)).toStringAsFixed(1)),
  pingMs: (8 + rnd.nextDouble() * 40).round(),
  jitterMs: (rnd.nextDouble() * 20).round(),
  ts: ts,
);

/// 环形仪表扫过角度（0~360，超量程钉满圈）。
double kitSpeedGaugeAngle(double mbps) =>
    math.min(360.0, mbps / kKitSpeedGaugeMax * 360.0);

/// 完成后的说明行（原型 `#spdMsg`）。
String kitSpeedMsg(KitSpeedResult r) =>
    '下载 ${r.down.toStringAsFixed(1)} · 上传 ${r.up.toStringAsFixed(1)} Mbps'
    ' · 延迟 ${r.pingMs}ms · 抖动 ${r.jitterMs}ms';

/// 分享文案（原型 `KIT_SHARE_TXT`）。
String kitSpeedShare(KitSpeedResult r) =>
    '测速 ${r.node} · 下载 ${r.down.toStringAsFixed(1)}Mbps'
    ' / 上传 ${r.up.toStringAsFixed(1)} · 延迟 ${r.pingMs}ms';

/// 新结果插到表头并裁到 5 条（原型 unshift + slice）。
List<KitSpeedResult> kitSpeedPush(
  List<KitSpeedResult> hist,
  KitSpeedResult r,
) => [r, ...hist].take(kKitSpeedHistMax).toList();

/// 对比标记：首条相对上一条的下载差 → ▲ / ▼（原型 `SPD_CMP && i==0`）。
String? kitSpeedDelta(List<KitSpeedResult> hist) {
  if (hist.length < 2) return null;
  return hist[0].down >= hist[1].down ? '▲' : '▼';
}

/// 测速留档进 `kit_tool_data.tool='speed'` 的 JSON（键名与原型 `KITS.spd` 同）。
Map<String, Object?> kitSpeedEncode(List<KitSpeedResult> hist) => {
  'spd': [for (final r in hist) r.toJson()],
};

List<KitSpeedResult> kitSpeedDecode(Map<String, Object?> d) {
  final raw = d['spd'];
  if (raw is! List) return const [];
  final out = <KitSpeedResult>[];
  for (final e in raw) {
    final r = KitSpeedResult.fromJson(e);
    if (r != null) out.add(r);
  }
  return out;
}
