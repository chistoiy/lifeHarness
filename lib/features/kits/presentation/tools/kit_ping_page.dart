// 工具屏 · Ping 工具（原型 `TOOLS.ping` / `pingGo` / `pingStatRender` 同源 · 批3）。
//
// 口径：**模拟网络层 · 不发真实请求**（页脚与首行都按此标注，红线 §4）。
// 发包节奏、丢包概率、延迟与 TTL 分布全部在 `domain/kit_net.dart` 里纯算，
// 本文件只管定时器编排与终端风格渲染；随机源注入固定种子的场合见测试。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_net.dart';
import 'kit_tools_kit.dart';

/// 终端配色（原型 `bg-slate-900` + `emerald-300` / 玫红超时）。
const Color _kTermBg = Color(0xFF0F172A);
const Color _kTermOk = Color(0xFF86EFAC);
const Color _kTermLost = Color(0xFFFB7185);

class KitPingBody extends ConsumerStatefulWidget {
  const KitPingBody({super.key});

  /// 随机源注入缝：默认每次真随机；widget 测试换成固定种子，逐轮可复现。
  static math.Random Function() randomProvider = math.Random.new;

  @override
  ConsumerState<KitPingBody> createState() => _KitPingBodyState();
}

class _KitPingBodyState extends ConsumerState<KitPingBody> {
  late math.Random _rnd = KitPingBody.randomProvider();
  final TextEditingController _host = TextEditingController(text: 'baidu.com');
  final ScrollController _scroll = ScrollController();

  int _times = 10;
  int _timeoutS = 2;
  Timer? _timer;
  bool _running = false;
  int _seq = 0;
  double _base = 0;
  String _head = '';
  String _hostShown = 'baidu.com';
  List<KitPingLine> _lines = const [];
  KitPingStats _stats = const KitPingStats();

  @override
  void dispose() {
    _timer?.cancel();
    _host.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _start() {
    _cancel();
    final host = _host.text.trim().isEmpty ? 'baidu.com' : _host.text.trim();
    _rnd = KitPingBody.randomProvider();
    _base = kitPingBase(_rnd);
    _seq = 0;
    setState(() {
      _running = true;
      _hostShown = host;
      _head = kitPingHead(host, kitPingIp(_rnd), _timeoutS);
      _lines = const [];
      _stats = const KitPingStats();
    });
    _timer = Timer.periodic(
      const Duration(milliseconds: kKitPingTickMs),
      (_) => _tick(),
    );
  }

  void _tick() {
    if (!_running) return;
    final n = _times.clamp(kKitPingMinTimes, kKitPingMaxTimes);
    _seq++;
    final line = kitPingProbe(
      seq: _seq,
      timeoutS: _timeoutS,
      base: _base,
      rnd: _rnd,
    );
    setState(() {
      _lines = [..._lines, line];
      _stats = kitPingApply(_stats, line);
    });
    _toBottom();
    if (_seq >= n) _stop();
  }

  /// 只掐定时器（重开一轮时用，不弹提示）。
  void _cancel() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _running = false);
  }

  void _stop() {
    _cancel();
    _toBottom();
    if (mounted) {
      AppToast.show(context, '已停止 · 统计为实算结果，可点「统计可分享」复制');
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _share() {
    kitToolCopy(
      context,
      kitPingShare(_hostShown, _stats),
      msg: '统计已复制 · 正式版走系统分享面板',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cells = kitPingCells(_stats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('kit-ping-host'),
                controller: _host,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '主机 / IP',
                  hintStyle: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 6),
            kitToolBtn(
              context,
              _running ? '进行中' : '开始',
              _running ? null : _start,
              keyName: 'kit-ping-go',
            ),
            kitToolBtn(
              context,
              '停止',
              _running ? _stop : null,
              keyName: 'kit-ping-stop',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              '次数',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
            const SizedBox(width: 4),
            KitToolNumberField(
              value: _times,
              onChanged: (v) => setState(
                () => _times = v.clamp(kKitPingMinTimes, kKitPingMaxTimes),
              ),
              width: 60,
              min: kKitPingMinTimes,
              max: kKitPingMaxTimes,
              keyName: 'kit-ping-times',
            ),
            const SizedBox(width: 10),
            const Text(
              '超时(s)',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
            const SizedBox(width: 4),
            KitToolNumberField(
              value: _timeoutS,
              onChanged: (v) => setState(
                () =>
                    _timeoutS = v.clamp(kKitPingMinTimeout, kKitPingMaxTimeout),
              ),
              width: 60,
              min: kKitPingMinTimeout,
              max: kKitPingMaxTimeout,
              keyName: 'kit-ping-timeout',
            ),
            const Spacer(),
            kitToolBtn(
              context,
              '统计可分享',
              _stats.empty ? null : _share,
              keyName: 'kit-ping-share',
              small: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('kit-ping-term'),
          width: double.infinity,
          height: 176,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kTermBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListView(
            controller: _scroll,
            children: [
              Text(
                _head.isEmpty ? '设置次数与超时后点击开始（本机模拟网络层）' : _head,
                key: const ValueKey('kit-ping-head'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.6,
                  color: Color(0xFFA7F3D0),
                ),
              ),
              for (final l in _lines)
                Text(
                  l.text,
                  key: ValueKey('kit-ping-line-${l.seq}'),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.6,
                    color: l.ok ? _kTermOk : _kTermLost,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                child: Container(
                  key: ValueKey('kit-ping-cell-$i'),
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: tokens.card.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        cells[i].$1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: i == 3 && !_stats.empty
                              ? (_stats.lossWarn
                                    ? Colors.redAccent
                                    : const Color(0xFF10B981))
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cells[i].$2,
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
