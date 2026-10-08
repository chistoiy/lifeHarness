import 'dart:math' as math;

import 'health_models.dart';

/// 症状规格单源（批3.5a · 事实源＝`tools/health/v2_pages.html` `#p-symptom` ＋
/// `tools/health/v2_js.js` 的 `syRender`/`syDur`/`syColor`/`syCloud`/`syEnd`/`sySave`）。
///
/// 屏上六块（发作卡·疼痛直方图·部位筛选·高频词云·流水·录入弹层）**都从这里取读数与文案**，
/// 不在页面与弹层两处各写一遍判据。四条口径：
/// · 疼痛是 0~10 的整数档，色带是**六档渐变**（`floor(l/2)` 夹紧 5），文案才归三档（轻/中/重）——
///   需求 182 行的「三档着色」按原型实态实现，偏离登记在批3.5 工单 §2；
/// · 部位多选**全量存**（库里 `,` 连接），筛选按包含匹配；原型只取第一枚，本实现不丢用户选的其余部位；
/// · 词云只吃**长度 >1** 的词（单字与空串进不了榜），源＝症状名＋感受描述＋诱发因素，取前 18；
/// · 「标记结束」＝`ongoing` 落下 **且** 持续时长 +15 分钟（原型 `syEnd` 的提示条原话），不是只清开关。

/// 常用症状十枚种子（原型 `HP.syNames` 原序）；用户自定义的名字另存 prefs，展示时接在后面。
const List<String> symSeedNames = [
  '头痛', '头晕', '关节痛', '乏力', '失眠', '恶心', '皮疹', '腹痛', '胸闷', '咳嗽',
];

/// 发生部位七枚（原型 `HP.parts` 原序）；筛选行的「全部」是第 0 枚，由页面自己铺。
const List<String> symParts = ['头部', '胸腹', '腰背', '四肢', '关节', '皮肤', '全身'];

/// 疼痛色带六档（原型 `syColor` 的表，色值取 tailwind emerald→red 原色）。
const List<int> symPainRamp = [
  0xFF10B981, 0xFF84CC16, 0xFFEAB308, 0xFFF59E0B, 0xFFF97316, 0xFFEF4444,
];

/// 持续时长滚轮档位（原型 `hNums(5,1440,5)`）：5 分钟一档、上限 24 小时，**档位集合就是可选集合**。
const int symDurLo = 5;
const int symDurStep = 5;
const int symDurCount = 288; // (1440-5)/5 + 1

/// 单条症状的照片上限（需求 182 行「照片最多 4 张」）。
const int symPhotoMax = 4;

/// 还能不能加一张（弹层的「＋格」显隐与点格守卫同吃这一句，两处不各写一遍）。
bool symCanAddPhoto(int have) => have < symPhotoMax;

/// 档位 → 色带下标（原型 `Math.min(5, Math.floor(l/2))`，越界先夹 0~10）。
int symColorIndex(int level) => (math.max(0, math.min(10, level)) ~/ 2).clamp(0, 5);

int symColorHex(int level) => symPainRamp[symColorIndex(level)];

/// 三档文案（原型 `_sySel.pain<4?'轻度':pain<7?'中度':'重度'`）。
String symTier(int level) => level < 4 ? '轻度' : (level < 7 ? '中度' : '重度');

/// 疼痛条下方那行读数（原型 `syPainTx`＝「6 分 · 中度」）。
String symPainTx(int level) => '$level 分 · ${symTier(level)}';

/// 持续时长三档文案（原型 `syDur`）：≥1440 天 / ≥60 一位小数小时 / 其余分钟。
String symDurTx(int? min) {
  final m = min ?? 0;
  if (m >= 1440) return '${(m / 1440).round()} 天';
  if (m >= 60) return '${(m / 60 * 10).round() / 10} 小时';
  return '$m 分钟';
}

/// 正在发作（`ongoing` 为真）——顺序沿用流水原序，页面自己按日期倒排。
List<SymptomRecord> symLive(List<SymptomRecord> all) =>
    [for (final s in all) if (s.ongoing) s];

/// 发作卡右上角的计数位（原型 `syLiveN`＝「n 项」/「无」）。
String symLiveTx(int n) => n == 0 ? '无' : '$n 项';

/// 疼痛直方图＝11 根柱（0~10 分）各落一条（原型 `Array(11)`＋`hist[min(10,max(0,lv))]++`）。
List<int> symHist(List<SymptomRecord> all) {
  final h = List<int>.filled(11, 0);
  for (final s in all) {
    h[math.max(0, math.min(10, s.level))]++;
  }
  return h;
}

/// 柱高归一化的分母（原型 `Math.max(1,...)`，全零时不炸除）。
int symHistMax(List<int> hist) => hist.fold(1, math.max);

/// 部位筛选（「全部」不过滤；其余按**包含**判，多选的行只要沾上就算命中）。
List<SymptomRecord> symByPart(List<SymptomRecord> all, String part) => part == '全部'
    ? all
    : [
        for (final s in all)
          if (s.parts.contains(part) || (s.parts.isEmpty && part == '全身')) s
      ];

