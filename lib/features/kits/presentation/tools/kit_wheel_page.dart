// 工具屏 · 轮盘抽签（原型 `TOOLS.wheel` + `sheetWheelCfg` 同源 · 批2）。
//
// 主屏只留轮盘、结果、设置入口卡与本套历史（V1.47 真机轮2 拍板：数据管理
// 整体移入弹层）；套/选项/权重/历史全部落 `kit_tool_data.tool='wheel'`。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_calc.dart' show kitRelText;
import '../../domain/kit_color.dart' show KitRgb, kitHexToRgb;
import '../../domain/kit_models.dart';
import '../../domain/kit_wheel.dart';
import '../kit_providers.dart';
import 'kit_tools_kit.dart';
import 'kit_wheel_sheet.dart';

class KitWheelBody extends ConsumerStatefulWidget {
  const KitWheelBody({super.key});

  @override
  ConsumerState<KitWheelBody> createState() => _KitWheelBodyState();
}

class _KitWheelBodyState extends ConsumerState<KitWheelBody>
    with SingleTickerProviderStateMixin {
  final math.Random _rnd = math.Random();

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  /// 绝对角度（度，可累计超过 360）；控制器只在 0~1 归一区间跑，
  /// 每次转盘的起止角放在 [_from, _to] 里插值，避免把越界值写回 controller。
  double _rotation = 0;
  double _from = 0;
  double _to = 0;
  bool _busy = false;
  String _result = '';

  List<KitWheelSet> _sets = const [];
  String _curId = '';
  bool _loaded = false;

  KitWheelSet? get _cur {
    for (final s in _sets) {
      if (s.id == _curId) return s;
    }
    return _sets.isEmpty ? null : _sets.first;
  }

  @override
  void initState() {
    super.initState();
    _spin.addListener(
      () => setState(() => _rotation = _from + (_to - _from) * _spin.value),
    );
    _boot();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final d = await ref.read(kitRepositoryProvider).toolData(kitToolKeyWheel);
    if (!mounted) return;
    final s = kitWheelDecode(d);
    setState(() {
      _sets = s.sets;
      _curId = s.curId;
      _loaded = true;
    });
  }

  Future<void> _save() => ref.read(kitRepositoryProvider).setToolData(
        kitToolKeyWheel,
        kitWheelEncode(_sets, _curId),
      );

  /// 打开设置弹层（弹层内部即时落库，关闭后本屏重取一遍）。
  Future<void> _openCfg() async {
    if (_cur == null) return;
    await kitOpenWheelCfg(context, sets: _sets, curId: _curId);
    if (mounted) await _boot();
  }

  Future<void> _go() async {
    final cur = _cur;
    if (_busy || cur == null || cur.items.length < kKitWheelMinItems) {
      if (cur != null) {
        AppToast.show(context, '至少 $kKitWheelMinItems 个选项才能转');
      }
      return;
    }
    final pick = kitWheelSpin(cur, currentRotation: _rotation, rand01: _rnd.nextDouble());
    setState(() {
      _busy = true;
      _result = '转动中…';
      _from = _rotation;
      _to = pick.rotateTo;
    });
    await _spin.animateTo(
      1,
      curve: const Cubic(0.15, 0.9, 0.15, 1),
    );
    _from = _to; // 归一区间收到终点，controller 复位不再改动角度
    _spin.value = 0;
    // 与原型 setTimeout(2850) 同步：动画结束后落结果并记历史。
    if (!mounted) return;
    final opt = cur.items[pick.index].text;
    final updated = KitWheelSet(
      id: cur.id,
      name: cur.name,
      items: cur.items,
      history: kitWheelPushHistory(
        cur.history,
        KitWheelResult(opt, DateTime.now().millisecondsSinceEpoch),
      ),
    );
    setState(() {
      _busy = false;
      _result = opt;
      _sets = [for (final s in _sets) s.id == cur.id ? updated : s];
    });
    await _save();
  }

  Future<void> _clearHist() async {
    final cur = _cur;
    if (cur == null) return;
    setState(() {
      _sets = [
        for (final s in _sets)
          if (s.id == cur.id)
            KitWheelSet(id: s.id, name: s.name, items: s.items)
          else
            s,
      ];
    });
    await _save();
    if (mounted) AppToast.show(context, '本套历史已清空');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cur = _cur;
    final now = DateTime.now();
    if (!_loaded) {
      return kitToolNote('正在读本机抽签数据…');
    }
    final items = cur?.items ?? const <KitWheelItem>[];
    final sectors = [if (cur != null) ...kitWheelSectors(cur)];
    return Column(
      children: [
        SizedBox(
          width: 196,
          height: 196,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -6,
                child: CustomPaint(
                  size: const Size(18, 14),
                  painter: _PointerPainter(const Color(0xFF0F172A)),
                ),
              ),
              Transform.rotate(
                angle: _rotation * math.pi / 180,
                child: CustomPaint(
                  key: const ValueKey('kit-wheel-disc'),
                  size: const Size(176, 176),
                  painter: _WheelPainter(items: items, sectors: sectors),
                ),
              ),
              GestureDetector(
                key: const ValueKey('kit-wheel-go'),
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : _go,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tokens.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: tokens.cardBorder),
                    boxShadow: tokens.cardShadow,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _busy ? '…' : '开始',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _result,
          key: const ValueKey('kit-wheel-res'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: tokens.accent,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          key: const ValueKey('kit-wheel-cfg'),
          behavior: HitTestBehavior.opaque,
          onTap: _openCfg,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: context.cardDecoration,
            child: Row(
              children: [
                Icon(Icons.tune, size: 20, color: tokens.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选项与权重 · 套管理 · 批量粘贴',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cur == null
                            ? '当前套 —'
                            : '当前套「${cur.name}」 · ${cur.items.length} 项 · 权重合计 ${cur.totalWeight}',
                        key: const ValueKey('kit-wheel-setsum'),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Text('设置 ›', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        kitToolSubCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              kitToolSection(
                '历史结果 · 本套',
                trailing: [
                  kitToolBtn(
                    context,
                    '清空',
                    (cur?.history.isEmpty ?? true) ? null : _clearHist,
                    keyName: 'kit-wheel-hist-clear',
                    small: true,
                    color: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (cur == null || cur.history.isEmpty)
                kitToolNote('本套尚无结果 · 转一次就有')
              else
                for (final h in cur.history)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 58,
                          child: Text(
                            kitRelText(h.ts, now),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: Text(h.option, style: const TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
              if (cur != null && cur.history.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    kitToolBtn(
                      context,
                      '结果写日记',
                      () {
                        kitToolCopy(context, cur.history.first.option,
                            msg: '结果已复制 · 请到日记页粘贴留档');
                        // 反馈轮5 同款口径：跳记录模块必须落到对应视图，
                        // 无段参会停在用户上次停留的段（可能停在笔记段）。
                        context.go('/journal?tab=diary');
                      },
                      keyName: 'kit-wheel-to-diary',
                      small: true,
                    ),
                    const SizedBox(width: 6),
                    kitToolBtn(
                      context,
                      '结果存笔记',
                      () => kitToolCopy(context, '抽签 · ${cur.history.first.option}'),
                      keyName: 'kit-wheel-to-note',
                      small: true,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部下指三角指针（原型 CSS 边框三角形）。
class _PointerPainter extends CustomPainter {
  _PointerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) => old.color != color;
}

/// 轮盘扇区 + 标签（原型 `wheelDraw` 的 conic-gradient + svg 文字同义）。
class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.items, required this.sectors});

  final List<KitWheelItem> items;
  final List<({double start, double end})> sectors;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    if (items.length < kKitWheelMinItems) {
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE2E8F0));
      return;
    }
    final colors = kitWheelColors(items.length);
    for (var i = 0; i < items.length; i++) {
      final s = sectors[i];
      final start = (s.start - 90) * math.pi / 180;
      final sweep = (s.end - s.start) * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        true,
        Paint()..color = _hex(colors[i % colors.length]),
      );
    }
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1);
    // 标签：扇区中线 58px 处，跨左半圈翻转 180°（原型同口径），字号按扇区宽度收敛。
    for (var i = 0; i < items.length; i++) {
      final s = sectors[i];
      final mid = (s.start + s.end) / 2;
      final a = (mid - 90) * math.pi / 180;
      final pos = Offset(r + 58 * math.cos(a), r + 58 * math.sin(a));
      final span = s.end - s.start;
      final label = items[i].text;
      final shown = items[i].weight > 1
          ? '${label.length > 7 ? '${label.substring(0, 6)}…' : label} ×${items[i].weight}'
          : (label.length > 7 ? '${label.substring(0, 6)}…' : label);
      final tp = TextPainter(
        text: TextSpan(
          text: shown,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: span < 26 ? 7.5 : 9.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      if (mid > 90 && mid < 270) canvas.rotate(math.pi);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  static Color _hex(String h) {
    final rgb = kitHexToRgb(h) ?? const KitRgb(0, 0, 0);
    return Color(0xFF000000 | (rgb.r << 16) | (rgb.g << 8) | rgb.b);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.items != items || old.sectors != sectors;
}
