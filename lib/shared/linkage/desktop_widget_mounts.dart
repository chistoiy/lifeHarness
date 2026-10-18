import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/platform/desktop_widget.dart';
import '../../core/providers.dart';
import '../../features/habit/domain/habit_calc.dart'
    show dayKey, habitStepOf, habitStreak;
import '../../features/habit/presentation/habit_providers.dart'
    show HabitData, habitDataProvider;
import '../../features/ledger/domain/ledger_calc.dart' show mStat, monthKey;
import '../../features/ledger/presentation/ledger_providers.dart'
    show LedgerData, ledgerDataProvider;
import 'stats_providers.dart' show Todo, todosProvider, todoRepositoryProvider;
// 打卡闭环的排空在 widget_checkin_mounts（写库编排）；本文件持有组合根
// mount 点，故此处反向 import——Dart 允许库间循环引用，两侧只碰各自符号。
import 'widget_checkin_mounts.dart' show drainPendingWidgetChecks;

/// 桌面模块批2 · 小组件快照同步挂载点（app.dart watch，仿 `desktopShortcutSeedProvider`）。
///
/// 规格＝docs/handoff/桌面模块-冻结版开发方案-20261013.md §2.2 F2-3 / §4.4 / §6.3。
///
/// **为什么在组合根挂**：R1 守护下 App 只经 `shared/linkage` 编排跨模块能力；
/// 「今日待办数 / 习惯打卡进度 / 今日支出」分属三个 feature，本文件是**唯一聚合点**
/// （features 之间不互相 import）。
///
/// **刷新口径（§6.3）**：App 存活时**按需刷新**——三源数据变化或设置页改动
/// （[desktopWidgetKickProvider]）各触发一次下发；**无常驻 Timer、无轮询**。
/// 系统侧调频导致的延迟不视为缺陷（C4）；widget 永不直读 sqlite（C5）。
///
/// **测试环境**：`AppDatabase` 未初始化（全 app widget 测试）直接不挂，
/// 与 `ledger_mounts` 同口径。
final desktopWidgetSyncProvider = Provider<void>((ref) {
  if (!AppDatabase.instance.isInitialized) return;

  // 聚合逻辑见文件下方 buildSnapshot —— 与设置页预览卡共用同一真源，禁在此另算一套。
  void push() {
    final snap = buildSnapshot(ref.read);
    if (snap == null) return;
    Future(() => pushDesktopWidgetSnapshot(snap));
  }

  // 桌面勾圈闭环的补写队列排空（批3）。见 [drainPendingWidgetToggles] 的来由。
  Future(() => drainPendingWidgetToggles(ref));

  // 打卡闭环的补写队列排空（批A 交互闭环层：广播直达写库失败时的兜底）。
  // 见 [drainPendingWidgetChecks] 的来由。
  Future(() => drainPendingWidgetChecks(ref));

  ref.listen(todosProvider, (_, _) => push());
  ref.listen(habitDataProvider, (_, _) => push());
  ref.listen(ledgerDataProvider, (_, _) => push());
  ref.listen(desktopWidgetKickProvider, (_, _) => push());
  Future(push);
});

/// 排空「桌面勾圈没当场写成的待办」（批3）。
///
/// **来由**：桌面勾圈走原生广播直接 UPDATE sqlite（`TodoActionReceiver`），那一刻
/// App 可能没起过、库被 sqflite 独占 ⇒ 写失败。Receiver 会把 id 存进
/// `desktop.widget_pending_toggles`；本函数在 App 启动时（库已开）补写。
///
/// 幂等：重复执行安全——`UPDATE … WHERE done=0` 对已完成者是 no-op；
/// 队列为空时立即返回，**无快照无监听**（不常驻）。
Future<void> drainPendingWidgetToggles(Ref ref) async {
  if (!AppDatabase.instance.isInitialized) return;
  final repo = ref.read(settingsRepositoryProvider);
  final ids = repo.loadDesktopPendingToggles();
  if (ids.isEmpty) return;
  try {
    for (final id in ids) {
      await ref.read(todoRepositoryProvider).completeById(id);
    }
    await repo.saveDesktopPendingToggles(const <int>[]);
    ref.read(desktopWidgetKickProvider.notifier).state++;
  } catch (_) {
    // catch-ok: 补写失败就保留队列，下次启动再试（不丢闭环意图）。
  }
}

