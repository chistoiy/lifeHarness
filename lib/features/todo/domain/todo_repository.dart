import '../../../core/host/event_bus.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../data/todo_dao.dart';
import '../domain/todo.dart';

/// 待办仓库：UI 不直接触 DAO（计划书 Repository 数据流约定）。
/// remind_at 联动通知排程（M0末A；NotificationService.ready=false 时全程 no-op）。
class TodoRepository {
  TodoRepository(this._dao, this._bus);

  final TodoDao _dao;
  final EventBus _bus;

  Future<List<Todo>> list() => _dao.list();

  Future<int> countOverdue() => _dao.countOverdue();

  Future<Todo> add(Todo t) async {
    final saved = await _dao.insert(t);
    _bus.publish(RecordAddedEvent('todo', saved.id!, DateTime.now().millisecondsSinceEpoch));
    await NotificationService.scheduleTodo(
        id: saved.id!, title: saved.title, remindAt: saved.remindAt);
    return saved;
  }

  Future<void> edit(Todo t) async {
    await _dao.update(t);
    await NotificationService.scheduleTodo(
        id: t.id!, title: t.title, remindAt: t.done ? null : t.remindAt);
  }

  Future<void> toggleDone(Todo t) async {
    await _dao.setDone(t.id!, !t.done);
    if (!t.done) {
      await NotificationService.cancel(t.id!); // 完成即撤提醒
      _bus.publish(TaskCompletedEvent(t.id!, DateTime.now().millisecondsSinceEpoch));
    } else {
      await NotificationService.scheduleTodo(
          id: t.id!, title: t.title, remindAt: t.remindAt);
    }
  }

  /// 拖拽改象限（AC：<300ms 持久化，直接 await 单条 UPDATE）。
  Future<void> moveQuadrant(Todo t, Quadrant q) => _dao.setQuadrant(t.id!, q);

  Future<void> remove(Todo t) async {
    await _dao.remove(t.id!);
    await NotificationService.cancel(t.id!);
  }
}
