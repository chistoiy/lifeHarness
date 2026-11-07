/// 商户名 → 分类的本地学习（竞品补全清单 C03 · 批1 子批 A）。
///
/// 口径改判：清单原写「本地规则表＋DB 迁移」，本批改为**从既有流水学习**
/// （`LedgerTxn.merchant ?? note` → `catId`），零新表、零 UI、零迁移。
/// 三条红线：
/// ① 只收「同一归一化商户名出现 ≥ [minHits] 次且分类一致」的规则——
///    把一次误分类固化成规格，就是「从实现反推断言」的同族错误；
/// ② 历史**只读不回写**，规则随用户后续分类自然演进，天然不回溯历史；
/// ③ 预填不是定案：导入预览里 `catOverride` 永远优先，用户点一下即可改。
library;

/// 一条历史样本：`name` 取商户名（缺失时回落备注），`catId` 为该笔最终分类。
class MerchantSample {
  const MerchantSample(this.name, this.catId);
  final String name;
  final int? catId;
}

/// 归一化：去所有空白与全角空格、去括号补充说明、去尾部编号、转小写。
/// 目的是让「星巴克(南京西路店)」「星巴克 001」「星巴克」命中同一条规则。
String normalizeMerchant(String raw) {
  var s = raw.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'[\s\u3000]+'), '');
  s = s.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '');
  s = s.replaceAll(RegExp(r'[-—_·].*$'), '');
  s = s.replaceAll(RegExp(r'\d+$'), '');
  return s;
}

/// 从历史流水学习规则。返回「归一化商户名 → 分类 id」。
///
/// [minHits] 默认 2；分类出现并列第一时不采纳（宁可不猜，不猜错）。
Map<String, int> learnMerchantRules(
  Iterable<MerchantSample> history, {
  int minHits = 2,
}) {
  final counts = <String, Map<int, int>>{};
  for (final h in history) {
    final cat = h.catId;
    if (cat == null) continue;
    final key = normalizeMerchant(h.name);
    if (key.isEmpty) continue;
    final m = counts.putIfAbsent(key, () => <int, int>{});
    m[cat] = (m[cat] ?? 0) + 1;
  }
  final out = <String, int>{};
  counts.forEach((key, m) {
    if (m.isEmpty) return;
    final sorted = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    if (top.value < minHits) return;
    if (sorted.length > 1 && sorted[1].value == top.value) return;
    out[key] = top.key;
  });
  return out;
}

/// 按对方/商户名取建议分类；无规则返回 null（调用方回落既有 `mapBillCat`）。
int? suggestCategory(String counterparty, Map<String, int> rules) =>
    rules[normalizeMerchant(counterparty)];
