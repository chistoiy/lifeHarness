import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/lh_wheel.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_goal.dart';
import '../domain/media_goal.dart';
import 'media_providers.dart';

/// 影音游目标屏（原型 `m-goal` · 路由 `/media/goal` · 词典 LH-C22 · 批8a）。
///
/// - 固定六行＝kMdsGoalDefs（逐字对齐计划 §八 L7 六路汇聚）；
/// - 未设＝虚线「设目标」、**行内零百分比**；已设＝目标 chip＋百分比＋细进度条（封顶 100）；
/// - 点行就地展开单列滚轮（LHWheel＝LH-K39），吸中即落库，「不设目标」清档回虚线；
/// - 读数恒吃真实时长，与统计屏「目标达成」块同源（`mediaGoalRowsProvider` 一份出口）。
class MediaGoalPage extends ConsumerStatefulWidget {
  const MediaGoalPage({super.key});

  @override
  ConsumerState<MediaGoalPage> createState() => _MediaGoalPageState();
}

class _MediaGoalPageState extends ConsumerState<MediaGoalPage> {
  String? _open;

  /// 本屏最近一次滚轮上报的存储值（bump 重建后用它认出「回的是我自己报的档」，
  /// 不再 jumpToItem 触发第二次回报＝写库链式爬档的实锤循环源）。
  int? _lastReported;

  Future<void> _pick(MediaGoalRow r, int value) async {
    // 同值不写＝防「写库→bump 重建→didUpdateWidget jumpToItem 再回报」的滚轮回写自循环
    // （LHWheel 段注明坑；吸中同一档＝什么都不发生）。
    if (r.goal?.target == value) return;
    _lastReported = value;
    await ref.read(mediaRepositoryProvider).setGoal(r.def.k, r.def.unit, value);
    _bump();
  }

  Future<void> _clear(String metric) async {
    await ref.read(mediaRepositoryProvider).clearGoal(metric);
    _lastReported = null;
    setState(() => _open = null);
    _bump();
  }

  void _bump() {
    final t = ref.read(mediaTickProvider.notifier);
    t.state = t.state + 1;
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(mediaGoalRowsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('影音目标')),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '目标没加载出来',
          error: e,
          onRetry: () => ref.invalidate(mediaGoalRowsProvider),
        ),
        data: (rs) => ListView(
          key: const ValueKey('mdg-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            for (final r in rs) _row(r),
          ],
        ),
      ),
    );
  }

  Widget _row(MediaGoalRow r) {
    final scheme = Theme.of(context).colorScheme;
    final d = r.def;
    final g = r.goal;
    final pct = (g != null && g.target > 0)
        ? (r.read / g.target * 100).round()
        : 0;
    final open = _open == d.k;
    return InkWell(
      key: ValueKey('mdg-${d.k}'),
      onTap: () => setState(() => _open = open ? null : d.k),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${kMdsPerWord[d.per]} ${mdsGoalReadText(d.k, r.read)} ${d.unit}',
                      key: ValueKey('mdgread-${d.k}'),
                      style: TextStyle(
                          fontSize: 10.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (g != null)
                Text(
                  '${mdsGoalTargetText(g)} · $pct%',
                  key: ValueKey('mdgt-${d.k}'),
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                )
              else
                Container(
                  key: ValueKey('mdgunset-${d.k}'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: scheme.outlineVariant,
                        strokeAlign: BorderSide.strokeAlignInside),
                  ),
                  child: Text('设目标',
                      style: TextStyle(
                          fontSize: 10.5, color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
          if (g != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LayoutBuilder(
                builder: (_, c) {
                  final w = (c.maxWidth *
                          (pct > 100 ? 1.0 : pct / 100.0))
                      .clamp(0.0, c.maxWidth);
                  return Container(
                    key: ValueKey('mdgbar-${d.k}'),
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: scheme.surfaceContainerHighest,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: w,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (open) _wheel(r),
          const SizedBox(height: 10),
          Divider(height: 1, color: scheme.outlineVariant),
        ],
      ),
    );
  }

  Widget _wheel(MediaGoalRow r) {
    final d = r.def;
    final labels = mdsGoalWheelDisplay(d.k);
    final store = mdsGoalWheelLabels(d.k);
    final cur = r.goal?.target;
    final idx = cur == null
        ? (labels.length ~/ 2)
        : store.indexOf('$cur').clamp(0, labels.length - 1);
    // 未设档的落库值是 null，但滚轮只会回报「当前居中档」＝idx 对应值；
    // 记住建议初始居中值，同值回报一律吞掉（首帧噪音另有判据，见 LHWheel 注）。
    final anchor = int.parse(store[idx]);
    return Padding(
      key: ValueKey('mdg-wheel-${d.k}'),
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PillChip(
                key: ValueKey('mdg-clear-${d.k}'),
                label: '不设目标',
                selected: false,
                onTap: () => _clear(d.k),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 140,
            child: LHWheel(
              key: ValueKey('mdg-wheelpick-${d.k}'),
              labels: labels,
              initialIndex: idx,
              height: 106,
              itemExtent: 30,
              keyPrefix: 'mdgw-${d.k}-',
              onSelect: (i) {
                final v = mdsGoalStoreValue(d.k, i);
                // 开轮居中档的回报（含落库重建后 jumpToItem 的二次回报）＝用户没动它，吞掉。
                if (cur == null && v == anchor) return;
                if (_lastReported == v) return;
                _pick(r, v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
