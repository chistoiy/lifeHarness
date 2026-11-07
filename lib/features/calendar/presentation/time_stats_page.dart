import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/block_ops.dart';
import '../domain/time_block.dart';
import '../domain/week_align.dart';
import 'calendar_page.dart' show daysInMonthOf;
import 'calendar_providers.dart';
import '../../../core/router/app_router.dart' show timeStatsRouteObserver;
import 'widgets/async_error_retry.dart';
import 'widgets/ts_cat_sheet.dart';

/// 「时间账本」统计页（需求 V1.52 批4）。
/// 与高保真原型 `prototype/index.html` p-timeStats 一一对应：
/// 日/周/月/年四档 + Hero 汇总 + 时钟图(日) / 面积图+堆叠柱(周月) / 热力+按月堆叠(年)
/// + 环形总时长(含未记录灰弧) + 分类排行(环比)。
/// 聚合口径全部复用 block_ops 纯函数（计时中块按 durationMin(now) 实时计入）；
/// 图表全部 CustomPainter/BoxDecoration 自绘，不引入任何第三方依赖。
class TimeStatsPage extends ConsumerStatefulWidget {
  const TimeStatsPage({super.key});

  @override
  ConsumerState<TimeStatsPage> createState() => _TimeStatsPageState();
}

// ————————————————————— 期间模型 —————————————————————

/// 一档统计期间的全部派生值（含上期区间，环比用）。
class _TsPeriod {
  const _TsPeriod({
    required this.span,
    required this.from,
    required this.to,
    required this.prevFrom,
    required this.prevTo,
    required this.label,
    required this.spanDays,
  });

  final String span; // d/w/m/y
  final DateTime from, to, prevFrom, prevTo; // 均为当日 00:00
  final String label;
  final int spanDays;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 锚点日 → 期间。上期=同长度紧邻区间（原型 pf/pt 口径）。
_TsPeriod _periodFor(String span, DateTime anchor) {
  final a = DateTime(anchor.year, anchor.month, anchor.day);
  if (span == 'd') {
    final p = DateTime(a.year, a.month, a.day - 1);
    return _TsPeriod(
      span: 'd',
      from: a,
      to: a,
      prevFrom: p,
      prevTo: p,
      label: '${a.month}.${_two(a.day)}',
      spanDays: 1,
    );
  }
  if (span == 'w') {
    // C6（冻结）：周起点=周日，与时间页周视图**同源**读 week_align（不许两处各算一套）。
    final from = weekStartOf(a);
    final to = DateTime(from.year, from.month, from.day + 6);
    final pf = DateTime(from.year, from.month, from.day - 7);
    return _TsPeriod(
      span: 'w',
      from: from,
      to: to,
      prevFrom: pf,
      prevTo: DateTime(pf.year, pf.month, pf.day + 6),
      label: '${from.month}.${_two(from.day)}-${to.month}.${_two(to.day)}',
      spanDays: 7,
    );
  }
  if (span == 'm') {
    final dm = daysInMonthOf(a.year, a.month);
    final pm = DateTime(a.year, a.month - 1); // DateTime 自动回绕到上年 12 月
    final pdm = daysInMonthOf(pm.year, pm.month);
    return _TsPeriod(
      span: 'm',
      from: DateTime(a.year, a.month, 1),
      to: DateTime(a.year, a.month, dm),
      prevFrom: DateTime(pm.year, pm.month, 1),
      prevTo: DateTime(pm.year, pm.month, pdm),
      label: '${a.year}.${_two(a.month)}',
      spanDays: dm,
    );
  }
  final from = DateTime(a.year, 1, 1);
  return _TsPeriod(
    span: 'y',
    from: from,
    to: DateTime(a.year, 12, 31),
    prevFrom: DateTime(a.year - 1, 1, 1),
    prevTo: DateTime(a.year - 1, 12, 31),
    label: '${a.year}',
    // 闰年 366 天：用两个元旦差值取，避开手写天数表。
    spanDays: DateTime(a.year + 1, 1, 1).difference(from).inDays,
  );
}

// ————————————————————— 聚合模型 —————————————————————

class _Agg {
  _Agg({required this.byCat, required this.total});

