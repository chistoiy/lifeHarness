import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/time_block.dart';
import '../calendar_providers.dart';
import 'block_mark_sheet.dart';

/// 日视图·格子时间块模式（需求 V1.4/V1.12 · 原型 calGridMode）。
///
/// 核心规则（与原型一致）：
/// G1 覆盖 06:00-24:00，1 格 = 粒度分钟（1/5/10/15/30/60）；
/// G2 **总面积固定**：cols=max(6,√(n*0.82))，格子随粒度自动伸缩，任意粒度全天一屏无需滚动；
/// G3 按住拖动滑选多格 → 松手弹标记面板；点已标记单格可取消/覆盖；
/// G4 整点标小时数（仅 cols≤12 时显示，防小格拥挤）；
/// G5 进行中事项区间红色脉冲。
class GridDayView extends ConsumerStatefulWidget {
  const GridDayView({super.key, required this.day});

  final DateTime day;

  @override
  ConsumerState<GridDayView> createState() => _GridDayViewState();
}

class _GridDayViewState extends ConsumerState<GridDayView>
    with SingleTickerProviderStateMixin {
  int? _selA;
  int? _selB;
  bool _selecting = false;
  late final AnimationController _pulse;

  static const _startMin = 360; // 06:00
  static const _endMin = 1440; // 24:00

  @override
  void initState() {
    super.initState();
    // 脉冲仅在存在进行中事项时运转（避免无谓永动动画干扰 pumpAndSettle/省电）。
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  int _cellIndexAt(Offset local, double cellW, double cellH, double gap, int cols) {
    final col = (local.dx / (cellW + gap)).floor();
    final row = (local.dy / (cellH + gap)).floor();
    if (col < 0 || row < 0 || col >= cols) return -1;
    return row * cols + col;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final gran = ref.watch(granularityProvider);
    final blocks = ref.watch(dayBlocksProvider(widget.day)).valueOrNull ?? const [];
    final active = ref.watch(activeEventProvider).valueOrNull;

    final n = (_endMin - _startMin) ~/ gran;
    final cols = math.max(6, (math.sqrt(n * 0.82)).round());
    final rows = (n / cols).ceil();
    final height = math.min(MediaQuery.sizeOf(context).height * 0.52, 470.0);
    const gap = 3.0;
    final cellH = (height - gap * (rows - 1)) / rows;
    final showHour = cols <= 12;

    // 进行中事项 → 分钟区间（仅当天）。
    int? liveS, liveE;
    if (active != null &&
        active.start.year == widget.day.year &&
        active.start.month == widget.day.month &&
        active.start.day == widget.day.day) {
      liveS = active.start.hour * 60 + active.start.minute;
      liveE = DateTime.now().hour * 60 + DateTime.now().minute;
      if (liveE <= liveS) liveE = liveS + 1;
    }
    if (liveS != null) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1;
    }

    TimeBlock? blockAt(int minute) {
      for (final b in blocks) {
        if (b.covers(minute)) return b;
      }
      return null;
    }

    final selLo = _selA == null || _selB == null
        ? null
        : math.min(_selA!, _selB!);
    final selHi = selLo == null ? null : math.max(_selA!, _selB!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🖐 拖动滑选 · 1 格 = $gran 分钟 · 总面积固定：任意粒度全天一屏概览 · 进行中块红色脉冲',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final cellW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) {
                final i = _cellIndexAt(e.localPosition, cellW, cellH, gap, cols);
                if (i < 0 || i >= n) return;
                setState(() {
                  _selecting = true;
                  _selA = _selB = i;
                });
              },
              onPointerMove: (e) {
                if (!_selecting) return;
                final i = _cellIndexAt(e.localPosition, cellW, cellH, gap, cols);
                if (i < 0 || i >= n || i == _selB) return;
                setState(() => _selB = i);
              },
              onPointerUp: (e) {
                if (!_selecting || _selA == null || _selB == null) {
                  _selecting = false;
                  return;
                }
                _selecting = false;
                final a = math.min(_selA!, _selB!);
                final b = math.max(_selA!, _selB!);
                final hit = (a == b) ? blockAt(_startMin + a * gran) : null;
                showBlockMarkSheet(
                  context,
                  ref,
                  day: widget.day,
                  gran: gran,
                  startMin: _startMin + a * gran,
                  endMin: _startMin + b * gran + gran,
                  existing: hit,
                ).then((_) {
                  if (mounted) {
                    setState(() {
                      _selA = _selB = null;
                    });
                    ref.invalidate(dayBlocksProvider(widget.day));
                  }
                });
              },
              child: SizedBox(
                height: height,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: cellW / cellH,
                  ),
                  itemCount: n,
                  itemBuilder: (context, i) {
                    final m = _startMin + i * gran;
                    final blk = blockAt(m);
                    final isLive = liveS != null && m >= liveS && m < (liveE ?? liveS + 1);
                    final selected = selLo != null && i >= selLo && i <= selHi!;
                    final hour = m % 60 == 0;
                    Color bg;
                    if (isLive) {
                      bg = const Color(0xFFF43F5E);
                    } else if (blk != null) {
                      bg = blk.category.colorOf(tokens.accent);
                    } else {
                      bg = scheme.onSurface.withValues(alpha: .06);
                    }
                    final cell = AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                        border: selected
                            ? Border.all(color: tokens.accent, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: showHour && hour
                          ? Text(
                              '${m ~/ 60}'.padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: blk != null || isLive
                                    ? Colors.white.withValues(alpha: .9)
                                    : scheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                    );
                    if (!isLive) return Tooltip(message: blk != null ? '${blk.category.label} ${_fmt(blk.startMin)}-${_fmt(blk.endMin)}${blk.note == null ? '' : ' · ${blk.note}'}' : '空格 ${_fmt(m)}', child: cell);
                    return FadeTransition(opacity: _pulse.drive(_LiveTween()), child: cell);
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        if (selLo != null)
          Text(
            '已选 ${_fmt(_startMin + selLo * gran)} - ${_fmt(_startMin + selHi! * gran + gran)} · ${selHi - selLo + 1} 格 = ${(selHi - selLo + 1) * gran} 分钟',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tokens.accent),
          ),
      ],
    );
  }

  static String _fmt(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

/// 脉冲只淡出到 55% 保持可读。
class _LiveTween extends Tween<double> {
  _LiveTween() : super(begin: 1.0, end: 0.55);
}
