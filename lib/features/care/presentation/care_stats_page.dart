import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/care_events.dart';
import '../domain/care_models.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// p-babyStats 喂养分析（原型 C10）：四 tab 换肤 + 7×24 时间规律钟 +
/// 喂奶量/睡眠量/换尿布三卡 + 分析与建议（本地规则引擎文案）。
class CareStatsPage extends ConsumerStatefulWidget {
  const CareStatsPage({super.key});

  @override
  ConsumerState<CareStatsPage> createState() => _CareStatsPageState();
}

const _bsColor = {
  'milk': '#ec4899',
  'sleep': '#8b5cf6',
  'dia': '#f59e0b',
  'all': '#ec4899',
};
const _bsKinds = {
  'milk': ['nurse', 'bmilk', 'formula', 'water', 'solids', 'pump'],
  'sleep': ['sleep'],
  'dia': ['diaper'],
};
const _bsIns = {
  'milk': '近7天瓶喂均值稳定，亲喂左侧时长略多于右侧，可交替起始侧平衡泌乳。'
      '6月龄前一般无需额外喂水，观察尿量即可。',
  'sleep': '昼夜睡眠总量在月龄参考区间内；入睡时间波动 ±40 分钟，'
      '建议固定睡前程序（洗澡→抚触→暗光）。',
  'dia': '大便颜色与饮食相关，金黄色糊状为母乳便典型表现。'
      '若出现砖红色、灰白色或带血丝，请拍照留档并咨询儿科（不构成医疗建议）。',
  'all': '喂养-排尿-睡眠链路节奏正常；数据将自动汇入周报（联动 L4），'
      '可在「分析与建议」持续追踪。',
};

class _CareStatsPageState extends ConsumerState<CareStatsPage> {
  String _tab = 'milk';
  List<String> _sel = const [];

  Color get _c => careHex(_bsColor[_tab]!);

  void _setTab(String t) => setState(() {
        _tab = t;
        _sel = const [];
      });

  void _setSel(List<String> s) => setState(() => _sel = s);

  void _toggleSel(String k) {
    final next = [..._sel];
    if (next.contains(k)) {
      next.remove(k);
    } else {
      next.add(k);
    }
    _setSel(next);
  }

