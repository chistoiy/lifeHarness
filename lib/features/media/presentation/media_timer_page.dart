import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_session.dart';
import '../domain/media_item.dart';
import 'media_actions.dart';
import 'media_progress_sheet.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 沉浸计时页（原型 `m-timer` · 路由 `/media/timer/:id`）。
///
/// 实物色板铺底（不叠 BackdropFilter——整页模糊是产品已否的既定坑）；
/// 大计时恒 HH:MM:SS；状态行与悬浮条共用 [mediaTimerWord] 按 kind 切文案；
/// 三钮＝名场面（笔记批未开工＝置灰不隐藏）/ 起停 / 记进度。
/// 计时态落库（`media_sessions` 单活行），杀进程重开从库里续——不存内存态。
class MediaTimerPage extends ConsumerStatefulWidget {
  const MediaTimerPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<MediaTimerPage> createState() => _MediaTimerPageState();
}

class _MediaTimerPageState extends ConsumerState<MediaTimerPage> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(int secs) {
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  Future<void> _startStop(MediaItem x, bool on) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(mediaRepositoryProvider);
    if (on) {
      final closed = await repo.endSession(x.id);
      refreshTimeAfterMediaSession(
        container,
        [closed?.startedAt, closed?.endedAt],
      );
      _bump();
      if (!mounted) return;
      if (closed != null) {
        AppToast.show(context, '计时结束 · 本次 ${closed.minutes} 分钟');
        if (await ref.read(mediaAutoAskProvider.future) && mounted) {
          final fresh = await repo.itemById(x.id);
          if (fresh != null && mounted) {
            showMediaProgressSheet(
              context,
              ref,
              fresh,
              sessionMinutes: closed.minutes,
            );
          }
        }
      } else if (mounted) {
        AppToast.show(context, '计时已取消');
      }
    } else {
      final other = await repo.runningSession();
      if (other != null && other.itemId != x.id) {
        // 单活语义：起新先结旧，结旧结果如实报（同阅读口径）。
        final closed = await repo.endSession(other.itemId);
        refreshTimeAfterMediaSession(
          container,
          [closed?.startedAt, closed?.endedAt],
        );
        if (mounted && closed != null) {
          AppToast.show(context, '上一条已先结算 · ${closed.minutes} 分钟');
        }
      }
      await repo.startSession(x.id);
      _bump();
    }
  }

  void _bump() {
    final t = ref.read(mediaTickProvider.notifier);
    t.state = t.state + 1;
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(mediaItemDetailProvider(widget.itemId));
    final x = item.valueOrNull;
    if (x == null) {
      // 条目没了（软删/脏 id）：给一个明确出口，不挂死在计时页。
      return Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('mds-timer-gone-back'),
            onPressed: () => context.pop(),
            child: const Text('返回'),
          ),
        ),
      );
    }
    final running = ref.watch(mediaRunningSessionProvider).valueOrNull;
    final on = running != null && running.itemId == x.id;
    final secs = on
        ? DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(running.startedAt))
              .inSeconds
        : 0;
    final (c1, c2) = kMdsCov[x.paletteIdx];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c1, c2],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: .45)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('mds-timer-back'),
                        onPressed: () => context.pop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          mediaTimerWord(x.kind),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('mds-timer-collapse'),
                        tooltip: '收起',
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 120,
                      height: x.kind == MediaItem.kGame ? 75 : 160,
                      child: MdsCoverArt(item: x),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    x.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${x.creator} · ${x.state}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: .7),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    _fmt(secs),
                    key: const ValueKey('mds-timer-clock'),
                    style: const TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFeatures: kMediaTabular,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    on
                        ? '${mediaTimerWord(x.kind)} · 结束后可直接记进度'
                        : '未开始',
                    key: const ValueKey('mds-timer-state'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: .7),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _roundBtn(
                        'mds-timer-scene',
                        Icons.auto_awesome_outlined,
                        enabled: false, // 名场面属笔记批（置灰不隐藏）
                        onTap: () {},
                      ),
                      const SizedBox(width: 30),
                      GestureDetector(
                        key: const ValueKey('mds-timer-toggle'),
                        onTap: () => _startStop(x, on),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [c2, c1],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .3),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            on ? Icons.stop_rounded : Icons.play_arrow_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 30),
                      _roundBtn(
                        'mds-timer-progress',
                        Icons.bookmark_add_outlined,
                        onTap: () => showMediaProgressSheet(context, ref, x),
                      ),
                    ],
                  ),
                  if (!on)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '名场面记录随影音笔记批开放',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: .6),
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  GestureDetector(
                    key: const ValueKey('mds-timer-open-detail'),
                    onTap: () => context.push('/media/item/${x.id}'),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withValues(alpha: .15),
                        border: Border.all(color: Colors.white.withValues(alpha: .25)),
                      ),
                      child: const Text(
                        '条目详情',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(
    String key,
    IconData ic, {
    required VoidCallback onTap,
    bool enabled = true,
  }) => GestureDetector(
    key: ValueKey(key),
    onTap: enabled ? onTap : null,
    child: Opacity(
      // 置灰不隐藏＝能力边界显式声明（§九.4 同口径）
      opacity: enabled ? 1 : .35,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: .16),
        ),
        child: Icon(ic, size: 20, color: Colors.white),
      ),
    ),
  );
}
