import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_models.dart';
import '../domain/health_symptom.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 症状与不适（原型 `p-symptom` · 路由 `/health/symptom` · 批3.5a）。
///
/// 五块共用**同一份档案内全量**（`healthSymptomProvider` 一次取数），四条口径写在最近处：
/// · 直方图与「正在发作」看**全量**，词云与流水看**部位筛选后**的子集（原型 `syRender` 就是这个顺序：
///   先算 live/hist，再 `ss=ss.filter(part)` 喂 cloud/list）——筛选不该改变疼痛分布的形状；
/// · 部位筛选是**包含匹配**：一条记了「头部·四肢」的记录，点头部或四肢都算命中，
///   没选部位的旧行按「全身」兜底（§2 口径，与 `symByPart` 同一判据）；
/// · 疼痛色带六档、文案三档（`health_symptom.dart` 单源），页面不再写第二份色表；
/// · 「标记结束」＝`ongoing` 落下**且**持续时长 +15 分钟，写库后 tick++ 整屏重取，
///   所以流水那行的「发作中」角标与「持续 X」会一起变，不是只清开关。
class HealthSymptomPage extends ConsumerStatefulWidget {
  const HealthSymptomPage({super.key});

  static const Key kLive = ValueKey('hsym-live');
  static const Key kHist = ValueKey('hsym-hist');
  static const Key kParts = ValueKey('hsym-parts');
  static const Key kCloud = ValueKey('hsym-cloud');
  static const Key kList = ValueKey('hsym-list');

  @override
  ConsumerState<HealthSymptomPage> createState() => _HealthSymptomPageState();
}

class _HealthSymptomPageState extends ConsumerState<HealthSymptomPage> {
  String _part = '全部';

