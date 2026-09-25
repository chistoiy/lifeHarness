import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/goal_calc.dart';
import '../domain/goal_models.dart';
import 'goal_detail_page.dart';
import 'goal_edit_page.dart';
import 'goal_review_page.dart';
import 'goals_kit.dart';
import 'goals_providers.dart';

/// P10 目标 OKR 主页（原型 renderOkr 4087-4119 对译）。
///
/// 口径：顶周期卡 ‹› 切当年四季（边界 toast 逐字）/ 季度·年度视角 chips /
/// O 卡（百分比=KR 均值实算、逐 KR 迷你条、底部口径行）/ ≤5 上限提示行 /
/// 空态双钮（新建 + 复制上期：回退找有内容周期、清零、重编号）/ 复盘引导卡 /
/// FAB 新建（归档拦截）。全实算禁写死（HG-E1）。
class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key});

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _toast(String msg) => AppToast.show(context, msg);

  /// ‹› 切周期：出界 toast 逐字（原型 goalPeriod）。
  void _shiftPeriod(int delta) {
    final now = ref.read(goalsClockProvider)();
    final qs = GoalPeriod.quartersOfYear(now.year);
    final cur = ref.read(goalsPeriodProvider);
    final idx = qs.contains(cur)
        ? qs.indexOf(cur)
        : qs.indexOf(GoalPeriod.current(now));
    final np = idx + delta;
    if (np < 0) {
      _toast('最早周期为 ${qs.first}');
      return;
    }
    if (np > qs.length - 1) {
      _toast('已是最后一个周期');
      return;
    }
    final d = ref.read(goalsDataProvider).valueOrNull;
    ref.read(goalsPeriodProvider.notifier).state = qs[np];
    _toast('已切换到 ${qs[np]} · '
        '${GoalPeriod.stateLabel(qs[np], d?.archivedPeriods ?? {}, now)}');
  }

  void _setView(String v) {
    ref.read(goalsViewProvider.notifier).state = v;
    _toast(v == 'year'
        ? '年度视角：跨周期总览全部 O（含归档）'
        : '周期视角：仅 ${ref.read(goalsPeriodProvider)}');
  }

  /// 新建入口（原型 goalNew）：归档拦截 + 上限提醒，逐字。
  void _newGoal(String period, GoalsData d) {
    if (d.isArchived(period)) {
      _toast('归档周期只读 · 请切到进行中周期再创建/编辑');
      return;
    }
    if (d.inPeriod(period).length >= kMaxOkrPerPeriod) {
      _toast('目标数量上限提醒：$period 已有 $kMaxOkrPerPeriod 个 O，建议先归档/收敛一个');
      return;
    }
    _push(GoalEditPage(goalId: null));
  }

  /// 复制上期（原型 goalCopyPrev）：回退找有内容周期 → 上限校验 → 清零重编号。
  Future<void> _copyPrev(String period, GoalsData d) async {
    var from = GoalPeriod.prevQuarter(period);
    var src = d.inPeriod(from);
    var guard = 0;
    while (src.isEmpty && guard++ < 8) {
      from = GoalPeriod.prevQuarter(from);
      src = d.inPeriod(from);
    }
    if (src.isEmpty) {
      _toast('没有可复制的历史周期');
      return;
    }
    if (d.inPeriod(period).length + src.length > kMaxOkrPerPeriod) {
      _toast('复制后将超出单周期 $kMaxOkrPerPeriod 个上限 · 请精简后再复制');
      return;
    }
    final n = await ref.read(goalsRepositoryProvider).copyGoals(from, period);
    if (!mounted) return;
    goalsTouch(ref);
    _toast('已从 $from 复制 $n 个目标为 $period 草稿（进度清零）');
  }

  /// 归档/恢复当前周期（g-period-archive / g-period-restore）。
  Future<void> _toggleArchived(String period, bool archived) async {
    await ref.read(goalsRepositoryProvider).setPeriodArchived(period, archived);
    if (!mounted) return;
    goalsTouch(ref);
    _toast(archived ? '已归档 $period · 周期转为只读' : '已恢复 $period · 可继续编辑');
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(goalsClockProvider)();
    final async = ref.watch(goalsDataProvider);
    final period = ref.watch(goalsPeriodProvider);
    final view = ref.watch(goalsViewProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('目标 OKR'),
            Text('计划 → 执行 → 复盘',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      floatingActionButton: GradFab(
        key: const ValueKey('g-fab'),
        icon: const Icon(Icons.add, color: Colors.white, size: 26),
        tooltip: '新建目标',
        onTap: () {
          final d = ref.read(goalsDataProvider).valueOrNull;
          if (d == null) return;
          _newGoal(period, d);
        },
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => _body(d, now, period, view),
      ),
    );
  }

  Widget _body(GoalsData d, DateTime now, String period, String view) {
    final arch = d.isArchived(period);
    final list = view == 'year'
        ? d.goals
        : [
            ...d.inPeriod(period),
            ...d.inPeriod(GoalPeriod.yearBucket),
          ];
    final avg = list.isEmpty
        ? 0
        : (list.fold<int>(0, (s, o) => s + o.pct) / list.length).round();
    final krTotal = list.fold<int>(0, (s, o) => s + o.krs.length);
    final krDone = list.fold<int>(0, (s, o) => s + o.krs.where((k) => k.achieved).length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        // 顶周期卡：‹ 标题+副行 ›（原型 L1227-1234）
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: context.tokens.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.tokens.cardBorder),
          ),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('g-period-prev'),
                icon: const Icon(Icons.chevron_left, size: 22),
                onPressed: () => _shiftPeriod(-1),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      view == 'year'
                          ? '${now.year} 年度视角 · 全部周期'
                          : '$period · ${GoalPeriod.stateLabel(period, d.archivedPeriods, now)}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                          style: const TextStyle(
                              fontSize: 10, color: kGoalsMuted),
                          children: [
                            TextSpan(text: '${list.length} 个目标 · 平均进度 '),
                            TextSpan(
                              text: '$avg%',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: context.tokens.accent),
                            ),
                            TextSpan(text: ' · KR 达成 $krDone/$krTotal'),
                          ]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('g-period-next'),
                icon: const Icon(Icons.chevron_right, size: 22),
                onPressed: () => _shiftPeriod(1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            PillChip(
              key: const ValueKey('g-scope-quarter'),
              label: '季度目标',
              selected: view != 'year',
              onTap: () => _setView('quarter'),
            ),
            const SizedBox(width: 8),
            PillChip(
              key: const ValueKey('g-scope-year'),
              label: '年度视角',
              selected: view == 'year',
              onTap: () => _setView('year'),
            ),
            const Spacer(),
            if (view != 'year')
              MiniBtn(
                key: ValueKey(arch ? 'g-period-restore' : 'g-period-archive'),
                icon: arch ? Icons.lock_open : Icons.inventory_2_outlined,
                label: arch ? '恢复编辑' : '归档周期',
                onTap: () => _toggleArchived(period, !arch),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final g in list) _okrCard(g, d, now, view),
        const SizedBox(height: 12),
        if (list.isNotEmpty)
          Container(
            key: const ValueKey('g-cap-hint'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: context.tokens.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.tokens.cardBorder),
            ),
            child: Text(
              '单周期建议 ≤ $kMaxOkrPerPeriod 个 O · 当前 ${list.length}/$kMaxOkrPerPeriod，超出时创建入口将提醒收敛',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: kGoalsMuted),
            ),
          )
        else
          _emptyCard(period, d),
        // 新建虚线钮（原型 L1240）
        GestureDetector(
          key: const ValueKey('g-new'),
          onTap: () => _newGoal(period, d),
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: context.tokens.cardBorder,
                  width: 2,
                  style: BorderStyle.solid),
            ),
            child: const Text('+ 新建目标（O ＋ 2~4 个 KR）',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: kGoalsMuted)),
          ),
        ),
        // 季度复盘引导卡（原型 L1241-1244）
        GestureDetector(
          key: const ValueKey('g-review-entry'),
          onTap: () => _push(const GoalReviewPage()),
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.tokens.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.tokens.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('季度复盘引导 · KPT',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                    Text(_reviewEntryHint(d, now),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: context.tokens.accent)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                    'Keep 做对了什么 / Problem 做错了什么 / Try 下季度怎么改 · 逐 O 对照 KR 达成度',
                    style: TextStyle(fontSize: 11, color: kGoalsMuted)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// O 卡（原型 renderOkr 卡片模板）。
  Widget _okrCard(Goal g, GoalsData d, DateTime now, String view) {
    final gArch = d.isArchived(g.period);
    final showChip = view == 'year' || gArch || g.period == GoalPeriod.yearBucket;
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return GestureDetector(
      key: ValueKey('g-okr-${g.id}'),
      onTap: () => _push(GoalDetailPage(goalId: g.id!)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.cardBorder),
        ),
        child: Opacity(
          opacity: gArch ? .8 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(g.title,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  if (showChip)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: GoalsTag(
                        g.period == GoalPeriod.yearBucket && !gArch
                            ? '年度目标'
                            : '${g.period}${gArch ? ' · 归档' : ''}',
                        muted: gArch || view == 'year',
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text('${g.pct}%',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: gArch ? kGoalsMuted : tokens.accent)),
                ],
              ),
              const SizedBox(height: 8),
              GoalsBar(pct: g.pct, height: 6, gray: gArch),
              const SizedBox(height: 12),
              for (final k in g.krs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(k.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: kGoalsMuted)),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: GoalsBar(
                          pct: k.progressPct,
                          height: 5,
                          solid: k.progressPct >= 100
                              ? kGoalsEmerald
                              : (k.progressPct > 0 ? null : kGoalsMuted),
                          gray: k.progressPct == 0 && gArch,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 36,
                        child: Text('${k.progressPct}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: k.progressPct >= 100
                                    ? kGoalsEmerald
                                    : scheme.onSurface)),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        gArch
                            ? '归档周期保留最终达成口径 · 复盘已关联'
                            : '进度由关联数据自动汇聚（联动 L3/L4/L5 · 可手动回填）',
                        style: const TextStyle(
                            fontSize: 10, color: kGoalsMuted),
                      ),
                    ),
                    Text('详情 ›',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: tokens.accent)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 空态卡（HG-D6：引导 + 双钮）。
  Widget _emptyCard(String period, GoalsData d) {
    return Container(
      key: const ValueKey('g-empty'),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 14),
      decoration: BoxDecoration(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tokens.cardBorder),
      ),
      child: Column(
        children: [
          const Text('本周期还没有目标。\n可从上一周期复制，或新建 2~4 个 KR 的目标。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.9, color: kGoalsMuted)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MiniBtn(
                key: const ValueKey('g-new-empty'),
                icon: Icons.add,
                label: '新建目标',
                onTap: () => _newGoal(period, d),
              ),
              const SizedBox(width: 8),
              MiniBtn(
                key: const ValueKey('g-copy-prev'),
                icon: Icons.copy_all_outlined,
                label: '复制上期目标',
                onTap: () => _copyPrev(period, d),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 复盘引导卡右侧提示（实算：存在已归档复盘 → 上季复盘已归档）。
  String _reviewEntryHint(GoalsData d, DateTime now) {
    return d.reviews.any((r) => r.archived) ? '上季复盘已归档 ›' : '进入 ›';
  }
}
