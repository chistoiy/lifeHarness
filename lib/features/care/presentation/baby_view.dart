import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/care_agg.dart';
import '../data/care_repository.dart';
import '../domain/care_models.dart';
import '../domain/growth_calc.dart';
import 'baby_sheets.dart';
import 'care_kit.dart';
import 'care_providers.dart';
import 'event_sheet.dart';
import 'ev_sheets.dart';

/// 宝宝主视图（原型 p-baby）。批2 hero；批3 速记宫格/计时条/今日列表；
/// 批5/6/7 补曲线疫苗双列卡、近7天柱、里程碑入口。
class CareBabyView extends ConsumerWidget {
  const CareBabyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(careDataProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (d) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (d.currentBaby == null)
            EmptyDashRow(
              text: '+ 建立宝宝档案（昵称/生日/性别）',
              onTap: () => showAddBabySheet(context),
            )
          else ...[
            _Hero(d: d),
            const _EvSection(),
            const _FeedBar(),
            _TodayCard(d: d),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _GrowthThumb()),
                  SizedBox(width: 12),
                  Expanded(child: _VaxMini()),
                ],
              ),
            ),
            const _WeekBars(),
            const _MilesCard(),
          ],
        ],
      ),
    );
  }
}

/// 事件速记区（头行 管理/⇅排序 + 五列宫格）。排序模式=▲▼逐格移位，完成即落库。
class _EvSection extends ConsumerStatefulWidget {
  const _EvSection();

  @override
  ConsumerState<_EvSection> createState() => _EvSectionState();
}

