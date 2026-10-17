import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/media_item.dart';
import 'media_actions.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 记录页·影音游 tab（计划 §〇 S-01 的批2 落点）：真实影音架入口＋四类在册计数
/// ＋最近四条俯瞰（原型 #recMedia「桌面俯瞰」同段）。
///
/// 今日时长环没有会话即整行不渲染（不留 00:00 假读数）；名场面复习的落面在笔记库
/// 与条目详情，这里只补一行笔记库直达（批5 回灌）。
class MediaWorkbench extends ConsumerWidget {
  const MediaWorkbench({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(mediaKindCountsProvider).valueOrNull ?? const {};
    final recent = ref.watch(mediaRecentProvider).valueOrNull ?? const [];
    final noteTotal = ref.watch(mediaNoteTotalProvider).valueOrNull ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // 晚间补记提示行（dailyQ＝应用内、不占系统通知；今天还没有已结算计时才出＝§0.4）。
        if (ref.watch(mediaDailyQHintProvider).valueOrNull ?? false)
          Padding(
            key: const ValueKey('mds-dailyq-row'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.bolt_outlined,
                    size: 15, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '今天还没有计时 · 有空补记一条',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        // 影音架入口（点=直达架面，管理动作都在那边）
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('media-open-shelf'),
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              // 进架口吃设置屏默认视图/排序（原型 mOpenShelf＝LH-C23 铁口径①）。
              applyMediaShelfPrefs(
                  ProviderScope.containerOf(context, listen: false));
              context.push('/media/shelf');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    mdsKindIcon(MediaItem.kMovie),
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '影音架',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '在册 ${counts['all'] ?? 0}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: kMediaTabular,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 四类直达（角标＝该类在册条数，与架面 chip 同源）
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in MediaItem.kinds)
              ActionChip(
                key: ValueKey('media-kind-$k'),
                avatar: Icon(mdsKindIcon(k), size: 16),
                label: Text('${MediaItem.labelOf(k)} ${counts[k] ?? 0}'),
                onPressed: () {
                  applyMediaShelfPrefs(
                      ProviderScope.containerOf(context, listen: false));
                  context.push('/media/shelf?kind=$k');
                },
              ),
          ],
        ),
        // 计时中行（批3）：有在跑会话才出现，实时分钟随 mediaTick/分钟刷新。
        const _RunningRow(),
        const SizedBox(height: 14),
        // 影音资料入口（原型 mdsEntryBar「资料」一枚＝通用管理器，本批交付）
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('media-open-mgr'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/media/mgr'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '影音资料',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '来源 · 分组 · 创作者 · 发行 · 标签',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 影音笔记库入口（批5 回灌：原型入口条 m-notes 一枚＝Flutter 侧的直达行）
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('media-open-notes'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/media/notes'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '影音笔记库',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '笔记 $noteTotal',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: kMediaTabular,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        // 全站统计入口（批7 回灌：原型入口条 m-stat 一枚＝直达行）
        const SizedBox(height: 14),
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('media-open-stat'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/media/stat'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.donut_small_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '影音统计',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        // 影音单直达（批8b 回灌成句：列表面＝工作台一行，底稿置顶零落库）
        _EntryRow(
          key: const ValueKey('media-open-lists'),
          icon: Icons.playlist_play_outlined,
          title: '影音单',
          onTap: () => context.push('/media/lists'),
        ),
        // 目标屏直达（批8a：图标条「目标」一枚的 Flutter 形态＝直达行）
        _EntryRow(
          key: const ValueKey('media-open-goal'),
          icon: Icons.track_changes_outlined,
          title: '影音目标',
          onTap: () => context.push('/media/goal'),
        ),
        // 设置屏直达（批8a 拍板⑤：图标条第 8 枚「设置」的 Flutter 形态＝直达行）
        _EntryRow(
          key: const ValueKey('media-open-set'),
          icon: Icons.settings_outlined,
          title: '影音设置',
          onTap: () => context.push('/media/settings'),
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '桌面俯瞰 · 最近四条',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 172,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final x in recent)
                  SizedBox(
                    width: 106,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: MediaItemCard(
                        item: x,
                        onTap: () {
                          applyMediaShelfPrefs(
                              ProviderScope.containerOf(context, listen: false));
                          context.push('/media/shelf?kind=${x.kind}');
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 工作台「计时中」行（批3 面板第 4 项回灌）：只吃库内单活会话，
/// 无在跑会话＝整行不渲染（不留 00:00 假读数）。点行＝进沉浸计时页。
class _RunningRow extends ConsumerWidget {
  const _RunningRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mediaTickProvider);
    final s = ref.watch(mediaRunningSessionProvider).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final item = ref.watch(mediaItemDetailProvider(s.itemId)).valueOrNull;
    final title = item?.title ?? '影音';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InkWell(
        key: const ValueKey('media-running-row'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/media/timer/${s.itemId}'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: mdsStateColor('i').withValues(alpha: .10),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mdsStateColor('i'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '《$title》 · ${mediaTimerWord(s.kind)} ${mediaLiveMinutes(s)} 分钟',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 工作台直达行（图标＋题名＋可选副注＋chevron；批8a 目标/设置两枚入口共用）。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
