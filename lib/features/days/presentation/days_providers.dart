import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/providers.dart';
import '../../todo/domain/todo.dart';
import '../../todo/presentation/todo_providers.dart';
import '../data/days_repository.dart';
import '../domain/day_calc.dart';
import '../domain/day_models.dart';

/// 日子模块 providers（仿 care/ledger：写库后 tick++ 全量重取快照）。

final daysRepositoryProvider =
    Provider<DaysRepository>((ref) => DaysRepository(AppDatabase.instance.db));

final daysTickProvider = StateProvider<int>((ref) => 0);

/// 时间源缝（careClockProvider 先例）：测试播种固定 now，消除跨日界抖动。
final daysClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 全域快照（列表/详情/提醒中心/仪表盘卡共用）。
/// 加载即重排各级提前提醒（NotificationService 未就绪环境全程静默 no-op）。
final daysDataProvider = FutureProvider<DaysData>((ref) async {
  ref.watch(daysTickProvider);
  final now = ref.watch(daysClockProvider)();
  final data = await ref.watch(daysRepositoryProvider).loadAll(now: now);
  syncDayNotifications(data.days, now);
  return data;
});

void daysTouch(WidgetRef ref) => ref.read(daysTickProvider.notifier).state++;
void daysTouchRef(Ref ref) => ref.read(daysTickProvider.notifier).state++;

/// 通知重排视界（未来 45 天内应触发的档位逐档注册/撤销，幂等）。
const kDayNotifHorizonDays = 45;

Future<void> syncDayNotifications(List<DayEntry> days, DateTime now) async {
  if (!NotificationService.ready) return;
  for (final d in days.where((x) => x.id != null)) {
    final hits = upcomingReminders(d, now, kDayNotifHorizonDays);
    for (final slot in NotificationService.dayOffsetSlots) {
      final hit = hits.where((h) => h.offset == slot).firstOrNull;
      if (hit == null) {
        await NotificationService.cancelDayReminder(d.id!, slot);
      } else {
        await NotificationService.registerDayReminder(
          dayId: d.id!,
          offset: slot,
          title: d.title,
          remindDay: hit.remindAt,
        );
      }
    }
  }
}

/// 日子发生日展示串（详情 hero「N 天后 · X月X日」）。
String occurrenceDateText(DateTime occ) => '${occ.month}月${occ.day}日';

// ==================== 联动出口（L3 转待办） ====================

/// 准备事项勾选即转待办（去重：已带 todo_id 不重复生成）。
/// 返回生成的待办 id；prepToTodo 关或已转过返回 null。
Future<int?> dayPrepToTodo(
    WidgetRef ref, DayEntry day, DayPrep prep, DateTime now) async {
  if (!day.prepToTodo || prep.todoId != null) return null;
  final occ = nextOccurrence(day, now);
  final todo = await ref.read(todoRepositoryProvider).add(Todo(
        title: prep.text,
        tag: '日子',
        quadrant: Quadrant.q2,
        dueAt: DateTime(occ.year, occ.month, occ.day, 18),
        note: '来自「${day.title}」准备事项',
      ));
  if (todo.id != null && prep.id != null) {
    await ref.read(daysRepositoryProvider).setPrepTodo(prep.id!, todo.id!);
  }
  return todo.id;
}

/// 「全部转待办」（详情页一键）。返回新生成条数。
Future<int> dayPrepsAllToTodo(WidgetRef ref, DayEntry day, DateTime now) async {
  var n = 0;
  for (final p in day.preps) {
    if (await dayPrepToTodo(ref, day, p, now) != null) n++;
  }
  return n;
}

/// 提醒中心「延后处理 → 转待办」（订阅=续订 X / 其余=办理 X；urg=一周内）。
Future<int> reminderToTodo(WidgetRef ref, ReminderItem r, DateTime now) async {
  final title = r.kind == 'sub' ? '续订 ${r.title}' : '办理 ${r.title}';
  final due = r.effectiveDate;
  final soon = dayDiff(now, due) <= 7;
  final todo = await ref.read(todoRepositoryProvider).add(Todo(
        title: title,
        tag: '日子',
        quadrant: Quadrant.q2,
        dueAt: DateTime(due.year, due.month, due.day, 18),
        remindAt: soon ? DateTime(due.year, due.month, due.day, 9) : null,
      ));
  return todo.id ?? 0;
}

/// 待办仓库门面复用（仪表盘卡片等处 import 本文件即可，不直触 todo 模块）。
final daysTodoRepositoryProvider = Provider(
    (ref) => ref.read(todoRepositoryProvider));

/// 全局搜索/事件总线挂载点保留位（批4 联动收口统一接线）。
final daysLinkageBusProvider = Provider((ref) => ref.read(eventBusProvider));
