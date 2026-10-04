import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/logging/app_log.dart';
import '../../features/habit/presentation/habit_providers.dart';
import '../../features/journal/presentation/journal_providers.dart';
import '../../features/read/presentation/read_providers.dart';
import '../../features/todo/domain/todo.dart';
import '../../features/todo/presentation/todo_providers.dart';
import 'trash_models.dart';
import 'trash_repository.dart';

/// 回收站仓储（六表只读出口）。
final trashRepositoryProvider =
    Provider<TrashRepository>((ref) => TrashRepository(AppDatabase.instance.db));

/// 写库后自增，触发 [trashItemsProvider] 重取（与 readTick/habitTick 同法）。
final trashTickProvider = StateProvider<int>((ref) => 0);

/// 六类垃圾箱条目（按删除时间倒序）。
///
/// 真机走查 6059 抓到：进屏前删的条目不会自动出现——FutureProvider 会缓存上一次结果。
/// 修法＝**监听六类源模块的写信号并自我失效**，而不是在十处删除入口各埋一次刷新：
/// 待办/笔记走各自 provider 的重取，习惯与阅读（书·划线·书单）走各自 tick。
final trashItemsProvider = FutureProvider<List<TrashItem>>((ref) {
  ref.listen(todosProvider, (_, _) => ref.invalidateSelf());
  ref.listen(notesProvider, (_, _) => ref.invalidateSelf());
  ref.listen(habitTickProvider, (_, _) => ref.invalidateSelf());
  ref.listen(readTickProvider, (_, _) => ref.invalidateSelf());
  ref.listen(trashTickProvider, (_, _) => ref.invalidateSelf());
  return ref.watch(trashRepositoryProvider).items();
});

/// 分段计数（含「全部」）——屏内 chips、记录管理行、待办页卡、笔记抽屉行四处同源。
final trashCountsProvider = Provider<({int total, Map<TrashKind, int> byKind})>(
    (ref) {
  final items = ref.watch(trashItemsProvider).valueOrNull ?? const <TrashItem>[];
  final byKind = <TrashKind, int>{for (final k in TrashKind.values) k: 0};
  for (final it in items) {
    byKind[it.kind] = (byKind[it.kind] ?? 0) + 1;
  }
  return (total: items.length, byKind: byKind);
});

/// 回收站动作出口（恢复/彻底删除按模块分派，并把各模块读数刷回原位）。
class TrashService {
  TrashService(this.ref);

  final Ref ref;

  /// 恢复＝回原模块原位（同一条记录，不新建）。孤行由屏层拦在外面，不会走到这里。
  Future<TrashOpResult> restore(List<TrashItem> items) async {
    for (final it in items) {
      await _restoreOne(it);
    }
    _refreshFor({for (final it in items) it.kind});
    final kinds = items.map((e) => e.kind.label).join('·');
    AppLog.addKey('回收站恢复 ${items.length} 项：$kinds');
    return TrashOpResult(count: items.length);
  }

  /// 彻底删除＝真 DELETE；书籍走连带口径（在库摘录/计时/目录/进度一起清）。
  Future<TrashOpResult> purge(List<TrashItem> items) async {
    var quotes = 0;
    var hadBook = false;
    for (final it in items) {
      if (it.kind == TrashKind.book) {
        hadBook = true;
        quotes += await ref
            .read(readRepositoryProvider)
            .purgeBook(it.rawId as String);
      } else {
        await _purgeOne(it);
      }
    }
    _refreshFor({for (final it in items) it.kind});
    AppLog.addKey('回收站彻底删除 ${items.length} 条'
        '${hadBook ? ' · 含书籍（连带清在库摘录 $quotes 条）' : ''}');
    return TrashOpResult(
        count: items.length, purgedBookQuotes: quotes, hadBook: hadBook);
  }

  Future<void> _restoreOne(TrashItem it) async {
    switch (it.kind) {
      case TrashKind.todo:
        await ref.read(todoRepositoryProvider).restore(it.src! as Todo);
      case TrashKind.note:
        await ref.read(noteDaoProvider).restore(it.rawId as int);
      case TrashKind.habit:
        await ref
            .read(habitRepositoryProvider)
            .restoreHabit(it.rawId as String);
      case TrashKind.book:
        await ref.read(readRepositoryProvider).restoreBook(it.rawId as String);
      case TrashKind.quote:
        await ref.read(readRepositoryProvider).restoreQuote(it.rawId as int);
      case TrashKind.list:
        await ref.read(readRepositoryProvider).restoreList(it.rawId as int);
    }
  }

  Future<void> _purgeOne(TrashItem it) async {
    switch (it.kind) {
      case TrashKind.todo:
        await ref.read(todoRepositoryProvider).purge([it.rawId as int]);
      case TrashKind.note:
        await ref.read(noteDaoProvider).purge(it.rawId as int);
      case TrashKind.habit:
        await ref.read(habitRepositoryProvider).purgeHabit(it.rawId as String);
      case TrashKind.book:
      // 调用方分派（要收连带读数）。
        break;
      case TrashKind.quote:
        await ref.read(readRepositoryProvider).purgeQuote(it.rawId as int);
      case TrashKind.list:
        await ref.read(readRepositoryProvider).purgeList(it.rawId as int);
    }
  }

  /// 只刷被触及模块的读数：恢复/删除后各模块页数字即时补回。
  void _refreshFor(Set<TrashKind> kinds) {
    ref.read(trashTickProvider.notifier).state++;
    if (kinds.contains(TrashKind.todo)) {
      ref.invalidate(todosProvider);
      ref.invalidate(overdueCountProvider);
    }
    if (kinds.contains(TrashKind.note)) {
      ref.invalidate(notesProvider);
      ref.invalidate(noteTreeProvider);
    }
    if (kinds.contains(TrashKind.habit)) {
      ref.read(habitTickProvider.notifier).state++;
    }
    if (kinds.contains(TrashKind.book) ||
        kinds.contains(TrashKind.quote) ||
        kinds.contains(TrashKind.list)) {
      ref.read(readTickProvider.notifier).state++;
    }
  }

  /// 单项恢复回执（原型 ttRestore 文案映射）。
  String restoreToastFor(TrashItem it) => switch (it.kind) {
        TrashKind.todo =>
          '已恢复到「${(it.src! as Todo).quadrant.label}」',
        TrashKind.quote => it.subs.isEmpty
            ? '已恢复到原书'
            : '已恢复到${it.subs.first.replaceFirst('所属', '')}',
        _ => it.kind.restoreToast,
      };
}

final trashServiceProvider = Provider<TrashService>(
    (ref) => TrashService(ref));
