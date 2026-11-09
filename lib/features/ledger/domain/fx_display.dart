/// C10 · 展示层币种 ＋ 汇率快照 ＋ 报表折算（纯函数、零网络）。
///
/// 三不动（竞品补全清单 C10 验收口径）：
/// - **不动账本模型**：本层不 import `ledger_txn.dart`，只吃/吐数值；
/// - **不改历史流水本币口径**：`ledger_calc.money()` / `mStat()` 等聚合仍输出本币，
///   折算只发生在「展示值」这一层，回写不进任何流水行；
/// - **折算可关**：[convertFx] 的 [enabled]=false 恒等返回原值。
///
/// 汇率快照由用户本地手填 / 本机 KV 注入，零新增网络目的地、零在线取价。
library;

/// 汇率快照：[base] 为本币代码，rates[code] = 1 单位 base 折多少 code。
class FxSnapshot {
  const FxSnapshot({
    required this.base,
    required this.rates,
    this.asOf = '',
  });

  final String base;
  final Map<String, double> rates;

  /// 快照基准日（YYYY-MM-DD，纯展示；空＝未标注）。
  final String asOf;

  /// 取 from→to 的换算率；基准不符 / 缺项 / 非法一律 null（不臆造汇率）。
  double? rate(String from, String to) {
    if (from != base) return null; // 快照基准不符＝不算交叉汇率
    if (from == to) return 1.0;
    final r = rates[to];
    if (r == null || !r.isFinite || r <= 0) return null;
    return r;
  }
}

/// 单值折算：可关 / 缺汇率 / 基准不符 / 同币种 一律原样返回（本币口径不变）。
double convertFx(
  double amountLocal,
  FxSnapshot snap, {
  required String base,
  required String target,
  bool enabled = true,
}) {
  if (!enabled || base == target) return amountLocal;
  final r = snap.rate(base, target);
  if (r == null) return amountLocal;
  return amountLocal * r;
}

/// 展示用币种金额（不改 `ledger_calc.money()` 的 ¥ 口径；只在展示层加币种码）。
String formatCurrency(double v, String code, {bool hide = false}) {
  if (hide) return '$code •••••';
  final sign = v < 0 ? '-' : '';
  return '$sign$code ${v.abs().toStringAsFixed(2)}';
}

/// 报表折算：只折算聚合值（exp/inc/net），不碰任何流水行、不回写模型。
({double exp, double inc, double net}) convertReport(
  double expLocal,
  double incLocal,
  FxSnapshot snap, {
  required String base,
  required String target,
  bool enabled = true,
}) {
  final e = convertFx(expLocal, snap,
      base: base, target: target, enabled: enabled);
  final i = convertFx(incLocal, snap,
      base: base, target: target, enabled: enabled);
  return (exp: e, inc: i, net: i - e);
}
