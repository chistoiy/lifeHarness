import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../features/journal/presentation/journal_providers.dart';
import '../../features/todo/presentation/todo_providers.dart';
import 'linkage_events.dart';

/// 日记 ⇄ 待办 L3 联动挂载点（语义断链批 2026-10-12 · 仿 habit_mounts 惯例）。
/// 待办模块不直接 import 日记模块，统一经本文件编排（宿主事件总线）。
///
/// 口径：
/// - L3 正向（既有）：日记正文 ☐ 行保存时同步为待办（`diary_edit_page._syncTodoLines`，
///   tag='日记'，标题＝行文本）。
/// - L3 反向（本批补齐，需求 L3「双向同步」）：待办完成 → [TaskCompletedEvent] →
///   [JournalRepository.tickTodoLine] 回勾日记正文同名 ☐ 行（链路真源＝标题约定，
///   同 habit L10；tag='日记' 门控，用户自建待办不打日记）。未命中静默（待办可能
///   已与日记解钩——删行/改文后完成旧待办不回写任何篇）。
/// - 解勾不做：待办取消完成不回退日记行（事件只在完成侧发布；保持简单口径）。

/// 应用根部订阅（app.dart watch）：待办完成事件 → 日记回勾 + 日记域刷新。
final journalLinkageProvider = Provider<void>((ref) {
  final sub = ref.watch(eventBusProvider).on<TaskCompletedEvent>().listen(
    (e) async {
      final todos = await ref.read(todoRepositoryProvider).list();
      final hit = todos.where((x) => x.id == e.todoId).toList();
      if (hit.isEmpty || hit.first.tag != '日记') return;
      final ok = await ref
          .read(journalRepositoryProvider)
          .tickTodoLine(hit.first.title);
      if (ok) ref.invalidate(journalsProvider);
    },
  );
  ref.onDispose(sub.cancel);
});
