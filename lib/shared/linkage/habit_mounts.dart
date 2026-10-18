import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/providers.dart';
import '../../features/habit/data/habit_repository.dart';
import '../../features/habit/domain/habit.dart';
import '../../features/habit/domain/habit_calc.dart';
import '../../features/habit/domain/habit_entry.dart';
import '../../features/habit/presentation/habit_providers.dart';
import '../../features/todo/domain/todo.dart';
import '../../features/todo/presentation/todo_providers.dart';
import '../widgets/nfc_receipt.dart' show nfcReceiptLater;
import 'linkage_events.dart';

/// 习惯 ⇄ 待办/番茄/日程 联动挂载点（习惯计划 §7 · 仿 read_mounts 惯例）。
/// 待办模块不直接 import 习惯模块，统一经本文件编排（宿主事件总线 L10）。
///
/// 口径：
/// - L10 正向：新建习惯勾选「待办勾选」源并开启关联待办时，经
///   [habitLinkedTodoDraft] 生成标题「打卡：<习惯名>」的待办（V1.23 既有
///   标题约定），`habits.todo_id` 记回该待办；`todos.habit_id` 为 int 历史
///   预留而习惯主键是 TEXT，链接真源＝标题约定 + `habits.source_kinds`。
/// - L10 反向：待办勾选完成 → [habitLinkageProvider] 订阅
///   [TaskCompletedEvent] → [habitSyncFromTitle] 回写打卡
///   （origin=auto-todo · 受 habit.autoChk / habit.autoMode 门控，§5-8）。
/// - L4 时间账本：番茄/阅读计时时长由各模块写入，习惯侧只落流水引用来源、
///   不重复写账本（防双计——此为口径声明，无代码）。
/// - L7 目标汇聚：今日达成聚合入口 [habitTodayAgg]，仪表盘「今日习惯」卡
///   （主页自由编排批次）直接消费，不另起算法。

/// 关联待办标题（新建习惯自动生成时用）。
String habitLinkedTodoTitle(String habitName) => '打卡：$habitName';

/// 关联待办草稿（形态：norm=常规勾选 / pomo=番茄档 25 分钟倒计时）。
Todo habitLinkedTodoDraft(String habitName, {required String form}) => Todo(
  title: habitLinkedTodoTitle(habitName),
  pomoMode: form == 'pomo' ? 'down' : null,
  pomoMin: form == 'pomo' ? 25 : null,
);

/// 落库一条关联待办（编辑弹层保存前调用，返回待办 id 以回写 todo_id）。
Future<int?> habitCreateLinkedTodo(
  WidgetRef ref,
  String habitName, {
  required String form,
}) async {
  final t = await ref.read(todoRepositoryProvider).add(
    habitLinkedTodoDraft(habitName, form: form),
  );
  return t.id;
}

/// 标题 → 自动达成回写（原型 syncHabit 口径）。
/// 返回 null＝非打卡约定标题/未找到绑定习惯；否则为拦截文案（今日已打卡等）。
Future<String?> habitSyncFromTitle(HabitRepository repo, String title) async {
  if (!title.startsWith('打卡：')) return null;
  final name = title.substring(3).trim();
  if (name.isEmpty) return null;
  final book = [
    for (final h in await repo.allHabits())
      if (!h.isArchived &&
          h.type == Habit.kPos &&
          h.sourceKinds.contains('待办勾选') &&
          h.name == name)
        h,
  ];
  if (book.isEmpty) return null;
  return repo.autoIngest(book.first, src: '待办勾选');
}

/// 应用根部订阅（app.dart watch）：待办完成事件 → 习惯回写 + 习惯域刷新。
final habitLinkageProvider = Provider<void>((ref) {
  final sub = ref.watch(eventBusProvider).on<TaskCompletedEvent>().listen(
    (e) async {
      final todos = await ref.read(todoRepositoryProvider).list();
      final hit = todos.where((x) => x.id == e.todoId).toList();
      if (hit.isEmpty) return;
      final done = await habitSyncFromTitle(
        ref.read(habitRepositoryProvider),
        hit.first.title,
      );
      if (done == null) return;
      ref.read(habitTickProvider.notifier).state++;
    },
  );
  ref.onDispose(sub.cancel);
});

/// L7 今日达成聚合（仪表盘卡消费）：(已打卡, 应打卡, 达成率%)。
(int, int, int) habitTodayAgg(HabitData d, DateTime today) {
  final t = dayStart(today);
  final k = dayKey(t);
  final due = d.dueToday(t);
  final done = due.where((h) => d.okOn(h, k)).length;
  return (done, due.length, due.isEmpty ? 0 : (done * 100 / due.length).round());
}

/// 习惯条目（id＋名 · **原名不加工**）——跨模块「挑一条习惯」用（批1b 起：
/// NFC 卡片「打卡」目标选择器消费）。
///
/// 与 [habitSyncFromTitle] 同源（同一个 `HabitRepository.allHabits()`：未删除，
/// 含归档——归档≠删除，归档习惯仍可被绑定）。**名字的原样给出**：要不要剥装饰符
/// 是消费方的事（NFC 模块零 emoji 是它的硬要求，见 `nfc_mounts.dart`），
/// 本文件不做任何展示层加工。
Future<List<HabitOption>> habitOptionList([Database? db]) async {
  final repo = HabitRepository(db ?? AppDatabase.instance.db);
  final list = await repo.allHabits();
  return [for (final h in list) HabitOption(id: h.id, name: h.name)];
}

