// 工具屏 · 测距（原型 `TOOLS.dist` / `dist*` 同源 · 批3）。
//
// 离线地图比例尺 = 自绘网格画布（原型 SVG 折线 + CSS 网格的 CustomPaint 同义），
// GPS 轨迹 = 点选反算经纬度后走大圆距离；轨迹只存内存（原型 `DIST` 同口径），
// 模式与比例尺落 `kit_tool_data.tool='dist'`。全程本机几何计算，零出站。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_dist.dart';
import '../../domain/kit_models.dart';
import '../kit_providers.dart';
import 'kit_tools_kit.dart';

class KitDistBody extends ConsumerStatefulWidget {
  const KitDistBody({super.key});

  @override
  ConsumerState<KitDistBody> createState() => _KitDistBodyState();
}

class _KitDistBodyState extends ConsumerState<KitDistBody> {
  final List<KitDistPoint> _pts = <KitDistPoint>[];
  Timer? _walk;
  int _walkK = 0;
  String _mode = kKitDistModeMap;
  double _scale = kKitDistScaleDefault;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _walk?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final d = await ref.read(kitRepositoryProvider).toolData(kitToolKeyDist);
    if (!mounted) return;
    final s = KitDistState.decode(d);
    setState(() {
      _mode = s.mode;
      _scale = s.scale;
      _loaded = true;
    });
  }

  Future<void> _persist() => ref
      .read(kitRepositoryProvider)
      .setToolData(kitToolKeyDist, kitDistEncode(mode: _mode, scale: _scale));

  Future<void> _setMode(String m) async {
    _walk?.cancel();
    setState(() {
      _mode = m;
      _pts.clear();
    });
    await _persist();
    if (mounted) {
      AppToast.show(
        context,
        m == kKitDistModeGps ? 'GPS 轨迹 · 轻点采集定位点' : '离线地图比例尺 · 轻点落点',
      );
    }
  }

  void _tap(Offset local) {
    setState(() => _pts.add(kitDistPointAt(local.dx, local.dy, mode: _mode)));
  }

  void _undo() => setState(() {
    final rest = kitDistUndo(_pts);
    _pts
      ..clear()
      ..addAll(rest);
  });

  void _clear() {
    setState(() {
      _pts.clear();
      _walk?.cancel();
      _walkK = 0;
    });
    AppToast.show(context, '轨迹已清空');
  }

  /// 模拟行走 60s（原型 14 步 × 260ms；空轨迹先落种子点）。
  void _walk60() {
    if (_mode != kKitDistModeGps) {
      AppToast.show(context, '请先切到 GPS 模式');
      return;
    }
    _walk?.cancel();
    if (_pts.isEmpty) setState(() => _pts.add(kKitGpsSeed));
    _walkK = 0;
    setState(() {});
    _walk = Timer.periodic(const Duration(milliseconds: kKitGpsWalkTickMs), (
      t,
    ) {
      _walkK++;
      final start = _pts.last;
      setState(() => _pts.add(kitGpsWalkStep(start, _walkK)));
      if (_walkK >= kKitGpsWalkSteps) {
        t.cancel();
        _walk = null;
        AppToast.show(context, '模拟行走 60s 完成 · 轨迹点与距离全部实算');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final gps = _mode == kKitDistModeGps;
    final meters = kitDistTotalMeters(_pts, mode: _mode, scaleMPerPx: _scale);
    final trail = kitDistTrailText(_pts, mode: _mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KitToolChip(
              keyName: 'kit-dist-mode-map',
              label: '离线地图比例尺',
              on: !gps,
              onTap: () => _setMode(kKitDistModeMap),
            ),
            const SizedBox(width: 6),
            KitToolChip(
              keyName: 'kit-dist-mode-gps',
              label: 'GPS 轨迹',
              on: gps,
              onTap: () => _setMode(kKitDistModeGps),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          key: const ValueKey('kit-dist-canvas'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _tap(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 224,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _KitMapPainter(
                        points: _pts,
                        accent: tokens.accent,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _overlay(
                      kitDistHintText(_mode, _scale),
                      keyName: 'kit-dist-hint',
                    ),
                  ),
                  if (trail != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _overlay(
                        trail,
                        dark: true,
                        keyName: 'kit-dist-trail',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!gps) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                '比例尺',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('kit-dist-scale'),
                  value: _scale,
                  min: kKitDistScaleMin,
                  max: kKitDistScaleMax,
                  divisions:
                      ((kKitDistScaleMax - kKitDistScaleMin) /
                              kKitDistScaleStep)
                          .round(),
                  label: '${_scale.toStringAsFixed(1)} m/px',
                  onChanged: (v) {
                    setState(() => _scale = v);
                    _persist();
                  },
                ),
              ),
              SizedBox(
                key: const ValueKey('kit-dist-scale-v'),
                width: 66,
                child: Text(
                  '${_scale.toStringAsFixed(1)} m/px',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              kitDistTotalText(meters, _pts.length),
              key: const ValueKey('kit-dist-total'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: tokens.accent,
              ),
            ),
            const Spacer(),
            kitToolBtn(
              context,
              '撤销',
              _pts.isEmpty ? null : _undo,
              keyName: 'kit-dist-undo',
              small: true,
            ),
            kitToolBtn(
              context,
              '清空',
              _pts.isEmpty ? null : _clear,
              keyName: 'kit-dist-clear',
              small: true,
            ),
            if (gps)
              kitToolBtn(
                context,
                '模拟行走 60s',
                _walk != null ? null : _walk60,
                keyName: 'kit-dist-walk',
                small: true,
              ),
          ],
        ),
        const SizedBox(height: 8),
        kitToolNote(
          _loaded
              ? (gps
                    ? 'GPS 点由画布坐标反算经纬度 · 距离按大圆（Haversine）实算'
                    : '轻点地图落点 · 距离 = 像素长度 × 比例尺 · 轨迹仅在本次停留')
              : '正在读本机测距设置…',
        ),
      ],
    );
  }

  Widget _overlay(String text, {bool dark = false, required String keyName}) =>
      Container(
        key: ValueKey(keyName),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: dark ? const Color(0xCC0F172A) : const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: dark ? 9 : 10,
            fontFamily: dark ? 'monospace' : null,
            color: dark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      );
}

/// 地图底 + 折线 + 起终点标记（原型 `#distMap` 渐变网格 + `#distSvg`）。
class _KitMapPainter extends CustomPainter {
  _KitMapPainter({required this.points, required this.accent});

  final List<KitDistPoint> points;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // 底：淡蓝→淡绿斜向渐变（原型 background-image 第三层）。
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDBEAFE), Color(0xFFE0F2FE), Color(0xFFD1FAE5)],
          stops: [0, .45, 1],
        ).createShader(Offset.zero & size),
    );
    // 24px 网格。
    final grid = Paint()
      ..color = const Color(0x2464708D)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length > 1) {
      final path = Path()..moveTo(points.first.x, points.first.y);
      for (final p in points.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (i == 0) {
        canvas.drawCircle(
          Offset(p.x, p.y),
          5,
          Paint()..color = const Color(0xFF22C55E),
        );
      } else if (i == points.length - 1) {
        canvas.drawRect(
          Rect.fromLTWH(p.x - 4, p.y - 4, 8, 8),
          Paint()..color = const Color(0xFFF43F5E),
        );
      } else {
        canvas.drawCircle(Offset(p.x, p.y), 4.5, Paint()..color = Colors.white);
        canvas.drawCircle(
          Offset(p.x, p.y),
          4.5,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KitMapPainter old) =>
      old.points.length != points.length ||
      (old.points.isNotEmpty &&
          points.isNotEmpty &&
          old.points.last != points.last) ||
      old.accent != accent;
}
