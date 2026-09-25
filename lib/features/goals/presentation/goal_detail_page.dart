import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/goal_calc.dart';
import '../domain/goal_models.dart';
import 'goal_edit_page.dart';
import 'goal_review_page.dart';
import 'goals_kit.dart';
import 'goals_providers.dart';

/// P10a 目标详情（原型 renderGoalDetail 4122-4146 对译）。
///
/// hero 环（实算 pct）+ 截止/剩 N 天 + 归档徽标；KR 卡（手动/自动汇聚 chip、
/// 进度、当前/目标、回填弹层、来源明细弹层、每日 00:00 自动重算行）；
/// 汇聚口径说明卡；归档态=复制+查看最近复盘，非归档=编辑+加入复盘。
class GoalDetailPage extends ConsumerStatefulWidget {
  const GoalDetailPage({required this.goalId, super.key});

  final int goalId;

  @override
  ConsumerState<GoalDetailPage> createState() => _GoalDetailPageState();
}

class _GoalDetailPageState extends ConsumerState<GoalDetailPage> {
  void _toast(String msg) => AppToast.show(context, msg);

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  /// 回填弹层：数字输入 + 保存 → bumpKr（kind 手动回填留痕）。
  Future<void> _bumpSheet(GoalKr k) async {
    final ctl = TextEditingController(text: k.curText);
    final v = await showGoalsSheet<double>(context,
        title: '回填进度 · ${k.label}',
        builder: (bc) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('g-bump-input'),
                  controller: ctl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: false),
                  decoration: const InputDecoration(
                      labelText: '当前值', suffixText: '（进度不可回退）'),
                ),
                const SizedBox(height: 6),
                Text('目标 ${k.tgtText} ${k.unit} · 回填后进度即时生效',
                    style: const TextStyle(
                        fontSize: 11, color: kGoalsMuted)),
                const SizedBox(height: 12),
                GradButton(
                  key: const ValueKey('g-bump-save'),
                  label: '保存回填',
                  onTap: () => Navigator.pop(bc, double.tryParse(ctl.text) ?? k.cur),
                ),
              ],
            ));
    if (v == null || !mounted) return;
    final cur = v < k.cur ? k.cur : v; // 进度只进不退（回填口径）
    await ref
        .read(goalsRepositoryProvider)
        .bumpKr(k.id!, cur, note: '手动回填');
    if (!mounted) return;
    goalsTouch(ref);
    final shown = cur == cur.roundToDouble() ? cur.toInt().toString() : '$cur';
    _toast('${k.label} 已回填 $shown/${k.tgtText} ${k.unit}');
  }

  /// 来源明细弹层：kr_updates 留痕（最近在前）+ 来源标签。
  Future<void> _sourceSheet(GoalKr k) async {
    await showGoalsSheet<void>(context,
        title: '来源明细 · ${k.label}',
        builder: (bc) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GoalsTag(k.source == KrSource.manual ? '手动' : '自动汇聚',
                        muted: k.source == KrSource.manual),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('数据源：${k.source.label} · 每日 00:00 自动重算',
                          style: const TextStyle(
                              fontSize: 11, color: kGoalsMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: k.updates.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('暂无回填与汇聚留痕',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: kGoalsMuted)),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final u in k.updates.reversed.toList())
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 58,
                                      child: Text(
                                          u.kind == 'manual' ? '手动回填' : '自动汇聚',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800)),
                                    ),
                                    Expanded(
                                      child: Text(
                                          '${u.note ?? ''} cur=${u.cur == u.cur.roundToDouble() ? u.cur.toInt() : u.cur}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: kGoalsMuted)),
                                    ),
                                    Text(goalsStamp(u.at),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: kGoalsMuted)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ));
  }

  /// 归档态复制为新周期目标（原型 goalCopy：目标=进行中周期）。
  Future<void> _copyToCurrent(Goal g, GoalsData d) async {
    final now = ref.read(goalsClockProvider)();
    final tgt = GoalPeriod.current(now);
    final id =
        await ref.read(goalsRepositoryProvider).copySingleGoal(g.id!, tgt);
    if (!mounted) return;
    if (id == null) {
      _toast('目标数量上限提醒：$tgt 已有 $kMaxOkrPerPeriod 个 O，建议先归档/收敛一个');
      return;
    }
    goalsTouch(ref);
    _toast('已复制为 $tgt 新目标 · 进度已清零');
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
            const Text('目标详情'),
            Builder(builder: (context) {
              final g = async.valueOrNull?.goals
                  .where((x) => x.id == widget.goalId)
                  .firstOrNull;
              return Text(
                  g == null
                      ? ''
                      : '${g.title.split(' ').first} · ${g.period}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.normal,
                      color: Theme.of(context).colorScheme.onSurfaceVariant));
            }),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final g =
              d.goals.where((x) => x.id == widget.goalId).firstOrNull;
          if (g == null) {
            return const Center(
                child:
                    Text('目标已删除', style: TextStyle(color: kGoalsMuted)));
          }
          return _body(g, d, now);
        },
      ),
    );
  }

  Widget _body(Goal g, GoalsData d, DateTime now) {
    final arch = d.isArchived(g.period);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final (start, end) = GoalPeriod.range(g.period, now);
    final endDate = end.subtract(const Duration(days: 1));
    final today = DateTime(now.year, now.month, now.day);
    final remain = endDate.difference(today).inDays;
    final state = GoalPeriod.stateLabel(g.period, d.archivedPeriods, now);
    final dueText = arch
        ? ' · 已归档'
        : state.startsWith('未开始')
            ? ' · 未开始'
            : remain >= 0
                ? '（剩 $remain 天）'
                : ' · 已结束';
    assert(start.isBefore(end));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        // hero 环卡
        Container(
          key: const ValueKey('g-hero'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.cardBorder),
          ),
          child: Row(
            children: [
              GoalsRing(pct: g.pct, gray: arch),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.title,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                        '${g.period} · ${g.krs.length} 个 KR · 截止 '
                        '${goalsMonthDay(endDate)}$dueText',
                        style: const TextStyle(
                            fontSize: 10, color: kGoalsMuted)),
                    if (arch)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: GoalsTag('归档周期 · 只读 · 保留最终达成口径', muted: true),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // KR 卡族
        for (var i = 0; i < g.krs.length; i++)
          Container(
            key: ValueKey('g-detail-$i'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(g.krs[i].label,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 6),
                    GoalsTag(
                        g.krs[i].source == KrSource.manual ? '手动' : '自动汇聚',
                        muted: g.krs[i].source == KrSource.manual),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GoalsBar(
                          pct: g.krs[i].progressPct,
                          height: 8,
                          gray: arch,
                          solid: g.krs[i].progressPct >= 100 && !arch
                              ? kGoalsEmerald
                              : null),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      child: Text('${g.krs[i].progressPct}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                            style: const TextStyle(
                                fontSize: 11, color: kGoalsMuted),
                            children: [
                              const TextSpan(text: '当前 '),
                              TextSpan(
                                text: g.krs[i].curText,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurface),
                              ),
                              TextSpan(
                                  text:
                                      ' / 目标 ${g.krs[i].tgtText} ${g.krs[i].unit}'),
                            ]),
                      ),
                    ),
                    if (!arch)
                      MiniBtn(
                        key: ValueKey('g-kr-bump-$i'),
                        icon: Icons.edit_outlined,
                        label: '回填进度',
                        onTap: () => _bumpSheet(g.krs[i]),
                      ),
                    const SizedBox(width: 6),
                    MiniBtn(
                      key: ValueKey('g-kr-detail-$i'),
                      label: '来源明细',
                      onTap: () => _sourceSheet(g.krs[i]),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('数据源：${g.krs[i].source.label} · 每日 00:00 自动重算',
                    style:
                        const TextStyle(fontSize: 10, color: kGoalsMuted)),
              ],
            ),
          ),
        // 汇聚口径说明卡（联动元信息，原型逐字）
        GoalsNoteCard(
          '汇聚口径：关联待办完成数 / 阅读本数 / 日记篇数 / 习惯打卡 / 记账结余自动计算 KR；'
          '关闭「自动汇聚」后该 KR 转手动回填。'
          '${arch ? '归档周期数据冻结在期末时点。' : ''}',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: arch
                  ? GradButton(
                      key: const ValueKey('g-detail-copy'),
                      icon: Icons.copy_all_outlined,
                      label: '复制为新周期目标',
                      onTap: () => _copyToCurrent(g, d),
                    )
                  : GradButton(
                      key: const ValueKey('g-detail-edit'),
                      icon: Icons.edit_outlined,
                      label: '编辑目标',
                      onTap: () => _push(GoalEditPage(
                          goalId: g.id,
                          onDeleted: () => Navigator.pop(context))),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlineButton(
                key: arch
                    ? const ValueKey('g-detail-review')
                    : const ValueKey('g-detail-add-review'),
                label: arch ? '查看最近复盘' : '加入复盘',
                onTap: arch
                    ? () => _push(const GoalReviewPage())
                    : () => _toast('本目标已加入「季度复盘」对照清单'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
