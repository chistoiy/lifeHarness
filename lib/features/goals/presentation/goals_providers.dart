import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/goals_repository.dart';
import '../domain/goal_models.dart';

/// 目标模块 providers（仿 care/items：写库后 tick++ 全量重取快照）。

final goalsRepositoryProvider =
    Provider<GoalsRepository>((ref) => GoalsRepository(AppDatabase.instance.db));

final goalsTickProvider = StateProvider<int>((ref) => 0);

/// 时间源缝：周期切换/进行中判定/汇聚窗口按固定 now 实算（测试可覆盖）。
final goalsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final goalsDataProvider = FutureProvider<GoalsData>((ref) {
  ref.watch(goalsTickProvider);
  return ref.watch(goalsRepositoryProvider).loadAll(now: ref.watch(goalsClockProvider)());
});

void goalsTouch(WidgetRef ref) => ref.read(goalsTickProvider.notifier).state++;
void goalsTouchRef(Ref ref) => ref.read(goalsTickProvider.notifier).state++;

/// 当前周期指针（列表 ‹› 切换与编辑周期 chips 默认值；跨导航保留）。
final goalsPeriodProvider = StateProvider<String>((ref) {
  final now = ref.watch(goalsClockProvider)();
  return '${now.year} Q${(now.month - 1) ~/ 3 + 1}';
});

/// 列表视角：quarter 周期视角 | year 年度视角（跨周期总览含归档）。
final goalsViewProvider = StateProvider<String>((ref) => 'quarter');