  final Map<String, int> byCat;
  final int total;
  final Map<String, int> cnt = <String, int>{};

  /// 当日 00:00 → (分类 → 分钟)。TimeBlock.day 即归属日（effEnd 已封顶 1440，不跨天）。
  final Map<DateTime, Map<String, int>> byDay = <DateTime, Map<String, int>>{};

  int dayTotal(DateTime d) {
    final m = byDay[DateTime(d.year, d.month, d.day)];
    return m == null ? 0 : m.values.fold(0, (t, v) => t + v);
  }
}

_Agg _aggregate(List<TimeBlock> blocks, DateTime now) {
  // 分类合计/总计直接复用 block_ops 纯函数，避免页面重写口径。
  final a = _Agg(
    byCat: minutesByCat(blocks, now),
    total: totalMinutes(blocks, now),
  );
  for (final b in blocks) {
    final mins = b.durationMin(now);
    if (mins <= 0) continue;
    a.cnt[b.catName] = (a.cnt[b.catName] ?? 0) + 1;
    final key = DateTime(b.day.year, b.day.month, b.day.day);
    final m = a.byDay.putIfAbsent(key, () => <String, int>{});
    m[b.catName] = (m[b.catName] ?? 0) + mins;
  }
  return a;
}

List<DateTime> _daysBetween(DateTime from, DateTime to) {
  final out = <DateTime>[];
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    out.add(d);
  }
  return out;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 堆叠柱的一根桶（周/月=单日；年=单月），对应原型 tsBuckets。
class _Bucket {
  _Bucket({required this.label, required this.parts});

  final String label;
  final Map<String, int> parts;

  int get total => parts.values.fold(0, (t, v) => t + v);
}

// ————————————————————— 页面 —————————————————————

const Map<String, String> _kSpanName = {
  'd': '当日',
  'w': '本周',
  'm': '本月',
  'y': '全年',
};

/// 「未记录」弧段/兜底灰（与 blockColor 兜底同色，原型 #94A3B8）。
const Color _kOther = Color(0xFF94A3B8);

class _TimeStatsPageState extends ConsumerState<TimeStatsPage> with RouteAware {
  String _span = 'w';

  /// 锚点默认取时间页当前选中日（V1.52：账本从时间页进入，延续语境）。
  late DateTime _anchor;

  /// family key 依赖 DateTime 实例等值（DateTime 无值相等重载），
  /// 期间派生值缓存在 State，仅切档/翻页时重算，保证 blocksInRangeProvider 缓存命中。
  late _TsPeriod _p;

  /// 卡片折叠态（仅 State，不持久化，对齐原型 tsFold 会话内记忆）。
  final Map<String, bool> _fold = {};

  Timer? _timer;

  /// F6-3 测试探针：离屏停表断言用（勿在业务代码读）。
  @visibleForTesting
  Timer? get debugTicker => _timer;

  /// F6-3：30s 刷新表的启停统一入口——离屏（被新页盖住/ pop）即停表。
  void _startTicker() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicker() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void initState() {
    super.initState();
    final sel = ref.read(calSelectedProvider);
    _anchor = DateTime(sel.year, sel.month, sel.day);
    _recompute();
    // 计时中块耗时/时钟红线随墙上时钟推进：30s 刷一次，粒度够展示用（V1.52）。
    _startTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // F6-3：路由观察订阅（observer 单例挂 GoRouter.observers）——离屏停表。
    timeStatsRouteObserver.subscribe(
        this, ModalRoute.of(context) as ModalRoute<dynamic>);
  }

  @override
  void didPush() => _startTicker();

  @override
  void didPopNext() => _startTicker();