class _EvSectionState extends ConsumerState<_EvSection> {
  bool _sortOn = false;
  List<String>? _draft;

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    final order = _draft ?? d.evOrder;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('事件速记',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              GestureDetector(
                key: const ValueKey('ev-manage'),
                onTap: _sortOn ? null : () => showEvManage(context),
                child: Text('管理',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _sortOn ? Colors.grey : tokens.accent)),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                key: const ValueKey('ev-sort-toggle'),
                onTap: () async {
                  if (_sortOn && _draft != null) {
                    await ref.read(careRepositoryProvider).saveEvOrder(_draft!);
                    _draft = null;
                    careTouch(ref);
                    if (context.mounted) AppToast.show(context, '事件顺序已保存（本机持久化）');
                  }
                  setState(() {
                    _sortOn = !_sortOn;
                    if (_sortOn) _draft = [...order];
                  });
                },
                child: Text(_sortOn ? '✓ 完成' : '⇅ 排序',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _sortOn ? tokens.accent : Colors.grey)),
              ),
            ],
          ),
        ),
        LayoutBuilder(builder: (context, c) {
          const cols = 5;
          const gap = 8.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < order.length; i++)
                SizedBox(
                  width: w,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        key: ValueKey('ev-open-${order[i]}'),
                        onTap: _sortOn
                            ? null
                            : () => showEventLogSheet(context, kind: order[i]),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: context.cardDecoration,
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color:
                                      careHex(d.evOf(order[i]).tint).withValues(alpha: .16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(d.evOf(order[i]).icon,
                                    style: const TextStyle(fontSize: 18)),
                              ),
                              const SizedBox(height: 4),
                              Text(d.evOf(order[i]).name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 9, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      if (_sortOn)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Column(
                            children: [
                              _arrow('▲', () {
                                if (i == 0) {
                                  AppToast.show(context, '已在边界');
                                  return;
                                }
                                setState(() {
                                  final list = [...order];
                                  list[i] = list[i - 1];
                                  list[i - 1] = order[i];
                                  _draft = list;
                                });
                              }),
                              _arrow('▼', () {
                                if (i == order.length - 1) {
                                  AppToast.show(context, '已在边界');
                                  return;
                                }
                                setState(() {
                                  final list = [...order];
                                  list[i] = list[i + 1];
                                  list[i + 1] = order[i];
                                  _draft = list;
                                });
                              }),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _arrow(String t, VoidCallback onTap) => GestureDetector(
        key: ValueKey('ev-move-$t'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(t,
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w800, color: context.tokens.accent)),
        ),
      );
}

/// hero 渐变卡：头像/昵称/年龄徽章/副行 + 记录人钮 + 三数据位（近7天真实聚合）。
class _Hero extends ConsumerWidget {
  const _Hero({required this.d});
  final CareData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = d.currentBaby!;
    final tokens = context.tokens;
    final today = DateTime.now().withoutTimeCare();
    final wk = careWeekStats(d.logs, today);
    final slots = [
      (wk.feedN > 0 ? '${wk.feedN}' : '—', '本周喂养', 'feed'),
      (wk.diaperN > 0 ? '${wk.diaperN}' : '—', '尿布片', 'diaper'),
      (wk.sleepAvgH > 0 ? '${wk.sleepAvgH.toStringAsFixed(1)}h' : '—', '日均睡眠', 'sleep'),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: careGrad(kBabyHeroStops,
            begin: const Alignment(-.7, -1), end: const Alignment(.7, 1)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: careHex('#818cf8').withValues(alpha: .22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -38,
            child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white.withValues(alpha: .1))),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .2)),
                    alignment: Alignment.center,
                    child: Text(b.avatar, style: const TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('hero-to-babies'),
                      onTap: () => context.push('/care/babies'),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(b.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius: BorderRadius.circular(999)),
                                      child: Text(careAgeText(b.birth, today),
                                          style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('${b.sex == '女' ? '女宝' : '男宝'} · 生日 ${careDayKey(b.birth)}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white70)),
                              ],
                            ),
                          ),
                          const Text('›',
                              style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    key: const ValueKey('hero-carer'),
                    onTap: () => showBabySwitchSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('${d.curCarer} · 记录中 ›',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final (v, l, grp) in slots)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          key: ValueKey('hero-$grp'),
                          onTap: () {
                            ref
                                .read(careDayFilterProvider.notifier)
                                .state = careHeroSlotKinds(grp);
                            context.push('/care/day');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(16)),
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                Text(v,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white)),
                                const SizedBox(height: 2),
                                Text(l,
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 2, child: DecoratedBox(decoration: BoxDecoration(color: tokens.page))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 计时条（卡内形态，原型 #feedTimer）：实时 mm:ss + 换边（亲喂）+ ■ 结束自动入账。
class _FeedBar extends ConsumerStatefulWidget {
  const _FeedBar();

  @override
  ConsumerState<_FeedBar> createState() => _FeedBarState();
}

class _FeedBarState extends ConsumerState<_FeedBar> {
  Timer? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final running = ref.read(feedTimerProvider) != null;
    if (running && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context, ) {
    final s = ref.watch(feedTimerProvider);
    if (s == null) return const SizedBox.shrink();
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final d = ref.watch(careDataProvider).valueOrNull;
    final E = d?.evOf(s.kind);
    final secs = DateTime.now().difference(s.t0).inSeconds;
    final mmss = '${secs ~/ 60}:${careP2(secs % 60)}';
    final isN = s.kind == 'nurse';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: context.cardDecoration,
      child: Row(
        children: [
          Text(E?.icon ?? '⏱', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${isN && s.side != null ? '${s.side}侧' : ''}${E?.name ?? s.kind}计时 · $mmss',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text(isN ? '换边继续计时，结束时自动生成分段记录' : '结束自动入账，时长=起止差',
                    style: const TextStyle(fontSize: 9, color: Colors.grey)),
              ],
            ),
          ),
          if (isN)
            GestureDetector(
              key: const ValueKey('ft-swap'),
              onTap: () => ref.read(feedTimerProvider.notifier).swap(),
              child: const _FtBtn('🔄 换边'),
            ),
          if (isN) const SizedBox(width: 6),
          GestureDetector(
            key: const ValueKey('ft-end'),
            onTap: () async {
              final r = await ref.read(feedTimerProvider.notifier).stop();
              if (r == null || !mounted) return;
              if (!context.mounted) return;
              AppToast.show(context,
                  '✔ 计时已存 · ${r.s}~${r.e ?? ''}（时长可二次修改）');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: careHex('#f43f5e').withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(999)),
              child: const Text('■ 结束',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF43F5E))),
            ),
          ),
        ],
      ),
    );
  }
}

