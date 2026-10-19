import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/journal_entry.dart';
import 'diary_edit_page.dart' show DiaryEditArg;
import 'journal_page.dart' show DiaryTabState;
import 'journal_providers.dart';
import 'widgets/diary_review_sheet.dart' show openDiaryPickSheet;
import 'widgets/journal_layout_kit.dart';
import 'widgets/journal_track_view.dart';
import 'widgets/journal_wall.dart';
extension JournalTrackUI on DiaryTabState {
  /// 轨道档滚动树：顶部月历图墙 + 日期块列表（批1a）。
  ///
  /// 图墙与日期块放在**同一条滚动**里（不是钉住的头）：图墙是「导航用」的，滚下去看内容时它该走开；
  /// 1b 要做的是把**日期块**吸附在顶部，那才需要 `SliverPersistentHeader`。
  Widget trackScroll(
    BuildContext context,
    WidgetRef ref,
    DateTime now,
    List<TrackDayBlock> blocks,
    Map<int, List<JournalEntry>> byDayAll,
  ) {
    final tokens = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        card(
          context,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: JournalWall(
              month: now,
              byDayFirst: {
                for (final b in blocks) b.day.day: b.entries.first,
              },
              moodColorOf: (e) =>
                  (e.mood == null) ? null : tokens.accent,
              onTapDay: (day) {
                final list = byDayAll[day];
                if (list == null || list.isEmpty) {
                  context.push('/journal/edit',
                      extra:
                          DiaryEditArg(day: DateTime(now.year, now.month, day)));
                } else {
                  openDiaryPickSheet(context, '${now.month}月$day日的日记', list);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        trackToolbar(context, ref),
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                '这个筛选下还没有日记',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          JournalTrackView(
            blocks: blocks,
            onOpenEntry: (e) => context
                .push('/journal/edit', extra: DiaryEditArg(entryId: e.id)),
          ),
      ],
    );
  }

  /// 轨道档工具栏：与列表档同一组（筛选 + 设置）。图墙自带月份，故这里不再出档位名。
  Widget trackToolbar(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          key: const ValueKey('diary-filter'),
          tooltip: '筛选',
          onPressed: () => diaryFilterSheet(
              context, ref, ref.read(journalFilterProvider), const <String>[]),
          icon: const Icon(Icons.filter_alt_outlined, size: 22),
        ),
        IconButton(
          key: const ValueKey('diary-set'),
          tooltip: '视图设置',
          onPressed: () =>
              showSetSheet(context, ref, ref.read(journalLayoutProvider)),
          icon: const Icon(Icons.tune, size: 22),
        ),
      ],
    );
  }

  /// 视图设置弹层（批1a）：三档横向三宫格，选中＝主色描边 + 淡底。
  ///
  /// 为什么不把三档直接铺在页面顶行：三个档名（日期轨道/列表/INS 卡片流）加起来太宽，
  /// 顶行右侧还要放筛选与设置两枚钮，512px 机身放不下；收进弹层后顶行只留两枚图标钮。
  Future<void> showSetSheet(
      BuildContext context, WidgetRef ref, String cur) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bc) {
        final tokens = bc.tokens;
        final scheme = Theme.of(bc).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('日记设置',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var j = 0; j < kJournalLayoutsOrdered.length; j++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: j == kJournalLayoutsOrdered.length - 1
                                  ? 0
                                  : 8),
                          child: _layoutOption(
                              bc, ref, kJournalLayoutsOrdered[j], cur),
                        ),
                      ),
                  ],
                ),
                // 2026-10-19 产品令（二次）：FAB 恒显示，设置里没有开关——
                // 设置与筛选都挂在右下角新建钮的长按扇形上，关掉它等于把三者一起关掉。
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _layoutOption(
      BuildContext bc, WidgetRef ref, String k, String cur) {
    final tokens = bc.tokens;
    final scheme = Theme.of(bc).colorScheme;
    final on = k == cur;
    return InkWell(
      key: ValueKey('dset-$k'),
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        ref.read(settingsControllerProvider.notifier).setJournalLayout(k);
        Navigator.of(bc).pop();
        AppToast.show(bc, '视图：${kJournalLayoutLabels[k]}');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: on
              ? tokens.accent.withValues(alpha: .08)
              : scheme.onSurfaceVariant.withValues(alpha: .06),
          border: Border.all(
              color: on ? tokens.accent : Colors.transparent, width: 1.2),
        ),
        child: Column(
          children: [
            Icon(journalLayoutIcon(k),
                size: 20,
                color: on ? tokens.accent : scheme.onSurfaceVariant),
            const SizedBox(height: 5),
            Text(
              kJournalLayoutLabels[k]!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? tokens.accent : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
