// 工具屏 · 网络测速（原型 `TOOLS.speed` / `spdGo` / `spdHistRender` 同源 · 批3）。
//
// 口径：**模拟网络层 · 不发真实请求**（页脚由外壳按 `KitTool.privacy` 标注）。
// 环形仪表 = 原型 conic 进度的 CustomPaint 同义；爬坡节奏、结果分布、
// 近 5 次留档与「对比」标记全部在 `domain/kit_net.dart` 纯算。
// 历史落 `kit_tool_data.tool='speed'` 的 `spd` 键（与原型 `KITS.spd` 同构）。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_calc.dart' show kitMonthDay;
import '../../domain/kit_models.dart';
import '../../domain/kit_net.dart';
import '../kit_providers.dart';
import 'kit_tools_kit.dart';

class KitSpeedBody extends ConsumerStatefulWidget {
  const KitSpeedBody({super.key});

  /// 随机源注入缝（测试换固定种子）。
  static math.Random Function() randomProvider = math.Random.new;

  @override
  ConsumerState<KitSpeedBody> createState() => _KitSpeedBodyState();
}

class _KitSpeedBodyState extends ConsumerState<KitSpeedBody> {
  late math.Random _rnd = KitSpeedBody.randomProvider();
  Timer? _timer;
  int _tick = 0;
  double _target = 0;

  String _node = kKitSpeedNodes.first;
  double _val = 0;
  String _phase = '待开始';
  String _msg = '正式版多节点实测下载 / 上传 / 延迟 / 抖动';
  List<KitSpeedResult> _hist = const [];
  bool _compare = false;
  bool _running = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final d = await ref.read(kitRepositoryProvider).toolData(kitToolKeySpeed);
    if (!mounted) return;
    setState(() {
      _hist = kitSpeedDecode(d);
      _loaded = true;
    });
  }

  Future<void> _persist() => ref
      .read(kitRepositoryProvider)
      .setToolData(kitToolKeySpeed, kitSpeedEncode(_hist));

  void _start() {
    _timer?.cancel();
    _rnd = KitSpeedBody.randomProvider();
    _tick = 0;
    _target = kitSpeedTarget(_rnd);
    setState(() {
      _running = true;
      _val = 0;
      _phase = '下载中…';
    });
    _timer = Timer.periodic(
      const Duration(milliseconds: kKitSpeedTickMs),
      (_) => _tickForward(),
    );
  }

  void _tickForward() {
    if (!_running) return;
    _tick++;
    final p = _tick * kKitSpeedTickMs / kKitSpeedRampMs;
    if (p >= 1) {
      _timer?.cancel();
      final r = kitSpeedFinish(
        node: _node,
        target: _target,
        ts: DateTime.now().millisecondsSinceEpoch,
        rnd: _rnd,
      );
      setState(() {
        _running = false;
        _val = r.down;
        _phase = '完成';
        _msg = kitSpeedMsg(r);
        _hist = kitSpeedPush(_hist, r);
      });
      _persist();
      return;
    }
    setState(
      () => _val = kitSpeedRampValue(progress: p, target: _target, rnd: _rnd),
    );
  }

  void _setNode(String n) {
    setState(() => _node = n);
    AppToast.show(context, '切换节点：$n');
  }

  void _toggleCompare() {
    setState(() => _compare = !_compare);
    AppToast.show(context, _compare ? '已与上一次结果对比' : '取消对比');
  }

  Future<void> _clearHist() async {
    setState(() => _hist = const []);
    await _persist();
    if (mounted) AppToast.show(context, '测速留档已清空');
  }

  Future<void> _share() async {
    if (_hist.isEmpty) {
      AppToast.show(context, '尚无测速结果 · 先完成一次测速');
      return;
    }
    kitToolCopy(context, kitSpeedShare(_hist.first), msg: '结果已复制 · 可粘贴到日记留档');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final delta = _compare ? kitSpeedDelta(_hist) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final n in kKitSpeedNodes)
              KitToolChip(
                keyName: 'kit-speed-node-$n',
                label: n,
                on: _node == n,
                onTap: () => _setNode(n),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: SizedBox(
            key: const ValueKey('kit-speed-gauge'),
            width: 176,
            height: 176,
            child: CustomPaint(
              painter: _KitGaugePainter(
                angle: kitSpeedGaugeAngle(_val),
                accent: tokens.accent,
                track: tokens.cardBorder,
              ),
              child: Center(
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    color: tokens.card,
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _val.toStringAsFixed(1),
                        key: const ValueKey('kit-speed-val'),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _phase,
                        key: const ValueKey('kit-speed-phase'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Mbps · 模拟',
                        style: TextStyle(fontSize: 9, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: kitToolBtn(
            context,
            _running ? '测速中…' : '开始测速（模拟）',
            _running ? null : _start,
            keyName: 'kit-speed-go',
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _msg,
            key: const ValueKey('kit-speed-msg'),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 12),
        kitToolSubCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              kitToolSection(
                '历史结果 · 近 $kKitSpeedHistMax 次',
                trailing: [
                  kitToolBtn(
                    context,
                    _compare ? '对比中' : '对比',
                    _hist.length < 2 ? null : _toggleCompare,
                    keyName: 'kit-speed-compare',
                    small: true,
                  ),
                  kitToolBtn(
                    context,
                    '写日记',
                    _hist.isEmpty ? null : _share,
                    keyName: 'kit-speed-to-diary',
                    small: true,
                  ),
                  kitToolBtn(
                    context,
                    '清空',
                    _hist.isEmpty ? null : _clearHist,
                    keyName: 'kit-speed-hist-clear',
                    small: true,
                    color: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_hist.isEmpty)
                kitToolNote(_loaded ? '尚无测速记录 · 完成一次测速自动留档' : '正在读本机记录…')
              else
                for (var i = 0; i < _hist.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 46,
                          child: Text(
                            kitMonthDay(_hist[i].ts),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _hist[i].node,
                            style: const TextStyle(fontSize: 10.5),
                          ),
                        ),
                        Text(
                          i == 0 && delta != null
                              ? '${_hist[i].down.toStringAsFixed(1)} $delta'
                              : _hist[i].down.toStringAsFixed(1),
                          key: ValueKey('kit-speed-hist-down-$i'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 92,
                          child: Text(
                            '↑${_hist[i].up.toStringAsFixed(1)} · ${_hist[i].pingMs}ms',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (_hist.isNotEmpty) kitToolNote('结果存本机 · 可写入日记留档'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 环形仪表（原型 `conic-gradient(accent 0deg→Ndeg, #e2e8f0 Ndeg)`）。
class _KitGaugePainter extends CustomPainter {
  _KitGaugePainter({
    required this.angle,
    required this.accent,
    required this.track,
  });

  /// 已扫过角度（度，0~360）。
  final double angle;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (angle <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      angle * math.pi / 180,
      false,
      base..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _KitGaugePainter old) =>
      old.angle != angle || old.accent != accent || old.track != track;
}
