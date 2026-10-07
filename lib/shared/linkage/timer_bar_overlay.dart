import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/calendar/domain/cal_event.dart';
import '../../features/calendar/presentation/calendar_providers.dart';
import '../../features/media/data/media_repo_session.dart';
import '../../features/media/presentation/media_actions.dart'
    show mediaLiveMinutes, mediaTimerWord, refreshTimeAfterMediaSession;
import '../../features/media/presentation/media_progress_sheet.dart'
    show showMediaProgressSheet;
import '../../features/media/presentation/media_providers.dart';
import '../../features/read/presentation/read_providers.dart';
import '../../features/read/presentation/read_sheets.dart'
    show readToast, showProgressSheet;

/// 悬浮计时条（需求 V1.11/V1.12 · M0 基础设施）：
/// 有进行中事项时跨页面常驻顶部，实时耗时 + ■ 结束。
/// V1.30 批2 追加读书计时长胶囊（read.timerUI=顶部胶囊 / read.floatBar）。
class TimerBarOverlay extends ConsumerWidget {
  const TimerBarOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeEventProvider).valueOrNull;
    final readOn = ref.watch(readTimerBarVisibleProvider).valueOrNull ?? false;
    // 影音计时条（批3 · media.floatBar/media.timerUI=capsule）：与阅读胶囊并存，互不遮蔽。
    final mediaOn = ref.watch(mediaTimerBarVisibleProvider);
    return Stack(
      children: [
        child,
        if (active != null || readOn || mediaOn)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 60,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (active != null) _TimerBar(event: active),
                if (readOn) ...[
                  if (active != null) const SizedBox(height: 8),
                  const _ReadTimerBar(),
                ],
                if (mediaOn) ...[
                  if (active != null || readOn) const SizedBox(height: 8),
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

class _TimerBar extends ConsumerWidget {
  const _TimerBar({required this.event});

  final CalEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(calendarTickerProvider);
    final mins = DateTime.now().difference(event.start).inMinutes;
    return Container(
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
              color: Color(0xFFFB7185),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${event.title} · 已 $mins 分钟',
              style: const TextStyle(color: Colors.white, fontSize: 11.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ended = await ref.read(eventRepositoryProvider).endActive();
              ref.invalidate(eventsProvider);
              ref.invalidate(activeEventProvider);
              if (ended != null) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      '✔ 耗时 ${ended.durationMin} 分钟 · 已回填 L1 · 入时间账本 L4',
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
    );
  }
}
