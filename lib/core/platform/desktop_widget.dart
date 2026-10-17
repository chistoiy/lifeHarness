/// 桌面模块批2 · 小组件快照桥（数据桥唯一实现 · 冻结档 §2.2 F2-3 / §4.4）。
///
/// 规格＝docs/handoff/桌面模块-冻结版开发方案-20261013.md。
///
/// **C5 红线**：小组件**只读 SharedPreferences 快照**，**禁**直读 sqlite——
/// 读数由本文件（App 存活时经 `home_widget` 写入）单向下发；系统调频导致的
/// 延迟是特性不是缺陷（C4）。
///
/// **C8/B7 隐私联动**：隐藏金额开 ⇒ 金额位一律 `••••`；呵护类读数**根本不进**
/// 快照（字段缺省，不写 0/空串——空串会被 widget 读成假读数）。
///
/// 桥＝`home_widget`（冻结档 §6.2「插件版本以 pubspec.yaml 实装为准，不引第二套
/// widget 桥」）；快照文件名 `HomeWidgetPreferences`［由插件持有］。
library;

import 'package:home_widget/home_widget.dart';

/// 快照键（**唯一真源**；`test/desktop_privacy_test.dart` 与小组件布局按此口径）。
///
/// 取值口径＝批1 已钉死的白名单（`todo_count`/`habit_done`/`habit_total`/
/// `amount_cell`）＋一个「有没有快照」标记（B6 无快照占位判据）。
class LhWidgetKeys {
  const LhWidgetKeys._();

  /// 今日待办数（截止日落在今天的未完待办）。
  static const String todoCount = 'todo_count';

  /// 今日习惯已完成项数。
  static const String habitDone = 'habit_done';

  /// 今日习惯应打卡项数。
  static const String habitTotal = 'habit_total';

  /// 今日支出金额位（**已经过隐私遮蔽**；原生侧原样显示，不二次加工）。
  static const String amountCell = 'amount_cell';

  /// 本月支出金额位（记账 2×2 三行读数之二；同样已遮蔽）。
  static const String monthAmountCell = 'month_amount_cell';

  /// 本月结余金额位（记账 2×2 三行读数之三；收入−支出，可为负；同样已遮蔽）。
  static const String balanceCell = 'balance_cell';

  /// 今日待办清单（待办 2×2 的行数据；**已按口径裁剪**）。
  ///
  /// 紧凑编码（非 JSON：widget 侧只做 `split`，禁引三方解析器）：
  /// 条目间`\u001e`、字段间 `\u001f`、字段序＝`id\u001fdone\u001ftitle`。
  /// 空串＝没有可显示的待办（原生显示空态，**不显示 0** · B6）。
  static const String todoItems = 'todo_items';

  /// 今日待办**被裁掉的剩余条数**（待办 2×2 显示「还有 N 条」）。
  ///
  /// 为什么不省掉、让原生拿 `todo_count` 自己减：两条口径不同——`todo_count`
  /// 是「截止日落在今天」的数，清单则是「今天到期 + 已逾期」的合并集。原生自行相减
  /// 会在两口径不一致时显示负数或凭空多出几条（V1.67 那一类「断言反推实现」的坑）。
  static const String todoMore = 'todo_more';

  /// 习惯今日状态表（打卡-单习惯 2×2 · 批A 渲染层）。
  ///
  /// 编码与待办行同族：条目间 `\u001e`、字段间 `\u001f`、字段序＝
  /// `name\u001fstreak\u001fdone`（`done` 用 `1`/`0`）。
  ///
  /// **为什么下发全量而不是「本实例那一枚」**：快照是**一份**、实例有多个
  /// （每枚绑一个习惯），原生侧按自己的绑定去表里查名——下发全量才能让
  /// 多枚实例各取所需；也让「绑的习惯被删了」这件事可判（查不到＝源失效）。
  static const String habitItems = 'habit_items';

  /// 是否有过快照（B6：从未写过 ⇒ 小组件显示占位而非 0）。
  static const String hasSnapshot = 'has_snapshot';

  /// 全部字段（写快照时逐键下发；**呵护类读数不在此列**·C8）。
  static const List<String> all = <String>[
    todoCount,
    habitDone,
    habitTotal,
    amountCell,
    monthAmountCell,
    balanceCell,
    todoItems,
    todoMore,
    habitItems,
    hasSnapshot,
  ];
}

/// 无数据占位（B6）。App 从未写过快照时读数位显示它，**不显示 0**（避免误读）。
const String kWidgetPlaceholder = '--';

/// 待办 2×2 最多显示几条（2×2 卡放3 条＋一行「还有 N 条」刚好铺满）。
///
/// 口径常量放这里（原生侧布局按此留行位），**禁在两处各写一个数字**。
const int kWidgetTodoRows = 3;

/// 原生小组件类名（`home_widget` 按「包名.类名」解析，见 §6.2）。
///
/// 与 `android/**` 的两个 `AppWidgetProvider` 逐字一致
/// （守护 `test/desktop_widget_test.dart` 扫原生源码核对）。
class LhWidgetNames {
  const LhWidgetNames._();