class _FtBtn extends StatelessWidget {
  const _FtBtn(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: context.tokens.cardBorder,
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

/// 今日列表卡（recRow 同构：时间/图标/标题/记录人；无删除钮，删除在弹层内 · 决策 4）。
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.d});
  final CareData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final today = careDayKey(DateTime.now());
    final logs = d.logsOfDay(today);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(TextSpan(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800), children: [
                const TextSpan(text: '今日 · '),
                TextSpan(text: '${logs.length}', style: TextStyle(color: tokens.accent)),
                const TextSpan(text: ' 条'),
              ])),
              GestureDetector(
                key: const ValueKey('today-to-day'),
                onTap: () => context.push('/care/day'),
                child: Text('全天时间线 ›',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: tokens.accent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (logs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                  child: Text('今天还没有记录，点上方事件速记',
                      style: TextStyle(fontSize: 11, color: Colors.grey))),
            )
          else
            for (final r in logs.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  key: ValueKey('today-rec-${r.id}'),
                  onTap: () => showEventLogSheet(context, edit: r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                        color: tokens.cardBorder.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        SizedBox(
                            width: 38,
                            child: Text(r.s,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey, fontFeatures: [FontFeature.tabularFigures()]))),
                        Text(d.iconOf(r), style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.titleOf(r),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700)),
                              Text('记录人：${r.rec ?? '—'}',
                                  style: const TextStyle(fontSize: 9, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const Text('›', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// 宝宝页生长曲线缩略卡（原型 #growthSvg 迷你描点 + gModeBtn P/SD/Z 轮换）。
/// 批6 将与疫苗卡组成双列；当前整宽。
class _GrowthThumb extends ConsumerStatefulWidget {
  const _GrowthThumb();

  @override
  ConsumerState<_GrowthThumb> createState() => _GrowthThumbState();
}

class _GrowthThumbState extends ConsumerState<_GrowthThumb> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null || d.currentBaby == null) return const SizedBox.shrink();
    final baby = d.currentBaby!;
    final isF = baby.sex == '女';
    final pts = growthSeries(m: GMetric.w, birth: baby.birth, measures: d.measures);
    final tokens = context.tokens;
    return GestureDetector(
      key: const ValueKey('thumb-growth'),
      onTap: () => context.push('/care/growth'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📈 生长曲线',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                GestureDetector(
                  key: const ValueKey('thumb-gmode'),
                  onTap: () => setState(() => _mode = (_mode + 1) % 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: tokens.cardBorder,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(['P', 'SD', 'Z'][_mode],
                        style: const TextStyle(
                            fontSize: 8, fontWeight: FontWeight.w800, color: Colors.grey)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 88,
              width: double.infinity,
              child: pts.isEmpty
                  ? const Center(
                      child: Text('尚无实测 · 保存测量后自动描点',
                          style: TextStyle(fontSize: 9, color: Colors.grey)))
                  : CustomPaint(
                      painter:
                          _ThumbPainter(points: pts, color: careHex('#6366f1')),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              pts.isEmpty
                  ? '体重 · 待首次测量'
                  : '体重 ${pts.last.$2.toStringAsFixed(1)}kg · '
                      '近 ${growthShortTag(isF, GMetric.w, pts.last.$1, pts.last.$2, _mode)} · '
                      '${pts.length} 次实测',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  const _ThumbPainter({required this.points, required this.color});
  final List<(double, double)> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final vals = points.map((p) => p.$2).toList();
    final lo = vals.reduce(math.min) * 0.78;
    final hi = vals.reduce(math.max) * 1.1;
    final maxM = points.map((p) => p.$1).reduce(math.max).clamp(1, 1000);
    double X(double m) => 16 + (m / maxM) * (size.width - 32);
    double Y(double v) =>
        size.height - 14 - ((v - lo) / (hi - lo)).clamp(0, 1) * (size.height - 24);
    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final x = X(points[i].$1), y = Y(points[i].$2);
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    for (final p in points) {
      canvas.drawCircle(Offset(X(p.$1), Y(p.$2)), 3, Paint()..color = color);
    }
    final tp = TextPainter(
      text: TextSpan(
          text: '${points.first.$1.toStringAsFixed(0)}m',
          style: const TextStyle(fontSize: 7, color: Color(0xFF94A3B8))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(X(points.first.$1) - 4, size.height - 10));
    final tp2 = TextPainter(
      text: TextSpan(
          text: '${points.last.$1.toStringAsFixed(0)}m',
          style: const TextStyle(fontSize: 7, color: Color(0xFF94A3B8))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(X(points.last.$1) - 8, size.height - 10));
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.points.length != points.length || old.color != color;
}

/// 宝宝页疫苗迷你卡（原型 .grid-cols-2 右卡：最近 3 针未完成 + D-N）。
class _VaxMini extends ConsumerWidget {
  const _VaxMini();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null || d.currentBaby == null) return const SizedBox.shrink();
    final today = DateTime.now().withoutTimeCare();
    final pending = d.vaccines.where((x) => !x.done).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    final shown = pending.take(3).toList();
    return GestureDetector(
      key: const ValueKey('thumb-vax'),
      onTap: () => context.push('/care/vaccine'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('💉 疫苗计划',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final x in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Text(x.status(today) == 'late' ? '⚠️' : '💉',
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text('${x.name} ${x.dose}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    Text(
                        '${x.due.substring(5)} · ${x.daysTo(today) > 0 ? 'D-${x.daysTo(today)}' : '已到期'}',
                        style: const TextStyle(fontSize: 8, color: Colors.grey)),
                  ],
                ),
              ),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('暂无接种计划 · 点此新增',
                    style: TextStyle(fontSize: 9, color: Colors.grey)),
              ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

/// 发育里程碑入口卡（msSub：近两项达成 ✓ · 下一个观察）。
class _MilesCard extends ConsumerWidget {
  const _MilesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null || d.currentBaby == null) return const SizedBox.shrink();
    final miles = d.milestones;
    final dn = miles.where((m) => m.done).toList();
    final wa = miles.where((m) => !m.done).toList();
    final sub = (dn.isNotEmpty
            ? dn.reversed.take(2).toList().reversed.map((m) => '${m.name} ✓').join(' · ')
            : '暂无达成') +
        (wa.isNotEmpty ? ' · 下一个观察：${wa.first.name}' : '');
    return GestureDetector(
      key: const ValueKey('thumb-milestones'),
      onTap: () => context.push('/care/milestones'),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: const Text('🏆', style: TextStyle(fontSize: 17)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('发育里程碑',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
            const Text('›', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// 近 7 天 · 喂养 × 睡眠 双柱卡（原型 #weekBars；次/时长双列，点击进汇总）。
class _WeekBars extends ConsumerWidget {
  const _WeekBars();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null || d.currentBaby == null) return const SizedBox.shrink();
    final days = [
      for (var i = 6; i >= 0; i--)
        careDayKey(DateTime.now().subtract(Duration(days: i))),
    ];
    final feeds = [
      for (final day in days)
        d.logsOfDay(day).where((r) => kFeedKinds.contains(r.k)).length
    ];
    final sleepH = [
      for (final day in days)
        d.logsOfDay(day).where((r) => r.k == 'sleep').fold<int>(0, (a, r) => a + r.durOr0) / 60
    ];
    final maxF = feeds.fold<int>(1, (a, b) => b > a ? b : a);
    return GestureDetector(
      key: const ValueKey('week-bars'),
      onTap: () => context.push('/care/stats'),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('近 7 天 · 喂养 × 睡眠',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dot(careHex('#6366f1')),
                    const SizedBox(width: 3),
                    const Text('次', style: TextStyle(fontSize: 9, color: Colors.grey)),
                    const SizedBox(width: 8),
                    _dot(careHex('#34d399')),
                    const SizedBox(width: 3),
                    const Text('时长 ›', style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Container(
                                height: (feeds[i] / maxF * 52).clamp(3, 52).toDouble(),
                                decoration: const BoxDecoration(
                                    color: Color(0xCC6366F1),
                                    borderRadius:
                                        BorderRadius.vertical(top: Radius.circular(4))),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Container(
                                height: (sleepH[i] / 14 * 52).clamp(3, 52).toDouble(),
                                decoration: const BoxDecoration(
                                    color: Color(0xB334D399),
                                    borderRadius:
                                        BorderRadius.vertical(top: Radius.circular(4))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}
