import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/cal_event.dart';
import '../../domain/category.dart';
import '../../domain/time_block.dart';
import '../calendar_providers.dart';
import 'time_pick_sheet.dart';

/// 块视图·格子时间块（V1.19~V1.21 · 原型 calBlockView）。
///
/// 规则：
/// G1 **全天 0-24**（V1.19.2 起，替代 06:00 起点），1 格 = 粒度分钟；
/// G2 总面积固定：cols=max(6,√(n*0.82))，任意粒度全天一屏；
/// G3 **选块即标记**：滑选（含单格）后点右侧分类=直接标记（块即时间，免弹层）；
///     V1.52：未选中时点分类=**开一段计时中块**（与 ＋ 添加同一状态机·仅今天可用）；
/// G4 重复标记=拆分覆盖同步（markRange 事务，原块非交叠段保留）；
/// G5 点已有块/事件=与添加同款统一编辑弹层（V1.52 起不再走详情层）。
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

  static const _startMin = 0; // V1.19.2 全天起点 00:00
  static const _endMin = 1440;

  @override
  void initState() {
    super.initState();
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

  void _clearSel() => setState(() => _selA = _selB = null);

  /// 分类速记列点击：有选区=标记选区（拆分覆盖）；
  /// V1.52：无选区=**开一段计时中块**（上一段自动收口·仅今天可用）。
  Future<void> _railTap(Category c, int gran) async {
    final now = DateTime.now();
    final isToday = widget.day.year == now.year &&
        widget.day.month == now.month &&
        widget.day.day == now.day;
    int s, e;
    if (_selA != null && _selB != null) {
      final a = math.min(_selA!, _selB!), b = math.max(_selA!, _selB!);
      s = _startMin + a * gran;
      e = math.min(_startMin + b * gran + gran, _endMin);
    } else if (isToday) {
      final nm = now.hour * 60 + now.minute;
      final dao = ref.read(timeBlockDaoProvider);
      final prev = await dao.activeTiming();
      await dao.startTiming(widget.day, nm, catId: c.id, catName: c.name, note: c.name);
      _clearSel();
      ref.invalidate(dayBlocksProvider(widget.day));
      ref.invalidate(timingBlockProvider);
      ref.invalidate(monthTimingDaysProvider((widget.day.year, widget.day.month)));
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text(prev == null
                  ? '▶ 开始计时「${c.name}」· 点该块「■ 结束计时」或点其他分类自动接龙'
                  : '▶ 上一段「${prev.catName}」已截止 ${_fmt(nm)} · 开始计时「${c.name}」'),
              duration: const Duration(milliseconds: 1600)));
      }
      return;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('仅今天可速记开始计时 · 其他日期请用 ＋ 补录'),
              duration: Duration(milliseconds: 1500)));
      }
      return;
    }
    _clearSel();
    await ref.read(timeBlockDaoProvider).markRange(widget.day, s, math.max(e, s + 1),
        catId: c.id, catName: c.name, note: c.tag == null ? c.name : '${c.name} ${c.tag}');
    ref.invalidate(dayBlocksProvider(widget.day));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('✔ 已标记 ${_fmt(s)}-${_fmt(math.min(e, 1439))} · ${c.name}（块即时间·免弹层 · L4 同步）'),
            duration: const Duration(milliseconds: 1400)));
    }
  }

  static String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final gran = ref.watch(granularityProvider);
    final blocks = ref.watch(dayBlocksProvider(widget.day)).valueOrNull ?? const [];
    final events = ref.watch(eventsProvider).valueOrNull ?? const [];
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final catColors = ref.watch(catColorsByNameProvider);
    final primaryCats = cats.where((c) => c.isPrimary).toList();

    final dayEvents = events
        .where((e) =>
            DateTime(e.start.year, e.start.month, e.start.day) ==
            DateTime(widget.day.year, widget.day.month, widget.day.day))
        .toList();
    final live = dayEvents.where((e) => e.status == EventStatus.active).toList();

    final n = (_endMin - _startMin) ~/ gran;
    final cols = math.max(6, (math.sqrt(n * 0.82)).round());
    final rows = (n / cols).ceil();
    final height = math.min(MediaQuery.sizeOf(context).height * 0.52, 470.0);
    const gap = 3.0;
    final cellH = (height - gap * (rows - 1)) / rows;
    final showHour = cols <= 12;

    int? liveS, liveE;
    if (live.isNotEmpty) {
      final now = DateTime.now();
      liveS = live.first.start.hour * 60 + live.first.start.minute;
      liveE = now.hour * 60 + now.minute;
      if (liveE <= liveS) liveE = liveS + 1;
    }
    if (liveS != null || blocks.any((b) => b.isTiming)) {
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

    CalEvent? eventAt(int minute) {
      for (final e in dayEvents) {
        if (e.allDay || e.end == null) continue;
        final s = e.start.hour * 60 + e.start.minute;
        final en = e.end!.hour * 60 + e.end!.minute;
        if (minute >= s && minute < math.max(en, s + 1)) return e;
      }
      return null;
    }

    final selLo = _selA == null || _selB == null ? null : math.min(_selA!, _selB!);
    final selHi = selLo == null ? null : math.max(_selA!, _selB!);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // R14-8：教学串摘除，只留刻度读数（原型同款「1 格 = N 分 · 全天 0-24」）。
                '1 格 = $gran 分 · 全天 0-24',
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
                      final m = _startMin + a * gran;
                      // V1.28⑧：进行中事件 end=null 不进 eventAt 覆盖判定，单独按 live 区命中 → 详情
                      final hitLive = (a == b && liveS != null &&
                              m >= liveS &&
                              m < (liveE ?? liveS + 1))
                          ? live.first
                          : null;
                      final hitEv = (a == b) ? eventAt(m) : null;
                      if (hitLive != null && hitEv == null) {
                        _clearSel();
                        showTimePickSheet(context, ref, event: hitLive);
                        return;
                      }
                      if (hitEv != null) {
                        _clearSel();
                        showTimePickSheet(context, ref, event: hitEv);
                        return;
                      }
                      final hit = (a == b) ? blockAt(m) : null;
                      if (hit != null && hit.source != kSrcEvent) {
                        _clearSel();
                        // V1.52：点已有块=与添加同款编辑弹层（含删除/拆分/合并/结束计时）
                        showTimePickSheet(context, ref, block: hit);
                        return;
                      }
                      // 保持选区，等右侧分类点选（V1.21 选块即标记）
                      setState(() {});
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
                          final ev = eventAt(m);
                          final isLive = liveS != null && m >= liveS && m < (liveE ?? liveS + 1);
                          final selected = selLo != null && i >= selLo && i <= selHi!;
                          Color bg;
                          if (isLive) {
                            bg = const Color(0xFFF43F5E);
                          } else if (blk != null && blk.isTiming) {
                            bg = const Color(0xFFF43F5E);
                          } else if (ev != null) {
                            bg = ev.status == EventStatus.done
                                ? const Color(0xFF34D399)
                                : tokens.accent;
                          } else if (blk != null) {
                            bg = blockColor(blk, catColors, tokens.accent);
                          } else {
                            bg = scheme.onSurface.withValues(alpha: .06);
                          }
                          final label = isLive
                              ? '●进行中'
                              : (blk != null && blk.isTiming
                                  ? '●计时中'
                                  : (ev != null
                                      ? (ev.status == EventStatus.done ? '✓完成' : '⚡事件')
                                      : (blk?.catName ?? '')));
                          final cell = AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, _) {
                              // 原型 .animate-pulse：进行中块红色脉冲
                              final liveBg = isLive
                                  ? Color.lerp(const Color(0xFFF43F5E),
                                      const Color(0xFFF43F5E).withValues(alpha: .4),
                                      _pulse.value)!
                                  : bg;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                decoration: BoxDecoration(
                                  color: liveBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: selected
                                      ? Border.all(color: tokens.accent, width: 2)
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: showHour && m % 60 == 0
                                    ? Text(
                                        '${m ~/ 60}'.padLeft(2, '0'),
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                          color: (blk != null || isLive || ev != null)
                                              ? Colors.white.withValues(alpha: .9)
                                              : scheme.onSurfaceVariant,
                                        ),
                                      )
                                    : null,
                              );
                            },
                          );
                          final tip = isLive
                              ? '$label ${_fmt(liveS)}-${_fmt(liveE ?? liveS + 1)}'
                              : (ev != null
                                  ? '$label ${ev.title} ${_fmt(ev.start.hour * 60 + ev.start.minute)}-${ev.end == null ? '' : _fmt(ev.end!.hour * 60 + ev.end!.minute)}'
                                  : (blk != null
                                      ? '${blk.catName} ${_fmt(blk.startMin)}-${_fmt(blk.endMin)}${blk.note == null ? '' : ' · ${blk.note}'}'
                                      : '空格 ${_fmt(m)}'));
                          return Tooltip(message: tip, child: cell);
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              if (selLo != null)
                Text(
                  '已选 ${_fmt(_startMin + selLo * gran)} - ${_fmt(math.min(_startMin + selHi! * gran + gran, 1440))} · ${(selHi - selLo + 1) * gran} 分钟 → 点右侧分类直接标记',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tokens.accent),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 右侧分类速记列（V1.19 · 有选区=标记选区，无选区=就地开计时块；
        // R14-8：列头教学串摘除，只留「分类」功能标签）。
        SizedBox(
          width: 64,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // R14-8：右列标题只留功能标签（原型 p-calendar 块视图同款「分类」）。
              Text('分类',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8.5, color: scheme.onSurfaceVariant, height: 1.3)),
              const SizedBox(height: 4),
              SizedBox(
                height: height - 24,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final c in primaryCats)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _railTap(c, gran),
                          child: Container(
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.name == '工作' ? tokens.accent : catColors[c.name],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(c.name,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
