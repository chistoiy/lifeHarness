import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_calc.dart';
import '../domain/health_drug.dart';
import '../domain/health_models.dart';
import 'health_providers.dart';

/// 工作台用药卡（原型 `p-health` 第五卡＝目标/喝水/睡眠/运动/**用药** 的末张 · 批5）：
/// 今日 o/t 读数＋至多五枚槽位 chips。
///
/// 单独成件而不塞回 `health_home_page.dart`＝那个文件已贴着 1200 行体积闸（批4 运动卡就吃掉一大截）。
///
/// 三条口径写在最近处：
/// · 读数与 chips **同吃一份 `MedBundle`**（`healthMedProvider` 一次取齐），所以这张卡的「2/4 次 · 今日」
///   与 `/health/med` 顶部那一行永远同数——两处各开各的查询必然出现错位帧；
/// · 计划位为 0（一支档案都没建）读数出「—」不出「0/0」：0 次没吃与根本没计划是两回事；
/// · chips 只铺前 5 枚（`mdChipsShown`），余下收进「+n 全部」整枚跳管理屏（原型 `hRenderMedChips`
///   同形）；点 chip＝**就地打卡/撤销**，不跳屏、不弹确认，写库后 tick++ 让卡／管理屏／概览同帧重算。
class HealthMedCard extends ConsumerWidget {
  const HealthMedCard({super.key});

  static const Key kPlan = ValueKey('health-med-plan');
  static const Key kChips = ValueKey('health-med-chips');
  static const Key kEmpty = ValueKey('health-med-empty');
  static const Key kMore = ValueKey('health-med-more');
  static const Key kManage = ValueKey('health-med-manage');

  /// 槽位 chip 的 key 前缀（`health-med-chip-<药id>-<时刻>`）。
  static Key chipKey(MedSlot s) => ValueKey('health-med-chip-${s.drugId}-${s.time}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final b = ref.watch(healthMedProvider).valueOrNull;
    final plan = b == null ? (t: 0, o: 0) : mdPlan(b.drugs, b.todayLogs);
    final slots = b == null ? const <MedSlot>[] : mdSlots(b.drugs, b.todayLogs);
    final more = mdChipsMoreTx(slots.length);
    // 打卡写的是「卡上看到的那一天」：加载未完时没 chips 可点，回落当天只为让类型闭合。
    final date = b?.date ?? dayKey(ref.read(healthClockProvider)());

    return Container(
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_services_outlined, size: 15, color: context.tokens.accent),
              const SizedBox(width: 4),
              const Text('用药',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                key: kManage,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact),
                onPressed: () => context.push('/health/med'),
                child: Text('管理 ›',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(mdPlanRead(plan),
              key: kPlan,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (slots.isEmpty)
            Text(medChipEmptyTx,
                key: kEmpty,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))
          else
            Wrap(
              key: kChips,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in mdChipsShown(slots))
                  PillChip(
                    key: chipKey(s),
                    label: mdSlotTx(s),
                    selected: s.taken,
                    onTap: () => _tap(context, date, s),
                  ),
                if (more != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: TextButton(
                      key: kMore,
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact),
                      onPressed: () => context.push('/health/med'),
                      child: Text(more,
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w800, color: context.tokens.accent)),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// 打卡／撤销（原型 `hMedTap`）：跨 await 之后只用 container，不带发起页的失效 ref。
  Future<void> _tap(BuildContext context, String date, MedSlot s) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final pid = container.read(activeHealthProfileProvider);
    final repo = container.read(healthRepositoryProvider);
    if (s.taken) {
      await repo.undoDrugLog(pid, s.drugId, date, s.time);
    } else {
      await repo.logDrug(DrugLog(
          profileId: pid, drugId: s.drugId, date: date, time: s.time, state: 'taken'));
    }
    container.read(healthTickProvider.notifier).state++;
    if (!context.mounted) return; // 等库之后才用 context 出提示条
    AppToast.show(context, medTapTx(s.time, s.name, !s.taken));
  }
}
