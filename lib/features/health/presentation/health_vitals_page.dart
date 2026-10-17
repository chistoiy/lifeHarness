import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_calc.dart';
import '../domain/health_models.dart';
import '../domain/health_vital.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 体征记录（原型 `p-vitals` · 路由 `/health/vitals` · 批2.5）。
///
/// 四条口径写在最近处：
/// · **周/月/季只是窗口**（7/30/90 天），一次取数喂瓦片/曲线/异常/流水四处，两处读数不许错位；
/// · **参考区间只吃 `health_calc.vitalRef`**（§11.3.1），屏上不出现第二份区间数字；血氧上限是「无上限」
///   哨兵，文案走 `refLabel` 的「参考 ≥95」；
/// · 无记录＝「未记录／暂无记录」＋空柱，**不拿 0 当读数**（与批2 工作台同口径）；
/// · 异常只作提示不作诊断（§11.3.1）——色标与「偏低/偏高」到此为止。
class HealthVitalsPage extends ConsumerStatefulWidget {
  const HealthVitalsPage({super.key, this.initialKind});

  /// `?kind=` 预选指标（工作台体征条点哪枚进来就选哪枚）；非法值按 `bp` 走。
  final String? initialKind;

  static const Key kTiles = ValueKey('hvt-tiles');
  static const Key kCurve = ValueKey('hvt-curve');
  static const Key kAbn = ValueKey('hvt-abn');
  static const Key kList = ValueKey('hvt-list');

  @override
  ConsumerState<HealthVitalsPage> createState() => _HealthVitalsPageState();
}