  bool _inTab(CareRecord r) {
    final ks = _bsKinds[_tab];
    if (ks != null && !ks.contains(r.k)) return false;
    if (_tab == 'all' && _sel.isNotEmpty && !_sel.contains(r.k)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(careDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('呵护 · 汇总'),
            Text('事件 × 时段 × 趋势',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final days = [
            for (var i = 6; i >= 0; i--)
              careDayKey(DateTime.now().subtract(Duration(days: i))),
          ];
          final dayLogs = [
            for (final day in days)
              d.logsOfDay(day).where(_inTab).toList(),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Seg(
                      labels: const ['喂奶', '睡眠', '换尿布', '全部'],
                      keys: const ['bst-milk', 'bst-sleep', 'bst-dia', 'bst-all'],
                      selected: ['milk', 'sleep', 'dia', 'all'].indexOf(_tab),
                      accent: _c,
                      onPick: (i) =>
                          _setTab(['milk', 'sleep', 'dia', 'all'][i]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    key: const ValueKey('bs-ref'),
                    onTap: () => AppToast.show(context,
                        '参考表：WHO 奶量 / 睡眠时长 / 排便性状参考标准（V1.x 接入）'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Text('参考表',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // —— 时间规律钟 ——
              Container(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                decoration: context.cardDecoration,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: _c,
                                borderRadius: BorderRadius.circular(999)),
                            child: const Text('时间规律',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                          if (_tab == 'all')
                            GestureDetector(
                              key: const ValueKey('bs-filter'),
                              onTap: () => _showBsFilter(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                    border: Border.all(color: _c),
                                    borderRadius: BorderRadius.circular(999)),
                                child: Text('筛选 ▾',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: _c)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _clock(days, dayLogs),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_tab == 'milk' || _tab == 'all') _milkCard(days, dayLogs),
              if (_tab == 'sleep' || _tab == 'all') _sleepCard(days, dayLogs),
              if (_tab == 'dia' || _tab == 'all') _diaCard(days, dayLogs),
              const SizedBox(height: 12),
              _insCard(),
            ],
          );
        },
      ),
    );
  }

  /// 24×7 时间规律网格（每格最多 3 图标，超出加粉色 + 角标）。
  Widget _clock(List<String> days, List<List<CareRecord>> dayLogs) {
    final perDay = [
      for (final l in dayLogs)
        [
          for (var h = 0; h < 24; h++) l.where((r) => int.parse(r.s.substring(0, 2)) == h).toList()
        ]
    ];
    final d = ref.read(careDataProvider).valueOrNull!;
    return Column(
      children: [
        for (var h = 0; h < 24; h++)
          SizedBox(
            height: 15,
            child: Row(
              children: [
                for (var di = 0; di < 7; di++)
                  Expanded(
                    child: Container(
                      color: di.isOdd ? Colors.transparent : _c.withValues(alpha: .05),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final ic in {
                            for (final r in perDay[di][h]) d.iconOf(r)
                          }
                                .take(3))
                            Text(ic, style: const TextStyle(fontSize: 8)),
                          if (perDay[di][h].length > 2 &&
                              perDay[di][h].length >
                                  {
                                    for (final r in perDay[di][h]) d.iconOf(r)
                                  }.length)
                            Text('+',
                                style: TextStyle(
                                    fontSize: 7, fontWeight: FontWeight.w800, color: _c)),
                        ],
                      ),
                    ),
                  ),
                SizedBox(
                  width: 24,
                  child: Text(h % 2 == 0 ? '$h' : '',
                      style: const TextStyle(fontSize: 7, color: Color(0xFFCBD5E1))),
                ),
              ],
            ),
          ),
        const SizedBox(height: 3),
        Row(
          children: [
            for (var di = 0; di < 7; di++)
              Expanded(
                child: Text(
                  '${days[di].substring(5).replaceFirst('-', '.')}${di == 6 ? ' 今天' : ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: di == 6 ? _c : Colors.grey),
                ),
              ),
            const SizedBox(width: 24),
          ],
        ),
        // 图例行（legend）
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 6),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final k in _tab == 'all'
                  ? kEventBaseKeys.where((k) => k != 'custom')
                  : _bsKinds[_tab]!)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(d.evOf(k).icon, style: const TextStyle(fontSize: 9)),
                    const SizedBox(width: 3),
                    Text(d.evOf(k).name,
                        style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                  ],
                ),
              if (_tab == 'dia')
                for (final (hex, t) in const [
                  ('#f59e0b', '嘘嘘'),
                  ('#10b981', '臭臭'),
                  ('#3b82f6', '嘘嘘+臭臭'),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: careHex(hex), shape: BoxShape.circle)),
                      const SizedBox(width: 3),
                      Text(t, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                    ],
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, List<String> vals, String unit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text(label,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 9, color: Colors.grey))),
          const SizedBox(width: 4),
          for (var i = 0; i < vals.length; i++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                alignment: Alignment.center,
                color: i.isOdd ? Colors.grey.withValues(alpha: .07) : null,
                child: Text('${vals[i]}$unit',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: vals[i] == '0' || vals[i].isEmpty
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF475569))),
              ),
            ),
        ],
      ),
    );
  }

  String _ml(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Widget _tag(String t, String hex) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: careHex(hex), borderRadius: BorderRadius.circular(999)),
        child: Text(t,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  Widget _avgBadge(String text, String hex) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            border: Border.all(color: careHex(hex)),
            borderRadius: BorderRadius.circular(999),
            color: context.tokens.card),
        child: Text(text,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: careHex(hex))),
      );

  List<String> _dow7() {
    return [
      for (var i = 6; i >= 0; i--)
        careDayKey(DateTime.now().subtract(Duration(days: i))).substring(5).replaceFirst('-', '.')
    ];
  }

  Widget _milkCard(List<String> days, List<List<CareRecord>> dayLogs) {
    final nu = [for (final l in dayLogs) l.where((r) => r.k == 'nurse').toList()];
    final bottle = [
      for (final l in dayLogs)
        l.where((r) => r.k == 'bmilk' || r.k == 'formula').toList()
    ];
    final left = nu.map((a) => a.fold<int>(0, (x, r) => x + _side(r, '左'))).toList();
    final right = nu.map((a) => a.fold<int>(0, (x, r) => x + _side(r, '右'))).toList();
    final bMl = bottle.map((a) => a.fold<double>(0, (x, r) => x + (r.ml ?? 0))).toList();
    final avgB = (bMl.reduce((a, b) => a + b) / 7).round();
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _tag('喂奶量', '#ec4899'),
              const SizedBox(width: 8),
              const Text('统计周期：每日00:00-24:00 · 近7天',
                  style: TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 4),
            child: Text('▎亲喂母乳',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFEC4899))),
          ),
          _row('次数', nu.map((a) => '${a.length}').toList(), '次'),
          _row('左侧', left.map((v) => '$v').toList(), '分钟'),
          _row('右侧', right.map((v) => '$v').toList(), '分钟'),
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 4),
            child: Text('▎瓶喂（配方奶 + 瓶喂母乳）',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFEC4899))),
          ),
          _row('次数', bottle.map((a) => '${a.length}').toList(), '次'),
          _row('总量', bMl.map(_ml).toList(), 'ml'),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(child: _avgBadge('近7天平均每天 $avgB ml', '#ec4899')),
          ),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var di = 0; di < 7; di++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(bMl[di] > 0 ? _ml(bMl[di]) : '',
                            style: const TextStyle(
                                fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
                        for (final r in bottle[di])
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 26,
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: careHex(r.k == 'formula' ? '#f97316' : '#ec4899'),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(_ml(r.ml ?? 0),
                                style: const TextStyle(
                                    fontSize: 7, color: Colors.white)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _dates('#ec4899'),
          const SizedBox(height: 6),
          Divider(height: 1, color: tokens.cardBorder),
        ],
      ),
    );
  }

  int _side(CareRecord r, String side) {
    final m = RegExp('$side(\\d+)').firstMatch(r.seg ?? '');
    if (m != null) return int.parse(m.group(1)!);
    if ((r.seg ?? '').isNotEmpty) return (r.durOr0 / 2).round();
    return (r.durOr0 / 2).round();
  }

  Widget _sleepCard(List<String> days, List<List<CareRecord>> dayLogs) {
    final sl = [for (final l in dayLogs) l.where((r) => r.k == 'sleep').toList()];
    final mins = sl.map((a) => a.fold<int>(0, (x, r) => x + r.durOr0)).toList();
    final avgS = mins.reduce((a, b) => a + b) / 7;
    String fmt(int m) => m == 0
        ? '0'
        : m >= 60
            ? '${m ~/ 60}h${m % 60 > 0 ? '${m % 60}′' : ''}'
            : '$m′';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tag('睡眠量', '#8b5cf6'),
          const SizedBox(height: 8),
          _row('总次数', sl.map((a) => '${a.length}').toList(), '次'),
          _row('总时长', mins.map(fmt).toList(), ''),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
                child: _avgBadge(
                    '近7天平均每天 ${avgS.floor()}小时${(avgS % 1 * 60).round()}分钟', '#8b5cf6')),
          ),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var di = 0; di < 7; di++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 22,
                          height: (mins[di] / (14 * 60) * 80).clamp(2, 80).toDouble(),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA78BFA),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _dates('#8b5cf6'),
        ],
      ),
    );
  }

  Widget _diaCard(List<String> days, List<List<CareRecord>> dayLogs) {
    final dp = [for (final l in dayLogs) l.where((r) => r.k == 'diaper').toList()];
    final avgD = dp.fold<int>(0, (a, x) => a + x.length) / 7;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tag('换尿布次数', '#f59e0b'),
          const SizedBox(height: 8),
          _row('总次数', dp.map((a) => '${a.length}').toList(), '次'),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
                child: _avgBadge('近7天平均每天 ${avgD.toStringAsFixed(1)}次', '#f59e0b')),
          ),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var di = 0; di < 7; di++)
                  Expanded(
                    child: Column(
                      children: [
                        for (final r in dp[di])
                          Container(
                            width: 11,
                            height: 11,
                            margin: const EdgeInsets.only(bottom: 3),
                            decoration: BoxDecoration(
                                color: careHex(r.dia == 'pee'
                                    ? '#f59e0b'
                                    : r.dia == 'mix'
                                        ? '#3b82f6'
                                        : '#10b981'),
                                shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _dates('#f59e0b'),
          const SizedBox(height: 4),
          const Text('● 嘘嘘　● 臭臭　● 嘘嘘+臭臭（橙/绿/蓝）',
              style: TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _dates(String hex) => Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Text(_dow7()[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: i == 6 ? careHex(hex) : Colors.grey)),
            ),
        ],
      );

  Widget _insCard() => Container(
        padding: const EdgeInsets.all(13),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('分析与建议',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_bsIns[_tab]!,
                style: const TextStyle(fontSize: 11, height: 1.6, color: Color(0xFF64748B))),
            const SizedBox(height: 6),
            const Text('规则引擎本地生成 · 不构成医疗建议 · AI 深度解读为 Opt-in（原始记录不出本机）',
                style: TextStyle(fontSize: 9, color: Color(0xFFCBD5E1))),
          ],
        ),
      );

  Future<void> _showBsFilter(BuildContext context) {
    return showCareSheet<void>(context, builder: (bc) => _BsFilter(state: this));
  }
}

