import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/book.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'widgets/bs_cover.dart';

/// 沉浸计时页（原型 p-readtimer 931-949 + renderReadTimer 5015-5027）。
/// 顶栏＝返回 + 「阅读计时」+ 收起（rtClose：计时未结束提示回胶囊继续）；
/// 封面小图 + 书名 + 副标题（作者 · 状态 [ · p%]）；大数字恒 HH:MM:SS；
/// rtFoot＝今日 X/dayMin 分钟进度条 + 连续 N 天 + 记摘录/记进度/书籍详情三钮；
/// 结束结算 toast 逐字「计时结束 · 本次 N 分钟」，autoAsk 开时弹记进度。
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
    if (running) {
      final closed = await ref.read(readRepositoryProvider).endSession(b.id);
      ref.read(readTickProvider.notifier).state++;
      if (!mounted) return;
      if (closed != null) {
        final mins = closed.minutes < 1 ? 1 : closed.minutes;
        readToast(context, '计时结束 · 本次 $mins 分钟');
        if (await ref.read(autoAskProvider.future) && mounted) {
          final nb = await ref.read(readRepositoryProvider).bookById(b.id);
          if (nb != null && mounted) {
            showProgressSheet(context, ref, nb, timerMinutes: mins);
          }
        }
      } else if (mounted) {
        readToast(context, '计时已取消');
      }
    } else {
      await ref.read(readRepositoryProvider).startSession(b.id);
      ref.read(readTickProvider.notifier).state++;
    }
  }

  /// 大数字恒 HH:MM:SS（原型 rtFmt 5013）。
  String _rtFmt(int secs) {
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
    final running = ref.watch(runningSessionProvider).valueOrNull;
    final on = running != null && running.bookId == b.id;
    final startMs = on ? running.startedAt : 0;
    final wb = ref.watch(workbenchProvider).valueOrNull;
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
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 顶栏：返回 · 「阅读计时」 · 收起（rtClose）
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
                        const Expanded(
                          child: Text(
                            '阅读计时',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('rt-collapse'),
                          tooltip: '收起',
                          onPressed: () {
                            if (running != null) {
                              readToast(
                                context,
                                '计时未结束 · 回到页面顶部胶囊继续显示',
                              );
                            }
                            context.pop();
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 封面小图 + 书名 + 副标题（作者 · 状态 [ · p%]）
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: BsCover(
                      book: b,
                      width: 112,
                      height: 160,
                      radius: 12,
                      showAuthor: false,
                      showBadge: false,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12, left: 24, right: 24),
                    child: Text(
                      b.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${b.author} · ${b.state}${b.percent > 0 ? ' · ${b.percent}%' : ''}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: .7),
                      ),
                    ),
                  ),
                  // 大数字（恒 HH:MM:SS）+ 状态行
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      _rtFmt(
                        on
                            ? DateTime.now().difference(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      startMs,
                                    ),
                                  ).inSeconds
                            : 0,
                      ),
                      key: const ValueKey('rt-clock'),
                      style: const TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                        height: 1.1,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      // 原型 rtState 三态：计时中 / 正在为《X》计时 / 未开始
                      on
                          ? '计时中 · 结束后可直接记进度'
                          : running != null
                          ? '正在为《${books.where((e) => e.id == running.bookId).firstOrNull?.title ?? running.bookId}》计时'
                          : '未开始',
                      key: const ValueKey('rt-state'),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: .7),
                      ),
                    ),
                  ),
                  // 三圆钮：记摘录 / 起停 / 记进度
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 8),
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
                          onTap: () => _startStop(b, on),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 64,
                            height: 64,
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
                              on ? Icons.stop_rounded : Icons.play_arrow_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 30),
                        _round(
                          'rt-prog',
                          BsIcons.pin,
                          () => showProgressSheet(
                            context,
                            ref,
                            b,
                            timerMinutes: on
                                ? _secs(startMs) ~/ 60 < 1
                                      ? 1
                                      : _secs(startMs) ~/ 60
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // rtFoot（原型 5023-5027）：今日进度卡 + 三钮行
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      children: [
                        Container(
                          key: const ValueKey('rt-foot'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '今日',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: .75),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${wb?.minutesToday ?? 0} / ${wb?.goalDay ?? 30} 分钟',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '连续 ${wb?.streak ?? 0} 天',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: .75),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  key: const ValueKey('rt-today-bar'),
                                  minHeight: 6,
                                  value: wb == null || wb.goalDay <= 0
                                      ? 0
                                      : (wb.minutesToday / wb.goalDay).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                  backgroundColor: Colors.white.withValues(
                                    alpha: .2,
                                  ),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _footBtn(
                              'rtf-quote',
                              '记摘录',
                              () => showQuoteSheet(context, ref, bookId: b.id),
                            ),
                            const SizedBox(width: 8),
                            _footBtn(
                              'rtf-prog',
                              '记进度',
                              () => showProgressSheet(
                                context,
                                ref,
                                b,
                                timerMinutes: on
                                    ? _secs(startMs) ~/ 60 < 1
                                          ? 1
                                          : _secs(startMs) ~/ 60
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _footBtn(
                              'rtf-detail',
                              '书籍详情',
                              () => context.push('/read/book/${b.id}'),
                            ),
                          ],
                        ),
                      ],
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

  int _secs(int startMs) => DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(startMs))
      .inSeconds;

  Widget _round(String key, IconData ic, VoidCallback onTap) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .16),
      ),
      child: Icon(ic, size: 20, color: Colors.white),
    ),
  );

  Widget _footBtn(String key, String label, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: .15),
          border: Border.all(color: Colors.white.withValues(alpha: .25)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}
