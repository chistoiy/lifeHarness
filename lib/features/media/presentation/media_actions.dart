import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/linkage/stats_providers.dart'
    show dayBlocksProvider, monthBlockDaysProvider;
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import 'media_providers.dart';

/// 影音游会话结算/进度写回后通知时间模块（6075 实机教训的 media 侧同款：
/// L4 块是 repo 层落库，时间侧日视图与月圆点不 invalidate 不会重取）。
void refreshTimeAfterMediaSession(ProviderContainer c, Iterable<int?> atMs) {
  final days = <DateTime>{};
  for (final ms in atMs.whereType<int>()) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    days.add(DateTime(d.year, d.month, d.day));
  }
  for (final day in days) {
    c.invalidate(dayBlocksProvider(day));
    c.invalidate(monthBlockDaysProvider((day.year, day.month)));
  }
}


/// 计时条/沉浸页的按 kind 文案（刀3：这张表退回单一「观影中」，悬浮条用例即红）。
String mediaTimerWord(String kind) => switch (kind) {
  MediaItem.kMovie => '观影中',
  MediaItem.kSeries => '追剧中',
  MediaItem.kMusic => '听歌中',
  MediaItem.kGame => '游玩中',
  _ => '计时中',
};

/// 进行中会话的实时读数（悬浮条与沉浸页同源；分钟粒度与阅读胶囊一致）。
int mediaLiveMinutes(MediaSession s) => DateTime.now()
    .difference(DateTime.fromMillisecondsSinceEpoch(s.startedAt))
    .inMinutes;

/// 进架口：把设置屏的默认视图/默认排序吃进架面态（原型 `mOpenShelf`＝LH-C23 铁口径①，
/// 刀3 摘掉本函数＝进架硬钉 desk/recent，设置生效连线断言独红）。
/// 默认排序六档按原型实态映射（工单 §3 偏离②）：title/progress 落架面既有键，不造第七档。
Future<void> applyMediaShelfPrefs(ProviderContainer c) async {
  final repo = c.read(mediaRepositoryProvider);
  final view = await mediaKvSafe(repo, 'media.defaultView', 'desk');
  if (const {'desk', 'spine', 'list'}.contains(view)) {
    c.read(mediaViewProvider.notifier).state = view;
  }
  final sort = await mediaKvSafe(repo, 'media.sortDefault', 'recent');
  c.read(mediaSortProvider.notifier).state = switch (sort) {
    'title' => 'name',
    'progress' => 'recent',
    _ => sort,
  };
}
