import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_calc.dart';
import '../domain/health_drug.dart';
import '../domain/health_models.dart';
import 'health_goal_row.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 用药管理（原型 `p-med` · 路由 `/health/med` · 批5）。
///
/// 四块（概览／药品卡／设置卡／脚注）共用**同一份 `MedBundle`**（档案＋今日打卡＋近 7 天分层，
/// 一次取齐），四条口径写在最近处：
/// · 打卡只有「已服」与「无行＝待服」两态（`skipped` 与 `note` 本期无写点，工单 §2 偏离①），
///   所以卡内按钮点一下就是 待服 ⇄ 已服用·可撤销；
/// · 删除＝**归档**：卡列表与今日计划当场少一支，历史流水一行不动（原型 toast 原话真做到）；
/// · 近 7 天热力**按单药算**（原型在每张卡里调全局 `hMedPlan`，所有卡的同一行都会一模一样＝假精确）；
/// · 漏服宽限用**就地内嵌滚轮**（点行展开、选档当场生效），改档后卡头徽标当场增减——
///   「设置必须当场生效」是本仓硬口径，原型 p-med 上没有这块徽标（偏离③）。
class HealthMedPage extends ConsumerWidget {
  const HealthMedPage({super.key});

  static const Key kSummary = ValueKey('hmed-summary');
  static const Key kCards = ValueKey('hmed-cards');
  static const Key kSettings = ValueKey('hmed-settings');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(healthTickProvider);
    final bundle = ref.watch(healthMedProvider);
    final profiles = (ref.watch(healthProfilesProvider).valueOrNull ?? const <HealthProfile>[])
        .where((p) => !p.archived)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('用药'),
        actions: [
          IconButton(
            key: const ValueKey('hmed-add'),
            tooltip: '新增药品',
            icon: const Icon(Icons.add),
            onPressed: () => showHealthDrugSheet(context),
          ),
        ],
      ),
      body: bundle.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '用药档案没加载出来',
          error: e,
          onRetry: () => ref.invalidate(healthMedProvider),
        ),
        data: (b) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _profileBar(context, ref, profiles),
            const SizedBox(height: 8),
            _summary(context, ref, b),
            const SizedBox(height: 12),
            _drugCards(context, ref, b),
            const SizedBox(height: 12),
            _addRow(context),
            const SizedBox(height: 12),
            _settingsCard(context, ref, b),
            const SizedBox(height: 14),
            Text(medFootnoteTx,
                key: const ValueKey('hmed-footnote'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ==================== 档案 chips（切档案即整模块重取，跨档案不聚合） ====================

  Widget _profileBar(BuildContext context, WidgetRef ref, List<HealthProfile> profiles) {
    final cur = ref.watch(activeHealthProfileProvider);
    return SizedBox(
      height: 30,
      child: ListView(
        key: const ValueKey('hmed-bar'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in profiles)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                key: ValueKey('hmed-profile-${p.id}'),
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

  // ==================== 今日概览（计划／已服／依从／漏服／症状关联） ====================

  Widget _summary(BuildContext context, WidgetRef ref, MedBundle b) {
    final scheme = Theme.of(context).colorScheme;
    final plan = mdPlan(b.drugs, b.todayLogs);
    final missed = mdMissedTotal(
        b.drugs, b.todayLogs, mdNowMin(ref.watch(healthClockProvider)()),
        graceMin: ref.watch(healthSettingsProvider).missedGraceMin());
    final badge = mdMissedBadgeTx(missed);
    final symRelated = (ref.watch(healthSymptomProvider).valueOrNull ?? const <SymptomRecord>[])
        .where((s) => s.drugRelated)
        .length;

    return Container(
      key: kSummary,
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(mdPlanRead(plan),
                    key: const ValueKey('hmed-plan'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ),
              Text('依从 ${mdRateTx(mdCompliance(b.drugs, b.todayLogs))}',
                  key: const ValueKey('hmed-rate'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: context.tokens.accent)),
            ],
          ),
          const SizedBox(height: 6),
          // 漏服徽标只在 n>0 时出现（摆一枚「今日漏服 0 次」是把没发生的事说成发生了）。
          if (badge == null)
            Text('今日无漏服',
                key: const ValueKey('hmed-missed-none'),
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))
          else
            Text(badge,
                key: const ValueKey('hmed-missed'),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: scheme.error)),
          const SizedBox(height: 6),
          InkWell(
            key: const ValueKey('hmed-sym-link'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.push('/health/symptom'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.link, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(mdSymLinkTx(symRelated),
                        key: const ValueKey('hmed-sym-tx'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  ),
                  Text('›', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 药品卡列表 ====================

  Widget _drugCards(BuildContext context, WidgetRef ref, MedBundle b) {
    if (b.drugs.isEmpty) {
      return EmptyDashRow(key: const ValueKey('hmed-empty'), text: medEmptyTx);
    }
    final nowMin = mdNowMin(ref.watch(healthClockProvider)());
    final grace = ref.watch(healthSettingsProvider).missedGraceMin();
    return Column(
      key: kCards,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in b.drugs) //
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _drugCard(context, b, d, nowMin, grace),
          ),
      ],
    );
  }

  Widget _drugCard(BuildContext context, MedBundle b, DrugPlan d, int nowMin,
      int grace) {
    final scheme = Theme.of(context).colorScheme;
    final logs = b.todayLogs[d.id] ?? const <String, String>{};
    final heat = mdHeatRow(drug: d, days: b.days, byDay: b.byDay);
    final missed = mdMissedOf(d, logs, nowMin, graceMin: grace);
    return Container(
      key: ValueKey('hmed-card-${d.id}'),
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.tokens.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.medical_services_outlined,
                    size: 16, color: context.tokens.accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(mdCardSub(d),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                key: ValueKey('hmed-del-${d.id}'),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _archive(context, d),
                child: Text('删除',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: scheme.error)),
              ),
            ],
          ),
          if (missed > 0) ...[
            const SizedBox(height: 8),
            Text(mdMissedBadgeTx(missed)!,
                key: ValueKey('hmed-card-missed-${d.id}'),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: scheme.error)),
          ],
          const SizedBox(height: 10),
          for (final t in d.times)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _slotRow(context, d, t, slotTaken(logs, t)),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text('按时刻提醒',
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
              ),
              Switch(
                key: ValueKey('hmed-rem-${d.id}'),
                value: d.remind,
                onChanged: (v) => _setRemind(context, d, v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('近 7 天打卡',
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          _heatRow(context, d, heat),
        ],
      ),
    );
  }

  /// 时刻行：时间＋状态文案＋打卡/撤销（原型 `hRenderMeds` 每行末的 mini-btn）。
  Widget _slotRow(BuildContext context, DrugPlan d, String t, bool taken) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('hmed-slot-${d.id}-$t'),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: taken ? context.tokens.accent.withValues(alpha: .08) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(t,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: taken ? context.tokens.accent : scheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(mdSlotStateTx(taken),
                style: TextStyle(
                    fontSize: 9.5, color: taken ? context.tokens.accent : scheme.onSurfaceVariant)),
          ),
          TextButton(
            key: ValueKey('hmed-tap-${d.id}-$t'),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact),
            onPressed: () => _tapSlot(context, d, t, taken),
            child: Text(mdSlotBtnTx(taken),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  /// 近 7 天三档格（旧→新）。无计划的日（`t=0`）**不画成达标格**——`mdHeatDay` 的 `t>0` 守卫
  /// 就是这条，摘掉它会让「一支还没开始吃的药」看起来天天吃满（变异刀2 靶）。
  Widget _heatRow(BuildContext context, DrugPlan d, List<MedDay> heat) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: ValueKey('hmed-heat-${d.id}'),
      children: [
        for (var i = 0; i < heat.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == heat.length - 1 ? 0 : 4),
              child: Container(
                key: ValueKey('hmed-heat-${d.id}-$i'),
                height: 18,
                decoration: BoxDecoration(
                  color: switch (heat[i].heat) {
                    MdHeat.full => const Color(mdHeatFullHex),
                    MdHeat.part => const Color(mdHeatPartHex).withValues(alpha: .9),
                    MdHeat.none => scheme.onSurface.withValues(alpha: .06),
                  },
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ==================== 新增入口 ====================

  Widget _addRow(BuildContext context) => OutlinedButton.icon(
        key: const ValueKey('hmed-add-btn'),
        onPressed: () => showHealthDrugSheet(context),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('＋ 新增药品', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
      );

  // ==================== 设置卡（三行：总开关／免打扰时段／漏服宽限） ====================

  Widget _settingsCard(BuildContext context, WidgetRef ref, MedBundle b) {
    final scheme = Theme.of(context).colorScheme;
    final st = ref.watch(healthSettingsProvider);
    final grace = st.missedGraceMin();
    // 窗口文案从判据反推（写死字面量会在窗口改了之后继续谎报；用例探 22:59/23:00/06:59/07:00）。
    final dnd = mdDndTx(NotificationService.inDndWindow, ref.watch(healthClockProvider)());
    final allOn = mdRemindAllOn(b.drugs);

    return Container(
      key: kSettings,
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('全部药品提醒',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
              Switch(
                key: const ValueKey('hmed-rem-all'),
                value: allOn,
                onChanged: (v) => _setAllRemind(context, b, v),
              ),
            ],
          ),
          Text('开关会覆写所有在册档案（不记得单药原状态）',
              key: const ValueKey('hmed-rem-all-hint'),
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
          const Divider(height: 14),
          InkWell(
            key: const ValueKey('hmed-dnd'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.push('/settings/notify'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                      child: Text('免打扰时段',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
                  Text(dnd ?? '未设置免打扰时段',
                      key: const ValueKey('hmed-dnd-tx'),
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800, color: context.tokens.accent)),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const Divider(height: 14),
          HealthGoalRow(
            rowKey: const ValueKey('hmed-grace-row'),
            wheelKey: const ValueKey('hmed-grace-wheel'),
            icon: Icons.notifications_paused_outlined,
            label: '漏服提醒',
            hint: '超过这个时长仍未打卡算漏服',
            valueText: medGraceTx(grace),
            labels: [for (final g in medGraceOptions) '$g 分钟'],
            currentIndex: medGraceOptions.indexOf(grace).clamp(0, medGraceOptions.length - 1),
            onChanged: (i) => _setGrace(context, medGraceOptions[i]),
          ),
        ],
      ),
    );
  }

  // ==================== 写路径（全部走 HealthRepository，之后 tick++ 整屏重取） ====================

  /// 打卡／撤销：无行＝待服 → 写 `taken`；已服 → 删行回到待服（两态口径见类注释）。
  Future<void> _tapSlot(
      BuildContext context, DrugPlan d, String t, bool taken) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(healthRepositoryProvider);
    final date = dayKey(container.read(healthClockProvider)());
    if (taken) {
      await repo.undoDrugLog(d.profileId, d.id!, date, t);
    } else {
      await repo.logDrug(DrugLog(
          profileId: d.profileId, drugId: d.id!, date: date, time: t, state: 'taken'));
    }
    container.read(healthTickProvider.notifier).state++;
    if (!context.mounted) return; // 等库之后才用 context 出提示条
    AppToast.show(context, medTapTx(t, d.name, !taken));
  }

  Future<void> _setRemind(
      BuildContext context, DrugPlan d, bool on) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthRepositoryProvider).setDrugRemind(d.profileId, d.id!, on);
    container.read(healthTickProvider.notifier).state++;
    if (!context.mounted) return;
    AppToast.show(context, on ? medRemOnTx : medRemOffTx);
  }

  /// 总开关＝**全量覆写**非归档行（原型 `tgMedAll` 语义，偏离⑤）；没有在册档案时给一句实话。
  Future<void> _setAllRemind(
      BuildContext context, MedBundle b, bool on) async {
    if (b.drugs.isEmpty) {
      AppToast.show(context, medNoDrugTx);
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final pid = container.read(activeHealthProfileProvider);
    await container.read(healthRepositoryProvider).setAllDrugRemind(pid, on);
    container.read(healthTickProvider.notifier).state++;
    if (!context.mounted) return;
    AppToast.show(context, on ? medAllOnTx : medAllOffTx);
  }

  /// 删除＝归档（历史流水保留，卡列表与今日计划当场少一支）。
  Future<void> _archive(BuildContext context, DrugPlan d) async {
    final ok = await lhConfirm(context, medDelConfirmTx(d.name));
    if (!ok || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthRepositoryProvider).archiveDrug(d.profileId, d.id!);
    container.read(healthTickProvider.notifier).state++;
    if (!context.mounted) return; // 确认＋写库两段 await 之后才用 context
    AppToast.show(context, medDeletedTx);
  }

  /// 宽限改档当场生效：设置重取 → 漏服徽标与概览同帧重算（不留「要退出重进才更新」的缝）。
  Future<void> _setGrace(BuildContext context, int v) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthSettingsProvider).setMissedGrace(v);
    if (!context.mounted) return;
    container.invalidate(healthSettingsProvider);
    container.read(healthTickProvider.notifier).state++;
  }
}