  /// 2×2 今日概览（F2-1）。
  static const String todayOverview = 'TodayOverviewWidget';

  /// 4×1 快捷记录（F2-2）。
  static const String quickRecord = 'QuickRecordWidget';

  /// 2×2 待办清单（批3·F2-4）：行内勾圈直接闭环、行文本进详情。
  static const String todoList = 'TodoListWidget';

  /// 2×2 记账概览（批3·F2-5）：今日支出／本月支出／本月结余三行读数。
  static const String ledgerOverview = 'LedgerOverviewWidget';

  /// 2×2 打卡-单习惯（批A·渲染层）：一枚绑一个习惯，点按钮即打卡。
  ///
  /// ⚠ 类名与 Dart `kWidgetKindHabit`（`habit`）是**两件事**：前者是 provider
  /// 类名（home_widget 按它解析），后者是绑定记录里的「哪一类小组件」
  /// （`WidgetConfigActivity` 据它认领预选绑定）。两者都由
  /// `test/desktop_widget_test.dart` 与原生常量交叉核对。
  static const String habitCheck = 'HabitCheckWidget';
}

/// 一条待办的行数据（待办 2×2 的最小下发单元）。
///
/// **为什么用模型而不是裸 Map**：`todoItems` 是桌面可见内容，编码格式一旦改动
/// 原生侧就会解错（多一列/少一列 ⇒ 整张卡显示乱码）。模型＋[encode] 收口后，
/// 格式只有这一处定义，守护测试直接对它断言。
class WidgetTodoItem {
  const WidgetTodoItem({required this.id, required this.done, required this.title});

  final int id;
  final bool done;
  final String title;
}

/// 紧凑编码的分隔符（见 [LhWidgetKeys.todoItems]）。
///
/// ⚠ 用控制字符而**不是** `|`／`\n`：`|` 是待办标题里的合法字符，`\n` 会被
/// SharedPreferences 与布局两头反复转义 ⇒ 行数据错位。U+001E/001F 在正常文本里
/// 不出现，可安全当分隔符。
const String kTodoItemSep = '\u001e';
const String kTodoFieldSep = '\u001f';

/// 把待办列表编码成快照串（**唯一编码出口**，原生侧只做 `split`）。
///
/// - [maxRows] 裁剪条数（2×2 卡最多 3 行，超出显示「还有 N 条」）；
/// - 标题里的控制字符一律剔除（否则会破坏分隔符结构）；
/// - 标题裁到 24 字（桌面行宽有限，超出由原生 `ellipsize` 兜底）。
String encodeWidgetTodoItems(List<WidgetTodoItem> items, {int maxRows = 3}) {
  final sb = StringBuffer();
  var n = 0;
  for (final it in items) {
    if (n >= maxRows) break;
    if (n > 0) sb.write(kTodoItemSep);
    final t = it.title
        .replaceAll(RegExp('[\u001e\u001f\n\r\t]'), ' ')
        .trim();
    sb..write('${it.id}')..write(kTodoFieldSep)
      ..write(it.done ? '1' : '0')..write(kTodoFieldSep)
      ..write(t);
    n++;
  }
  return sb.toString();
}

/// 一个习惯的今日状态（打卡-单习惯 2×2 的最小下发单元）。
///
/// [name] 是**绑定键**（widget 绑定记录里的 `sub` 就是习惯名·与 NFC 目标同口径），
/// 原生侧按名字查这一行；查不到＝该习惯已被删/改名 ⇒ 桌面显示「内容已失效」。
class WidgetHabitItem {
  const WidgetHabitItem({
    required this.name,
    required this.streak,
    required this.done,
  });

  final String name;

  /// 当前连续天数（`habitStreak` 口径·0＝没有连击，桌面不显示「连击 0 天」）。
  final int streak;

  /// 今日是否已达成（`habitOkAt` 口径）。
  final bool done;
}

/// 把习惯状态表编码成快照串（**唯一编码出口**，原生侧只做 `split`）。
///
/// 字段序 `name\u001fstreak\u001fdone`；名字里的控制字符一律剔除（否则破坏分隔符
/// 结构）。
///
/// ⚠ **名字不截断**（与待办标题不同）：这个名字是**绑定键**——实例绑定里存的
/// `sub` 就是它，原生按 `==` 找行。一旦在这边裁成 24 字，长名习惯就永远匹配不上，
/// 桌面会一直显示「内容已失效」。显示不下交给布局的 `ellipsize` 兜（不改变值）。
String encodeWidgetHabitItems(List<WidgetHabitItem> items) {
  final sb = StringBuffer();
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final n = it.name
        .replaceAll(RegExp('[\u001e\u001f\n\r\t]'), ' ')
        .trim();
    if (n.isEmpty) continue; // 无名目标不可绑，下发也无用
    if (sb.isNotEmpty) sb.write(kTodoItemSep);
    sb..write(n)..write(kTodoFieldSep)
      ..write(it.streak)..write(kTodoFieldSep)
      ..write(it.done ? '1' : '0');
  }
  return sb.toString();
}

