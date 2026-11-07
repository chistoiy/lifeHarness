import 'ledger_txn.dart';

/// L12 搜索筛选纯函数层（原型 index-ledger.html fs/fsResults/fsRun 5322~5355 行
/// 逐条对译；批3b）。计划书 §4「条件即时组合过滤（AND），结果合计实时；标签
/// 单选切换」+ 九·补1 双账本回归（结果随 bk 过滤）。
class LedgerSearchQuery {
  const LedgerSearchQuery({
    this.kw = '',
    this.min,
    this.max,
    this.catId,
    this.acctId,
    this.tag,
    this.from,
    this.to,
  });

  /// 关键词（原型 fs.kw：命中 备注 n 或 分类名 lcatN(cat) 任一）。
  final String kw;
  final double? min;
  final double? max;
  final int? catId;
  final int? acctId;

  /// 标签单选（原型 fs.tag：'' 或唯一标签名；再点同 chip 取消）。
  final String? tag;

  /// 日期区间 'YYYY-MM-DD'（含端点，原型 t.d 小于 from / 大于 to 剔除）。
  final String? from;
  final String? to;
}

/// 原型 fsResults（5341~5350 行）逐条件对译，全部 AND 组合：
/// - bk：`t.bk!==curBook` 剔除（5341，双账本回归）；
/// - kw：备注与分类名双 contains（5342，分类名经 [catName]，未知回落「其他」
///   同 lcatN 5331 的 `||'其他'`）；
/// - min：expense 比 amt、其余比 |amt|（5343，含等号：`<` 才剔除）；
/// - max：**仅 expense 生效**（5344 `if(fs.max&&isEx&&...)`，income 大额不误杀）；
/// - cat：等值匹配（5345，不限收支树——与下拉仅列支出大类是原型既有语义）；
/// - acct：转入转出双向命中（5346 `t.a||t.to`）；
/// - tag：tags 包含（5347）；from/to：字符串日期比较含端点（5348~5349）；
/// - kind 白名单 expense/income/transfer/refund（5350，adjust 不进搜索结果）；
/// - 排序 date DESC、同日 id DESC（5350 `a.d<b.d?1:...:b.id-a.id`）。
List<LedgerTxn> ledgerSearch({
  required Iterable<LedgerTxn> txns,
  required int bk,
  required LedgerSearchQuery q,
  required String Function(int? catId) catName,
}) {
  final out = txns.where((t) {
    if (t.bk != bk) return false;
    if (q.kw.isNotEmpty &&
        !t.note.contains(q.kw) &&
        !catName(t.catId).contains(q.kw)) {
      return false;
    }
    final isEx = t.kind == LedgerTxn.kExpense;
    final min = q.min;
    if (min != null && (isEx ? t.amt < min : t.amt.abs() < min)) return false;
    final max = q.max;
    if (max != null && isEx && t.amt > max) return false;
    final catId = q.catId;
    if (catId != null && t.catId != catId) return false;
    final acctId = q.acctId;
    if (acctId != null && t.accountId != acctId && t.toAccountId != acctId) {
      return false;
    }
    final tag = q.tag;
    if (tag != null && !t.tags.contains(tag)) return false;
    final from = q.from;
    if (from != null && t.date.compareTo(from) < 0) return false;
    final to = q.to;
    if (to != null && t.date.compareTo(to) > 0) return false;
    return t.kind == LedgerTxn.kExpense ||
        t.kind == LedgerTxn.kIncome ||
        t.kind == LedgerTxn.kTransfer ||
        t.kind == LedgerTxn.kRefund;
  }).toList();
  out.sort((a, b) =>
      a.date != b.date ? b.date.compareTo(a.date) : b.id.compareTo(a.id));
  return out;
}

/// 原型 fsRun 合计（5352 行取证：`ts.filter(kind==='expense')` 与
/// `filter(kind==='income')` 各自 fold，**无 nb 剔除条件**——「不计入」行参与
/// 搜索结果合计，与 mStat（剔 nb）口径不同，属原型明示差异）；
/// refund/transfer 不计入两侧合计。
({int n, double exp, double inc}) ledgerSearchTotals(List<LedgerTxn> ts) {
  final exp = ts
      .where((t) => t.kind == LedgerTxn.kExpense)
      .fold<double>(0, (s, t) => s + t.amt);
  final inc = ts
      .where((t) => t.kind == LedgerTxn.kIncome)
      .fold<double>(0, (s, t) => s + t.amt);
  return (n: ts.length, exp: exp, inc: inc);
}
