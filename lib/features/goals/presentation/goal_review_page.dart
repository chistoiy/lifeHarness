import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/share_card.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/goal_calc.dart';
import '../domain/goal_models.dart';
import 'goals_kit.dart';
import 'goals_providers.dart';

/// P10c 季度复盘 KPT（原型 renderGoalReview 4183-4209 对译）。
///
/// 口径：季 chips（已结束归档 + 当前撰写中，grIdx 本地态）；KR 达成对照表
/// 按该季 goals + 年度桶实算；KPT 三段归档后只读；保存复盘 → 转只读归档；
/// Try → 下季草稿（tryToNextDraft）后退回列表。
class GoalReviewPage extends ConsumerStatefulWidget {
  const GoalReviewPage({super.key});

  @override
  ConsumerState<GoalReviewPage> createState() => _GoalReviewPageState();
}

class _GoalReviewPageState extends ConsumerState<GoalReviewPage> {
  final _keep = TextEditingController();
  final _problem = TextEditingController();
  final _trial = TextEditingController();
  String? _selected;

  /// 已把内容装载进控制栏的周期（切 chip 才重载，避免回填打断输入）。
  String? _boundPeriod;

  @override
  void dispose() {
    _keep.dispose();
    _problem.dispose();
    _trial.dispose();
    super.dispose();
  }

  void _toast(String msg) => AppToast.show(context, msg);

  /// KPT 复盘分享卡（原型 scData('review') 同构；整体达成/均达＝该季各 O 进度均值）。
  ShareCardModel _shareReviewCard(String sel, List<Goal> goals, GoalReview rv) {
    final krCount = goals.fold<int>(0, (s, g) => s + g.krs.length);
    final avg = goals.isEmpty
        ? 0
        : (goals.fold<int>(0, (s, g) => s + g.pct) / goals.length).round();
    return ShareCardModel(
      file: '复盘-${sel.replaceAll(' ', '')}',
      eyebrow: 'LifeHarness · 季度复盘',
      title: '$sel KPT 复盘',
      line: '${goals.length} 个目标 · $krCount 条 KR · 已归档',
      big: '$avg%',
      unit: '整体达成',
      tiles: [
        ShareCardTile('目标', '${goals.length} 个'),
        ShareCardTile('KR', '$krCount 条'),
        ShareCardTile('均达', '$avg%'),
      ],
      sections: [
        ShareCardSection(head: 'KR 达成对照', rows: [
          for (final g in goals)
            for (final k in g.krs)
              ShareCardRow(k.label, '${k.progressPct}%'),
        ]),
        if (rv.keep.trim().isNotEmpty)
          ShareCardSection(head: 'Keep · 做对了什么', rows: [ShareCardRow(rv.keep)]),
        if (rv.problem.trim().isNotEmpty)
          ShareCardSection(head: 'Problem · 卡在哪', rows: [ShareCardRow(rv.problem)]),
        if (rv.trial.trim().isNotEmpty)
          ShareCardSection(head: 'Try · 下季怎么改', rows: [ShareCardRow(rv.trial)]),
      ],
    );
  }

  /// 当年「已结束或当前」四季：有归档/草稿复盘的季 + 当前季恒在。
  List<String> _chips(GoalsData d, DateTime now) {
    final cur = GoalPeriod.current(now);
    final out = <String>[];
    for (final q in GoalPeriod.quartersOfYear(now.year)) {
      final r = d.reviewFor(q);
      final isCur = q == cur;
      if (r == null && !isCur) continue;
      if (r != null && !r.archived && !isCur) continue; // 过去季只认归档
      out.add(q);
    }
    return out;
  }

  void _bind(String period, GoalsData d) {
    if (_boundPeriod == period) return;
    _boundPeriod = period;
    final r = d.reviewFor(period);
    _keep.text = r?.keep ?? '';
    _problem.text = r?.problem ?? '';
    _trial.text = r?.trial ?? '';
  }

  Future<void> _save(String period) async {
    await ref.read(goalsRepositoryProvider).saveReview(
        GoalReview(
            period: period,
            keep: _keep.text,
            problem: _problem.text,
            trial: _trial.text),
        asArchived: true);
    if (!mounted) return;
    goalsTouch(ref);
    _toast('复盘已保存 · 已转为只读归档视图');
  }