/// 快照内容（App 侧算好，原生侧只渲染）。
class DesktopWidgetSnapshot {
  const DesktopWidgetSnapshot({
    required this.todoCount,
    required this.habitDone,
    required this.habitTotal,
    required this.amountCell,
    this.monthAmountCell = '',
    this.balanceCell = '',
    this.todoItems = const <WidgetTodoItem>[],
    this.todoOverflow = 0,
    this.habitItems = const <WidgetHabitItem>[],
    this.hasSnapshot = true,
  });

  final int todoCount;
  final int habitDone;
  final int habitTotal;

  /// 已格式化的金额位（含隐私遮蔽结果）。
  final String amountCell;

  /// 本月支出位（记账 2×2）。
  final String monthAmountCell;

  /// 本月结余位（记账 2×2；收入−支出，可为负）。
  final String balanceCell;

  /// 今日待办行数据（待办 2×2）。
  final List<WidgetTodoItem> todoItems;

  /// 裁剪掉的剩余条数（显示「还有 N 条」；0＝不显示）。
  final int todoOverflow;

  /// 习惯今日状态表（打卡-单习惯 2×2；每枚实例按自己的绑定名查行）。
  final List<WidgetHabitItem> habitItems;

  /// 是否已有快照（false ⇒ 各读数位一律占位）。
  final bool hasSnapshot;

  /// 下发用的扁平键值（**只含白名单字段**）。
  Map<String, String> toData() => <String, String>{
        LhWidgetKeys.todoCount: hasSnapshot ? '$todoCount' : '',
        LhWidgetKeys.habitDone: hasSnapshot ? '$habitDone' : '',
        LhWidgetKeys.habitTotal: hasSnapshot ? '$habitTotal' : '',
        LhWidgetKeys.amountCell: hasSnapshot ? amountCell : '',
        LhWidgetKeys.monthAmountCell: hasSnapshot ? monthAmountCell : '',
        LhWidgetKeys.balanceCell: hasSnapshot ? balanceCell : '',
        LhWidgetKeys.todoItems:
            hasSnapshot ? encodeWidgetTodoItems(todoItems) : '',
        LhWidgetKeys.todoMore: hasSnapshot ? '$todoOverflow' : '',
        LhWidgetKeys.habitItems:
            hasSnapshot ? encodeWidgetHabitItems(habitItems) : '',
        LhWidgetKeys.hasSnapshot: '$hasSnapshot',
      };
}

/// 金额位格式化（**B7 隐私联动的唯一口径**，原生侧不再判一次）。
///
/// - [hideAmount] 开 ⇒ 一律 `••••`（**不泄露真值、不做部分遮蔽**——位数不同也全遮，
///   否则泄露量级）；
/// - 无数据（null）⇒ [kWidgetPlaceholder]；
/// - 否则千分位整数（原型 `¥1,286` 的数值部分；`¥` 由原生布局补）。
String widgetAmountCell(double? amount, {required bool hideAmount}) {
  if (hideAmount) return '••••';
  if (amount == null) return kWidgetPlaceholder;
  final n = amount.round();
  final neg = n < 0;
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return neg ? '-$buf' : buf.toString();
}

/// 结余位格式化（记账 2×2 第三行；**B7 隐私联动的唯一口径**，与金额位同源）。
///
/// 与 [widgetAmountCell] 的唯一差别：结余**可能为负**，要保留符号（`-¥1,286`），
/// 否则「亏了 1286」会显示成「赚了 1286」——这是记账类产品最不该犯的错。
String widgetBalanceCell(double? balance, {required bool hideAmount}) {
  if (hideAmount) return '••••';
  if (balance == null) return kWidgetPlaceholder;
  final cell = widgetAmountCell(balance.abs(), hideAmount: false);
  return balance < 0 ? '-$cell' : cell;
}

/// 下发快照并触发四个小组件重绘（App 存活时调用；无桥/异常一律静默降级）。
///
/// 一次性副作用：无常驻 Timer、无轮询（§6.3 功耗口径）。
Future<void> pushDesktopWidgetSnapshot(DesktopWidgetSnapshot snap) async {
  try {
    for (final e in snap.toData().entries) {
      await HomeWidget.saveWidgetData<String>(e.key, e.value);
    }
    await HomeWidget.updateWidget(androidName: LhWidgetNames.todayOverview);
    await HomeWidget.updateWidget(androidName: LhWidgetNames.quickRecord);
    await HomeWidget.updateWidget(androidName: LhWidgetNames.todoList);
    await HomeWidget.updateWidget(androidName: LhWidgetNames.ledgerOverview);
    await HomeWidget.updateWidget(androidName: LhWidgetNames.habitCheck);
  } catch (_) {
    // catch-ok: 无 home_widget 通道的设备/测试环境（MissingPluginException）
    // 静默降级——小组件保留上次快照，不影响 App 主链路（B13）。
  }
}
