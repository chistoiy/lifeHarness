import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/care_repository.dart';
import '../domain/care_models.dart';
import '../domain/growth_calc.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// p-growth 生长曲线全屏（原型 C8）：w/h/head × P/SD/Z 三模、WHO 参考带、
/// 自身测量描点、跨带预警与测量历史 + sheetBabyMeasure。
class GrowthPage extends ConsumerStatefulWidget {
  const GrowthPage({super.key});

  @override
  ConsumerState<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends ConsumerState<GrowthPage> {
  GMetric _metric = GMetric.w;
  int _mode = 0; // 0=P 1=SD 2=Z

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(careDataProvider);
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('生长曲线'),
            Text('WHO 百分位 · P3/P50/P97',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final baby = d.currentBaby;
          if (baby == null) {
            return const Center(
                child: Text('先建立宝宝档案',
                    style: TextStyle(fontSize: 11, color: Colors.grey)));
          }
          final isF = baby.sex == '女';
          final pts = growthSeries(
              m: _metric, birth: baby.birth, measures: d.measures);
          final warn =
              growthCrossWarn(isFemale: isF, m: _metric, birth: baby.birth, measures: d.measures);
          final (medText, colText) = pts.isEmpty
              ? ('尚无实测 · 保存测量后自动描点', '')
              : _readout(isF, pts);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SegBar(
                      labels: [for (final m in GMetric.values) m.name],
                      keys: [for (final m in GMetric.values) 'gk-${m.name}'],
                      selected: GMetric.values.indexOf(_metric),
                      onPick: (i) => setState(() => _metric = GMetric.values[i]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 132,
                    child: _SegBar(
                      labels: const ['P', 'SD', 'Z'],
                      keys: const ['gm-0', 'gm-1', 'gm-2'],
                      selected: _mode,
                      onPick: (i) => setState(() => _mode = i),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 340 / 220,
                      child: CustomPaint(
                        painter: _GrowthPainter(
                          metric: _metric,
                          isFemale: isF,
                          points: pts,
                          mode: _mode,
                          babyName: baby.name,
                          accent: careHex('#4f46e5'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('横轴 0-18 月龄 · 色带 WHO P3~P97 · 白线 P50 · 圆点为自身测量值',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: context.cardDecoration,
                child: Text.rich(
                  TextSpan(style: const TextStyle(fontSize: 11), children: [
                    const TextSpan(text: '最新：', style: TextStyle(color: Colors.grey)),
                    TextSpan(
                        text: medText,
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: tokens.accent)),
                    if (colText.isNotEmpty) TextSpan(text: ' · $colText'),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('跨带预警',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      warn ??
                          '当前曲线平滑跟随自身百分位通道，未触发预警。'
                              '规则：30 天内跨 2 条主百分位带（升或降）→ 温柔提醒并给出儿保就诊参考'
                              '（不构成医疗建议）。',
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          color: warn != null
                              ? const Color(0xFFDC2626)
                              : Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _measureHist(context, ref, d, isF, baby.birth),
            ],
          );
        },
      ),
    );
  }

  /// 读数：最新值@月龄 + 三模文案（近3次增速简述）。
  (String, String) _readout(bool isF, List<(double, double)> pts) {
    final (m0, v0) = pts.last;
    final stat = growthStatText(isF, _metric, m0, v0, _mode);
    final val = v0.toStringAsFixed(1);
    var trend = '';
    if (pts.length >= 2) {
      final last3 = pts.length >= 4 ? pts.sublist(pts.length - 4) : pts;
      var allUp = true;
      for (var i = 1; i < last3.length; i++) {
        if (last3[i].$2 <= last3[i - 1].$2) allUp = false;
      }
      trend = allUp ? '近 ${last3.length - 1} 次增速正常' : '增速有回落 · 建议关注趋势';
    }
    return ('$val${_metric.unit} @ ${m0.toStringAsFixed(1)} 月龄 · $stat', trend);
  }

  Widget _measureHist(BuildContext context, WidgetRef ref, CareData d,
      bool isF, DateTime birth) {
    final tokens = context.tokens;
    final ms = [...d.measures]..sort((a, b) => b.day.compareTo(a.day));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('测量历史',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              GestureDetector(
                key: const ValueKey('g-measure-add'),
                onTap: () => showBabyMeasureSheet(context),
                child: Text('+ 记测量',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: tokens.accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _HistGrid(ms: ms, isF: isF, birth: birth),
        ],
      ),
    );
  }
}

/// 六列网格（原型 grid-cols-6 表）。
class _HistGrid extends StatelessWidget {
  const _HistGrid({required this.ms, required this.isF, required this.birth});
  final List<CareMeasure> ms;
  final bool isF;
  final DateTime birth;

  @override
  Widget build(BuildContext context) {
    const heads = ['日期', '体重', '身高', '头围', '百分位', '记录人'];
    final accent = careHex('#6366f1');
    return Column(
      children: [
        Row(
          children: [
            for (final h in heads)
              Expanded(
                  child: Text(h,
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey))),
          ],
        ),
        Container(height: 1, color: context.tokens.cardBorder),
        for (final m in ms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                    child: Text(m.day.substring(5),
                        style: const TextStyle(fontSize: 10, color: Colors.grey))),
                Expanded(
                    child: Text('${m.w}kg',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
                Expanded(child: Text('${m.h}cm', style: const TextStyle(fontSize: 10))),
                Expanded(child: Text('${m.head}cm', style: const TextStyle(fontSize: 10))),
                Expanded(
                    child: Text(
                        growthPctTag(isF, GMetric.w,
                            careAgeMonths(birth, DateTime.parse(m.day)), m.w),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent))),
                Expanded(
                    child: Text(m.rec ?? '—',
                        style: const TextStyle(fontSize: 10, color: Colors.grey))),
              ],
            ),
          ),
        if (ms.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('尚无实测 · 保存测量后自动描点',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ),
      ],
    );
  }
}

/// 品牌分段钮（原型 .seg 圆角槽）。
class _SegBar extends StatelessWidget {
  const _SegBar({required this.labels, required this.selected, required this.onPick,
      required this.keys});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onPick;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.cardBorder.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey(keys[i]),
                onTap: () => onPick(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? tokens.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == selected
                        ? [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 4)]
                        : null,
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: i == selected ? tokens.accent : Colors.grey)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// sheetBabyMeasure 记测量（三数值 + 记录人 chips + 预警说明）。
Future<void> showBabyMeasureSheet(BuildContext context) {
  return showCareSheet<void>(context, builder: (bc) => const _MeasureSheet());
}

class _MeasureSheet extends ConsumerStatefulWidget {
  const _MeasureSheet();

  @override
  ConsumerState<_MeasureSheet> createState() => _MeasureSheetState();
}

class _MeasureSheetState extends ConsumerState<_MeasureSheet> {
  final _w = TextEditingController();
  final _h = TextEditingController();
  final _c = TextEditingController();
  String _rec = '';
  bool _prefilled = false;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    if (!_prefilled) {
      _prefilled = true;
      final last = d.measures.isNotEmpty
          ? ([...d.measures]..sort((a, b) => b.day.compareTo(a.day))).first
          : null;
      _w.text = last == null ? '' : '${last.w}';
      _h.text = last == null ? '' : '${last.h}';
      _c.text = last == null ? '' : '${last.head}';
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('宝宝测量记录',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            children: [
              _num(context, _w, '体重 kg', 'bm-w'),
              const SizedBox(width: 8),
              _num(context, _h, '身高 cm', 'bm-h'),
              const SizedBox(width: 8),
              _num(context, _c, '头围 cm', 'bm-c'),
            ],
          ),
          const CLabel('记录人', top: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in d.carers)
                CChip(
                  key: ValueKey('bm-rec-${c.name}'),
                  label: c.name,
                  dense: true,
                  selected: (_rec.isEmpty ? d.curCarer : _rec) == c.name,
                  onTap: () => setState(() => _rec = c.name),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('保存后自动描点生长曲线并计算偏离预警（跨越 2 条百分位带时提醒）',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 14),
          GestureDetector(
            key: const ValueKey('bm-save'),
            onTap: () async {
              final w = double.tryParse(_w.text.trim());
              final h = double.tryParse(_h.text.trim());
              final c = double.tryParse(_c.text.trim());
              final baby = d.currentBaby;
              if (baby == null) return;
              final messenger = ScaffoldMessenger.of(context);
              if (w == null || h == null || c == null || w <= 0 || h <= 0 || c <= 0) {
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                      content: Text('请填写三项测量值'),
                      duration: Duration(milliseconds: 1500)));
                return;
              }
              await ref.read(careRepositoryProvider).addMeasure(CareMeasure(
                  babyId: baby.id,
                  day: careDayKey(DateTime.now()),
                  w: w,
                  h: h,
                  head: c,
                  rec: _rec.isEmpty ? d.curCarer : _rec));
              careTouch(ref);
              if (context.mounted) Navigator.pop(context);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                    content: Text('✔ 已描点生长曲线 · 下次体检提醒已更新（测量量可二次修改）'),
                    duration: Duration(milliseconds: 1800)));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: careGrad(const ['#6366f1', '#8b5cf6', '#c084fc'],
                    begin: const Alignment(-1, 0), end: const Alignment(1, 0)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('保存测量',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _num(BuildContext context, TextEditingController ctl, String label, String key) {
    final tokens = context.tokens;
    return Expanded(
      child: Column(
        children: [
          TextField(
            key: ValueKey(key),
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              hintText: label.split(' ').first,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: tokens.cardBorder)),
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }
}

/// 主图 CustomPaint（原型 renderGrowthFull 同构：色带/P50 虚线/描点/轴注）。
class _GrowthPainter extends CustomPainter {
  const _GrowthPainter({
    required this.metric,
    required this.isFemale,
    required this.points,
    required this.mode,
    required this.babyName,
    required this.accent,
  });

  final GMetric metric;
  final bool isFemale;
  final List<(double, double)> points;
  final int mode;
  final String babyName;
  final Color accent;

  static const double _xs = 34, _xe = 330, _yb = 178, _hgt = 150, _nm = 18;

  @override
  void paint(Canvas canvas, Size size) {
    // 统一按 340×220 逻辑坐标系等比缩放。
    canvas.scale(size.width / 340, size.height / 220);

    final bd = gBands(isFemale);
    final med = [for (var m = 0; m <= _nm; m++) gMed(metric, m.toDouble())];
    final lo = med.first * bd[0] * 0.92;
    final hi = med.last * bd[7] * 1.06;
    double X(double m) => _xs + (m / _nm) * (_xe - _xs);
    double Y(double v) => _yb - ((v - lo) / (hi - lo)) * _hgt;

    void band(double fa, double fb, double op) {
      final p = Path();
      for (var m = 0; m <= _nm; m++) {
        final x = X(m.toDouble()), y = Y(med[m] * fb);
        m == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      for (var m = _nm.toInt(); m >= 0; m--) {
        p.lineTo(X(m.toDouble()), Y(med[m] * fa));
      }
      p.close();
      canvas.drawPath(p, Paint()..color = accent.withValues(alpha: op));
    }

    band(bd[0], bd[7], .07);
    band(bd[2], bd[5], .10);
    band(bd[3], bd[4], .15);

    // P50 虚线
    final dash = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final p50 = Path();
    for (var m = 0; m <= _nm; m++) {
      final x = X(m.toDouble()), y = Y(med[m]);
      m == 0 ? p50.moveTo(x, y) : p50.lineTo(x, y);
    }
    _drawDashed(canvas, p50, dash);

    // 带标签（18 月龄处）
    const labels = ['P3', 'P25', 'P50', 'P97'];
    for (var i = 0; i < 4; i++) {
      _text(canvas, labels[i], 4, Y(med.last * bd[[0, 2, 4, 6][i]]) + 3, 7,
          const Color(0xFF94A3B8));
    }

    // 自身曲线
    if (points.isNotEmpty) {
      final line = Paint()
        ..color = accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final pl = Path();
      for (var i = 0; i < points.length; i++) {
        final x = X(points[i].$1.clamp(0.0, _nm)), y = Y(points[i].$2);
        i == 0 ? pl.moveTo(x, y) : pl.lineTo(x, y);
      }
      canvas.drawPath(pl, line);
      for (final p in points) {
        final c = Offset(X(p.$1.clamp(0.0, _nm)), Y(p.$2));
        canvas.drawCircle(c, 3.6, Paint()..color = accent);
        canvas.drawCircle(c, 3.6,
            Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.2);
      }
      final last = points.last;
      final tag = growthShortTag(isFemale, metric, last.$1, last.$2, mode);
      _text(
          canvas,
          tag,
          X(last.$1.clamp(0, _nm)) - 10,
          Y(last.$2) - 8,
          8,
          accent,
          bold: true);
    }

    // 横轴刻度
    for (var m = 0; m <= _nm; m += 3) {
      _text(canvas, '$m', X(m.toDouble()) - 4, 196, 7, const Color(0xFF94A3B8));
    }
    _text(canvas, '月龄', _xe - 12, 212, 7, const Color(0xFF94A3B8));
    _text(
        canvas,
        '${metric.name} · $babyName · ${isFemale ? '女宝' : '男宝'} WHO 参考带',
        _xs,
        14,
        8,
        const Color(0xFF64748B),
        bold: true);
  }

  void _drawDashed(Canvas canvas, Path src, Paint paint) {
    for (final metric in src.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  void _text(Canvas canvas, String t, double x, double y, double size, Color color,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontSize: size, color: color, fontWeight: bold ? FontWeight.w800 : null)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y - size));
  }

  @override
  bool shouldRepaint(_GrowthPainter old) =>
      old.metric != metric ||
      old.isFemale != isFemale ||
      old.mode != mode ||
      old.points.length != points.length;
}
