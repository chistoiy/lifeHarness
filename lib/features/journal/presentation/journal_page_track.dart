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
                  // 批2e：图墙自带卡片底与说明行（原型把说明放在卡片**外**），
                  // 这里不再套 `card()`——套了说明行就被关进卡片里。
                  return JournalWall(
                    month: viewed,
                    byDayFirst: byDayViewed,
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

  /// 视图设置弹层（批1a）：三档横向三宫格；批2e 按原型 `renderDiarySetSheet` 对齐
  /// ——补「展示方式」小标题、选中卡改**主色实底＋白字＋右上 ✓**（原来是描边淡底，
  /// 三个卡里分不出哪个是当前档）。
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
          // 原型 `.sheet-panel{padding:20px 20px 32px}`：底部多留 12 给手势条。
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
                // 原型 `.font-extrabold`（16/800），不是 18/600——比「筛选」那档 `.dr-title`
                // 小一号但更重，两个弹层标题本来就不是同一套字级。
                const Text('日记设置',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                // 原型 `.row-title`（13/800）。缺了它三张卡就是「三块不知所以的方块」。
                const Text('展示方式',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
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
    // 原型 `.ds-lay-on{background:var(--accent);color:#fff;box-shadow:0 4px 12px accent-28}`。
    // 白字取 `scheme.onPrimary` 而不是字面 `Colors.white`：主色实底上的前景色本就该由主题给，
    // 写死白字在深色/低饱和主题上既可能不达标，也会撞深色观感棘轮（该闸按行匹配白字面）。
    final fg = on ? scheme.onPrimary : scheme.onSurfaceVariant;
    return InkWell(
      key: ValueKey('dset-$k'),
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        ref.read(settingsControllerProvider.notifier).setJournalLayout(k);
        Navigator.of(bc).pop();
        AppToast.show(bc, '视图：${kJournalLayoutLabels[k]}');
      },
      child: Container(
        // 原型 `py-2.5 rounded-xl`＝上下 10、圆角 12。
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: on
              ? tokens.accent
              : scheme.onSurfaceVariant.withValues(alpha: .06),
          boxShadow: on
              ? [
                  BoxShadow(
                      color: tokens.accent.withValues(alpha: .28),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // 原型 svg 18×18；旧实现 20，三张卡并排时显得头重。
                Icon(journalLayoutIcon(k), size: 18, color: fg),
                const SizedBox(height: 4),
                Text(
                  kJournalLayoutLabels[k]!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
            // 原型右上角 `✓`（10px）。选中卡已是主色实底，对勾是**第二重信号**：
            // 只靠底色的话，主题色偏浅时（如翠绿档）与未选卡对比度会掉。
            if (on)
              Positioned(
                top: 2,
                right: 6,
                child: Text('✓',
                    style: TextStyle(
                        fontSize: 10,
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}