class _HealthVitalsPageState extends ConsumerState<HealthVitalsPage> {
  late String _kind = vitalSpecs.containsKey(widget.initialKind) ? widget.initialKind! : 'bp';
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    ref.watch(healthTickProvider);
    final pid = ref.watch(activeHealthProfileProvider);
    final profiles = (ref.watch(healthProfilesProvider).valueOrNull ?? const <HealthProfile>[])
        .where((p) => !p.archived)
        .toList();
    final profile = profiles.where((p) => p.id == pid).firstOrNull;
    final now = ref.watch(healthClockProvider)();
    final from = dayKey(now.subtract(Duration(days: _days - 1)));
    final to = dayKey(now);
    final all = ref.watch(_vitalsRangeProvider((pid, from, to))).valueOrNull ?? const <HealthVital>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('体征记录'),
        actions: [
          IconButton(
            key: const ValueKey('hvt-add'),
            tooltip: '记一次',
            icon: const Icon(Icons.add),
            onPressed: () => showHealthVitalSheet(context, kind: _kind),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _profileBar(profiles),
          const SizedBox(height: 8),
          SegRow<int>(
            key: const ValueKey('hvt-seg'),
            keyPrefix: 'hvt-seg',
            value: _days,
            items: const [(id: 7, label: '周'), (id: 30, label: '月'), (id: 90, label: '季')],
            onChanged: (v) => setState(() => _days = v),
          ),
          const SizedBox(height: 12),
          _tiles(context, all, profile),
          const SizedBox(height: 12),
          _curveCard(context, all),
          const SizedBox(height: 12),
          _abnormalCard(context, all, from, to),
          const SizedBox(height: 12),
          _streamCard(context, all),
        ],
      ),
    );
  }

  // ==================== 档案 chips（切换即整模块重取） ====================

  Widget _profileBar(List<HealthProfile> profiles) {
    final cur = ref.read(activeHealthProfileProvider);
    // 「管理 ›」那枚随档案屏落地（工单 §2），本批只给切换。
    return SizedBox(
      height: 30,
      child: ListView(
        key: const ValueKey('hvt-bar'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in profiles)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                key: ValueKey('hvt-profile-${p.id}'),
                label: '${p.name} ${p.rel}',
                selected: p.id == cur,
                onTap: () {
                  ref.read(activeHealthProfileProvider.notifier).state = p.id;
                  healthTouch(ref);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 五枚指标瓦片（两列，五枚＝两行＋末行补空位） ====================

  Widget _tiles(BuildContext context, List<HealthVital> all, HealthProfile? profile) {
    final rows = <Widget>[
      for (var i = 0; i < vitalOrder.length; i += 2)
        // 五枚同构（同一套行结构），自然等高；这里不能用 `CrossAxisAlignment.stretch`——
        // Row 在 ListView 里高度不受限，stretch 会把 h=Infinity 压给子项（performLayout 直接炸）。
        Row(
          children: [
            for (final k in vitalOrder.sublist(i, i + 2 > vitalOrder.length ? vitalOrder.length : i + 2))
              Expanded(child: _tile(context, all, profile, k)),
            // 第五枚落单：右侧留空位，别让最后一枚拉满整行（原型 grid-cols-2）。
            if (vitalOrder.length - i < 2) const Expanded(child: SizedBox()),
          ],
        ),
    ];
    return Column(
      key: HealthVitalsPage.kTiles,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          rows[i],
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, List<HealthVital> all, HealthProfile? profile, String kind) {
    final scheme = Theme.of(context).colorScheme;
    final spec = vitalSpecs[kind]!;
    final vs = all.where((v) => v.kind == kind).toList();
    final recent = vs.length <= 8 ? vs : vs.sublist(vs.length - 8);
    final last = recent.isEmpty ? null : recent.last;
    // 角标「N 异常」按原型在**最近 8 条**里数（`vtRender` 的 vs 已 slice(-8)），
    // 不是整窗口全量——否则一个记了几十条血压的档案，瓦片角标会报出与迷你柱不成比例的数。
    final ab = vitalAbnormalCount(recent);
    return InkWell(
      key: ValueKey('hvt-tile-$kind'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _kind = kind),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _kind == kind ? context.tokens.accent : scheme.outlineVariant.withValues(alpha: .6)),
        ),
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(spec.name, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
                if (recent.isEmpty)
                  Text('未记录', key: ValueKey('hvt-tile-state-$kind'),
                      style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant))
                else
                  Text(ab > 0 ? '$ab 异常' : '正常',
                      key: ValueKey('hvt-tile-state-$kind'),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: ab > 0 ? scheme.error : scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(last?.valueText ?? '—',
                    key: ValueKey('hvt-tile-value-$kind'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1.5),
                  child: Text(spec.unit, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(last == null ? '暂无记录' : last.deltaText(profile),
                key: ValueKey('hvt-tile-delta-$kind'),
                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            SizedBox(
              height: 24,
              child: recent.isEmpty
                  ? Text('—', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant))
                  : Row(
                      key: ValueKey('hvt-tile-bars-$kind'),
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final v in recent)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: .8),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: v.flag == null || v.flag == 'normal'
                                      ? context.tokens.accent.withValues(alpha: .55)
                                      : scheme.error,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                ),
                                child: SizedBox(height: 24 * v.barFrac()),
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

  // ==================== 当前指标曲线 ====================

  Widget _curveCard(BuildContext context, List<HealthVital> all) {
    final scheme = Theme.of(context).colorScheme;
    final spec = vitalSpecs[_kind]!;
    final vs = all.where((v) => v.kind == _kind).toList();
    final vals = vs.map((v) => v.primary).whereType<double>().toList();
    final ref = spec.ref;
    final insufficient = vals.length < 2;
    final mean = vitalMean(vs, spec.decimals);
    // 轴端＝实算上下界（原型 `min(vals, ref)−1 / max(vals, ref)+1`），标签与画笔吃同一对数（一处口径）。
    final lo = insufficient ? null : _axisLo(vals, ref?.$1);
    final hi = insufficient ? null : _axisHi(vals, spec.barBase);
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('当前指标曲线', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(insufficient ? '${spec.name} · 数据不足' : '${spec.name} · ${spec.unit} · 近 $_days 天',
                  key: const ValueKey('hvt-cur-tx'),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            key: HealthVitalsPage.kCurve,
            height: 96,
            width: double.infinity,
            child: insufficient
                ? Center(
                    child: Text('该指标记录不足 2 条 · 暂无曲线',
                        key: const ValueKey('hvt-curve-empty'),
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  )
                : CustomPaint(
                    painter: _CurvePainter(
                      vals: vals,
                      flags: vs.map((v) => v.flag).toList(),
                      ref: ref,
                      lo: lo!,
                      hi: hi!,
                      accent: context.tokens.accent,
                      bad: scheme.error,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(lo == null ? '—' : VitalSpec.trimNum(lo),
                  key: const ValueKey('hvt-axis-lo'),
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
              Text(spec.refLabel,
                  key: const ValueKey('hvt-ref-tx'),
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
              Text(hi == null ? '—' : VitalSpec.trimNum(hi),
                  key: const ValueKey('hvt-axis-hi'),
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          if (!insufficient)
            Row(
              children: [
                _stat('均值', '${spec.fmt(mean)}${spec.unit}'),
                _stat('异常', '${vitalAbnormalCount(vs)} 次'),
                _stat('记录', '${vs.length} 条'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        key: ValueKey('hvt-stat-$label'),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ==================== 异常汇总 ====================

  Widget _abnormalCard(BuildContext context, List<HealthVital> all, String from, String to) {
    final scheme = Theme.of(context).colorScheme;
    final ab = all.where((v) => v.flag != null && v.flag != 'normal').toList();
    // 原型 `vtAbn` 取的是升序前 8（＝最旧的八条）；待关注的列表按**最近优先**才有意义，
    // 这一处偏离原型写在工单 §3 落地记录里，等产品定夺。
    final recent = ab.length <= 8 ? ab.reversed.toList() : ab.reversed.take(8).toList();
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('异常记录汇总', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(recent.isEmpty ? '近 $_days 天无异常' : '${ab.length} 条待关注',
                  key: const ValueKey('hvt-abn-n'),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            Text('全部落在参考范围内',
                key: const ValueKey('hvt-abn-none'),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
          else
            Column(
              key: HealthVitalsPage.kAbn,
              children: [
                for (final v in recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      key: ValueKey('hvt-abn-row-${v.id}'),
                      children: [
                        _flag(v.flag!, long: true),
                        Expanded(
                          child: Text('${v.spec.name} ${v.valueText} ${v.spec.unit} · ${v.date} ${v.time}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                        ),
                        TextButton(
                          key: ValueKey('hvt-abn-add-${v.kind}'),
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact),
                          onPressed: () => setState(() => _kind = v.kind),
                          child: const Text('补记录 ›', style: TextStyle(fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ==================== 记录流水 ====================

  Widget _streamCard(BuildContext context, List<HealthVital> all) {
    final scheme = Theme.of(context).colorScheme;
    final desc = all.reversed.take(20).toList();
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('记录流水', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                key: const ValueKey('hvt-add-inline'),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact),
                onPressed: () => showHealthVitalSheet(context, kind: _kind),
                child: const Text('＋ 记录', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (desc.isEmpty)
            const EmptyDashRow(text: '该档案暂无体征记录')
          else
            Column(
              key: HealthVitalsPage.kList,
              children: [
                for (final v in desc)
                  InkWell(
                    key: ValueKey('hvt-row-${v.id}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showHealthVitalSheet(context, editing: v),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          _flag(v.flag ?? 'normal'),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${v.spec.name} ${v.valueText} ${v.spec.unit}',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                                Text([
                                  '${v.date} ${dayWd(v.date)}',
                                  '${v.time}${v.slot == null ? '' : ' · ${v.slot}'}',
                                  if ((v.note ?? '').trim().isNotEmpty) v.note!.trim(),
                                ].join(' · '),
                                    style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          TextButton(
                            key: ValueKey('hvt-del-${v.id}'),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact),
                            onPressed: () => _delete(v),
                            child: Text('删除',
                                style: TextStyle(fontSize: 10, color: scheme.error, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _delete(HealthVital v) async {
    final ok = await lhConfirm(context, '删除这条${v.spec.name}记录？曲线与统计会同步重算。');
    if (!ok || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthRepositoryProvider).deleteVital(v.id!);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return; // 确认＋删库两段 await 之后才用 context 提示条
    AppToast.show(context, '已删除 · 统计重算');
  }

  Widget _flag(String flag, {bool long = false}) {
    final scheme = Theme.of(context).colorScheme;
    // 流水行＝单字（原型 `mflag`「正常/低/高」），异常汇总＝两字（「偏低/偏高」）——同形不同处，别混用。
    final label = switch (flag) {
      'low' => long ? '偏低' : '低',
      'high' => long ? '偏高' : '高',
      _ => '正常',
    };
    final color = switch (flag) {
      'low' || 'high' => scheme.error,
      _ => context.tokens.accent,
    };
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// 曲线绘制：参考带＋折线＋异常点变红（原型 `vtCurve` 的 SVG 等价形）。
/// 上下界由调用侧算好传入（与轴端标签同一对数），画笔内部不再复算一遍。
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.vals,
    required this.flags,
    required this.ref,
    required this.lo,
    required this.hi,
    required this.accent,
    required this.bad,
  });

  final List<double> vals;
  final List<String?> flags;
  final (double, double)? ref;
  final double lo;
  final double hi;
  final Color accent;
  final Color bad;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int i) => 8 + i * ((size.width - 16) / (vals.length - 1).clamp(1, 9999));
    double y(double v) => (size.height - 12) - ((v - lo) / math.max(0.0001, hi - lo)) * (size.height - 28);
    if (ref != null) {
      // 参考带上沿夹在刻度内：血氧的参考上限是 999 哨兵，带子不能画出画布。
      final top = math.min(ref!.$2, hi);
      canvas.drawRect(
        Rect.fromLTRB(4, y(top), size.width - 4, y(ref!.$1)),
        Paint()..color = accent.withValues(alpha: .10),
      );
    }
    final path = Path();
    for (var i = 0; i < vals.length; i++) {
      final p = Offset(x(i), y(vals[i]));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    final dot = Paint();
    for (var i = 0; i < vals.length; i++) {
      dot.color = flags[i] == 'normal' ? accent : bad;
      canvas.drawCircle(Offset(x(i), y(vals[i])), 2, dot);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.vals != vals || old.lo != lo || old.hi != hi || old.accent != accent;
}

/// 轴端下界＝min(实值下界, 参考下界)−1（原型 `vtCurve` 同式；无参考区间就只按实值）。
double _axisLo(List<double> vals, double? refLo) =>
    math.min(vals.reduce((a, b) => a < b ? a : b), refLo ?? double.infinity) - 1;

/// 轴端上界＝max(实值上界, 展示上限)+1。展示上限取 `spec.barBase` 而不是 `vitalRef` 的上限——
/// 血氧的参考上限是「无上限」哨兵 999，直接拿来定刻度会把曲线压成一条贴底直线。
double _axisHi(List<double> vals, double barBase) =>
    math.max(vals.reduce((a, b) => a > b ? a : b), barBase) + 1;

/// 一段窗口的全部体征读数（按档案隔离；瓦片/曲线/异常/流水共用同一份，免两处错位）。
final _vitalsRangeProvider = FutureProvider.family<List<HealthVital>, (int, String, String)>((ref, a) async {
  ref.watch(healthTickProvider);
  return ref.watch(healthRepositoryProvider).vitals(a.$1, a.$2, a.$3);
});