/// 设置页改动小组件偏好后踢一脚（隐藏金额 / 两个读数开关）。
///
/// 与 `ledgerTickProvider` 同款手法：跨模块不需要直连，只借一个计数源触发重算。
final desktopWidgetKickProvider = StateProvider<int>((ref) => 0);

/// 读取函数别名：Provider 挂载点（[Ref]）与设置页（`WidgetRef`）都提供
/// 签名完全一致的 `read`，取出来当参数传即可——**不用 dynamic**。
///
/// ⚠ 2026-10-15 踩坑：曾把 [buildSnapshot] 的 `ref` 参数声明为 `dynamic`「走 duck
/// typing」，结果 `ref.read(...)` 的静态返回类型退化为 `dynamic`，于是
/// `AsyncValue.valueOrNull` 这个**扩展方法不再参与解析**，真机运行到就抛
/// `NoSuchMethodError: Class 'AsyncData...>' has no instance getter
/// 'valueOrNull'`。而 `flutter analyze` 对 `dynamic` 成员调用不做检查，守护测试
/// 又是扫源码文本 ⇒ analyze 与全绿测试都漏了，只在真机炸。
/// **教训：只要用到扩展方法，就必须保住静态类型。**
typedef WidgetSnapshotRead = T Function<T>(ProviderListenable<T> provider);

/// 今日三项聚合快照（[desktopWidgetSyncProvider] 与设置页预览卡的**唯一真源**）。
///
/// 设置页的预览卡（2026-10-15 产品改口「先看样式、再勾选」）直接读本函数，
/// **禁在 UI 层另算一套**——预览与桌面上的实际读数必须一致，否则预览就是骗人的。
///
/// 三源都还没首次到达时返回 null ⇒ 预览显示占位（B6 · 与桌面同口径）。
///
/// [read] 传 `ref.read`（两个调用点各传自己那个），保住 `AsyncValue` 静态类型，
/// `valueOrNull` 扩展才可用——**别改回 dynamic**。
DesktopWidgetSnapshot? buildSnapshot(WidgetSnapshotRead read) {
  // 测试环境（AppDatabase 未初始化）直接不出快照，与挂载点同口径。
  if (!AppDatabase.instance.isInitialized) return null;
  final todos = read(todosProvider).valueOrNull;
  final habit = read(habitDataProvider).valueOrNull;
  final ledger = read(ledgerDataProvider).valueOrNull;
  // 三源都还没首次到达 ⇒ 不出快照（小组件保持占位 · B6）。
  if (todos == null && habit == null && ledger == null) return null;

  final now = DateTime.now();

  // 今日待办数＝截止日落在今天（口径与今天页问候卡逐字一致：逾期不混计）。
  final todoCount =
      (todos ?? const <Todo>[]).where((t) => _isOnToday(t.dueAt, now)).length;

  // 今日习惯：应打卡集合（dueToday）＋其中已完成（okOn）。
  // null＝习惯域还没首达（预览卡占位；桌面保持上次快照 · B6）。
  final (habitDone, habitTotal) = habitDueCounts(habit, now);
  // 打卡-单习惯 2×2 的查表数据：**未归档**全部习惯的今日状态（唯一真源
  // ＝[widgetHabitItems]，后台 isolate 打卡收敛与设置页预览都走它）。
  final habitItems = widgetHabitItems(habit, now);

  // 今日支出／本月支出／本月结余：口径在 [ledgerWidgetCells] 一处（弹窗引擎
  // 只推这三键，两处各算一套必然漂移）。
  final hide = read(settingsRepositoryProvider).loadDesktopHideAmount();
  final cells = ledgerWidgetCells(ledger, now, hideAmount: hide);

  // 待办 2×2 的行数据：今天到期 + 已逾期（都还没完事的），按截止日升序取前3。
  // ⚠ 与 `todo_count` 口径**故意不同**：那张卡报的是「今天要做几件」，这张卡要的是
  //「桌面上能直接点的三件事」——逾期待办同样该出现在桌面上。
  final pool = (todos ?? const <Todo>[])
      .where((t) => !t.done && !t.dropped && !t.trashed && t.dueAt != null)
      .where((t) => _isOnToday(t.dueAt, now) || t.dueAt!.isBefore(now))
      .toList()
    ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  final rows = pool.take(kWidgetTodoRows).toList();

  return DesktopWidgetSnapshot(
    todoCount: todoCount,
    habitDone: habitDone,
    habitTotal: habitTotal,
    amountCell: cells.amount,
    monthAmountCell: cells.month,
    balanceCell: cells.balance,
    todoItems: <WidgetTodoItem>[
      for (final t in rows)
        WidgetTodoItem(id: t.id ?? 0, done: t.done, title: t.title),
    ],
    todoOverflow: pool.length - rows.length,
    habitItems: habitItems,
  );
}

