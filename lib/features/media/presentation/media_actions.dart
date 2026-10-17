import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/linkage/stats_providers.dart'
    show dayBlocksProvider, monthBlockDaysProvider;
import '../data/media_repo_session.dart';
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import 'media_progress_sheet.dart';
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

/// 悬浮条/详情页/计时页共用的起停语义（单活：起新先结旧）。
///
/// 三条既定口径：
/// - **不与阅读计时互杀**：media 仓储只碰 `media_sessions`；阅读在跑时给一行提示
///   （能力边界显式声明，不静默糊过去）；
/// - 结束弹记进度按 `media.autoAsk`（跨弹层提交不带发起页 ref——入口先抓 container）；
/// - 结算/写回后刷新时间模块（L4 实时性）。
Future<void> mediaTimerTap(BuildContext context, WidgetRef ref, MediaItem item) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = ref.read(mediaRepositoryProvider);
  final running = await repo.runningSession();
  if (running != null && running.itemId == item.id) {
    final closed = await repo.endSession(item.id);
    refreshTimeAfterMediaSession(container, [closed?.startedAt, closed?.endedAt]);
    _bump(ref);
    if (closed != null && await ref.read(mediaAutoAskProvider.future)) {
      final fresh = await repo.itemById(item.id);
      // 跨弹层提交不带发起页失效 ref：context 用前判活（既定坑口径）。
      if (fresh != null && ref.context.mounted) {
        showMediaProgressSheet(context, ref, fresh, sessionMinutes: closed.minutes);
      }
    }
    return;
  }
  // LH-C23 铁口径①：timerUI 两条真路径——全屏档＝起停直接进沉浸页（胶囊档就地起停＋悬浮条）。
  if ((await mediaKvSafe(repo, 'media.timerUI', 'capsule')) == 'full' &&
      ref.context.mounted) {
    context.push('/media/timer/${item.id}');
    return;
  }
  if (running != null) {
    // 别的条目在跑：起新先结旧（同阅读单活语义），结旧结果如实报。
    final closed = await repo.endSession(running.itemId);
    refreshTimeAfterMediaSession(container, [closed?.startedAt, closed?.endedAt]);
  }
  await repo.startSession(item.id);
  _bump(ref);
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

void _bump(WidgetRef ref) {
  final t = ref.read(mediaTickProvider.notifier);
  t.state = t.state + 1;
}

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
