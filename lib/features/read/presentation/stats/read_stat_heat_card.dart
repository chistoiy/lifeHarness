import 'dart:math';

import 'package:flutter/material.dart';

/// 卡片描边（与 `read_stat_page.dart` 的 `_deco` 同一份，抽出供本件复用）。
BoxDecoration readStatCardDeco(ColorScheme cs) => BoxDecoration(
  color: cs.surfaceContainerLow,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
);

/// 热力五档色（原型 HS 数组）。
const kReadStatHeatColors = [
  Color(0xFFE2E8F0),
  Color(0xFFC7D2FE),
  Color(0xFFA5B4FC),
  Color(0xFF818CF8),
  Color(0xFF6366F1),
];

/// 阅读热力图卡（原型 p-readstat `.hm`：7 行×周列横向滚 · 点格 toast · 色深随度量）。
///
/// 自 `read_stat_page.dart` 抽出＝治理体积棘轮（该文件登记值随之下调），格面行为零改动。
/// 本批追加 U4 两件事：
/// **月份刻度行**——与格子同处一个横向滚动容器，节距＝13＋3＝16px，刻度与列严格对齐；
/// **默认视口定位**——按月＝该月首列贴左；当年＝最后一个有数据的周贴右（无数据以今天列
/// 兜底）；往年＝该年第一个有数据的列贴左。修的是「全年明明有数据却整片灰」：有数据的列
/// 滚在屏幕外、又没有月份刻度，用户读不到（UX 审计真机批 U4 定案）。
/// 换范围（年/月/度量）由调用方换 key ⇒ 本件状态重建 ⇒ 视口按新口径重算；
/// 同一范围内用户手动滚动的位置照旧保留。
class ReadStatHeatCard extends StatefulWidget {
  const ReadStatHeatCard({
    super.key,
    required this.year,
    required this.month,
    required this.scopeTag,
    required this.metricName,
    required this.goalDay,
    required this.valueAt,
    required this.minutesAt,
    required this.summary,
    required this.onTapDay,
  });

  final int year;

  /// 0＝全年，否则自然月（非本月格子淡显）。
  final int month;

  /// 年·月·度量键：变化即重算默认视口（调用方同时把它作本件 key）。
  final String scopeTag;
  final String metricName;
  final int goalDay;

  /// 度量取值（时长/摘录/天数三档由调用方给，索引＝年内第几天，0 基）。
  final double Function(int dayIndex) valueAt;

  /// 当日分钟数（Tooltip 与「已打卡 √」判定用）。
  final int Function(DateTime day) minutesAt;

  /// 右下角汇总（与页面其余读数同源，由调用方算好）。
  final String summary;

  /// 点格（调用方出 toast，文案口径与原型一致）。
  final void Function(BuildContext context, DateTime day, int dayIndex) onTapDay;

  static const double cell = 13, gap = 3, pitch = 16, rulerH = 12;
  static const double gridH = 7 * cell + 6 * gap;

  @override
  State<ReadStatHeatCard> createState() => _ReadStatHeatCardState();
}

class _ReadStatHeatCardState extends State<ReadStatHeatCard> {
  final ScrollController _sc = ScrollController();
  String? _appliedKey;

  DateTime get _first => DateTime(widget.year);
  int get _days => DateTime(widget.year, 12, 31).difference(_first).inDays + 1;

  /// 年内有数据的日索引区间（无数据＝first/last 均 -1）。
  ({int first, int last}) _dataSpan() {
    var f = -1, l = -1;
    for (var i = 0; i < _days; i++) {
      if (widget.valueAt(i).round() > 0) {
        if (f < 0) f = i;
        l = i;
      }
    }
    return (first: f, last: l);
  }

  /// U4 默认视口目标列：按月＝该月首列；当年＝最后一个有数据的周（今天兜底）；
  /// 往年＝该年第一个有数据的列。`rightEdge` 档贴右缘（留一列余量），其余贴左缘。
  ({int col, bool rightEdge}) _focus() {
    final w = widget, first = _first, today = DateTime.now();
    if (w.month != 0) {
      return (
        col: DateTime(w.year, w.month).difference(first).inDays ~/ 7,
        rightEdge: false,
      );
    }
    if (today.year != w.year) {
      final f = _dataSpan().first;
      return (col: (f < 0 ? 0 : f) ~/ 7, rightEdge: false);
    }
    return (
      col: max(_dataSpan().last, today.difference(first).inDays) ~/ 7,
      rightEdge: true,
    );
  }

