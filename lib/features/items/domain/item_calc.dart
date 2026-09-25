/// 每日成本引擎（HG-E1 全实算：成本池/日均/双口径/止损触线/决算）。
///
/// 直线法 `(价＋Σ二次付费−Σ回收残值) ÷ 持有天数`；
/// 按次均摊＝成本池÷计划次数，双口径并列（每次成本 + 近30天频次折算日均）；
/// 预估止损＝直线折旧净值曲线 + 止损线（购入价 X%）预估触线日，接近止损线提示。
library;

import 'item_models.dart';

DateTime parseYmd(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String fmtYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String fmtY(num v) {
  final s = v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(2);
  final neg = s.startsWith('-');
  final body = neg ? s.substring(1) : s;
  final parts = body.split('.');
  final buf = StringBuffer();
  for (var i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
    buf.write(parts[0][i]);
  }
  return '${neg ? '-¥' : '¥'}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// 持有天数（购入日→今天，至少 1）。
int daysHeld(String buyDate, DateTime today) {
  final b = parseYmd(buyDate);
  final diff = DateTime(today.year, today.month, today.day)
      .difference(DateTime(b.year, b.month, b.day))
      .inDays;
  return diff < 1 ? 1 : diff;
}

double extraSum(ItemProfile it) => it.events
    .where((e) => e.kind == kEvExtra)
    .fold<double>(0, (s, e) => s + e.amount);

double recycleSum(ItemProfile it) => it.events
    .where((e) => e.kind == kEvRecycle)
    .fold<double>(0, (s, e) => s + e.amount);

/// 成本池（净值）＝购入价 + 二次付费 − 回收残值。
double poolOf(ItemProfile it) => it.price + extraSum(it) - recycleSum(it);

/// 总投入（含二次付费，不含回收）。
double investedOf(ItemProfile it) => it.price + extraSum(it);

/// 按次口径：每次成本＝成本池 ÷ 计划次数。
double perUseCost(ItemProfile it) {
  final plan = it.planUnits ?? 0;
  return plan <= 0 ? 0 : poolOf(it) / plan;
}

double usedTotal(ItemProfile it) =>
    it.usages.fold<double>(0, (s, u) => s + u.qty);

/// 近 30 天用量（含今天，按 day 字符串窗口）。
double usedLast30(ItemProfile it, DateTime today) {
  final from = fmtYmd(today.subtract(const Duration(days: 29)));
  final to = fmtYmd(today);
  return it.usages
      .where((u) => u.day.compareTo(from) >= 0 && u.day.compareTo(to) <= 0)
      .fold<double>(0, (s, u) => s + u.qty);
}

/// 当前日均成本（计费中条目；冻结条目返回 null＝停止计费）。
double? costPerDay(ItemProfile it, DateTime today) {
  if (!it.billing) return null;
  switch (it.mode) {
    case ItemMode.times:
      return perUseCost(it) * usedLast30(it, today) / 30;
    case ItemMode.day:
    case ItemMode.stop:
      return poolOf(it) / daysHeld(it.buyDate, today);
  }
}

/// 今日合计持有成本（全计费中条目求和；仪表盘持有成本卡同口径）。
double totalDailyCost(List<ItemProfile> items, DateTime today) =>
    items.fold<double>(0, (s, it) => s + (costPerDay(it, today) ?? 0));

/// 止损预估信息（净值曲线/止损线/触线日/接近提示）。
class StopInfo {
  const StopInfo({
    required this.net,
    required this.line,
    required this.lineDate,
    required this.expired,
  });
  final double net; // 当前预估净值
  final double line; // 止损线金额
  final DateTime lineDate; // 预估触线日
  final bool expired; // 净值已跌破线

  /// 接近止损线（净值 < 线×1.2）→ 提示择机回收/转卖。
  bool get near => net < line * 1.2;
}

StopInfo stopInfoOf(ItemProfile it, DateTime today) {
  final yrs = (it.expectedYears ?? 5).toDouble();
  final pct = it.stopPct / 100.0;
  final days = daysHeld(it.buyDate, today);
  final net =
      it.price * (1 - days / (yrs * 365)).clamp(0.0, 1.0).toDouble();
  final line = it.price * pct;
  final lineDate =
      parseYmd(it.buyDate).add(Duration(days: (yrs * 365 * (1 - pct)).round()));
  return StopInfo(net: net, line: line, lineDate: lineDate, expired: net <= line);
}

/// 决算口径（冻结时全周期最终数值）。
class SettleInfo {
  const SettleInfo({
    required this.invested,
    required this.days,
    required this.residue,
    required this.netHold,
    required this.realDaily,
    required this.recoverRate,
    required this.auditCount,
  });
  final double invested;
  final int days;
  final double residue;
  final double netHold;
  final double realDaily;
  final int recoverRate; // 回收率 %
  final int auditCount;
}

SettleInfo settleOf(ItemProfile it, DateTime today) {
  final pool = poolOf(it);
  final days = daysHeld(it.buyDate, today);
  final inv = investedOf(it);
  return SettleInfo(
    invested: inv,
    days: days,
    residue: recycleSum(it),
    netHold: pool,
    realDaily: pool / days,
    recoverRate: inv <= 0 ? 0 : (recycleSum(it) / inv * 100).round(),
    auditCount: it.events.length,
  );
}

/// 冻结/留用判定：状态→billing（已报废与转出停计）。
bool billingForStatus(String status) =>
    status != kItemStatusScrapped && status != kItemStatusRecycleOut;

/// 闲置提示判定（列表行「⚠ 建议回收」后缀：状态闲置即提示，对齐原型）。
bool idleWarn(ItemProfile it) => it.status == kItemStatusIdle && it.billing;
