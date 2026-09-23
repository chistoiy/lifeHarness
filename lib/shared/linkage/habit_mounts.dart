import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../features/habit/data/habit_repository.dart';
import '../../features/habit/domain/habit.dart';
import '../../features/habit/domain/habit_calc.dart';
import '../../features/habit/presentation/habit_providers.dart';
import '../../features/todo/domain/todo.dart';
import '../../features/todo/presentation/todo_providers.dart';
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