  @override
  void didPop() => _stopTicker();

  @override
  void didPushNext() => _stopTicker();

  @override
  void dispose() {
    timeStatsRouteObserver.unsubscribe(this);
    _stopTicker();
    super.dispose();
  }

  void _recompute() => _p = _periodFor(_span, _anchor);

  void _setSpan(String s) => setState(() {
        _span = s;
        _recompute();
      });

  void _shift(int dir) {
    setState(() {
      final a = _anchor;
      _anchor = switch (_span) {
        'd' => DateTime(a.year, a.month, a.day + dir),
        'w' => DateTime(a.year, a.month, a.day + 7 * dir),
        'm' => () {
            final t = DateTime(a.year, a.month + dir, 1);
            return DateTime(
                t.year, t.month, a.day.clamp(1, daysInMonthOf(t.year, t.month)));
          }(),
        _ => () {
            final y = a.year + dir;
            return DateTime(y, a.month,
                a.day.clamp(1, daysInMonthOf(y, a.month)));
          }(),
      };
      _recompute();
    });
  }

  bool _isFolded(String k) => _fold[k] == true;

  void _toggleFold(String k) => setState(() => _fold[k] = !_isFolded(k));

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final accent = tokens.accent;
    final catColors = ref.watch(catColorsByNameProvider);
    final p = _p;

