/// 跨模块联动事件（L1~L14 编排的载荷占位）。
///
/// 联动经 `shared/linkage` 服务 + 事件总线解耦（ADR D8），防止 feature 循环依赖。
/// 骨架阶段仅定义少数高频事件类型，业务实现随后续里程碑补 *Service。
library;

/// 任务完成 → 可用于今日概览/习惯统计刷新（L 关联待办↔仪表盘）。
///
/// **批5 扩口径**：`source` 标注完成动作来自哪个域，默认 `'todo'` ⇒ **既有全部
/// 构造点（`todo_repository` 唯一发射处）逐值不变，行为零变化**。非待办域的
/// 「完成」另有自己的事件类（如导图节点的 `MmNodeTaskEvent`），**不塞进本类**——
/// `todoId` 语义被污染后订阅方无法区分来源（工单 §4f.3 口径二）。
class TaskCompletedEvent {
  const TaskCompletedEvent(this.todoId, this.atMs, {this.source = 'todo'});
  final int todoId;
  final int atMs;
  final String source;
}

/// 记录写入（收集箱/日记/记账等新增）→ 仪表盘与角标刷新。
class RecordAddedEvent {
  const RecordAddedEvent(this.source, this.refId, this.atMs);
  final String source; // 'inbox' | 'journal' | 'finance' | ...
  final int refId;
  final int atMs;
}

/// 日程「开始/结束」两态流转 → 计时条与耗时回填（L1/L4）。
class TimeTrackingEvent {
  const TimeTrackingEvent(this.eventId, this.started, this.atMs);
  final int eventId;
  final bool started;
  final int atMs;
}

/// 主题切换事件（供需要感知换肤的模块刷新）。
class ThemeChangedEvent {
  const ThemeChangedEvent(this.themeId);
  final String themeId;
}

/// 快捷记录请求（仪表盘 FAB 菜单 → 目标模块自行打开新增弹层）。
/// target: 'todo' | 'inbox' | 'journal' | 'event' | 'items'。
class QuickAddEvent {
  const QuickAddEvent(this.target);
  final String target;
}

/// V1.27 P3：设置页「主页编排直达」→ 跳今天页并直接进入卡片编排模式。
class EnterDashEditEvent {
  const EnterDashEditEvent();
}
