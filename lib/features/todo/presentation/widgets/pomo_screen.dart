import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/linkage/pomo_linkage.dart';
import '../../../../shared/linkage/stats_providers.dart';

/// 番茄全屏专注页（V1.21 · 参考图1：圆环大时钟 + 随机励志语 + ⏸//■）。
/// 倒计时归零自动完成入账；暂停期间时钟冻结不计耗时。
class PomoScreen extends ConsumerStatefulWidget {
  const PomoScreen({super.key, required this.session});
  final PomoSession session;

  @override
  ConsumerState<PomoScreen> createState() => _PomoScreenState();
}

class _PomoScreenState extends ConsumerState<PomoScreen> {
  Timer? _timer;
  late final String _quote;

  static const quotes = [
    '没有过不去的坎，只有回不去的昨天。向前看，路就在脚下。',
    '种一棵树最好的时间是十年前，其次是现在。',
    '慢慢来，比较快。',
    '自律即自由。',
    '星光不问赶路人，时光不负有心人。',
    '把每一件简单的事做好，就是不简单。',
    '你专注的样子，很好看。',
    '不积跬步，无以至千里。',
    '既然选择了远方，便只顾风雨兼程。',
    '今天的拖延，是明天的负债。',
    '心之所向，素履以往。',
    '每一次专注，都是对未来的投资。',
    '流水不争先，争的是滔滔不绝。',
    '你只管努力，其余的交给时间。',
    '千里始足下，高山起微尘。',
    '日日行，不怕千万里；常常做，不怕千万事。',
    '别慌，月亮也正在大海某处迷茫。',
    '关关难过关关过，前路漫漫亦灿灿。',
    '专注当下，未来自会清晰。',
    '所有坚持，终有回响。',
  ];

  @override
  void initState() {
    super.initState();
    _quote = quotes[math.Random().nextInt(quotes.length)];
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final s = widget.session;
      if (s.mode == 'down' &&
          s.minutes != null &&
          s.runningSec() >= s.minutes! * 60) {
        finishPomo(context, ref, s, auto: true);
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _clockText {
    final s = widget.session;
    final sec = s.mode == 'down' && s.minutes != null
        ? math.max(0, s.minutes! * 60 - s.elapsedSec())
        : s.elapsedSec();
    return '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  double get _progress {
    final s = widget.session;
    if (s.mode == 'down' && s.minutes != null) {
      return (s.elapsedSec() / (s.minutes! * 60)).clamp(0.0, 1.0);
    }
    return (s.elapsedSec() % 600) / 600;
  }

  void _togglePause() {
    setState(() {
      final s = widget.session;
      if (s.pauseStarted != null) {
        s.pausedMs += DateTime.now().difference(s.pauseStarted!).inMilliseconds;
        s.pauseStarted = null;
      } else {
        s.pauseStarted = DateTime.now();
      }
    });
  }

  void _reset() {
    setState(() {
      final s = widget.session;
      s.pausedMs = 0;
      s.pauseStarted = null;
    });
    // 重置=重新开始计时（改 startedAt 需重建会话）。
    ref.read(activePomoProvider.notifier).state = PomoSession(
        todoId: widget.session.todoId,
        title: widget.session.title,
        mode: widget.session.mode,
        minutes: widget.session.minutes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final paused = s.pauseStarted != null;
    return Scaffold(
      backgroundColor: const Color(0xFF41618C),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF41618C), Color(0xFF7D93B5), Color(0xFFD8A9A2)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
                  child: Text('❝',
                      style: TextStyle(
                          fontSize: 30, color: Colors.white.withValues(alpha: .8))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 8, 36, 0),
                child: Text(_quote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, height: 1.6, color: Colors.white)),
              ),
              const Spacer(),
              SizedBox(
                width: 220,
                height: 220,
                child: CustomPaint(
                  painter: _RingPainter(progress: _progress),
                  child: Center(
                    child: Text(_clockText,
                        style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 2)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(s.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                  '${paused ? '已暂停' : '进行中'} · ${s.mode == 'down' ? '倒计时 ${s.minutes ?? 25} 分' : '正计时'}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withValues(alpha: .85))),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundBtn(
                      icon: paused ? Icons.play_arrow : Icons.pause,
                      label: paused ? '继续' : '暂停',
                      onTap: _togglePause,
                    ),
                    const SizedBox(width: 36),
                    _RoundBtn(
                        icon: Icons.refresh, label: '重置', onTap: () => _reset()),
                    const SizedBox(width: 36),
                    _RoundBtn(
                      icon: Icons.stop,
                      label: '停止 · 入账',
                      onTap: () => finishPomo(context, ref, s),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 完成/停止：按实际耗时写入时间模块（L4 · 关联计时分类可选）+ 待办置完成（L2）。
void finishPomo(BuildContext context, WidgetRef ref, PomoSession s, {bool auto = false}) {
  final elapsedMin = math.max(1, (s.runningSec() / 60).round());
  Navigator.of(context).pop();
  _settle(s, elapsedMin, ref, auto);
}

Future<void> _settle(PomoSession s, int minutes, WidgetRef ref, bool auto) async {
  final now = DateTime.now();
  final nowMin = now.hour * 60 + now.minute;
  final startMin = math.max(0, nowMin - minutes);
  final todos = ref.read(todosProvider).valueOrNull ?? const [];
  final todo = todos.where((t) => t.id == s.todoId).firstOrNull;
  final linkName = await catNameById(todo?.linkCat);
  await writePomoBlock(
      startMin: startMin,
      endMin: nowMin,
      catId: todo?.linkCat,
      catName: linkName ?? '工作',
      note: '🍅 ${s.title} · 番茄');
  if (todo != null && !todo.done) {
    await ref.read(todoRepositoryProvider).toggleDone(todo);
  }
  ref.read(activePomoProvider.notifier).state = null;
  final day0 = DateTime(now.year, now.month, now.day);
  ref.invalidate(todosProvider);
  ref.invalidate(dayBlocksProvider(day0));
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .15),
              border: Border.all(color: Colors.white.withValues(alpha: .25)),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: .75))),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = Colors.white.withValues(alpha: .28);
    canvas.drawCircle(c, r, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}
