import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../data/todo_dao.dart';
import '../domain/todo.dart';
import '../domain/todo_repository.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(TodoDao(AppDatabase.instance.db), ref.watch(eventBusProvider));
});

/// 同一条读取异常只在首次留痕：Provider 失败态每次 build 都会重读重抛，
/// 全记会把 300 行环形缓冲刷满（同 L2「取消与开关关不记」的降噪口径）。
/// 按文案去重，故「列表」与「逾期计数」各自仍有一条。
final Set<String> _readErrLogged = {};

void _logReadErrOnce(String what, Object e) {
  if (!_readErrLogged.add(what)) return;
  AppLog.add('$what：$e（同类只记一次）', level: LhLevel.error);
}

/// 全部待办（变更后 invalidate 刷新）。
/// 读取异常照常抛出（`rethrow` 不改控制流），但必须留痕：
/// 消费侧一律 `valueOrNull ?? 默认值`，不记日志就会把「读失败」看成「空列表」。
final todosProvider = FutureProvider<List<Todo>>((ref) async {
  try {
    return await ref.watch(todoRepositoryProvider).list();
  } catch (e) {
    _logReadErrOnce('待办列表读取失败（页面将显示为空）', e);
    rethrow;
  }
});

/// 逾期计数（仪表盘角标 / 列表头提示共用）。
final overdueCountProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(todoRepositoryProvider).countOverdue();
  } catch (e) {
    _logReadErrOnce('待办逾期扫描失败（角标将显示 0）', e);
    rethrow;
  }
});

/// 番茄会话（V1.20 · 单活：全局同时仅一个番茄，与日程「进行中」同规则）。
class PomoSession {
  PomoSession({
    required this.todoId,
    required this.title,
    required this.mode,
    this.minutes,
    DateTime? startedAt,
  })  : startedAt = startedAt ?? DateTime.now();

  final int todoId;
  final String title;

  /// up=正计时 / down=倒计时。
  final String mode;
  final int? minutes;

  /// T7：页内「重置」需原地重设起点，故可变。
  DateTime startedAt;

  /// 累计暂停毫秒与本次暂停起点（V1.22.1：暂停期间时钟冻结，不计耗时）。
  int pausedMs = 0;
  DateTime? pauseStarted;

  int elapsedSec() {
    final live = DateTime.now().difference(startedAt).inMilliseconds -
        pausedMs -
        (pauseStarted == null ? 0 : DateTime.now().difference(pauseStarted!).inMilliseconds);
    return (live ~/ 1000).clamp(0, 24 * 3600);
  }

  int runningSec() =>
      DateTime.now().difference(startedAt).inMilliseconds ~/ 1000 - pausedMs ~/ 1000;
}

final activePomoProvider = StateProvider<PomoSession?>((ref) => null);

/// 列表 / 四象限视图切换（页面级临时状态）。
final todoViewModeProvider = StateProvider<bool>((ref) => false); // false=清单 true=四象限

/// 清单智能筛选（原型 todoChips）：all/today/week/scheduled/done/overdue。
final todoFilterProvider = StateProvider<String>((ref) => 'all');

/// V1.26 筛选面板开合（顶栏漏斗按钮控制；清单视图只留列表防臃肿）。
final todoFilterOpenProvider = StateProvider<bool>((ref) => false);