/// 截止日是否落在今天（今天页问候卡同口径）。
bool _isOnToday(DateTime? dueAt, DateTime now) =>
    dueAt != null &&
    dueAt.year == now.year &&
    dueAt.month == now.month &&
    dueAt.day == now.day;

/// 今日达成聚合（`widgetHabitItems`/概览 2×2 计数共用的唯一真源）。
///
/// 返回 `(已完成, 应打卡)`；[habit] 为 null（域未首达）⇒ `(0, 0)`。
(int, int) habitDueCounts(HabitData? habit, DateTime now) {
  if (habit == null) return (0, 0);
  final due = habit.dueToday(now);
  final k = dayKey(now);
  return (due.where((h) => habit.okOn(h, k)).length, due.length);
}

/// 打卡-单习惯 2×2 的查表数据（**未归档**全部习惯的今日状态）。
///
/// 归档/删除的习惯不进表 ⇒ 绑着它的桌面实例查不到行 ⇒ 桌面显示「内容已失效」
/// （不需要另设失效标记位）。
///
/// **为什么抽成共享函数**：App 内快照下发（[buildSnapshot]）、后台 isolate
/// 打卡收敛推送、设置页预览卡三处消费同一份表——各算一套必然漂移（批A
/// 交互闭环层口径）。[now] 可注入（测试/调用点统一传同一个时刻）。
///
/// **数值型口径**（2026-10-18 真机报障补）：`goal > 0` 的非组习惯带上
/// `value/goal/unit/step`——桌面显示 `3/8 杯` 并给 `+N` 增量按钮。
/// · `value` 取今日流水的 `value`（无记录＝0），**不是** `subValues` 之和；
/// · `step` 走 `habitStepOf(goal)`，与记量弹层的加减档同源；
/// · 组习惯（`isGroup`）即使带 unit 也按布尔型下发：组是「多子项各记各的」，
///   桌面 2×2 放不下一排子项，给个总数反而错。
List<WidgetHabitItem> widgetHabitItems(HabitData? habit, DateTime now) {
  if (habit == null) return const <WidgetHabitItem>[];
  final k = dayKey(now);
  return <WidgetHabitItem>[
    for (final h in habit.book)
      () {
        final goal = h.isGroup ? 0.0 : (h.goal ?? 0);
        return WidgetHabitItem(
          name: h.name,
          streak: habitStreak(h, habit.of(h.id), now),
          done: habit.okOn(h, k),
          value: goal > 0 ? (habit.of(h.id)[k]?.value ?? 0) : null,
          goal: goal > 0 ? goal : null,
          unit: goal > 0 ? (h.unit ?? '') : null,
          step: goal > 0 ? habitStepOf(goal) : null,
        );
      }(),
  ];
}

/// 记账三键（今日支出／本月支出／本月结余）的**唯一口径**。
///
/// 两个消费点：App 存活时的整包下发（[buildSnapshot]）与 4×1「记一笔」弹窗
/// 引擎（只推这三键）。**禁在两处各算一套**——否则同一天会「App 里一个数、
/// 弹窗保存后另一个数」。
///
/// 口径同 `mStat`：排除「不计入」（nb）、refund 按冲抵；结余＝本月收入−本月支出。
/// [ledger] 为 null（域未首达）⇒ 三个位置占位。
({String amount, String month, String balance}) ledgerWidgetCells(
  LedgerData? ledger,
  DateTime now, {
  required bool hideAmount,
}) {
  double? todayExp;
  double? monthExp;
  double? monthBal;
  if (ledger != null) {
    final k = dayKey(now);
    todayExp = mStat(ledger.txns.where((t) => !t.nb && t.date == k)).exp;
    final mk = monthKey(now);
    final monthStat = mStat(
      ledger.txns.where((t) => !t.nb && t.date.startsWith(mk)),
    );
    monthExp = monthStat.exp;
    monthBal = monthStat.inc - monthStat.exp;
  }
  return (
    amount: widgetAmountCell(todayExp, hideAmount: hideAmount),
    month: widgetAmountCell(monthExp, hideAmount: hideAmount),
    balance: widgetBalanceCell(monthBal, hideAmount: hideAmount),
  );
}
