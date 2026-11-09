/// 重要日子域模型（需求 V1.42 模块 11 · 专版 index-day_aim__goods.html P8 系四屏）。
///
/// 图标口径：UI 禁 emoji（全局纪律），iconId 为语义键，presentation 层映射线性图标。
/// 色彩：colorKey 对应六档渐变（原型 DE_COLORS tailwind 键的语义化）。
library;

/// 四种重复方式（deRepPick 四 chip）。
enum DayRepeat {
  once('once', '一次性倒数'),
  solarYear('solar-year', '每年（公历）'),
  lunar('lunar', '每年（农历）'),
  monthly('monthly', '每月循环');

  const DayRepeat(this.wire, this.label);
  final String wire;
  final String label;
  static DayRepeat of(String w) => DayRepeat.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => DayRepeat.solarYear,
      );
}

/// 日子分类（列表 seg 胶囊；「已归档」为筛选态非存储值）。
const kDayCats = ['生日', '纪念日', '循环', '证件', '倒数'];

/// 提前提醒档位（deRemChips 多选）。
const kDayRemOffsets = [30, 15, 7, 3, 1, 0];

/// 图标语义键（编辑屏 12 枚 · 实现映射 Icons 线性图）。
const kDayIcons = [
  'cake', 'heart', 'wallet', 'alert', 'medical', 'id',
  'flight', 'gift', 'school', 'home', 'hourglass', 'doc'
];

/// 卡片渐变色键（六档 · 首尾色对）。
const kDayGradients = <String, (String, String)>{
  'rose': ('#FB7185', '#DB2777'),
  'violet': ('#A78BFA', '#C026D3'),
  'emerald': ('#34D399', '#0D9488'),
  'amber': ('#FBBF24', '#EA580C'),
  'sky': ('#38BDF8', '#2563EB'),
  'slate': ('#94A3B8', '#475569'),
};

class DayPrep {
  const DayPrep({
    this.id,
    required this.dayId,
    required this.text,
    this.done = false,
    this.todoId,
  });

  final int? id;
  final int dayId;
  final String text;
  final bool done;

  /// 勾选转待办后回写的 todo.id（重复勾选不再生成）。
  final int? todoId;

  static DayPrep fromRow(Map<String, Object?> r) => DayPrep(
        id: r['id'] as int,
        dayId: r['day_id'] as int,
        text: r['label'] as String,
        done: (r['done'] as int? ?? 0) == 1,
        todoId: r['todo_id'] as int?,
      );
}

/// 一条日子（days 表行 + 子表 preps 组装）。
class DayEntry {
  const DayEntry({
    this.id,
    required this.title,
    required this.iconId,
    required this.colorKey,
    required this.category,
    required this.repeat,
    this.targetDate,
    this.lunarMonth,
    this.lunarDay,
    this.monthDay,
    this.remOffsets = const [7, 0],
    this.note,
    this.pinned = false,
    this.archived = false,
    this.linkDiary = true,
    this.prepToTodo = true,
    this.preps = const [],
  });

  final int? id;
  final String title;
  final String iconId;
  final String colorKey;
  final String category;
  final DayRepeat repeat;

  /// once / solarYear 锚点日期（自然日）。
  final DateTime? targetDate;

  /// lunar 月/日号（1~12 / 1~30，平月优先换算）。
  final int? lunarMonth;
  final int? lunarDay;

  /// monthly 日号（1~31，小月收敛到月末）。
  final int? monthDay;

  final List<int> remOffsets;
  final String? note;
  final bool pinned;
  final bool archived;
  final bool linkDiary;
  final bool prepToTodo;
  final List<DayPrep> preps;

  DayEntry copyWith({
    int? id,
    String? title,
    String? iconId,
    String? colorKey,
    String? category,
    DayRepeat? repeat,
    DateTime? targetDate,
    int? lunarMonth,
    int? lunarDay,
    int? monthDay,
    List<int>? remOffsets,
    String? note,
    bool? pinned,
    bool? archived,
    bool? linkDiary,
    bool? prepToTodo,
    List<DayPrep>? preps,
  }) =>
      DayEntry(
        id: id ?? this.id,
        title: title ?? this.title,
        iconId: iconId ?? this.iconId,
        colorKey: colorKey ?? this.colorKey,
        category: category ?? this.category,
        repeat: repeat ?? this.repeat,
        targetDate: targetDate ?? this.targetDate,
        lunarMonth: lunarMonth ?? this.lunarMonth,
        lunarDay: lunarDay ?? this.lunarDay,
        monthDay: monthDay ?? this.monthDay,
        remOffsets: remOffsets ?? this.remOffsets,
        note: note ?? this.note,
        pinned: pinned ?? this.pinned,
        archived: archived ?? this.archived,
        linkDiary: linkDiary ?? this.linkDiary,
        prepToTodo: prepToTodo ?? this.prepToTodo,
        preps: preps ?? this.preps,
      );
}

/// 提醒中心条目（reminder_items 表行）。
/// kind：cert 手动建档 · sub 记账周期账单派生 · warranty 物品档案派生。
class ReminderItem {
  const ReminderItem({
    this.id,
    required this.kind,
    required this.title,
    required this.iconId,
    required this.dueDate,
    this.tip,
    this.meta,
    this.sourceKey,
    this.handled = false,
    this.handledAt,
    this.snoozeDate,
    this.snoozeHour,
  });

  final int? id;
  final String kind;
  final String title;
  final String iconId;

  /// 原始到期日（派生条目随源刷新）。
  final DateTime dueDate;
  final String? tip;
  final String? meta;

  /// 派生唯一键（`recur:周期账单id` / `item:物品id`）；手动条目为 null。
  final String? sourceKey;

  /// 已处理＝静默归档保留审计。
  final bool handled;
  final int? handledAt;

  /// 改提醒日（就地三滚轮：月/日/时）。
  final DateTime? snoozeDate;
  final int? snoozeHour;

  /// 有效提醒日（改期优先）。
  DateTime get effectiveDate => snoozeDate ?? dueDate;

  static const kKindLabels = {'cert': '证件', 'sub': '订阅', 'warranty': '保修'};

  String get kindLabel => kKindLabels[kind] ?? kind;

  static ReminderItem fromRow(Map<String, Object?> r) => ReminderItem(
        id: r['id'] as int,
        kind: r['kind'] as String,
        title: r['title'] as String,
        iconId: r['icon'] as String,
        dueDate: _d(r['due_date'] as String),
        tip: r['tip'] as String?,
        meta: r['meta'] as String?,
        sourceKey: r['source_key'] as String?,
        handled: (r['handled'] as int? ?? 0) == 1,
        handledAt: r['handled_at'] as int?,
        snoozeDate:
            r['snooze_date'] == null ? null : _d(r['snooze_date'] as String),
        snoozeHour: r['snooze_hour'] as int?,
      );

  static DateTime _d(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
}

/// 一次加载的全域快照（列表/详情/提醒中心/仪表盘卡共用，仿 CareData）。
class DaysData {
  const DaysData({required this.days, required this.reminders});

  final List<DayEntry> days;
  final List<ReminderItem> reminders;

  /// 未归档日子（置顶在前，其余保持库序=创建/保存序）。
  List<DayEntry> get active =>
      days.where((d) => !d.archived).toList(growable: false);

  List<ReminderItem> get unhandled =>
      reminders.where((r) => !r.handled).toList(growable: false);
}

String fmtDateYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
