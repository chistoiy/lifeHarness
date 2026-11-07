/// 思维导图节点菜单的**频次档**（批P7 · 2026-10-21）。
///
/// 动因（`评估结论-20261019-思维导图连接器与质感补强.md` §5 第 6 条的后手）：
/// 节点菜单到批P3 已 17 项、「添/连/改/换/剪/删」六组固定排，而脑图高频动作其实
/// 只有两三枚（加子级、编辑标题、删）。项数下不来（能力都要留着），那就把**高频
/// 顶上去**——分组与组序一律不动（「删」永远在最后、「上移/下移」永远并排），
/// 只让**排在组头的非并排项**按用过的次数整体前移。
///
/// 三条硬口径：
/// 1. **不记也不排危险项与导航项**（[mmSortPinned]）：删除/断开/剪贴板与
///    收起/展开/归位都不参与——一个是重手误触代价太高，一个是纯视图态，
///    都该待在固定位置让人闭着眼能摸到。它们连同全组随组走。
/// 2. **没足够样本一律回基线序**（`mmRankKeys`）：新装或低频用户看到的仍是
///    设计稿那一份次序，不会因为点了两下就整体洗牌。
/// 3. **同票保持基线相对序**（稳定排序）：所以计数全为 0 时输出与基线**逐项相等**
///    ——这条是「没样本 ⇒ 零变化」的守护点，用例按它断。
///
/// 用 `shared_preferences` 单 key 存（同 `MmStyleStore`/`MmLayoutStore` 先例：
/// 每图一套的隔离点在那里；这里刻意**全图共用一份**——用户的手感是跨图一致的，
/// 按图分开会让新图永远从零开始学）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 基线次序（＝设计稿里 `_showNodeMenu` 的组序与组内序）。
///
/// 只收**组内非并排**的可排项（并排项如「上移/下移」「收起/展开」「粘贴两枚」
/// 是成对语义，拆开就没了对照，见 [mmSortPinned]）。
const List<List<String>> mmMenuBaselineGroups = [
  ['child', 'sibling'],
  ['connect', 'detach'],
  ['edit', 'bind', 'fold', 'collapse', 'expand'],
  ['reset'],
  ['up', 'down'],
  ['copy', 'cut', 'pasteSib', 'pasteChild'],
  ['del'],
];

/// 不参与频次排序的键：危险项（删/断/剪贴板）与纯视图态（收/展/归位）。
///
/// 单列一份而不是在 [mmMenuBaselineGroups] 里标——这份清单同时是**白名单校验**：
/// `mmRankKeys` 只认「在基线里、且不在此表」的键，陌生键与置顶键都留在原位。
const Set<String> mmSortPinned = {
  'detach', // 断开并移到根层级：误触＝整枝搬家
  'reset', // 归位到自动布局：清掉手工拖的落点
  'collapse', // 收起整枝
  'expand', // 展开全部
  'up', // 与 down 并排成对
  'down',
  'copy', // 剪贴板四枚：跨图粘贴的状态依赖，位置要稳
  'cut',
  'pasteSib',
  'pasteChild',
  'del', // 删除：永远在最后一组最后一枚
};

/// 参与排序的键（基线顺序，已剔 [mmSortPinned]）。
List<String> get mmSortableKeys => [
      for (final g in mmMenuBaselineGroups)
        for (final k in g)
          if (!mmSortPinned.contains(k)) k,
    ];

/// 每档最少样本数：不足就**回基线序**。
///
/// 取值理由：菜单一次操作只能点一枚，3 次才算「用过三次」；低于 3 时一次误点
/// 就足以让菜单换脸，观感是「怎么跟刚才不一样」。
const int mmRankMinSamples = 3;

/// 纯函数：按计数重排一组键（**不含**判闸，判闸在 [mmRankKeys]）。
///
/// 算法＝**插空**，不是整体排序：置顶项（[mmSortPinned]）连相对序都不动，
/// 可排项按「票数降序、同票守基线」排好后，顺序填进那几格非置顶槽位。
///
/// 为什么不是「带权整体排序」：那样一旦有项拿到票，零次的项会越过置顶项
/// （实测：`edit` 点 3 次就把零次的「归位」挤到第 3 位之后），菜单会长成
/// 「前面一堆动过、后面一堆没动过」的两截。插空法保证**动的只有可排槽位**，
/// 置顶项的屏幕位置一次都不变——这也是「删除永在末位」的机械保证。
List<String> mmOrderByCount(List<String> keys, Map<String, int> counts) {
  final n = keys.length;
  // **只做插空**：置顶项一个位置都不动（连相对序也不动），可排项按
  // 「票数降序、同票守基线」排好后，顺序填进那几格非置顶的槽位。
  final pinned = <int>{};
  final sortable = <int>[];
  for (var i = 0; i < n; i++) {
    if (mmSortPinned.contains(keys[i])) {
      pinned.add(i);
    } else {
      sortable.add(i);
    }
  }
  final order = List<int>.of(sortable)
    ..sort((a, b) {
      final c = (counts[keys[b]] ?? 0).compareTo(counts[keys[a]] ?? 0);
      return c != 0 ? c : a.compareTo(b); // 同票守基线相对序
    });
  final out = List<String>.filled(n, '');
  for (final i in pinned) {
    out[i] = keys[i];
  }
  for (var k = 0; k < sortable.length; k++) {
    out[sortable[k]] = keys[order[k]];
  }
  return out;
}

