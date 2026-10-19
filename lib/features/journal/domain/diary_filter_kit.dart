/// 日记改版批2c · 筛选弹层的胶囊几何、标签段折叠判定与筛选命中（纯逻辑）。
///
/// 为什么「要不要折叠」放在 domain 而不是 widget 里：原型在同一个坑上踩过三次——
/// 折叠态是「定高一行 + 裁掉溢出」，被裁掉的胶囊在布局阶段就被排除，
/// 于是「先裁再量」永远量到 `scrollHeight == clientHeight`，恒判「不超一行」；
/// 反过来先解折叠再量，容器当场变成两行，判据又回到原点。
/// 定案是**容器宽度判据**：逐枚累加「胶囊宽 + 间距」，装不下即折行。
/// 这个判据不依赖渲染时序，所以能整段脱开 widget 树做单测
/// （别改成「按标签数 > 4 猜」——那是原型明确否掉的硬编码）。
library;

import 'journal_entry.dart';

/// 胶囊几何（与原型 `.df-chip` 同口径：高 32 / 左右内边距 12 / 描边 1 / 圆角 16 / 字号 13）。
///
/// 改这里必须同步原型 `index-journal.html` 的 `.df-chip`，否则「按宽度算折行」
/// 会与实际渲染错开，出现「明明两行却没折叠」或「只有一行却多出一枚按钮」。
const double kDfChipH = 32;
const double kDfChipPadX = 12;
const double kDfChipBorder = 1;
const double kDfChipIcon = 14;
const double kDfChipIconGap = 6;
const double kDfChipFontSize = 13;

/// 胶囊横竖间距（原型 `.df-tags{gap:8px}` 与 `flex-wrap gap-2` 同一值）。
const double kDfChipGap = 8;

/// 固定键顺序（与原型 `DF_GROUPS[0].items` 同序：全部 / 收藏 / 点亮 / 待办）。
///
/// 顺序留在 kit 里而不是 UI 里：`journal_flags_test` 与筛选弹层都读它，
/// 两处各写一份就会出现「弹层顺序改了、纯逻辑断言还按老顺序」的假绿。
const List<String> kDfMarkKeys = ['all', 'starred', 'liked', 'todo'];

/// 固定键的中文名（原型 `dfLabel` 同名口径）。
///
/// **不带符号**：原型曾把 `♥ 收藏` 整串当显示名，行首已有一枚线性图标、
/// 文字前又出现同一个符号，产品实测点名「同一个符号出现两遍」。
/// 符号只留在筛选值（`'♥ 收藏'` 那种历史键）里。
String dfMarkLabel(String key) => switch (key) {
      'todo' => '待办',
      'starred' => '收藏',
      'liked' => '点亮',
      _ => '全部',
    };

/// 一枚胶囊的占位宽＝左右内边距 + 描边 + 图标 + 图标与文字间距 + 文字宽。
///
/// 只服务「会不会折行」的估算，故不把 `Wrap` 的亚像素取整算进来——
/// 差 1px 以内不影响「一行还是两行」的判定，但会影响可读性（贴边那枚差一点点就折）。
double dfChipWidth(double textWidth) =>
    kDfChipPadX * 2 + kDfChipBorder * 2 + kDfChipIcon + kDfChipIconGap + textWidth;

/// 这些宽度的胶囊在 [maxW] 里排得下几行（贪心累加，与 `Wrap` 的折行一致）。
///
/// 空列表返回 0（无内容＝零行，调用方据此连分组标题都不出）。
int dfChipLines(List<double> widths, double maxW, {double gap = kDfChipGap}) {
  if (widths.isEmpty) return 0;
  if (maxW <= 0) return 1; // 未测量到宽度：按「一行」处理，绝不无中生有地折叠
  var run = 0.0;
  var lines = 1;
  for (final w in widths) {
    if (run > 0 && run + gap + w > maxW) {
      lines++;
      run = w;
    } else {
      run = run > 0 ? run + gap + w : w;
    }
  }
  return lines;
}

/// 标签段是否该折叠（严格超一行才折叠，才出「展开全部」）。
///
/// 产品口径「不超一行时不出按钮、不裁剪」就落在这一个 return 上：
/// 一行以内返回 false，调用方连 `ClipRect` 都不挂——按钮不存在，也不占位。
bool dfTagsOverflow(List<double> widths, double maxW, {double gap = kDfChipGap}) =>
    dfChipLines(widths, maxW, gap: gap) > 1;

/// 展开按钮文案：折叠态「展开全部 (N)」，展开态「收起」。
///
/// N 是**池内全量标签数**（不是「被裁掉几枚」）：用户点它是想看全量，
/// 报「还有 3 枚」会让池子大小看起来比实际小。
String dfMoreLabel({required bool open, required int total}) =>
    open ? '收起' : '展开全部 ($total)';

/// 一篇日记是否命中筛选键。
///
/// 固定键走白名单，其余按标签名比（兼容历史 `#标签` 键——原型 `dwHit` 曾因
/// 「按名字精确等于 `'#复盘'` 比、池内名字不带 `#`」导致该标签恒 0 篇）。
///
/// 放在 domain 是给两处共用：页面列表的 `shown` 与筛选弹层的实时计数。
/// 分两份写过一次就出过「弹层说筛出 3 篇、关掉弹层只剩 1 篇」。
bool diaryHit(JournalEntry e, String key) => switch (key) {
      'all' => true,
      'todo' => e.todoLines().isNotEmpty,
      'starred' => e.starred,
      'liked' => e.liked,
      _ => e.tags.any((t) => t == key || '#$t' == key),
    };