  /// 目标列换算成 scrollExtent（[viewW]＝横向可视宽，末尾由 maxScrollExtent 夹取）。
  double _targetFor(double viewW) {
    final contentW = (_days / 7).ceil() * ReadStatHeatCard.pitch -
        ReadStatHeatCard.gap;
    final f = _focus();
    final raw = f.rightEdge
        ? (f.col + 2) * ReadStatHeatCard.pitch - viewW
        : f.col * ReadStatHeatCard.pitch;
    return min(max(0.0, contentW - viewW), max(0.0, raw));
  }

  /// 首帧布局后一次 `jumpTo`（本版本 `SingleChildScrollView` 无 initialScrollExtent）。
  /// 口径键含可视宽：宽窄变了（转屏／测试换面）按新宽重算，同一宽下不动用户手动位置。
  void _scheduleFocus(double viewW) {
    final key = '${widget.scopeTag}|${viewW.toStringAsFixed(1)}';
    if (_appliedKey == key) return;
    _appliedKey = key;
    final target = _targetFor(viewW);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sc.hasClients) return;
      _sc.position.jumpTo(target.clamp(0.0, _sc.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final cs = Theme.of(context).colorScheme;
    final first = _first, n = _days;
    var mx = 1;
    for (var i = 0; i < n; i++) {
      mx = max(mx, w.valueAt(i).round());
    }
    final today = DateTime.now();
    final curMonth = today.year == w.year ? today.month : 0;
    final cols = (n / 7).ceil();
    final contentW = cols * ReadStatHeatCard.pitch - ReadStatHeatCard.gap;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: readStatCardDeco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${w.year} 年阅读热力图 · ${w.metricName}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Text(
                '每格＝一天 · 色深＝${w.metricName}',
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              _scheduleFocus(box.maxWidth);
              return SizedBox(
                height:
                    ReadStatHeatCard.rulerH + 3 + ReadStatHeatCard.gridH,
                child: SingleChildScrollView(
                  controller: _sc,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: ReadStatHeatCard.rulerH,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (final m in w.month == 0
                                  ? const [
                                      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
                                    ]
                                  : [w.month])
                                Positioned(
                                  key: ValueKey('rs-heat-m$m'),
                                  left:
                                      DateTime(w.year, m)
                                              .difference(first)
                                              .inDays ~/
                                          7 *
                                          ReadStatHeatCard.pitch,
                                  child: Text(
                                    '$m月',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      height: 1,
                                      fontWeight: m == curMonth
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: m == curMonth
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: ReadStatHeatCard.gridH,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var c = 0; c < cols; c++)
                                Padding(
                                  padding: EdgeInsets.only(
                                    right:
                                        c == cols - 1
                                            ? 0
                                            : ReadStatHeatCard.gap,
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      for (var r = 0; r < 7; r++)
                                        _cellAt(
                                          context,
                                          first,
                                          c * 7 + r,
                                          n,
                                          mx,
                                          cs,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '少',
                style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              for (final c in kReadStatHeatColors)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Text(
                '多',
                style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  text: '全年 ',
                  children: [
                    TextSpan(
                      text: w.summary,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cellAt(
    BuildContext context,
    DateTime first,
    int i,
    int n,
    int mx,
    ColorScheme cs,
  ) {
    if (i >= n) return const SizedBox(width: 13, height: 13);
    final d = first.add(Duration(days: i));
    final m = widget.minutesAt(d);
    // 轮3：日历视图体现打卡（当日分钟数 ≥ 每日目标＝已打卡 √）。
    final ck = m > 0 && m >= widget.goalDay;
    final v = widget.valueAt(i).round();
    final lvl =
        v == 0
            ? 0
            : v > mx * .7
            ? 4
            : v > mx * .45
            ? 3
            : v > mx * .22
            ? 2
            : 1;
    final inM = widget.month == 0 || d.month == widget.month;
    return Tooltip(
      message: '$m 分钟${ck ? ' · 已打卡' : ''}',
      child: GestureDetector(
        key: ValueKey('rs-heat-$i'),
        onTap: () => widget.onTapDay(context, d, i),
        child: Container(
          width: 13,
          height: 13,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2.5),
            color: kReadStatHeatColors[lvl].withValues(alpha: inM ? 1 : .34),
          ),
          child: ck
              ? const Text(
                  '√',
                  style: TextStyle(
                    fontSize: 8,
                    height: 1,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