    final curAsync = ref.watch(blocksInRangeProvider((p.from, p.to)));
    final prevAsync = ref.watch(blocksInRangeProvider((p.prevFrom, p.prevTo)));
    final timing = ref.watch(timingBlockProvider).valueOrNull;
    // F5-3：有计时中块时接秒级心跳，「已 X 分」前台每秒刷新（离屏/无计时自动停）。
    if (timing != null) {
      ref.watch(calendarTickerProvider);
    }
    // F4-3：账本页同样分「空」与「取数失败」两态——失败显错误卡＋重试。
    if (curAsync.hasError && curAsync.valueOrNull == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('时间账本')),
        body: SafeArea(
          child: AsyncErrorRetry(
              onRetry: () =>
                  ref.invalidate(blocksInRangeProvider((p.from, p.to)))),
        ),
      );
    }

    final now = DateTime.now();
    final blocks = curAsync.valueOrNull ?? const <TimeBlock>[];
    final agg = _aggregate(blocks, now);
    final prevAgg =
        _aggregate(prevAsync.valueOrNull ?? const <TimeBlock>[], now);
    final cap = p.spanDays * 1440;
    final un = math.max(0, cap - agg.total);
    // 首次异步加载未完成时不闪空态（valueOrNull 空数组 ≠ 真没数据）。
    final reallyEmpty = agg.total == 0 && !curAsync.isLoading;

    // 分类取色：与 blockColor 同规则（工作随主题 accent），但排行/堆叠按名字聚合。
    Color catColor(String name) =>
        name == '工作' ? accent : (catColors[name] ?? _kOther);

    return Scaffold(
      appBar: AppBar(title: const Text('时间账本')),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
          children: [
            _controlsRow(scheme),
            _heroCard(agg, timing, now, cap, un, blocks.length, tokens),
            // 图表区：空态统一一张提示卡（V1.52 规格 9），有数据才按档位出图。
            if (reallyEmpty)
              _emptyCard()
            else if (p.span == 'd')
              _foldCard('clock', '时钟图',
                  _clockChart(blocks, timing, now, catColors, accent, scheme)),
            if (!reallyEmpty && p.span != 'd')
              _foldCard('cmp', p.span == 'y' ? '单月时长对比' : '单日时长对比',
                  _areaChart(agg, p, accent, scheme)),
            if (!reallyEmpty && p.span == 'y')
              _foldCard('heat', '热力图', _heatChart(agg, p, accent, scheme)),
            if (!reallyEmpty && p.span != 'd')
              _foldCard(
                  'dist',
                  '时间分布',
                  _distChart(_buckets(agg, p), p, catColor, scheme)),
            _foldCard('donut', '总时长汇总',
                _donutChart(agg, un, cap, catColor, scheme)),
            _foldCard('rank', '分类时长汇总',
                _rankList(agg, prevAgg, blocks, catColor, scheme, tokens)),
          ],
        ),
      ),
    );
  }

  // ——————— 顶栏：四档分段 + 期间翻页 ———————

  Widget _controlsRow(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<String>(
              key: const ValueKey('ts-seg'),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
              segments: const [
                ButtonSegment(value: 'd', label: Text('日')),
                ButtonSegment(value: 'w', label: Text('周')),
                ButtonSegment(value: 'm', label: Text('月')),
                ButtonSegment(value: 'y', label: Text('年')),
              ],
              selected: {_span},
              onSelectionChanged: (s) => _setSpan(s.first),
            ),
          ),
          IconButton(
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left, size: 20)),
          SizedBox(
            width: 84,
            child: Text(
              _p.label,
              key: const ValueKey('ts-period'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface),
            ),
          ),
          IconButton(
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right, size: 20)),
        ],
      ),
    );
  }

  // ——————— Hero：渐变汇总卡 + 计时中/未记录 chips ———————

  Widget _heroCard(_Agg agg, TimeBlock? timing, DateTime now, int cap, int un,
      int segCount, ThemeTokens tokens) {
    final cov = cap > 0 ? (agg.total / cap * 100).round() : 0;
    Widget chip(String text, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: strong ? 0.24 : 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 10, color: Colors.white, height: 1.2)),
        );
    return Container(
      key: const ValueKey('ts-hero'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        gradient: tokens.gradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_kSpanName[_span]}已记录',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: .85))),
                    const SizedBox(height: 2),
                    Text(fmtDur(agg.total),
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1)),
                  ],
                ),
              ),
              Text(
                '日均 ${fmtDur((agg.total / _p.spanDays).round())}\n'
                '覆盖 $cov% · $segCount 段',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: .92),
                    height: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (timing != null)
                chip('● 计时中 · ${timing.catName} · '
                    '已 ${timing.durationMin(now)} 分',
                    strong: true)
              else
                chip('无计时中事件'),
              chip('未记录 ${fmtDur(un)}'),
            ],
          ),
        ],
      ),
    );
  }

  // ——————— 可折叠卡片骨架（原型 tsCard：点标题行切折叠，∧/∨ 指示） ———————

  Widget _foldCard(String key, String title, Widget body) {
    final scheme = Theme.of(context).colorScheme;
    final folded = _isFolded(key);
    return Container(
      key: ValueKey('ts-card-$key'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(button: true, label: '展开或折叠', child: InkWell(
            onTap: () => _toggleFold(key),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                  ),
                  Icon(
                      folded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 18,
                      color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          )),
          if (!folded) body,
        ],
      ),
    );
  }

  Widget _emptyCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      decoration: context.cardDecoration,
      child: Text(
        '该时段还没有时间块 · 去时间页记几段吧',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }

  // ——————— 日档：24 小时极坐标时钟图（原型 tsClock） ———————

  Widget _clockChart(List<TimeBlock> dayBlocks, TimeBlock? timing,
      DateTime now, Map<String, Color> catColors, Color accent,
      ColorScheme scheme) {
    final mine = dayBlocks
        .where((b) => _sameDay(b.day, _p.from) && b.startMin < 1440)
        .toList();
    // 红线只在「计时中块属于本日」时出现（日档 from==to）。
    final hand = timing != null && _sameDay(timing.day, _p.from);
    return Column(
      children: [
        SizedBox(
          width: 240,
          height: 240,
          child: CustomPaint(
            painter: _ClockPainter(
              blocks: mine,
              colorOf: (b) => blockColor(b, catColors, accent),
              nowMin: now.hour * 60 + now.minute,
              hand: hand,
              tickColor: scheme.onSurfaceVariant.withValues(alpha: .55),
              numColor: scheme.onSurface,
              discColor: scheme.onSurfaceVariant.withValues(alpha: .10),
              dotColor: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '24 小时盘面 · 扇区=时间块 · 红线=当前时刻'
          '${hand ? ' · 正在计时「${timing.catName}」' : ''}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ——————— 周/月/年：面积折线（原型 tsArea） ———————

  Widget _areaChart(_Agg agg, _TsPeriod p, Color accent, ColorScheme scheme) {
    final List<int> vals;
    final List<String> labels;
    if (p.span == 'y') {
      vals = List.generate(12, (i) => 0);
      agg.byDay.forEach((d, m) {
        vals[d.month - 1] +=
            m.values.fold(0, (t, v) => t + v); // 热力按月归桶
      });
      labels = [for (var i = 1; i <= 12; i++) '$i月'];
    } else {
      final days = _daysBetween(p.from, p.to);
      vals = [for (final d in days) agg.dayTotal(d)];
      labels = [for (final d in days) '${d.day}日'];
    }
    final mx = vals.isEmpty ? 1 : vals.reduce(math.max).clamp(1, 1 << 31);
    final n = labels.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 96,
          child: CustomPaint(
            painter: _AreaPainter(
                vals: vals, color: accent, gridColor: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _tiny(labels.first, scheme),
            _tiny(labels[n ~/ 2], scheme),
            _tiny(labels[n - 1], scheme),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          // 日尺度量级小直接「分」，周月年展示小时更可读（对齐原型 tsHM 口径）。
          '峰值 ${p.span == 'y' ? fmtDur(mx) : '$mx 分'}',
          style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _tiny(String s, ColorScheme scheme) =>
      Text(s, style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant));

  // ——————— 年档：整年日历格热力（原型 tsHeat；年档一次取全年，直接铺 53 周） ———————

  Widget _heatChart(_Agg agg, _TsPeriod p, Color accent, ColorScheme scheme) {
    final yearStart = DateTime(p.from.year, 1, 1);
    final lead = yearStart.weekday % 7; // 周日开头，与月历表头一致
    final ndays = p.spanDays;
    final weeks = (lead + ndays) / 7;
    final cells = weeks.ceil();
    var mx = 1;
    for (final d in agg.byDay.keys) {
      final v = agg.dayTotal(d);
      if (v > mx) mx = v;
    }
    Widget cell(int dayNo) {
      if (dayNo < 1 || dayNo > ndays) {
        return Container(
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.transparent));
      }
      final v = agg.dayTotal(DateTime(yearStart.year, 1, dayNo));
      final f = v / mx;
      return Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          // alpha 梯度：无记录=浅底，有记录按深浅 0.12~0.9（原型 tsHeat 同参）。
          color: v > 0
              ? accent.withValues(alpha: 0.12 + f * 0.78)
              : scheme.onSurfaceVariant.withValues(alpha: .08),
        ),
      );
    }

    // GitHub 式转置：7 行（周几）× N 列（周），整年一屏放得下。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        for (var r = 0; r < 7; r++)
          SizedBox(
            height: 11,
            child: Row(
              children: [
                for (var w = 0; w < cells; w++)
                  Expanded(child: cell(w * 7 + r - lead + 1)),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('少',
                style:
                    TextStyle(fontSize: 8.5, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 4),
            for (final a in const [0.12, 0.3, 0.5, 0.7, 0.9])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: accent.withValues(alpha: a),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Text('多',
                style:
                    TextStyle(fontSize: 8.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  // ——————— 时间分布：满高底轨堆叠柱（原型 tsStack） ———————

  List<_Bucket> _buckets(_Agg agg, _TsPeriod p) {
    if (p.span == 'y') {
      final months = [for (var i = 0; i < 12; i++) <String, int>{}];
      agg.byDay.forEach((d, m) {
        final t = months[d.month - 1];
        m.forEach((k, v) => t[k] = (t[k] ?? 0) + v);
      });
      // 稀疏标月号：每 3 个月一标，避免 12 根柱下标签打架。
      return [
        for (var i = 0; i < 12; i++)
          _Bucket(label: (i + 1) % 3 == 0 ? '${i + 1}月' : '', parts: months[i]),
      ];
    }
    final days = _daysBetween(p.from, p.to);
    final today = DateTime.now();
    return [
      for (final d in days)
        _Bucket(
          // 稀疏日号：今天标「今」，逢 5 或短区间标全，其余留空（原型同规则）。
          label: _sameDay(d, today)
              ? '今'
              : (d.day % 5 == 0 || days.length <= 10 ? '${d.day}' : ''),
          parts: agg.byDay[d] ?? const <String, int>{},
        ),
    ];
  }

  Widget _distChart(List<_Bucket> buckets, _TsPeriod p,
      Color Function(String) catColor, ColorScheme scheme) {
    final maxT = buckets.fold(1, (m, b) => math.max(m, b.total));
    // 轴下限：日尺度至少 24h（半天空隙也看得见柱），年尺度至少 600min（原型 cap 口径）。
    final axis = math.max(maxT, p.span == 'y' ? 600 : 240).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        SizedBox(
          height: 104,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in buckets)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: _StackBarPainter(
                            // 小段在下、大段在上（原型升序堆叠，顶部大色块更稳）。
                            segs: [
                              for (final e in (b.parts.entries.toList()
                                ..sort((x, y) => x.value.compareTo(y.value))))
                                (
                                  color: catColor(e.key),
                                  frac: e.value / axis
                                )
                            ],
                            track: scheme.onSurfaceVariant
                                .withValues(alpha: .10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 11,
                        child: Text(b.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 8,
                                color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _tiny('0', scheme),
            _tiny('柱高=满格 ${fmtDur(axis.round())}（含未记录）', scheme),
          ],
        ),
      ],
    );
  }

  // ——————— 总时长环形：分类弧 + 未记录灰弧，中心总时长（原型 tsDonut） ———————

  Widget _donutChart(_Agg agg, int un, int cap,
      Color Function(String) catColor, ColorScheme scheme) {
    final entries = agg.byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dn = [
      for (final e in entries)
        (name: e.key, color: catColor(e.key), frac: e.value / cap),
      if (un > 0) (name: '未记录', color: _kOther, frac: un / cap),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 104,
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(104, 104),
                  painter: _DonutPainter(
                    segs: [
                      for (final e in dn) (color: e.color, frac: e.frac),
                    ],
                    trackColor:
                        scheme.onSurfaceVariant.withValues(alpha: .12),
                  ),
                ),
                // 中心总时长：年档可达四位数小时，字号收敛防溢出。
                Text(
                  fmtDur(agg.total),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: agg.total >= 10000 ? 9 : 10.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in dn.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: e.color),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, color: scheme.onSurface)),
                        ),
                        Text('${(e.frac * 100).round()}%',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
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

  // ——————— 分类排行：进度条归一 + 环比 deltaPct（原型 rank 卡） ———————

  Widget _rankList(_Agg agg, _Agg prevAgg, List<TimeBlock> blocks,
      Color Function(String) catColor, ColorScheme scheme, ThemeTokens tokens) {
    final entries = agg.byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '该时段还没有时间块 · 去时间页记几段吧',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    final maxM = entries.first.value;
    Widget row(int i, MapEntry<String, int> e) {
      final name = e.key;
      final m = e.value;
      final pm = prevAgg.byCat[name] ?? 0;
      // 环比=与上一同期区间比；上期为 0 无可比（deltaPct 返回 null，不显示）。
      final delta = deltaPct(m, pm);
      final color = catColor(name);
      return Semantics(button: true, label: '查看分类明细', child: InkWell(
        // V1.57 C 批：明细下钻半屏（原型 tsOpenCat；谓词与本页汇总同源）。
        onTap: () => showTsCatSheet(
          context,
          blocks: blocks,
          cat: name,
          from: _p.from,
          to: _p.to,
          spanDays: _p.spanDays,
          periodText: '${{'d': '当日', 'w': '本周', 'm': '本月', 'y': '全年'}[_p.span] ?? _p.span} · ${_p.label}',
          color: catColor(name),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: color),
                child: Center(
                  child: Text(name.isEmpty ? '?' : name.substring(0, 1),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface)),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '(${agg.cnt[name] ?? 0} 次) '
                          '${(m / math.max(1, agg.total) * 100).round()}%',
                          style: TextStyle(
                              fontSize: 9, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 按最大值归一的进度条（原型 width=m/max*100%）。
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: scheme.onSurfaceVariant.withValues(alpha: .10),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: (m / maxM).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: color),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmtDur(m),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface)),
                  if (delta != null)
                    Text(
                      '${delta >= 0 ? '+' : ''}${delta.round()}% · 上期 ${fmtDur(pm)}',
                      style: TextStyle(
                          // 花得更多标红、更省标绿（原型配色逻辑）。
                          fontSize: 9,
                          color: delta >= 0
                              ? const Color(0xFFF43F5E)
                              : const Color(0xFF10B981)),
                    ),
                ],
              ),
              Icon(Icons.chevron_right,
                  size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ));
    }

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: .6, color: tokens.cardBorder),
          row(i, entries[i]),
        ],
      ],
    );
  }
}

// ————————————————————— CustomPainters —————————————————————

/// 24 小时极坐标盘面：分钟 m → 角度 m/1440*2π，0 点朝上、顺时针（原型 pol/sector）。
class _ClockPainter extends CustomPainter {
  _ClockPainter({
    required this.blocks,
    required this.colorOf,
    required this.nowMin,
    required this.hand,
    required this.tickColor,
    required this.numColor,
    required this.discColor,
    required this.dotColor,
  });

  final List<TimeBlock> blocks;
  final Color Function(TimeBlock) colorOf;
  final int nowMin;
  final bool hand;
  final Color tickColor, numColor, discColor, dotColor;

  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final R = math.min(size.width, size.height) / 2;
    final rOut = R * 0.92;
    final rIn = R * 0.32;
    double ang(int m) => m / 1440 * _tau - math.pi / 2;
    Offset pol(double r, double a) =>
        Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));

    // 24 刻度：每 6 小时加粗。
    for (var h = 0; h < 24; h++) {
      final bold = h % 6 == 0;
      final a = ang(h * 60);
      canvas.drawLine(pol(R * 0.94, a), pol(bold ? R : R * 0.97, a),
          Paint()
            ..color = tickColor
            ..strokeWidth = bold ? 2 : 0.8
            ..strokeCap = StrokeCap.round);
    }

    // 内盘浅底（原型 r0-6 灰圆）。
    canvas.drawCircle(c, rIn - 6, Paint()..color = discColor);

    // 扇区 = 时间块；<6 分钟的块给最小可视角 1.2°（原型 Math.max(a0+1.2,a1)）。
    final minSweep = 1.2 * math.pi / 180;
    // F6-2：paint 一帧取时一次下传，循环内不再逐次 effEnd()。
    final frameNow = DateTime.now();
    for (final b in blocks) {
      final end = math.min(b.effEnd(frameNow), 1440);
      if (end <= b.startMin) continue;
      final a0 = ang(b.startMin);
      final a1 = a0 +
          math.min(math.max(ang(end) - a0, minSweep), _tau - 0.01);
      final path = Path()
        ..moveTo(pol(rOut, a0).dx, pol(rOut, a0).dy)
        ..arcTo(Rect.fromCircle(center: c, radius: rOut), a0, a1 - a0, false)
        ..lineTo(pol(rIn, a1).dx, pol(rIn, a1).dy)
        ..arcTo(Rect.fromCircle(center: c, radius: rIn), a1, -(a1 - a0), false)
        ..close();
      canvas.drawPath(
          path,
          Paint()
            ..color = colorOf(b).withValues(alpha: .85)
            ..style = PaintingStyle.fill);
    }

    // 数字 0/6/12/18：压环中央，扇区之上（原型数字在下、扇区半透可叠读）。
    for (final h in const [0, 6, 12, 18]) {
      final tp = TextPainter(
        text: TextSpan(
            text: '$h',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: numColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = pol((rIn + rOut) / 2, ang(h * 60));
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    }

    // 计时中：圆心 → 当前时刻红色细线 + 中心点。
    if (hand) {
      final a = ang(nowMin);
      canvas.drawLine(c, pol(rOut * 0.9, a),
          Paint()
            ..color = const Color(0xFFF43F5E)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
    }
    canvas.drawCircle(c, 5, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) =>
      old.nowMin != nowMin ||
      old.hand != hand ||
      old.blocks.length != blocks.length ||
      old.tickColor != tickColor;
}

/// 面积折线：vals → 等距横轴，纵向按峰值归一（原型 tsArea）。
class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.vals,
    required this.color,
    required this.gridColor,
  });

  final List<int> vals;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 25% 分格线（原型 0/.25/.5/.75/1）。
    for (final f in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final y = h - h * f;
      canvas.drawLine(Offset(0, y), Offset(w, y),
          Paint()
            ..color = gridColor.withValues(alpha: .18)
            ..strokeWidth = .6);
    }
    final mx = math.max(1, vals.fold(0, (m, v) => v > m ? v : m)).toDouble();
    final n = vals.length;
    final pts = [
      for (var i = 0; i < n; i++)
        Offset(i / math.max(1, n - 1) * w, h - 2 - vals[i] / mx * (h - 10)),
    ];
    if (pts.isEmpty) return;
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      line.lineTo(pts[i].dx, pts[i].dy);
    }
    // 折线回落底边闭合成半透明面积（原型 path M0 H L… L W H Z）。
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, h)
      ..lineTo(pts.first.dx, h)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..color = color.withValues(alpha: .16)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) =>
      old.vals != vals || old.color != color;
}