/// 判闸：样本够才给新序，不够原样返回 [keys]（**同一个 List 实例语义**上等价，
/// 但调用侧按值比较即可）。[counts] 里置顶键的值会被忽略。
List<String> mmRankKeys(List<String> keys, Map<String, int> counts) {
  var total = 0;
  for (final k in keys) {
    if (mmSortPinned.contains(k)) continue;
    total += counts[k] ?? 0;
  }
  if (total < mmRankMinSamples) return List.of(keys);
  return mmOrderByCount(keys, counts);
}

// ======================== prefs 存取 ========================

/// 频次存储：单 key `lh.mm_menu_hits`，装 `键 → 次数` 的 JSON map（全图共用）。
///
/// 写入口唯一是 [bump]（画布菜单分发那一下调）；读入口唯一是 [load]。
/// 不做「按时间衰减」：菜单十七项里有十一项被置顶，真正会挪的只有 6 枚，
/// 衰减的收益（半年前的习惯自动淡出）抵不过「同一天内点数变了菜单就跳」的风险。
class MmMenuUsageStore {
  const MmMenuUsageStore(this.prefs);

  final SharedPreferences prefs;

  static const String key = 'lh.mm_menu_hits';

  /// 单键计数上限：防止脏数据/自动化刷出天文数字（封了上界，计数比较不会退化成大数运算）。
  static const int cap = 9999;

  /// 读全表：损坏 JSON / 类型不符一律返回空表（同 `MmStyleStore.load` 口径——
  /// 用户数据坏了不许炸菜单，回基线序就是了）。
  Map<String, int> load() {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, int>{};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // catch-ok: prefs 里的计数 JSON 是本模块自己写的，损坏只可能来自外部改
      // 文件/旧版残留——按「还没统计过」回落（走基线序），不炸页面。
      return <String, int>{};
    }
    if (decoded is! Map) return <String, int>{};
    final out = <String, int>{};
    decoded.forEach((k, v) {
      if (k is! String) return;
      final n = v is int ? v : (v is num ? v.toInt() : 0);
      if (n <= 0) return;
      out[k] = n > cap ? cap : n;
    });
    return out;
  }

  /// 记一次点击（只认基线里、且非置顶的键——其余键**一个字都不写**）。
  ///
  /// 返回是否真写了：未登记键/置顶键返回 false，调用侧可据此免掉一次 IO。
  Future<bool> bump(String actionKey) async {
    if (!mmSortableKeys.contains(actionKey)) return false;
    final all = load();
    final next = (all[actionKey] ?? 0) + 1;
    all[actionKey] = next > cap ? cap : next;
    return prefs.setString(key, jsonEncode(all));
  }

  /// 清空统计（回基线序）。当前无界面入口——留给「重置」类设置将来的挂点，
  /// 也让用例能干净隔离。
  Future<void> clear() => prefs.remove(key);
}

/// 基线键全集（= 各组取并）。
Set<String> get mmMenuBaselineKeys =>
    {for (final g in mmMenuBaselineGroups) ...g};

/// 画布菜单的**真实**组序（契约钉在这里，用例比对着它断）。
///
/// 为什么不从 `_showNodeMenu` 里反推：那是 widget 闭包，用例拿不到；
/// 在两处各写一份又必然漂移。所以把**次序本身**提到域层当数据，画布照它渲染、
/// 用例照它断言——新增菜单项时只要改这一处，`mm_menu_rank_test` 会立刻指出
/// 「菜单多了/少了哪一枚」（该用例逐项比对基线表与这里）。
const List<List<String>> mmMenuBaselineFromCanvas = [
  ['child', 'sibling'],
  ['connect', 'detach'],
  ['edit', 'bind', 'fold', 'collapse', 'expand'],
  ['reset'],
  ['up', 'down'],
  ['copy', 'cut', 'pasteSib', 'pasteChild'],
  ['del'],
];
