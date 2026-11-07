import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_review.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/cycle_calc.dart';
import 'care_kit.dart';
import 'care_providers.dart';
import 'cycle_sheet.dart' show kCycP;

/// p-cycleStats 周期统计全屏（四指标 + 近12周期柱 + 异常波动提示 + 经量分布 + 症状 TOP5）。
class CycleStatsPage extends ConsumerStatefulWidget {
  const CycleStatsPage({super.key});

  @override
  ConsumerState<CycleStatsPage> createState() => _CycleStatsPageState();
}

class _CycleStatsPageState extends ConsumerState<CycleStatsPage> {
  static const _flowColors = {'少': '#fda4af', '中': '#fb7185', '多': '#e11d48'};

  /// AI 周期解读结果：仅展示不落库（红线）；再次点击重新生成即覆盖。
  String? _aiInsight;
  bool _aiBusy = false;

  Future<void> _runCycleInsight(String stats) async {
    if (_aiBusy) return;
    _aiBusy = true;
    try {
      final res = await aiRunWithReview(context, ref,
          taskId: 'care.cycle_insight', vars: {'stats': stats});
      // 失败/取消静默：归因 toast 已由 aiRunWithReview 处理。
      if (res != null && mounted) setState(() => _aiInsight = res.requireText());
    } finally {
      _aiBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(careDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('周期统计'),
            Text('规律度分析 · 本机构建',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final runs = periodRuns(d.cycleDays);
          final lens = cycleLengths(runs);
          final recent = lens.length > 12 ? lens.sublist(lens.length - 12) : lens;
          final avg = avgCycleLen(runs);
          final avgP = avgPeriodLen(runs);
          final reg = regularity(runs);
          final abn = abnormalCycles(runs);
          // 经量分布：全部经期日的 flow 计数。
          final flowN = {'少': 0, '中': 0, '多': 0};
          for (final c in d.cycleDays.values) {
            final f = c.flow;
            if (f != null && flowN.containsKey(f)) flowN[f] = flowN[f]! + 1;
          }
          final flowTot = flowN.values.fold<int>(0, (a, b) => a + b);
          // 症状 TOP5。
          final symN = <String, int>{};
          for (final c in d.cycleDays.values) {
            for (final s in c.syms) {
              symN[s] = (symN[s] ?? 0) + 1;
            }
          }
          final top = symN.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final top5 = top.take(5).toList();
          final maxSym = top5.isEmpty ? 1 : top5.first.value;
          // AI 周期解读红线：只发页面已算好的聚合数字，原始日记级记录不出本机。
          final aiStats = _aggregateStats(
            runs: runs,
            lens: lens,
            avg: avg,
            avgP: avgP,
            std: reg.std,
            flowN: flowN,
            flowTot: flowTot,
            top5: top5,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Row(
                children: [
                  _metric(context, '${avg == null ? '—' : avg.toStringAsFixed(1)}天', '平均周期', null),
                  const SizedBox(width: 8),
                  _metric(context, '${avgP == null ? '—' : avgP.toStringAsFixed(1)}天', '平均经期', null),
                  const SizedBox(width: 8),
                  _metric(context, runs.length < 3 ? '—' : reg.label, '规律度', '#2dd4bf'),
                  const SizedBox(width: 8),
                  _metric(context, '${runs.length}', '连续周期', null),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('近 12 个周期长度',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 96,
                      child: recent.isEmpty
                          ? Center(
                              child: Text('记录满 2 个经期起始后生成',
                                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)))
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (var i = 0; i < recent.length; i++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Text('${recent[i]}',
                                              style: TextStyle(
                                                  fontSize: 7.5,
                                                  fontWeight: (avg != null &&
                                                          (recent[i] - avg).abs() > 7)
                                                      ? FontWeight.w800
                                                      : FontWeight.normal,
                                                  color: (avg != null &&
                                                          (recent[i] - avg).abs() > 7)
                                                      ? careHex('#f43f5e')
                                                      : scheme.onSurfaceVariant)),
                                          const SizedBox(height: 2),
                                          Container(
                                            height: (recent[i] / 40 * 78).clamp(6, 78),
                                            decoration: BoxDecoration(
                                              borderRadius: const BorderRadius.vertical(
                                                  top: Radius.circular(3)),
                                              gradient: (avg != null &&
                                                      (recent[i] - avg).abs() > 7)
                                                  ? null
                                                  : careGrad(const [
                                                      '#6366f1',
                                                      '#8b5cf6',
                                                      '#c084fc'
                                                    ],
                                                      begin: Alignment.bottomCenter,
                                                      end: Alignment.topCenter),
                                              color: (avg != null &&
                                                      (recent[i] - avg).abs() > 7)
                                                  ? careHex('#fb7185')
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text('${i + 1}',
                                              style: const TextStyle(
                                                  fontSize: 7.5, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text('虚线 = 平均 ${avg == null ? '—' : avg.toStringAsFixed(1)} 天 · 红色 = 超 ±7 天异常波动',
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              if (abn.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: careHex(kCycP).withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: careHex(kCycP).withValues(alpha: .35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in abn)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Text('🌡 ', style: TextStyle(fontSize: 12)),
                              Expanded(
                                child: Text.rich(TextSpan(
                                    style: const TextStyle(
                                        fontSize: 11.5, height: 1.7),
                                    children: [
                                      TextSpan(
                                          text: '第 ${a.index} 个周期 ${a.len} 天',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800)),
                                      const TextSpan(text: '，超出正常波动范围。'),
                                    ])),
                              ),
                              GestureDetector(
                                onTap: () => AppToast.show(
                                    context,
                                    '就医参考说明：单次波动多为压力/作息所致；'
                                    '连续 3 次超 ±7 天建议妇科检查（演示文案，不构成医疗建议）',
                                    ms: 3200),
                                child: const Text('了解',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFF43F5E))),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('经量分布',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (flowTot == 0)
                      Text('暂无经量记录',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
                    else
                      for (final k in ['少', '中', '多'])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                  width: 24,
                                  child: Text(k,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey))),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: flowN[k]! / flowTot,
                                    minHeight: 8,
                                    backgroundColor: tokens.cardBorder,
                                    valueColor: AlwaysStoppedAnimation(
                                        careHex(_flowColors[k]!)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${flowN[k]} 次',
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('症状 TOP 5',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (top5.isEmpty)
                      Text('暂无感受记录',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
                    else
                      for (final e in top5)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                  width: 80,
                                  child: Text(e.key,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey))),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: e.value / maxSym,
                                    minHeight: 6,
                                    backgroundColor: tokens.cardBorder,
                                    valueColor: AlwaysStoppedAnimation(tokens.accent),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${e.value}次',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('AI 周期解读',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('仅上传本页聚合统计，原始记录不出本机；结果只展示、不存储',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const ValueKey('ai-cycle-insight'),
                      onPressed: () => _runCycleInsight(aiStats),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11)),
                      child: const Text('AI 周期解读',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    if (_aiInsight != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: careHex(kCycP).withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: careHex(kCycP).withValues(alpha: .25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('AI 生成 · 基于聚合统计 · 不构成医学建议',
                                  style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                              const SizedBox(height: 6),
                              Text(_aiInsight!,
                                  style: const TextStyle(fontSize: 12, height: 1.6)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 聚合统计文本（AI 出网唯一口径）：仅数字与区间，无任何日记级原始记录。
  String _aggregateStats({
    required List<PeriodRun> runs,
    required List<int> lens,
    required double? avg,
    required double? avgP,
    required double std,
    required Map<String, int> flowN,
    required int flowTot,
    required List<MapEntry<String, int>> top5,
  }) {
    final parts = <String>['连续周期 ${runs.length} 个'];
    if (lens.isNotEmpty) {
      parts.add('周期长度序列：${lens.join('、')} 天');
      parts.add('最短 ${lens.reduce((a, b) => a < b ? a : b)} 天、'
          '最长 ${lens.reduce((a, b) => a > b ? a : b)} 天');
    }
    if (avg != null) parts.add('平均周期 ${avg.toStringAsFixed(1)} 天');
    if (avgP != null) {
      parts.add('经期天数序列：${runs.map((r) => r.len).join('、')} 天，'
          '平均经期 ${avgP.toStringAsFixed(1)} 天');
    }
    if (lens.length >= 2) parts.add('周期长度标准差 ${std.toStringAsFixed(1)} 天');
    if (flowTot > 0) {
      parts.add('经量记录出现次数：少 ${flowN['少']}、中 ${flowN['中']}、多 ${flowN['多']}，'
          '合计 $flowTot 次');
    }
    if (top5.isNotEmpty) {
      parts.add('症状出现次数：${top5.map((e) => '${e.key} ${e.value} 次').join('、')}');
    }
    return parts.join('；');
  }

  Widget _metric(BuildContext context, String v, String l, String? color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: context.cardDecoration,
          alignment: Alignment.center,
          child: Column(
            children: [
              Text(v,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: color == null ? null : careHex(color))),
              const SizedBox(height: 2),
              Text(l, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
            ],
          ),
        ),
      );
}