/// 单根满高底轨柱：底轨=24h(或轴上限)，内部按分类自下而上堆叠（原型 tsBarCol）。
class _StackBarPainter extends CustomPainter {
  _StackBarPainter({required this.segs, required this.track});

  /// 自下而上的 (颜色, 占轴高度比例)。
  final List<({Color color, double frac})> segs;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(3));
    canvas.drawRRect(rr, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(rr);
    var acc = 0.0;
    for (final s in segs) {
      final fh = s.frac.clamp(0.0, 1.0) * size.height;
      if (fh <= 0) continue;
      canvas.drawRect(
          Rect.fromLTWH(0, size.height - acc - fh, size.width, fh + 0.4),
          Paint()..color = s.color);
      acc += fh;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StackBarPainter old) =>
      old.segs != segs || old.track != track;
}

/// 环形图：灰底轨 + 各分类弧段（含「未记录」），12 点起顺时针（原型 tsDonutSvg）。
class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segs, required this.trackColor});

  final List<({Color color, double frac})> segs;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = size.width * 0.15;
    final c = Offset(size.width / 2, size.height / 2);
    final r = (math.min(size.width, size.height) - sw) / 2 - 1;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.butt;
    paint.color = trackColor;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    var a0 = -math.pi / 2;
    for (final s in segs) {
      if (s.frac <= 0) continue;
      final sweep = math.min(s.frac, 1.0) * math.pi * 2;
      paint.color = s.color;
      canvas.drawArc(rect, a0, sweep, false, paint);
      a0 += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.segs != segs || old.trackColor != trackColor;
}
