import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/media_repository.dart';
import '../domain/media_item.dart';

/// 影音游模块 providers（批2 · 影音架）。
///
/// 写库后统一 `mediaTickProvider.state++` 触发重取（与 readTickProvider 同法）。

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MediaRepository(AppDatabase.instance.db),
);

final mediaTickProvider = StateProvider<int>((ref) => 0);

/// 影音架视图：桌面 / 脊 / 列表（原型 mCurView，偏好属 §七 media.defaultView）。
final mediaViewProvider = StateProvider<String>((ref) => 'desk');

/// 类型 chip（all|movie|series|music|game）。
final mediaKindProvider = StateProvider<String>((ref) => 'all');

/// 分区 chip（all ＋ 该 kind 的分区名；all 类型下吃四档语义归并）。
final mediaStateProvider = StateProvider<String>((ref) => 'all');

/// 关键词（片名/原名/主创/发行/标签，原型 mFilter 同范围）。
final mediaQueryProvider = StateProvider<String>((ref) => '');

/// 影音架在册条目（筛选与排序的唯一取数面；deleted 行永不进来）。
final mediaItemsProvider = FutureProvider<List<MediaItem>>((ref) {
  ref.watch(mediaTickProvider);
  final kind = ref.watch(mediaKindProvider);
  return ref
      .watch(mediaRepositoryProvider)
      .items(
        kind: kind,
        stateGroup: ref.watch(mediaStateProvider),
        query: ref.watch(mediaQueryProvider),
        sort: ref.watch(mediaSortProvider),
      );
});

/// 类型 chip 角标计数（与架面同源，不受关键词影响＝在册总量口径）。
final mediaKindCountsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).kindCounts();
});

/// 桌面俯瞰 · 最近四条（记录页影音游 tab 用）。
final mediaRecentProvider = FutureProvider<List<MediaItem>>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).recentPerKind();
});

/// 排序键（§七 media.sortDefault＝recent）。
final mediaSortProvider = StateProvider<String>((ref) => 'recent');
