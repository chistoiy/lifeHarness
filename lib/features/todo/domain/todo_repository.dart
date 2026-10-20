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

  /// **按 id** 标记完成（批3 · 桌面勾圈补写用；手上只有 id、没有整条 Todo）。
  ///
  /// 与 [toggleDone] 的区别：后者要 `Todo` 对象（取 `!t.done` 反值 + 撤提醒 + 发事件）。
  /// 补写场景拿到的 id 可能对应的待办已被 App 内操作完成过 ⇒ 这里**只置 done**，
  /// 不反值、不重复撤提醒（撤了会误伤用户在 App 内重新勾上的同一条）。已完成的
  /// 调用是 no-op（`setDone` 幂等）。
  Future<void> completeById(int id) => _dao.setDone(id, true);

  /// 拖拽改象限（AC：<300ms 持久化，直接 await 单条 UPDATE）。
  Future<void> moveQuadrant(Todo t, Quadrant q) => _dao.setQuadrant(t.id!, q);

  /// 长按拖拽排序（V1.27 T6）：按新展示序持久化 sort_order。
  Future<void> reorder(List<int> ids) => _dao.reorder(ids);

  Future<void> remove(Todo t) async {
    await _dao.remove(t.id!);
    await NotificationService.cancel(t.id!);
  }

  // ---- V1.57 E 批 · 待办垃圾箱 ----

  /// 删除＝软删进垃圾箱：撤提醒（恢复时重排）；清单/象限/今日数字即时消失。
  Future<void> softRemove(Todo t) async {
    await _dao.softRemove(t.id!);
    await NotificationService.cancel(t.id!);
  }

  Future<List<Todo>> trashed() => _dao.trashed();

  /// 恢复＝回原象限原截止（同一条目，不新建）；提醒重排。
  Future<void> restore(Todo t) async {
    await _dao.restore(t.id!);
    if (!t.done) {
      await NotificationService.scheduleTodo(
          id: t.id!, title: t.title, remindAt: t.remindAt);
    }
  }

  /// 彻底删除（真删·不可恢复）。
  Future<int> purge(List<int> ids) => _dao.purge(ids);
}