/// sheetBsFilter 记录项多选（仅「全部」tab；粉主题）。
class _BsFilter extends ConsumerWidget {
  const _BsFilter({required this.state});
  final _CareStatsPageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    const pink = Color(0xFFEC4899);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('请筛选记录项',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            const cols = 3;
            const gap = 8.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final k in kEventBaseKeys.where((k) => k != 'custom'))
                  SizedBox(
                    width: w,
                    child: CChip(
                      key: ValueKey('bsf-$k'),
                      label: '${d.evOf(k).icon} ${d.evOf(k).name}',
                      accent: pink,
                      selected: state._sel.contains(k),
                      onTap: () => state._toggleSel(k),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('bsf-clear'),
                  onPressed: () => state._setSel(const []),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: pink),
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: const Text('不筛选',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: pink)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('bsf-ok'),
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: pink, borderRadius: BorderRadius.circular(14)),
                    child: const Text('确定',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 四 tab 分段钮（选中色随 tab 主色）。
class _Seg extends StatelessWidget {
  const _Seg({
    required this.labels,
    required this.keys,
    required this.selected,
    required this.accent,
    required this.onPick,
  });
  final List<String> labels;
  final List<String> keys;
  final int selected;
  final Color accent;
  final ValueChanged<int> onPick;

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
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? tokens.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: i == selected ? accent : Colors.grey)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
