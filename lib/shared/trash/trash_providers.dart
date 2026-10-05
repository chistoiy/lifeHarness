import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/logging/app_log.dart';
import 'trash_models.dart';
import 'trash_repository.dart';
import 'trash_specs.dart';

/// 回收站仓储（各类只读出口的编排者）。
final trashRepositoryProvider =
    Provider<TrashRepository>((ref) => TrashRepository(AppDatabase.instance.db));

/// 写库后自增，触发 [trashItemsProvider] 重取（与 readTick/habitTick 同法）。
final trashTickProvider = StateProvider<int>((ref) => 0);

/// 各类垃圾箱条目（按删除时间倒序）。
///
/// 真机走查 6059 抓到：进屏前删的条目不会自动出现——FutureProvider 会缓存上一次结果。
/// 修法＝**监听各源模块的写信号并自我失效**，而不是在十处删除入口各埋一次刷新。
/// V1.61 起要听哪几路由注册表自带（[trashSourceSignals]），加一类不用再回来加一行。
final trashItemsProvider = FutureProvider<List<TrashItem>>((ref) {
  for (final p in trashSourceSignals) {
    ref.listen(p, (_, _) => ref.invalidateSelf());
  }
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

/// 回收站动作出口（恢复/彻底删除按登记项分派，并把各模块读数刷回原位）。
///
/// 本文件**不再按类别分支**：每类怎么恢复、怎么彻底删除、刷谁、回执说什么，
/// 全部在 `trash_specs.dart` 登记（工单 §C0）。
class TrashService {
  TrashService(this.ref);

  final Ref ref;

  /// 恢复＝回原模块原位（同一条记录，不新建）。孤行由屏层拦在外面，不会走到这里。
  Future<TrashOpResult> restore(List<TrashItem> items) async {
    for (final it in items) {
      await trashSpecOf(it.kind).restore(ref, it);
    }
    _refreshFor({for (final it in items) it.kind});
    final kinds = items.map((e) => e.kind.label).join('·');
    AppLog.addKey('回收站恢复 ${items.length} 项：$kinds');
    return TrashOpResult(count: items.length);
  }

  /// 彻底删除＝真 DELETE；连带口径（如书籍清在库摘录）由各类登记项自己返回条数。
  Future<TrashOpResult> purge(List<TrashItem> items) async {
    var cascade = 0;
    for (final it in items) {
      cascade += await trashSpecOf(it.kind).purge(ref, it);
    }
    _refreshFor({for (final it in items) it.kind});
    final hadBook = items.any((e) => e.kind == TrashKind.book);
    AppLog.addKey('回收站彻底删除 ${items.length} 条'
        '${hadBook ? ' · 含书籍（连带清在库摘录 $cascade 条）' : ''}');
    return TrashOpResult(
        count: items.length, purgedBookQuotes: cascade, hadBook: hadBook);
  }

  /// 只刷被触及模块的读数：恢复/删除后各模块页数字即时补回。
  /// 同 [TrashKindSpec.refreshGroup] 只刷一遍（阅读线三路共用一个 tick）。
  void _refreshFor(Set<TrashKind> kinds) {
    ref.read(trashTickProvider.notifier).state++;
    final seen = <Object>{};
    for (final k in kinds) {
      final s = trashSpecOf(k);
      if (seen.add(s.refreshGroup)) s.refresh(ref);
    }
  }

  /// 单项恢复回执（原型 ttRestore 文案映射；不给则走枚举缺省文案）。
  String restoreToastFor(TrashItem it) {
    final of = trashSpecOf(it.kind).restoreToastOf;
    return of != null ? of(it) : it.kind.restoreToast;
  }
}

final trashServiceProvider = Provider<TrashService>(
    (ref) => TrashService(ref));
