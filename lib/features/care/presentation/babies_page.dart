import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/care_repository.dart';
import '../domain/care_models.dart';
import 'baby_sheets.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// p-babies 宝宝档案（多宝宝 CRUD + 记录人身份 CRUD + 过敏史展示 + V1.x 过渡卡）。
class BabiesPage extends ConsumerWidget {
  const BabiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(careDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('宝宝档案'),
            Text('多宝宝 · 记录人身份',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            const Text('宝宝档案',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final b in d.babies)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _babyCard(context, ref, b,
                    current: b.id == d.currentBaby?.id, count: d.logCounts[b.id] ?? 0),
              ),
            OutlinedButton(
              key: const ValueKey('add-baby'),
              onPressed: () => showAddBabySheet(context),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('+ 新增宝宝档案', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 14),
            _carerCard(context, ref, d),
            const SizedBox(height: 12),
            _allergyCard(context, ref, d),
            const SizedBox(height: 12),
            Opacity(
              opacity: .7,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: const [
                        Text('👶→🧒 成长过渡',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        SizedBox(width: 6),
                        _VChip('V1.x'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('宝宝满 3 岁后档案归档，喂养记录转为历史只读，里程碑并入日记年度回顾。',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _babyCard(BuildContext context, WidgetRef ref, CareBaby b,
      {required bool current, required int count}) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: context.cardDecoration.copyWith(
        border: current
            ? Border.all(color: tokens.accent, width: 2)
            : Border.all(color: tokens.cardBorder),
      ),
      child: Row(
        children: [
          CareAvatar(baby: b),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(b.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: tokens.cardBorder,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(b.sex,
                          style: const TextStyle(
                              fontSize: 9, color: Colors.grey)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${careAgeText(b.birth, DateTime.now())} · 生日 ${careDayKey(b.birth)} · 累计 $count 条记录',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (current)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: careGrad(kCycleHeroStops),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('当前',
                  style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
            )
          else
            GestureDetector(
              key: ValueKey('switch-${b.id}'),
              onTap: () async {
                await ref.read(careRepositoryProvider).setCurBaby(b.id);
                careTouch(ref);
              },
              child: const _MiniBtn('切换'),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            key: ValueKey('edit-${b.id}'),
            onTap: () => showAddBabySheet(context, edit: b),
            child: const Text('编辑',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _carerCard(BuildContext context, WidgetRef ref, CareData d) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('记录人身份',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 6,
            children: [
              for (final c in d.carers)
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        key: ValueKey('carer-${c.name}'),
                        onTap: () async {
                          await ref.read(careRepositoryProvider).setCurCarer(c.name);
                          careTouch(ref);
                        },
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: c.name == d.curCarer ? tokens.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: c.name == d.curCarer ? tokens.accent : tokens.cardBorder),
                          ),
                          child: Text(
                            c.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.name == d.curCarer ? Colors.white : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => showCarerSheet(context, edit: c),
                      child: const Text('改名',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                    GestureDetector(
                      key: ValueKey('carer-del-${c.name}'),
                      onTap: () async {
                        final repo = ref.read(careRepositoryProvider);
                        final removed = await repo.delCarer(c.id);
                        careTouch(ref);
                        if (context.mounted && removed == null) {
                          AppToast.show(context, '至少保留一个记录人身份');
                        } else if (context.mounted) {
                          AppToast.show(context, '已删除身份「$removed」· 历史记录中的署名保留');
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text('×',
                            style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ),
                    ),
                  ],
                ),
              GestureDetector(
                key: const ValueKey('carer-add'),
                onTap: () => showCarerSheet(context),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.cardBorder)),
                  child: const Text('＋ 添加',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('每条记录自动带上当时选中的记录人 · 可在记录详情中修改',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _allergyCard(BuildContext context, WidgetRef ref, CareData d) {
    final baby = d.currentBaby;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('过敏史 · ${baby?.name ?? '—'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              GestureDetector(
                key: const ValueKey('ala-add'),
                onTap: baby == null
                    ? null
                    : () => showAllergySheet(context, forProfile: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: context.tokens.cardBorder)),
                  child: const Text('＋ 添加', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (d.allergies.isEmpty)
            const Text('暂无已记录的过敏食物',
                style: TextStyle(fontSize: 11, color: Colors.grey))
          else
            for (final a in d.allergies)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: context.tokens.cardBorder.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Text('⚠️ ', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.food,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                            if (a.reaction?.isNotEmpty ?? false)
                              Text(a.reaction!,
                                  style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        key: ValueKey('ala-del-${a.id}'),
                        onTap: () async {
                          await ref
                              .read(careRepositoryProvider)
                              .delAllergy(a.id!);
                          careTouch(ref);
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text('×', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: context.tokens.accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: context.tokens.accent)),
      );
}

class _VChip extends StatelessWidget {
  const _VChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
