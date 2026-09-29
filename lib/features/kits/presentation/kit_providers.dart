/// 小工具合集 providers（照 habit_providers 范式：写库后 tick++ 全量重取）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/kit_repository.dart';
import '../domain/kit_models.dart';

final kitRepositoryProvider = Provider<KitRepository>(
  (ref) => KitRepository(AppDatabase.instance.db),
);

/// 变更计数：任何写库后自增，让首页/统计页重新取数。
final kitTickProvider = StateProvider<int>((ref) => 0);

/// 首页一次取齐的数据包（足迹 + 收藏 + 隐藏 + 编排 + 数据位 + 插件）。
class KitHomeData {
  const KitHomeData({
    required this.log,
    required this.fav,
    required this.hidden,
    required this.order,
    required this.hero,
    required this.recent,
    required this.plugins,
  });

  final List<KitUsage> log;
  final List<String> fav;
  final List<String> hidden;
  final List<String>? order;
  final List<KitMetric> hero;
  final List<String> recent;
  final List<KitPlugin> plugins;
}

final kitHomeProvider = FutureProvider<KitHomeData>((ref) async {
  ref.watch(kitTickProvider);
  final repo = ref.watch(kitRepositoryProvider);
  return KitHomeData(
    log: await repo.usage(),
    fav: await repo.favorites(),
    hidden: await repo.hidden(),
    order: await repo.order(),
    hero: await repo.heroSlots(),
    recent: await repo.recent(),
    plugins: await repo.plugins(),
  );
});
