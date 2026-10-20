import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';

/// 日记改版批1a · 视图档位常量（与 `UserSettings.kJournalLayouts` 同源顺序）。
///
/// 放在 presentation 层而不是 settings 层：设置层只管「存哪个字符串」，
/// 这里管「这一档叫什么、怎么排」，免得设置层为一个 feature 背一套 UI 文案。
const String kJournalLayoutTrack = 'track';
const String kJournalLayoutList = 'list';
const String kJournalLayoutIns = 'ins';

/// 设置弹层里的排列顺序（左→右：日期轨道 / 列表 / INS）。
/// 与 `UserSettings.kJournalLayouts` 同序，但那个是「存储合法值集合」的语义，
/// 这里单列一条，改弹层顺序时不必动存储层。
const List<String> kJournalLayoutsOrdered = [
  kJournalLayoutTrack,
  kJournalLayoutList,
  kJournalLayoutIns,
];

/// 档位中文名（设置弹层与顶行回显共用）。
const Map<String, String> kJournalLayoutLabels = {
  kJournalLayoutTrack: '日期轨道',
  kJournalLayoutList: '列表',
  kJournalLayoutIns: 'INS 卡片流',
};

/// 档位图标（设置弹层三宫格：图标在上、名称在下）。
///
/// 批2e 按原型 `DIARY_LAYOUT_ICO` 换：轨道＝左侧短竖列＋右侧长行（时间轴列表）、
/// 列表＝三行横线（末行更短）、INS＝四宫格。原来轨道用 `view_timeline_outlined`、
/// 列表用 `view_agenda_outlined`，在 18px 上看起来像「文档/便签」，与原型不是一个语义。
IconData journalLayoutIcon(String k) => switch (k) {
      kJournalLayoutTrack => Icons.format_list_bulleted,
      kJournalLayoutIns => Icons.grid_view,
      _ => Icons.subject,
    };

/// 心情强度色阶（原型 `DR_SCALE` 口径）：`step` 0＝最浅、1＝最深。
///
/// 为什么不照抄原型的 `#e3e5fb…#8a90e8`：那 5 阶是**靛紫一族**写死的，换到翠绿/琥珀/蓝
/// 主题上会变成「别家的紫」，与全仓「新增淡底一律走主色淡化档」的铁律冲突。
/// 这里改成**主色与卡片底混**派生——4 主题 × 明暗自动跟随。
/// 深色档不能往白里混（会糊成一片亮块），改往 `card` 混并整体加厚一档。
Color journalAccentStep(ThemeTokens t, double step) {
  final dark = ThemeData.estimateBrightnessForColor(t.page) == Brightness.dark;
  final s = step.clamp(0.0, 1.0);
  return Color.lerp(
      t.card, t.accent, (dark ? .20 : .12) + (dark ? .50 : .58) * s)!;
}

/// 心情值 → 强度档（0＝最正向/最浅 … 1＝最负面/最深）；未记录给 null。
///
/// 口径来源＝图墙说明文案「底色越深，当日情绪越低落」。原型 `dwRenderWall` 的
/// `DR_SCALE[min(4,mood)]` 取的是「越负面越浅」，与它自己的文案正好相反——
/// 两者冲突时以**用户看得见的那句文案**为准（文案是承诺，取色是实现细节）。
double? journalMoodDepth(int? mood) {
  if (mood == null || mood < 1 || mood > kJournalMoods.length) return null;
  return (mood - 1) / (kJournalMoods.length - 1);
}

/// 日期轨道左栏的日期块数据（同日多篇只出一次，见工单 §2 硬口径 1）。
class TrackDayBlock {
  const TrackDayBlock({
    required this.day,
    required this.dayNo,
    required this.monthLabel,
    required this.weekLabel,
    required this.entries,
    required this.hasMoodColor,
    required this.moodColor,
  });

  final DateTime day;
  final String dayNo;
  final String monthLabel;
  final String weekLabel;
  final List<JournalEntry> entries;

  /// 当天是否记过心情（决定图墙格是否用心情色实心块）。
  final bool hasMoodColor;
  final Color? moodColor;