  @override
  Widget build(BuildContext context) {
    ref.watch(healthTickProvider);
    final profiles = (ref.watch(healthProfilesProvider).valueOrNull ?? const <HealthProfile>[])
        .where((p) => !p.archived)
        .toList();
    final all = ref.watch(healthSymptomProvider).valueOrNull ?? const <SymptomRecord>[];
    final live = symLive(all);
    final shown = symListDesc(symByPart(all, _part));

    return Scaffold(
      appBar: AppBar(
        title: const Text('症状与不适'),
        actions: [
          IconButton(
            key: const ValueKey('hsym-add'),
            tooltip: '记录症状',
            icon: const Icon(Icons.add),
            onPressed: () => showHealthSymptomSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _profileBar(profiles),
          const SizedBox(height: 8),
          _liveCard(context, live),
          const SizedBox(height: 12),
          _histCard(context, all),
          const SizedBox(height: 12),
          _partRow(context, all),
          const SizedBox(height: 12),
          _cloudCard(context, shown),
          const SizedBox(height: 12),
          _streamCard(context, shown),
        ],
      ),
    );
  }

  // ==================== 档案 chips（切换即整模块重取，跨档案不聚合） ====================

  Widget _profileBar(List<HealthProfile> profiles) {
    final cur = ref.read(activeHealthProfileProvider);
    return SizedBox(
      height: 30,
      child: ListView(
        key: const ValueKey('hsym-bar'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in profiles)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                key: ValueKey('hsym-profile-${p.id}'),
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

  // ==================== 正在发作 ====================

  Widget _liveCard(BuildContext context, List<SymptomRecord> live) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('正在发作', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(symLiveTx(live.length),
                  key: const ValueKey('hsym-live-n'),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if (live.isEmpty)
            Text(symLiveEmptyTx,
                key: const ValueKey('hsym-live-empty'),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
          else
            Column(
              key: HealthSymptomPage.kLive,
              children: [
                for (final s in live)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      key: ValueKey('hsym-live-row-${s.id}'),
                      children: [
                        _flag(context, '发作中', scheme.error),
                        Expanded(
                          child: Text('${s.name} · ${symPartsTx(s)} · ${s.level} 分',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                        ),
                        TextButton(
                          key: ValueKey('hsym-end-${s.id}'),
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact),
                          onPressed: () => _end(s),
                          child: Text('标记结束',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w800, color: context.tokens.accent)),
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

  /// 「标记结束」走域层 `ended()`（ongoing 落下＋时长 +15 分钟同一处定义），写库后整屏重取。
  Future<void> _end(SymptomRecord s) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthRepositoryProvider).endSymptom(s);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return; // 等库之后才用 context 出提示条
    AppToast.show(context, symEndTx);
  }

  // ==================== 疼痛等级分布（11 根柱·0~10 分） ====================

  Widget _histCard(BuildContext context, List<SymptomRecord> all) {
    final scheme = Theme.of(context).colorScheme;
    final hist = symHist(all);
    final mx = symHistMax(hist);
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('疼痛等级分布', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('0 ~ 10 分',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            key: HealthSymptomPage.kHist,
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < hist.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: TweenAnimationBuilder<double>(
                        // 原型 `Math.max(6, n/mxh*100)%`：零次也留一段矮桩，别画成「没有这根柱」。
                        key: ValueKey('hsym-hist-$i'),
                        tween: Tween(begin: 0.06, end: (hist[i] / mx).clamp(0.06, 1.0)),
                        duration: const Duration(milliseconds: 260),
                        builder: (_, t, _) => Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: t,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(symColorHex(i)),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            key: const ValueKey('hsym-hist-ax'),
            children: [
              for (var i = 0; i < 11; i++)
                Expanded(
                    child: Text('$i',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant))),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 部位筛选（全部＋七枚·点一下换档，不是循环切） ====================

  Widget _partRow(BuildContext context, List<SymptomRecord> all) {
    final has = {for (final s in all) ...s.parts};
    return SizedBox(
      key: HealthSymptomPage.kParts,
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final x in ['全部', ...symParts])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                key: ValueKey('hsym-part-$x'),
                // 只给真出现过的部位带条数（包含匹配，与 `symByPart` 同一判据）；「全部」不写数。
                label: x == '全部' || !has.contains(x)
                    ? x
                    : '$x ${all.where((s) => s.parts.contains(x)).length}',
                selected: x == _part,
                onTap: () => setState(() => _part = x),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 高频描述词云 ====================

  Widget _cloudCard(BuildContext context, List<SymptomRecord> shown) {
    final scheme = Theme.of(context).colorScheme;
    final words = symWordCloud(shown);
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('高频描述', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(symCloudTx(words.length),
                  key: const ValueKey('hsym-cloud-n'),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if (words.isEmpty)
            Text('暂无文本可统计',
                key: const ValueKey('hsym-cloud-empty'),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
          else
            Wrap(
              key: HealthSymptomPage.kCloud,
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final w in words)
                  Text('${w.w} ${w.n}',
                      key: ValueKey('hsym-word-${w.w}'),
                      style: TextStyle(
                          fontSize: symCloudFont(w.ratio),
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface.withValues(alpha: symCloudOpacity(w.ratio)))),
              ],
            ),
        ],
      ),
    );
  }

  // ==================== 症状流水 ====================

  Widget _streamCard(BuildContext context, List<SymptomRecord> list) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('症状流水', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                key: const ValueKey('hsym-add-inline'),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact),
                onPressed: () => showHealthSymptomSheet(context),
                child: const Text('＋ 记录', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (list.isEmpty)
            const EmptyDashRow(text: symEmptyTx)
          else
            Column(
              key: HealthSymptomPage.kList,
              children: [
                for (final s in list.take(50))
                  InkWell(
                    key: ValueKey('hsym-row-${s.id}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showHealthSymptomSheet(context, editing: s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            key: ValueKey('hsym-badge-${s.id}'),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Color(symColorHex(s.level)).withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${s.level}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Color(symColorHex(s.level)))),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(symRowMain(s),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 12.5, fontWeight: FontWeight.w900)),
                                    ),
                                    if (s.drugRelated) ...[
                                      const SizedBox(width: 6),
                                      _flag(context, '用药相关', context.tokens.accent),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(symRowSub(s),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            key: ValueKey('hsym-del-${s.id}'),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact),
                            onPressed: () => _delete(s),
                            child: Text('删除',
                                style: TextStyle(
                                    fontSize: 10, color: scheme.error, fontWeight: FontWeight.w700)),
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

  Future<void> _delete(SymptomRecord s) async {
    final ok = await lhConfirm(context, symDelTx);
    if (!ok || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthRepositoryProvider).deleteSymptom(s.profileId, s.id!);
    container.read(healthTickProvider.notifier).state++;
    if (!mounted) return; // 确认＋删库两段 await 之后才用 context 提示条
    AppToast.show(context, '已删除');
  }

  Widget _flag(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
    );
  }
}
