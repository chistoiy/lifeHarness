import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/media_repo_dict.dart';
import '../data/media_repo_session.dart';
import '../data/media_repository.dart';
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import '../domain/media_summary.dart';

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

/// settings 表 `media.*` 键通用取值（计划 §七：KV 存 settings 表，不散落 SharedPreferences）。
final mediaKvProvider =
    FutureProvider.family<String, (String key, String def)>((ref, arg) async {
  ref.watch(mediaTickProvider);
  final raw = await ref.watch(mediaRepositoryProvider).kv(arg.$1);
  return raw ?? arg.$2;
});

/// 计时形态（§七 media.timerUI＝capsule；full＝起停直接进沉浸页）。
final mediaTimerUIProvider = FutureProvider<String>(
  (ref) => ref.watch(mediaKvProvider(('media.timerUI', 'capsule')).future),
);

/// 悬浮计时条开关（media.floatBar，默认开）。
final mediaFloatBarProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(mediaKvProvider(('media.floatBar', 'true')).future)) ==
      'true',
);

/// 结束计时即弹记进度（media.autoAsk，默认开）。
final mediaAutoAskProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(mediaKvProvider(('media.autoAsk', 'true')).future)) ==
      'true',
);

/// 影音悬浮条可见＝有在跑会话 × floatBar 开（与 read 侧 readTimerBarVisibleProvider 同法）。
/// 两路读数都按「取不到＝不显示」的 AsyncValue 口径走，不硬断言非空。
final mediaTimerBarVisibleProvider = Provider<bool>((ref) {
  // floatBar 默认开＝装载中也按开处理，读数落地后再校正。
  final floatOn = ref.watch(mediaFloatBarProvider).valueOrNull ?? true;
  final running = ref.watch(mediaRunningSessionProvider).valueOrNull;
  return floatOn && running != null;
});

/// 全库单活的影音会话（杀进程重开延续靠这条库内读数，不存内存态）。
final mediaRunningSessionProvider = FutureProvider<MediaSession?>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).runningSession();
});

/// 详情/计时页条目取数（软删行＝null＝屏走「已不在架」空态）。
final mediaItemDetailProvider = FutureProvider.family<MediaItem?, String>((
  ref,
  id,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).itemById(id);
});

/// 条目「一页总结」（final_note JSON 三键；空＝MediaSummary()，UI 侧出虚线属 A3）。
final mediaSummaryProvider = FutureProvider.family<MediaSummary, String>((
  ref,
  id,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).summaryOf(id);
});

/// 单条目会话明细（倒序；进行中那条置顶由页面处理）。
final mediaSessionsProvider = FutureProvider.family<List<MediaSession>, String>((
  ref,
  id,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).sessionsOf(id);
});

/// 单条目累计入账分钟（详情统计行）。
final mediaMinutesProvider = FutureProvider.family<int, String>((ref, id) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).minutesOfItem(id);
});

/// 管理器当前类（原型 mMgrTab＝src/grp/creator/pub/tags）。
final mediaDictTabProvider = StateProvider<String>((ref) => 'source');

/// 一类名册清单（名册 ∪ 条目实际值＋引用数；写库后随 mediaTick 重取）。
final mediaDictRowsProvider =
    FutureProvider.family<List<({String name, int refCount})>, String>((
  ref,
  tab,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).dictRows(
    MediaDictRepo.dictKinds[tab] ?? tab,
  );
});
