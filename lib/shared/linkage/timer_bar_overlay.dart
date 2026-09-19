import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calendar/domain/cal_event.dart';
import '../../features/calendar/presentation/calendar_providers.dart';

/// 悬浮计时条（需求 V1.11/V1.12 · M0 基础设施）：
/// 有进行中事项时跨页面常驻顶部，实时耗时 + ■ 结束。
class TimerBarOverlay extends ConsumerWidget {
  const TimerBarOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeEventProvider).valueOrNull;
    return Stack(
      children: [
        child,
        if (active != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 60,
            left: 16,
            right: 16,
            child: _TimerBar(event: active),
          ),
      ],
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
          BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFFFB7185))),
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
              final ended =
                  await ref.read(eventRepositoryProvider).endActive();
              ref.invalidate(eventsProvider);
              ref.invalidate(activeEventProvider);
              if (ended != null) {
                messenger.showSnackBar(SnackBar(
                    content: Text(
                        '✔ 耗时 ${ended.durationMin} 分钟 · 已回填 L1 · 入时间账本 L4'),
                    duration: const Duration(seconds: 3)));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text('■ 结束',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
