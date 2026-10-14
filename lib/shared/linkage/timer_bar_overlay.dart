import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/calendar/presentation/calendar_providers.dart' show calendarTickerProvider;
import '../../features/media/data/media_repo_session.dart';
import '../../features/media/presentation/media_actions.dart'
    show mediaLiveMinutes, mediaTimerWord, refreshTimeAfterMediaSession;
import '../../features/media/presentation/media_progress_sheet.dart'
    show showMediaProgressSheet;
import '../../features/media/presentation/media_providers.dart';
import '../../features/read/presentation/read_providers.dart';
import '../../features/read/presentation/read_sheets.dart'
    show readToast, showProgressSheet;

/// 悬浮条落点（相对壳内容顶）＝安全区 + 8（**贴状态栏下悬浮**）。
///
/// 真机口径修正（产品 2026-10-14）：旧值 60＝「让过页面自带顶栏」，条被顶到
/// 页面标题下方且内容垫掉 104px，观感＝「胶囊占据顶部一块地」。改贴顶悬浮：
/// 条浮在状态栏正下（叠在页面顶栏区上方），内容只让出条高（F2-5 预留保留）。
/// 与 [kTimerBarHeight] 一起构成 F2-5 的占位预留口径。
const double kTimerBarTopOffset = 8;

/// 悬浮条单条内容高（两条并存时另加 [kTimerBarGap] 间距）。
///
/// **44 ＝ 实测渲染高**（`read_f2_nav_test` 现场量）＝
/// 容器上下各 9 内边距 ＋ 行内最高件（「■ 结束」胶囊：上下各 5 内边距 ＋ 11px 文本）。
/// 曾按「11.5px 文本 + 上下各 9」记作 38——**少算 6px**，预留 < 条底时首卡仍被压。
/// 改常量而非改断言。
const double kTimerBarHeight = 44;

/// 悬浮条间距（两条并存时）。
const double kTimerBarGap = 8;

/// 悬浮计时条（需求 V1.11/V1.12 · M0 基础设施）：
/// B10（2026-10-13 裁决）起旧 events 表已退役，**进行中事项条随表退役**——
/// 「计时中」唯一源=时间块（V1.52），轴视图卡内结束；本壳只承载
/// 读书长胶囊（read.timerUI）与影音计时条（media.floatBar/media.timerUI=capsule）。
///
/// **产品改口（2026-10-14，真机回知两轮）**：胶囊是**纯悬浮**——叠在页面内容
/// 之上、内容**零让位**（不再给页面垫顶，旧 F2-5「预留等量空间」口径废弃；
/// 原型 `timerBarSpace` 同步作废）。条浮在状态栏正下（top+8），压住页面标题带
/// 上沿属设计内（悬浮件本来就在内容 Z 序之上）。
class TimerBarOverlay extends ConsumerWidget {
  const TimerBarOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOn = ref.watch(readTimerBarVisibleProvider).valueOrNull ?? false;
    // 影音计时条（批3 · media.floatBar/media.timerUI=capsule）：与阅读胶囊并存，互不遮蔽。
    final mediaOn = ref.watch(mediaTimerBarVisibleProvider);
    final bars = (readOn ? 1 : 0) + (mediaOn ? 1 : 0);
    final topPad = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        child,
        if (bars > 0)
          Positioned(
            top: topPad + kTimerBarTopOffset,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (readOn) const _ReadTimerBar(),
                if (mediaOn) ...[
                  if (readOn) const SizedBox(height: kTimerBarGap),
                  const _MediaTimerBar(),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 读书长胶囊（§3.3 顶部胶囊形态：跨页常驻 · 原地结束）。
class _ReadTimerBar extends ConsumerWidget {
  const _ReadTimerBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(readTickProvider);
    ref.watch(calendarTickerProvider); // 分钟级刷新（与日程条共用 ticker）
    final s = ref.watch(runningSessionProvider).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final books = ref.watch(booksProvider).valueOrNull ?? const [];
    final title =
        books.where((b) => b.id == s.bookId).firstOrNull?.title ?? '阅读';
    final mins = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(s.startedAt))
        .inMinutes;
    return GestureDetector(
      key: const ValueKey('read-bar'),
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/read/timer/${s.bookId}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xE60F172A),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '《$title》 · 阅读中 $mins 分钟',
                style: const TextStyle(color: Colors.white, fontSize: 11.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () async {
                final repo = ref.read(readRepositoryProvider);
                final closed = await repo.endSession(s.bookId);
                ref.read(readTickProvider.notifier).state++;
                if (!context.mounted) return;
                readToast(
                  context,
                  closed == null
                      ? '《$title》计时已取消'
                      : '《$title》已结束计时 · ${closed.minutes} 分钟',
                );
                if (closed != null &&
                    await ref.read(autoAskProvider.future) &&
                    context.mounted) {
                  final nb = await repo.bookById(s.bookId);
                  if (nb != null && context.mounted) {
                    showProgressSheet(context, ref, nb);
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  '■ 结束',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 影音计时长胶囊（批3 · 与阅读胶囊同构，文案按 kind：观影中/追剧中/听歌中/游玩中）。
class _MediaTimerBar extends ConsumerWidget {
  const _MediaTimerBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mediaTickProvider);
    ref.watch(calendarTickerProvider); // 分钟级刷新（三条共用 ticker）
    final s = ref.watch(mediaRunningSessionProvider).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final item = ref.watch(mediaItemDetailProvider(s.itemId)).valueOrNull;
    final title = item?.title ?? '影音';
    final mins = mediaLiveMinutes(s);
    return GestureDetector(
      key: const ValueKey('media-bar'),
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/media/timer/${s.itemId}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xE60F172A),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF472B6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '《$title》 · ${mediaTimerWord(s.kind)} $mins 分钟',
                style: const TextStyle(color: Colors.white, fontSize: 11.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () async {
                // 跨弹层/跨页提交不带发起页 ref 之外的依赖：container 现抓（既定坑口径）。
                final c = ProviderScope.containerOf(context, listen: false);
                final repo = ref.read(mediaRepositoryProvider);
                final closed = await repo.endSession(s.itemId);
                refreshTimeAfterMediaSession(
                  c,
                  [closed?.startedAt, closed?.endedAt],
                );
                ref.read(mediaTickProvider.notifier).state++;
                if (!context.mounted) return;
                readToast(
                  context,
                  closed == null
                      ? '《$title》计时已取消'
                      : '《$title》已结束计时 · ${closed.minutes} 分钟',
                );
                if (closed != null &&
                    await ref.read(mediaAutoAskProvider.future) &&
                    context.mounted) {
                  final ni = await repo.itemById(s.itemId);
                  if (ni != null && context.mounted) {
                    showMediaProgressSheet(context, ref, ni, sessionMinutes: closed.minutes);
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  '■ 结束',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