  /// 时刻列（同一天多篇时的「几时」，取当篇创建时间）。
  String timeOf(JournalEntry e) {
    final t = e.createdAt;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

const List<String> _weekCn = ['一', '二', '三', '四', '五', '六', '日'];

/// 把「新→旧」的日记列表折成日期块（今日在前，同日合并）。
///
/// 判定口径（工单 §2 硬口径 1）：**同日多篇只出一次日期块**，首篇处出，后续同日在右栏继续排。
/// 纯函数、不碰 UI——单测直接喂列表断言块数与每块的篇数，比在 widget 树里找文本稳。
List<TrackDayBlock> buildTrackBlocks(
  List<JournalEntry> entries, {
  Color? Function(JournalEntry e)? moodColorOf,
}) {
  final byDay = <String, List<JournalEntry>>{};
  final order = <String>[];
  for (final e in entries) {
    final k = '${e.day.year}-${e.day.month}-${e.day.day}';
    if (!byDay.containsKey(k)) {
      byDay[k] = <JournalEntry>[];
      order.add(k);
    }
    byDay[k]!.add(e);
  }
  return [
    for (final k in order)
      () {
        final list = byDay[k]!;
        final d = list.first.day;
        final color = moodColorOf?.call(list.first);
        return TrackDayBlock(
          day: d,
          dayNo: d.day.toString().padLeft(2, '0'),
          monthLabel: '${d.month}月',
          weekLabel: '周${_weekCn[d.weekday - 1]}',
          entries: list,
          hasMoodColor: color != null,
          moodColor: color,
        );
      }(),
  ];
}

/// 月历图墙的一格三态（工单 §2 硬口径 3，顺序不可对调）。
enum WallCellState {
  /// 该日无日记 → 空环格子。
  empty,

  /// 有日记无图 → 心情色实心块（不画缩略图、不画占位图标）。
  written,

  /// 有日记有图 → 心情色实心块 + 右上「有图」角标（只表示有图，不做浏览）。
  writtenWithImage,
}

/// 单格状态判定，**次序就是口径**：先判有没有日记，再判有没有图。
WallCellState wallCellStateOf(JournalEntry? e) {
  if (e == null) return WallCellState.empty;
  if (e.imagePaths.isEmpty) return WallCellState.written;
  return WallCellState.writtenWithImage;
}

/// 月历首格偏移（周一开头 ⇒ `weekday-1`；7 列）。
int wallLeadingBlanks(DateTime month) => 0;

/// 该月格数（含前置空位），7 的倍数。
int wallCellCount(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final days = DateTime(month.year, month.month + 1, 0).day;
  final lead = first.weekday - 1;
  final total = lead + days;
  return ((total + 6) ~/ 7) * 7;
}

/// 左栏日期块的四档分层字号（工单 §3）：日号 22 / 月份·星期·时刻 10。
const double kTrackDayNoSize = 22;
const double kTrackMetaSize = 10;

/// 轨道档右栏正文行数上限（列表 3 行 → 轨道 2 行，同日多篇才不会把屏占满）。
const int kTrackBodyMaxLines = 2;

/// 心情色（与列表/INS 同源：读主题 accent 的七档派生；未记心情给中性灰蓝）。
///
/// 这里刻意**不**引 UI 层 moodEmoji 之类，只按 `JournalEntry.mood` 是否为空配色，
/// 具体色值由调用方从 tokens 派生后传入（见 `journal_track_view.dart`）。
Color? trackMoodColorOf(BuildContext context, JournalEntry e) {
  // `JournalEntry.mood` 是 int?（心情档位索引），判「记没记」只看是否为空。
  if (e.mood == null) return null;
  final tokens = context.tokens;
  return tokens.accent;
}
/// 收藏 / 点亮两枚语义色（INS 卡与轨道左栏共用，色值集中一条，免得多处硬编码各写各的）。
///
/// 为什么是固定色值而不是 `--accent` 派生：这两个是**互动态**，语义上必须与主题主色区分开
/// （换主题时「收藏」还是那颗星、还是那个琥珀黄，用户才认得出）。深色档照用——
/// 两枚色在深浅两档上的对比度都过 4.5:1，无需分档。
const Color kJournalLiked = Color(0xFFE11D48);
const Color kJournalStarred = Color(0xFFF59E0B);
