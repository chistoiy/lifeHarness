import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/book.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'widgets/bs_cover.dart';

/// 沉浸计时页（原型 p-readtimer · §3.3 计时形态=全屏）。
/// 封面模糊整页背景；页内自带返回/收起两枚图标钮（无全局顶栏底栏）；
/// 开始按钮左右＝添加摘录 / 记进度，三枚统一圆钮；结束按 read.autoAsk 弹记进度。
class ReadTimerPage extends ConsumerStatefulWidget {
  const ReadTimerPage({super.key, required this.bookId});
  final String bookId;

  @override
  ConsumerState<ReadTimerPage> createState() => _ReadTimerPageState();
}

class _ReadTimerPageState extends ConsumerState<ReadTimerPage> {
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

  Future<void> _startStop(Book b, bool running) async {
    final ref_ = ref;
    if (running) {
      final repo = ref_.read(readRepositoryProvider);
      final closed = await repo.endSession(b.id);
      ref_.read(readTickProvider.notifier).state++;
      if (!mounted) return;
      if (closed != null) {
        readToast(context, '已结束计时 · ${bsFmt(closed.minutes)}');
        if (await ref_.read(autoAskProvider.future) && mounted) {
          final nb = await repo.bookById(b.id);
          if (nb != null && mounted) showProgressSheet(context, ref_, nb);
        }
      } else if (mounted) {
        readToast(context, '计时已取消');
      }
    } else {
      await ref_.read(readRepositoryProvider).startSession(b.id);
      ref_.read(readTickProvider.notifier).state++;
    }
  }

  String _elapsed(int startMs) {
    final secs = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(startMs))
        .inSeconds;
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, sec = secs % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final b = books.where((e) => e.id == widget.bookId).firstOrNull;
    if (b == null) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.pop(),
            child: const Text('返回'),
          ),
        ),
      );
    }
    final running =
        (ref.watch(runningSessionProvider).valueOrNull != null &&
        ref.watch(runningSessionProvider).valueOrNull!.bookId == b.id);
    final startMs = running
        ? ref.watch(runningSessionProvider).valueOrNull!.startedAt
        : 0;
    final pal = kBsCov[b.paletteIdx];
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [pal.$1, pal.$2],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: .35)),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 10, 0),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('rt-back'),
                        onPressed: () => context.pop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          b.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('rt-collapse'),
                        tooltip: '收起',
                        onPressed: () => context.pop(),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  running ? _elapsed(startMs) : '00:00',
                  key: const ValueKey('rt-clock'),
                  style: const TextStyle(
                    fontSize: 54,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  running ? '计时中' : b.author,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: .75),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 42),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _round(
                        'rt-quote',
                        BsIcons.quote,
                        () => showQuoteSheet(context, ref, bookId: b.id),
                      ),
                      const SizedBox(width: 30),
                      GestureDetector(
                        key: const ValueKey('rt-toggle'),
                        onTap: () => _startStop(b, running),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [pal.$3, pal.$2],
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
                            running
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 30),
                      _round(
                        'rt-prog',
                        BsIcons.pin,
                        () => showProgressSheet(context, ref, b),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _round(String key, IconData ic, VoidCallback onTap) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .16),
      ),
      child: Icon(ic, size: 22, color: Colors.white),
    ),
  );
}
