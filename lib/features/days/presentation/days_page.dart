import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/days_repository.dart';
import '../domain/day_calc.dart';
import '../domain/day_models.dart';
import 'day_detail_page.dart';
import 'day_edit_page.dart';
import 'day_remind_page.dart';
import 'days_kit.dart';
import 'days_providers.dart';

/// P8 重要日子主页（需求 V1.42 模块11 · 原型 renderDays 3881-3910 对译）。
///
/// 口径：分类 seg 胶囊行 / 计数行（排序翻转 + 列表·卡片翻转，均本地 setState）/
/// 2 列渐变卡与列表行双视图 / 到期提醒中心预览 / 去年今天（联动 L5，实算）/
/// 虚线新建钮 + GradFab；倒数数值全部走 day_calc，禁写死。
class DaysPage extends ConsumerStatefulWidget {
  const DaysPage({super.key});

  @override
  ConsumerState<DaysPage> createState() => _DaysPageState();
}

class _DaysPageState extends ConsumerState<DaysPage> {
  String _cat = '全部';
  bool _listMode = false;
  bool _sortAsc = true;

  Future<List<DiaryEcho>>? _annFuture;
  String? _annKey;

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _tapDay(DayEntry d, DateTime now) {
    if (d.archived || !isOverdue(d, now)) {
      _push(DayDetailPage(dayId: d.id!));
    } else {
      // once 已过期 → 提醒中心（原型 dayTap d.d<0 → goRemind）
      _push(const DayRemindPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(daysClockProvider)();
    final async = ref.watch(daysDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('重要日子'),
            Text('倒数 · 纪念日 · 到期提醒',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      floatingActionButton: GradFab(
        key: const ValueKey('d-fab'),
        icon: const Icon(Icons.add, color: Colors.white, size: 26),
        tooltip: '新建日子',
        onTap: () => _push(DayEditPage(dayId: null)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => _body(d, now),
      ),
    );
  }

  Widget _body(DaysData d, DateTime now) {
    final act = d.days.where((x) => !x.archived).toList();
    final counts = {
      for (final c in kDayCats)
        c: act.where((x) => x.category == c).length,
    };
    // 过滤 + 排序（sortDays：置顶恒前、|倒数| 升/降）
    var list = act;
    if (_cat != '全部') {
      list = _cat == '已归档'
          ? d.days.where((x) => x.archived).toList()
          : act.where((x) => x.category == _cat).toList();
    }
    final sorted = sortDays(list, now, asc: _sortAsc);
    // 计数行「最近」：全量未归档非过期里倒数最小者（不随分类筛选变化·原型口径）
    final upcoming = act
        .where((x) => !x.archived && countdownDays(x, now) >= 0)
        .toList()
      ..sort((a, b) =>
          countdownDays(a, now).compareTo(countdownDays(b, now)));
    final nearest = upcoming.isEmpty ? null : upcoming.first;

    final unhandled = d.reminders.where((r) => !r.handled).toList()
      ..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));

    final annKey = fmtDateYmd(now);
    if (_annKey != annKey) {
      _annKey = annKey;
      _annFuture = ref
          .read(daysRepositoryProvider)
          .anniversaryEntries(now.month, now.day, now.year);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        _segRow(counts, d.days.length - act.length),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '${act.length} 个日子 · 最近「${nearest?.title ?? '—'}」'
                '还 ${nearest == null ? '—' : countdownDays(nearest, now)} 天',
                style: const TextStyle(fontSize: 11, color: kDaysMuted),
              ),
            ),
            MiniBtn(
              key: const ValueKey('d-sort-btn'),
              icon: Icons.swap_vert,
              label: _sortAsc ? '最近优先' : '最久优先',
              onTap: () => setState(() => _sortAsc = !_sortAsc),
            ),
            const SizedBox(width: 8),
            MiniBtn(
              key: const ValueKey('d-view-btn'),
              icon: _listMode ? Icons.grid_view : Icons.sort,
              label: _listMode ? '卡片' : '列表',
              onTap: () => setState(() => _listMode = !_listMode),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('暂无日子',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: kDaysMuted)),
          )
        else if (_listMode)
          Column(
            children: [
              for (final x in sorted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _listRow(x, now),
                ),
            ],
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.28,
            children: [for (final x in sorted) _gradCard(x, now)],
          ),
        const SizedBox(height: 16),
        EmptyDashRow(
          key: const ValueKey('d-new-day'),
          text: '＋ 新建倒数日 / 纪念日',
          onTap: () => _push(DayEditPage(dayId: null)),
        ),
        const SizedBox(height: 20),
        _remindPreviewCard(unhandled, now),
        FutureBuilder<List<DiaryEcho>>(
          future: _annFuture,
          builder: (bc, snap) {
            final rows = snap.data ?? const <DiaryEcho>[];
            if (rows.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _anniversaryCard(rows.take(2).toList()),
            );
          },
        ),
      ],
    );
  }

  Widget _segRow(Map<String, int> counts, int archivedCount) {
    final cats = ['全部', ...kDayCats, '已归档'];
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PillChip(
                key: ValueKey('d-cat-$c'),
                label: c == '全部'
                    ? c
                    : '$c ${c == '已归档' ? archivedCount : (counts[c] ?? 0)}',
                selected: _cat == c,
                onTap: () => setState(() => _cat = c),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gradCard(DayEntry d, DateTime now) {
    final dd = countdownDays(d, now);
    final overdue = dd < 0;
    return GestureDetector(
      key: ValueKey('d-day-card-${d.id}'),
      onTap: () => _tapDay(d, now),
      child: Opacity(
        opacity: overdue ? .8 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          decoration: BoxDecoration(
            gradient: dayGradientOf(d.colorKey),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                bottom: -12,
                child: Icon(dayIconOf(d.iconId),
                    size: 72, color: Colors.white.withValues(alpha: .18)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(overdue ? '—' : '$dd',
                          style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      if (!overdue)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text('天后',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${occurrenceLabel(d, now)}${overdue ? ' · 去处理 ›' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 9.5,
                        color: Colors.white.withValues(alpha: .82)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listRow(DayEntry d, DateTime now) {
    final dd = countdownDays(d, now);
    final overdue = dd < 0;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey('d-day-row-${d.id}'),
      onTap: () => _tapDay(d, now),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: dayGradientOf(d.colorKey),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(dayIconOf(d.iconId), size: 20, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(occurrenceLabel(d, now),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(overdue ? '已过${-dd}' : '$dd',
                        style: TextStyle(
                            fontSize: overdue ? 18 : 24,
                            fontWeight: FontWeight.w800,
                            color: overdue ? scheme.onSurfaceVariant : null)),
                    Text(overdue ? ' 天' : ' 天后',
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
                if (overdue)
                  const Text('去处理 ›',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: kDaysRose)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _remindPreviewCard(List<ReminderItem> unhandled, DateTime now) {
    return GestureDetector(
      key: const ValueKey('d-remind-preview'),
      onTap: () => _push(const DayRemindPage()),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('到期提醒中心（证件 / 订阅 / 保修）',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                Text('${unhandled.length} 项待关注',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: kDaysRose)),
              ],
            ),
            for (final r in unhandled.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(reminderIconOf(r.iconId), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.meta == null ? r.title : '${r.title}  ${r.meta}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    _remindStatusText(r, now, prefix: '剩 '),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text(
                '订阅项由记账模块自动生成（联动 L8）· 保修由物品档案汇入（联动 L13）· 查看全部 ›',
                style: TextStyle(fontSize: 10, color: kDaysMuted)),
          ],
        ),
      ),
    );
  }

  Widget _remindStatusText(ReminderItem r, DateTime now, {String prefix = ''}) {
    final diff = dayDiff(now, r.effectiveDate);
    return Text(
      diff < 0 ? '已于${-diff}天前到期' : '$prefix$diff 天',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: switch (diff) { < 0 => kDaysMuted, <= 7 => kDaysRose, _ => kDaysAmber },
      ),
    );
  }

  Widget _anniversaryCard(List<DiaryEcho> rows) {
    return SectionCard(
      key: const ValueKey('d-anniversary'),
      title: '去年今天（联动 L5）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in rows)
            GestureDetector(
              key: ValueKey('d-ann-${fmtDateYmd(e.date)}'),
              onTap: () => AppToast.show(context, '已打开当年日记'),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  e.text.isEmpty
                      ? fmtDateYmd(e.date)
                      : '${fmtDateYmd(e.date)} · ${_trunc40(e.text)}',
                  style: const TextStyle(fontSize: 11, height: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _trunc40(String t) {
    final flat = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 40 ? flat : '${flat.substring(0, 40)}…';
  }
}