  Future<void> _draft(String period, DateTime now) async {
    final trial = _trial.text.trim();
    if (trial.isEmpty) {
      _toast('先在 Try 里写下改法');
      return;
    }
    final id = await ref
        .read(goalsRepositoryProvider)
        .tryToNextDraft(period, _trial.text);
    if (!mounted) return;
    if (id == null) {
      final to = GoalPeriod.nextQuarter(period, now);
      _toast('目标数量上限提醒：$to 已有 $kMaxOkrPerPeriod 个 O，建议先归档/收敛一个');
      return;
    }
    goalsTouch(ref);
    _toast('已从 Try 生成 ${GoalPeriod.nextQuarter(period, now)} 目标草稿 · 可在列表继续编辑');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(goalsClockProvider)();
    final async = ref.watch(goalsDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('季度复盘 · KPT'),
            Text('逐 O 对照 KR 达成 · Keep / Problem / Try',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => _body(d, now),
      ),
    );
  }

  Widget _body(GoalsData d, DateTime now) {
    final chips = _chips(d, now);
    final sel = _selected != null && chips.contains(_selected)
        ? _selected!
        : (chips.contains(GoalPeriod.current(now))
            ? GoalPeriod.current(now)
            : chips.last);
    _selected = sel;
    _bind(sel, d);
    final review = d.reviewFor(sel);
    final archived = review?.archived ?? false;
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;

    // 对照表：该季 goals + 年度桶，全部实算
    final goals = [...d.inPeriod(sel), ...d.inPeriod(GoalPeriod.yearBucket)];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < chips.length; i++)
              PillChip(
                key: ValueKey('g-review-q-$i'),
                label:
                    '${chips[i]} · ${d.reviewFor(chips[i])?.archived == true ? '已归档' : '撰写中'}',
                selected: chips[i] == sel,
                onTap: () => setState(() => _selected = chips[i]),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('g-review-table'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$sel KR 达成对照（自动汇聚）',
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (goals.isEmpty)
                Text(
                    archived
                        ? '该周期没有目标记录。'
                        : '季度结束后一键生成对照表；撰写中周期可随时预览。',
                    style: const TextStyle(
                        fontSize: 11, color: kGoalsMuted, height: 1.8))
              else
                for (final g in goals)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(g.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        Text('${g.pct}%',
                            key: ValueKey('g-review-pct-${g.id}'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: g.pct >= 70
                                    ? kGoalsEmerald
                                    : kGoalsAmber)),
                        const SizedBox(width: 8),
                        Text(
                            '${g.krs.where((k) => k.achieved).length}/${g.krs.length} KR 达成',
                            style: const TextStyle(
                                fontSize: 11, color: kGoalsMuted)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        for (final seg in [
          ('keep', 'Keep · 做对了什么（继续保持）', '哪几周节奏好？哪些习惯真正留下来了？', _keep),
          ('problem', 'Problem · 做错了什么（问题与卡点）', '没达成的 KR 卡在哪？外部干扰还是目标本身不合理？', _problem),
          ('trial', 'Try · 下季度怎么改（行动项）', '每个 Problem 至少配一条可执行的 Try；下季度 KR 从 Try 里选', _trial),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SectionCard(
              title: seg.$2,
              child: TextField(
                key: ValueKey('g-review-${seg.$1}'),
                controller: seg.$4,
                maxLines: 3,
                readOnly: archived,
                style: const TextStyle(fontSize: 12.5, height: 1.7),
                decoration: InputDecoration(
                    hintText: seg.$3,
                    filled: true,
                    fillColor: archived
                        ? scheme.surfaceContainerHighest.withValues(alpha: .5)
                        : scheme.surfaceContainerHighest,
                    border: InputBorder.none),
              ),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: archived
                  // 原型：归档态按钮行＝「分享复盘卡」（未归档仍是保存/Try 两钮）。
                  ? GradButton(
                      key: const ValueKey('g-review-share'),
                      label: '分享复盘卡',
                      icon: Icons.ios_share,
                      onTap: () => showShareCardSheet(
                          context, _shareReviewCard(sel, goals, review!),
                          src: '目标'),
                    )
                  : GradButton(
                      key: const ValueKey('g-review-save'),
                      label: '保存复盘',
                      onTap: () => _save(sel),
                    ),
            ),
            if (!archived) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlineButton(
                  key: const ValueKey('g-review-draft'),
                  label: 'Try → 下季草稿',
                  onTap: () => _draft(sel, now),
                ),
              ),
            ],
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
              'KPT 三段与笔记模块「周复盘模板（KPT）」同源 · 保存后可导出（联动 L15）',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: kGoalsMuted)),
        ),
      ],
    );
  }
}