/// 词云一枚：词＋频次＋相对最高频的比值（页面按比值算字号与透明度）。
typedef SymWord = ({String w, int n, double ratio});

/// 高频描述词云（原型 `syCloud`）：源＝症状名＋感受描述＋诱发因素，分隔符 `[ ·,，。]`，
/// **只留长度 >1 的词**，按频次降序取前 18。
///
/// 同频词按**首次出现序**排（不是按 `Map` 序碰运气）：Dart 的 `List.sort` 非稳定排序，
/// 全同频时 comparator 恒返回 0，取哪 18 枚会变成不确定的——原型靠 JS 稳定排序侥幸成立，
/// 这里显式带序号（一处口径，测试才能钉死）。
List<SymWord> symWordCloud(List<SymptomRecord> all, {int max = 18}) {
  final c = <String, int>{};
  final first = <String, int>{};
  var seq = 0;
  void feed(String? src) {
    if (src == null || src.isEmpty) return;
    for (final w in src.split(RegExp(r'[ ·,，。]'))) {
      if (w.length < 2) continue;
      first.putIfAbsent(w, () => seq++);
      c[w] = (c[w] ?? 0) + 1;
    }
  }

  for (final s in all) {
    feed(s.name);
    feed(s.desc);
    feed(s.trig);
  }
  final ks = c.keys.toList()
    ..sort((a, b) {
      final d = c[b]! - c[a]!;
      return d != 0 ? d : first[a]! - first[b]!;
    });
  final top = ks.take(max).toList();
  if (top.isEmpty) return const [];
  final mx = c[top.first]!;
  return [for (final k in top) (w: k, n: c[k]!, ratio: c[k]! / mx)];
}

/// 词云卡右上角计数（原型 `syWcN`＝「n 个高频词」/「暂无文本」）。
String symCloudTx(int n) => n == 0 ? '暂无文本' : '$n 个高频词';

/// 字号：原型 `10 + 频次/最高*8`（px）。
double symCloudFont(double ratio) => 10 + ratio * 8;

/// 透明度：原型 `.45 + .55*比值`。
double symCloudOpacity(double ratio) => 0.45 + 0.55 * ratio;

/// 流水排序＝日期倒序（原型 `sort((a,b)=>a.d<b.d?1:-1)`）；同日多条按 id 倒序补稳。
List<SymptomRecord> symListDesc(List<SymptomRecord> all) {
  final xs = [...all]..sort((a, b) {
    final d = b.date.compareTo(a.date);
    return d != 0 ? d : (b.id ?? 0) - (a.id ?? 0);
  });
  return xs;
}

/// 流水主行（原型 `syList` 的加粗行）：`头痛 · 发作中` ＋（用药相关角标由页面另铺 chip）。
String symRowMain(SymptomRecord r) => '${r.name}${r.ongoing ? ' · 发作中' : ''}';

/// 流水副行（原型副行原样拼装）：`日期 时刻 · 部位 · 持续 X`（有图接「· 照片 n」，有描述接「· 描述」）。
String symRowSub(SymptomRecord r) {
  final head = '${r.date}${r.time.isEmpty ? '' : ' ${r.time}'} · ${symPartsTx(r)} · 持续 ${symDurTx(r.durationMin)}';
  final pics = r.photos.isEmpty ? '' : ' · 照片 ${r.photos.length}';
  final d = (r.desc ?? '').trim();
  return '$head$pics${d.isEmpty ? '' : ' · $d'}';
}

/// 部位显示＝全量以 `·` 连接（原型只显示第一枚，这里不丢用户多选结果——偏离一条见工单 §2）。
String symPartsTx(SymptomRecord r) => r.parts.isEmpty ? '全身' : r.parts.join('·');

/// 保存提示条（原型 `sySave` 原话）：`已记录 头痛 6 分` ＋（用药相关时追加）。
String symSavedTx(SymptomRecord r) =>
    '已记录 ${r.name} ${r.level} 分${r.drugRelated ? ' · 已标为用药相关' : ''}';

/// 标记结束提示条（原型 `syEnd` 原话）。
const String symEndTx = '已标记结束 · 持续时长 +15 分钟';

/// 删除确认文案（原型 `syDel` 的 `confirmRow` 原话）。
const String symDelTx = '删除该条症状记录';

/// 空态（原型 `syList` 空分支）。
const String symEmptyTx = '该档案暂无症状记录';

/// 发作卡空态（原型 `syLive` 空分支）。
const String symLiveEmptyTx = '当前无发作中症状';

/// 常用症状列表＝十枚种子＋自定义（保序去重，原型 `syAddName` 是 push 进同一数组）。
List<String> symNamesWith(List<String> custom) {
  final out = [...symSeedNames];
  for (final c in custom) {
    final v = c.trim();
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out;
}
