import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/journal_entry.dart';
import 'diary_edit_page.dart' show DiaryEditArg;
import 'journal_page.dart' show DiaryTabState;
import 'widgets/diary_review_sheet.dart' show openDiaryPickSheet;
import 'widgets/journal_layout_kit.dart';
import 'widgets/journal_track_view.dart';
import 'widgets/journal_wall.dart';
extension JournalTrackUI on DiaryTabState {
  /// 轨道档滚动树：顶部月历图墙 + 日期块列表（批1a），**日期块吸顶**（批1b）。
  ///
  /// 图墙与日期块同处一条滚动：图墙是「导航用」的，滚下去看内容时它该走开。
  /// 批1b 只把**日期块**钉住——用 `CustomScrollView` + 每个日期块的 `SliverPersistentHeader(pinned)`。
  /// 1a 用 `ListView` 无法挂 pinned 头（`ListView` 的 children 只能是 box）。
  Widget trackScroll(
    BuildContext context,
    WidgetRef ref,
    DateTime now,
    List<TrackDayBlock> blocks, {
    /// 未过滤的全部条目（图墙要跨月看，不能用「当月过滤后」的 blocks）。
    required List<JournalEntry> wallAllEntries,
    /// 年 → 月 → 日 → 该日全部篇（点格时给选择弹层用）。
    required Map<int, Map<int, Map<int, List<JournalEntry>>>> wallDayAll,
  }) {
    final tokens = context.tokens;
    const padH = 16.0;
    return CustomScrollView(
      slivers: [
        // 顶部：图墙 + 工具栏（随滚走开，不钉）
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(padH, 8, padH, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Builder(builder: (context) {
                  // 图墙看的是**查看月**（可翻月），不是固定本月；日历块列表仍按筛选后的全部条目。
                  final viewed = wallMonthOf(now);
                  // 按查看月重算当日首篇：翻到 3 月时 blocks 里全是本月的，直接用会整屏空格。
                  final byDayViewed = <int, JournalEntry>{};
                  for (final e in wallAllEntries) {
                    if (e.day.year == viewed.year && e.day.month == viewed.month) {
                      byDayViewed.putIfAbsent(e.day.day, () => e);
                    }
                  }
                  return card(
                    context,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: JournalWall(
                        month: viewed,
                        byDayFirst: byDayViewed,
                        moodColorOf: (e) =>
                            (e.mood == null) ? null : tokens.accent,
                        onMonthStep: (d) => wallStep(context, d),
                        onTapDay: (day) {
                          final list = wallDayAll[viewed.year]?[viewed.month]?[day];
                          if (list == null || list.isEmpty) {
                            context.push('/journal/edit',
                                extra: DiaryEditArg(
                                    day: DateTime(viewed.year, viewed.month, day)));
                          } else {
                            openDiaryPickSheet(
                                context,
                                '${viewed.month}月$day日的日记',
                                list);
                          }
                        },
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        if (blocks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: padH),
              child: Center(
                child: Text(
                  '这个筛选下还没有日记',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          // 日期块逐块拍平**铺到顶层 slivers**（每块＝pinned 日期头 + 该天条目）。
          // 不能塞进 SliverList：pinned 头是 sliver，而 SliverList 的 itemBuilder 只收 box
          // （本批实伤：会抛 RenderRepaintBoundary expected RenderBox）。
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: padH),
            sliver: SliverMainAxisGroup(
              slivers: [
                for (final b in blocks)
                  ...trackBlockSlivers(
                    block: b,
                    onOpenEntry: (e) => context.push('/journal/edit',
                        extra: DiaryEditArg(entryId: e.id)),
                  ),
              ],
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
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