/// 一个习惯条目（跨模块只读视图）。
class HabitOption {
  const HabitOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// 打卡结果（NFC 贴卡消费 · 2026-10-17）。
class HabitCheckOutcome {
  const HabitCheckOutcome({
    required this.checked,
    required this.already,
    required this.name,
    required this.streak,
  });

  /// 本次是否真的新打卡（false ＋ [already] ＝ 今天早就打过了）。
  final bool checked;

  /// 今天已打卡——**不撤销**（贴卡是「补一下」不是「切换」，误触不该抹掉记录）。
  final bool already;

  final String name;

  /// 打卡后的连续天数。
  final int streak;
}

/// 按习惯 id 打卡（NFC 贴卡出口 · 2026-10-17 产品令）。
///
/// 口径与打卡页手动打卡**同源**：`upsertEntry(checked:true, origin:manual)`，
/// 连续天数由仓库重算后回读。**已打卡不重复计、也不撤销**。
/// 打卡成功同时发一条 Heads-Up 横幅（与打卡页同一出口 ⇒ 两处行为一致）。
///
/// 返回 null ＝ 习惯不在册（已删）。
///
/// ⚠ 写库核心已抽成 [habitCheckinWrite]——小组件后台 isolate 打卡
/// （`widget_checkin_mounts.dart`）与之**共用同一实现**：两处入口可以不同
/// （一个按 id 一个按名字），写库口径禁分叉（评估件 §4.1：打卡不是单列写，
/// 复刻＝行为分叉）。
Future<HabitCheckOutcome?> habitCheckInById(
  String habitId, {
  Database? db,
  DateTime? now,
}) async {
  final repo = HabitRepository(db ?? AppDatabase.instance.db);
  final h = await repo.habitById(habitId);
  if (h == null) return null;
  final out = await habitCheckinWrite(repo, h, now: now);
  // 回执**延后发**（不 await）：本出口的唯一调用方是 NFC 贴卡——App 在执行链上
  // 可能正在退后台，横幅得等界面落定再弹（前台则由触发链自己的 toast 覆盖）。
  // 批3e：改走自绘悬浮横幅（系统 Heads-Up 在本机 ROM 上只进通知栏不上浮）。
  unawaited(nfcReceiptLater(
      out.streak > 0 ? '打卡成功 · ${h.name} · 连续 ${out.streak} 天' : '打卡成功 · ${h.name}'));
  return out;
}

/// 打卡写库核心（**NFC 贴卡与小组件后台打卡共用的唯一写出口**）。
///
/// 口径＝打卡页手动打卡：`upsertEntry(checked:true, origin:manual)`，连续天数
/// 由仓库重算后回读。**已打卡不重复计、也不撤销**（贴卡/点小组件都是「补一下」，
/// 误触不该抹掉记录）。整段不含任何 UI/回执依赖——后台 isolate 可直接调用。
///
/// ⚠ [h] 必须已在册（调用方负责判空）；习惯被删/改名后原样调用会抛，由上层兜。
Future<HabitCheckOutcome> habitCheckinWrite(
  HabitRepository repo,
  Habit h, {
  DateTime? now,
}) async {
  final t = now ?? DateTime.now();
  final k = dayKey(t);
  final entries = await repo.entriesOf(h.id);
  if (entries[k]?.checked ?? false) {
    return HabitCheckOutcome(
        checked: false, already: true, name: h.name, streak: h.streak);
  }
  await repo.upsertEntry(
    h.id,
    day: k,
    checked: true,
    origin: HabitEntry.oManual,
    checkAt: '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}',
  );
  final after = await repo.habitById(h.id);
  return HabitCheckOutcome(
      checked: true, already: false, name: h.name, streak: after?.streak ?? 0);
}

/// 数值型习惯「加一档」写库核心（桌面 `+N` 按钮 · 2026-10-18 真机报障补）。
///
/// ## 为什么不能复用 [habitCheckinWrite]
///
/// 那个函数是**布尔**口径：`checked:true` 且**不带 value**，且「已打卡就返回
/// already」——对数值型习惯（喝水 8 杯／阅读 30 分钟）意味着桌面点一下就
/// 「今天完成了」，量还是空的。用户原话：「带数值的打卡也只显示一个打卡，
/// 不显示数值修改能力」。
///
/// 本函数口径＝App 内记量弹层 `_save()` 的**增量版**：
///  · 读今日已有流水 → 当前值（无记录＝0）；
///  · `+ habitStepOf(goal)`（与弹层加减按钮同一个 domain 阶梯，禁各算一套）；
///  · `upsertEntry(checked:true, value:新值)` —— **已达标也照样加**
///    （喝了第 9 杯就是 9 杯，卡在目标上等于把真数据抹掉）；
///  · `checkAt` 保留首次打卡时刻（同弹层 `e?.checkAt ?? now`）。
///
/// 不加「只允许加不许减」之外的守卫：负数目标/0 目标不走本函数（调用方按
/// `goal > 0` 分流，见 `widgetCheckinByName`）。
Future<HabitCheckOutcome> habitIncrementWrite(
  HabitRepository repo,
  Habit h, {
  DateTime? now,
}) async {
  final t = now ?? DateTime.now();
  final k = dayKey(t);
  final entries = await repo.entriesOf(h.id);
  final cur = entries[k];
  final step = habitStepOf(h.goal ?? 0);
  final next = (cur?.value ?? 0) + step;
  await repo.upsertEntry(
    h.id,
    day: k,
    checked: true,
    value: next,
    origin: HabitEntry.oManual,
    checkAt: cur?.checkAt ??
        '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}',
  );
  final after = await repo.habitById(h.id);
  return HabitCheckOutcome(
      checked: true, already: false, name: h.name, streak: after?.streak ?? 0);
}
