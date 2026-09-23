import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/grad_fab.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_entry.dart';
import 'habit_aux_sheets.dart';
import 'habit_auto_sheets.dart';
import 'habit_backfill_sheet.dart';
import 'habit_edit_sheet.dart';
import 'habit_providers.dart';
import 'habit_sheets.dart';
import 'widgets/habit_card.dart';
import 'widgets/habit_kit.dart';
import 'widgets/habit_tile.dart';
import 'widgets/habit_tile_row.dart';

/// 习惯主页（原型 p-habits · TITLES ['习惯','今日打卡 · 数值记录 · 组打卡']）。
/// hero 今日卡 + 日期行（‹ 标签 ›）+ 状态/分类双下拉 + 视图三态 + 列表。
class HabitsPage extends ConsumerStatefulWidget {
  const HabitsPage({super.key});

  @override
  ConsumerState<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends ConsumerState<HabitsPage> {
  /// 回看偏移（0=今天 · 原型限 -6..0，仅今天可打卡）。
  int _dayOff = 0;

  static const _segs = [
    ('all', '全部'),
    ('todo', '待打卡'),
    ('ok', '已达成'),
    ('grp', '分组'),
    ('neg', '负向'),
    ('arch', '归档'),
  ];
  static const _views = [
    ('list', '列表 · 明细与操作'),
    ('compact', '紧凑 · 一行一个'),
    ('grid', '方块 · 完成度'),
  ];

  DateTime get _today => dayStart(DateTime.now());
  DateTime get _viewDay => _today.subtract(Duration(days: -_dayOff));

  void _toast(String m) => habitToast(context, m);

  Future<void> _setKv(String key, String value) async {
    await ref.read(habitRepositoryProvider).setKv(key, value);
    ref.read(habitTickProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(habitDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('习惯'),
            Text(
              '今日打卡 · 数值记录 · 组打卡',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          // 原型 renderHdrActs(p-habits)：周/月/年统计 + 打卡设置。
          IconButton(
            tooltip: '周 / 月 / 年统计',
            icon: Icon(HIcons.resolve('chart'), size: 20),
            onPressed: () => context.push('/habit-stat'),
          ),
          IconButton(
            tooltip: '打卡设置',
            icon: Icon(HIcons.resolve('cog'), size: 20),
            onPressed: () => context.push('/habit-set'),
          ),
        ],
      ),
      floatingActionButton: GradFab(
        icon: const Icon(Icons.add, color: Colors.white),
        onTap: () => showHabitEditSheet(context, ref, null),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => _body(d),
      ),
    );
  }

  Widget _body(HabitData d) {
    final today = _today;
    final tKey = dayKey(today);
    final book = d.book;
    final due = d.dueToday(today);
    final done = due.where((h) => d.okOn(h, tKey)).length;
    final pct = due.isEmpty ? 0 : (done * 100 / due.length).round();
    final allDone = due.isNotEmpty && done == due.length;
    final maxStreak = book.isEmpty
        ? 0
        : book.map((h) => h.streak).reduce((a, b) => a > b ? a : b);
    final rates = book.map((h) => buildRowInfo(d, h, today, _viewDay).rate);
    final weekRateAvg = rates.isEmpty
        ? 0
        : (rates.reduce((a, b) => a + b) / rates.length).round();
    // 本周已记数值条数（原型 recN：有量流水计数 · 滚动 7 日窗）
    var recN = 0;
    final loK = dayKey(today.subtract(const Duration(days: 6)));
    for (final h in book) {
      for (final e in d.of(h.id).values) {
        if (e.day.compareTo(loK) < 0) continue;
        if (e.value != null || e.subValues.values.any((v) => v > 0)) recN++;
      }
    }
    final negLeft = book
        .where((h) => h.isNeg)
        .fold<int>(
          0,
          (a, h) =>
              a +
              (h.negLimit -
                      buildRowInfo(d, h, today, _viewDay).negUsed)
                  .clamp(0, 99),
        );

    final actions = HabitActions(
      open: (h) => context.push('/habit/${h.id}'),
      tap: (h) => _tap(h, d),
      avoid: (h) => _avoid(h, d),
      trigger: (h) => showHabitTriggerSheet(context, h),
      freeze: (h) => _freeze(h, d),
      archiveToggle: (h) async {
        final repo = ref.read(habitRepositoryProvider);
        await repo.setArchived(h.id, !h.isArchived);
        ref.read(habitTickProvider.notifier).state++;
        _toast(
          h.isArchived ? '已恢复跟踪' : '已归档 · 纪录保留，不再出现在今日列表',
        );
      },
      openLog: (h) => showHabitLogSheet(context, ref, h),
      dotTap: (h, day) => _dotTap(h, day, d),
    );

    // 筛选（§3.2 状态×分类双下拉 · 计数进钮面）
    var list = book;
    final seg = d.seg;
    if (seg == 'todo') {
      list = due.where((h) => !d.okOn(h, tKey)).toList();
    } else if (seg == 'ok') {
      list = due.where((h) => d.okOn(h, tKey)).toList();
    } else if (seg == 'grp') {
      list = book.where((h) => h.isGroup).toList();
    } else if (seg == 'neg') {
      list = book.where((h) => h.isNeg).toList();
    } else if (seg == 'arch') {
      list = d.archived;
    }
    if (d.catF != '全部') list = list.where((h) => h.cat == d.catF).toList();

    final cntOf = {
      'all': book.length,
      'todo': due.length - done,
      'ok': done,
      'grp': book.where((h) => h.isGroup).length,
      'neg': book.where((h) => h.isNeg).length,
      'arch': d.archived.length,
    };
    final catCount = {
      for (final c in d.cats)
        c.name: book.where((h) => h.cat == c.name).length,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        _hero(
          d: d,
          pct: pct,
          done: done,
          dueN: due.length,
          recN: recN,
          negLeft: negLeft,
          maxStreak: maxStreak,
          weekRateAvg: weekRateAvg,
        ),
        const SizedBox(height: 10),
        _dateRow(),
        const SizedBox(height: 10),
        _filterRow(d, cntOf, catCount, list.length, book.length),
        const SizedBox(height: 12),
        if (allDone && _dayOff == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: context.tokens.gradient,
              ),
              child: Row(
                children: [
                  const Icon(HIcons.resolveFlame, size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '今日应打卡 ${due.length} 项全部达成 · 连续纪录继续推进',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (list.isEmpty)
          Container(
            decoration: hCardDeco(context),
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '该筛选下暂无习惯 · ',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                GestureDetector(
                  onTap: () => showHabitEditSheet(context, ref, null),
                  child: Text(
                    '新建一个',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.tokens.accent,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (d.view == 'grid')
          _gridView(list, d, actions)
        else
          Column(
            children: [
              for (final (i, h) in list.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                d.view == 'compact'
                    ? HabitTileRow(
                      habit: h,
                      info: buildRowInfo(d, h, _today, _viewDay),
                      enabled: _dayOff == 0 && !h.isArchived,
                      actions: actions,
                    )
                    : HabitCardView(
                      habit: h,
                      info: buildRowInfo(d, h, _today, _viewDay),
                      dayOff: _dayOff,
                      grace: d.graceOf[h.id] ?? 0,
                      actions: actions,
                    ),
              ],
            ],
          ),
        const SizedBox(height: 8),
        EmptyDashRow(
          text: '＋ 新建习惯',
          onTap: () => showHabitEditSheet(context, ref, null),
        ),
      ],
    );
  }

  // ---- hero（原型 grad 卡：环 + 标题 + 副行 + 进度条 + 连击/本周/补卡 + auto 行）----

  Widget _hero({
    required HabitData d,
    required int pct,
    required int done,
    required int dueN,
    required int recN,
    required int negLeft,
    required int maxStreak,
    required int weekRateAvg,
  }) {
    final title = _dayOff != 0
        ? '回看 ${habitDayLabel(_today, _viewDay).split(' · ').first}'
        : dueN > 0 && pct == 100
        ? '今日全部达成'
        : pct >= 50
        ? '今日进行中'
        : '今日待开始';
    final sub =
        '已打卡 $done / 应打卡 $dueN'
        '${recN > 0 ? ' · 本周已记数值 $recN 条' : ''}'
        ' · 负向剩余额度 $negLeft 次';
    final autoHabits = d.book
        .where((h) => h.sourceKinds.any((s) => s != '手动打卡'))
        .length;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: context.tokens.gradient,
        boxShadow: [
          BoxShadow(
            color: context.tokens.g1.withValues(alpha: .2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RingProgress(
                value: pct / 100,
                child: Text(
                  '$done/$dueN',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Container(
                              color: Colors.white.withValues(alpha: .25),
                            ),
                            FractionallySizedBox(
                              widthFactor: pct / 100,
                              child: Container(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              HPill(text: '最长连击 $maxStreak 天'),
              HPill(text: '本周完成率 $weekRateAvg%'),
              const Spacer(),
              HPill(
                text: '补卡 ${d.bfTotal}',
                onTap: () => showHabitBackfillSheet(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (autoHabits > 0 || d.pendCount > 0)
            HPill(
              key: const ValueKey('hb-auto-row'),
              text: d.autoMode == 1
                  ? '待确认 ${d.pendCount} 项 · 逐条确认'
                  : '今日自动达成 $autoHabits 项 · 查看来源',
              icon: HIcons.resolve(d.autoMode == 1 ? 'undo' : 'flame'),
              onTap: () => d.autoMode == 1
                  ? showHabitPendSheet(context)
                  : showHabitSrcSheet(context),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '全部为手动打卡 · 可绑定自动达成源',
                style: TextStyle(fontSize: 10.5, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  // ---- 日期行 ----

  Widget _dateRow() {
    return Row(
      children: [
        _shiftBtn(Icons.chevron_left, () {
          setState(() => _dayOff = (_dayOff - 1).clamp(-6, 0));
          if (_dayOff != 0) _toast('回看模式 · 仅今天可打卡');
        }),
        Expanded(
          child: InkWell(
            onTap: () => showHabitDaySheet(
              context,
              ref,
              -_dayOff,
              onPick: (back) => setState(() => _dayOff = -back),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                habitDayLabel(_today, _viewDay),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        _shiftBtn(Icons.chevron_right, () {
          setState(() => _dayOff = (_dayOff + 1).clamp(-6, 0));
        }),
      ],
    );
  }

  Widget _shiftBtn(IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(icon, size: 16, color: scheme.onSurfaceVariant),
      ),
    );
  }

  // ---- 筛选行（LH-K18 成对下拉 + LH-K19 三态循环钮 + 计数 hint）----

  Widget _filterRow(
    HabitData d,
    Map<String, int> cntOf,
    Map<String, int> catCount,
    int shown,
    int total,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget dd(String value, List<(String, String)> items, ValueChanged<String?> onPick) =>
        Container(
          width: 102,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.any((x) => x.$1 == value) ? value : items.first.$1,
              isExpanded: true,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
              items: [
                for (final (v, t) in items)
                  DropdownMenuItem(value: v, child: Text(t)),
              ],
              onChanged: onPick,
            ),
          ),
        );
    final iconName = switch (d.view) {
      'grid' => 'list', // 钮面显示「下一个视图」图标（原型同构）
      'compact' => 'chart',
      _ => 'grid',
    };
    return Row(
      children: [
        dd(
          d.seg,
          [
            for (final (k, t) in _segs) (k, '$t ${cntOf[k] ?? 0}'),
          ],
          (v) {
            if (v != null) _setKv(kHabitSegKey, v);
          },
        ),
        const SizedBox(width: 6),
        dd(
          d.catF,
          [
            ('全部', '全部分类 ${cntOf['all'] ?? 0}'),
            for (final c in d.cats) (c.name, '${c.name} ${catCount[c.name] ?? 0}'),
          ],
          (v) {
            if (v != null) _setKv(kHabitCatKey, v);
          },
        ),
        const SizedBox(width: 6),
        Tooltip(
          message:
              '当前 ${_views.firstWhere((x) => x.$1 == d.view).$2} · 点击切换视图',
          child: InkWell(
            key: const ValueKey('btn-habit-view'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final i = _views.indexWhere((x) => x.$1 == d.view);
              final next = _views[(i + 1) % _views.length];
              _setKv(kHabitViewKey, next.$1);
              _toast('切到${next.$2}');
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                HIcons.resolve(iconName),
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const Spacer(),
        Text(
          '显示 $shown / $total',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _gridView(List<Habit> list, HabitData d, HabitActions actions) {
    final rows = <Widget>[];
    for (var i = 0; i < list.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < list.length ? 8 : 0),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: HabitTile(
                    habit: list[i],
                    info: buildRowInfo(d, list[i], _today, _viewDay),
                    today: _today,
                    enabled: _dayOff == 0 && !list[i].isArchived,
                    actions: actions,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < list.length
                      ? HabitTile(
                        habit: list[i + 1],
                        info: buildRowInfo(d, list[i + 1], _today, _viewDay),
                        today: _today,
                        enabled: _dayOff == 0 && !list[i + 1].isArchived,
                        actions: actions,
                      )
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  // ---- 打卡动作（§3.2 落库范围：UPSERT habit_entries + 重算 streak/best）----

  Future<void> _tap(Habit h, HabitData d) async {
    if (_dayOff != 0 || h.isArchived) return;
    final k = dayKey(_today);
    final repo = ref.read(habitRepositoryProvider);
    if (!h.isPos) return _avoid(h, d);
    if (h.hasVal) {
      await showHabitLogSheet(context, ref, h);
      return;
    }
    if (d.okOn(h, k)) {
      await repo.deleteEntry(h.id, k);
      ref.read(habitTickProvider.notifier).state++;
      _toast('已撤销今日打卡');
      return;
    }
    await repo.upsertEntry(
      h.id,
      day: k,
      checked: true,
      origin: HabitEntry.oManual,
      checkAt: hhmm(DateTime.now()),
    );
    final after = await repo.habitById(h.id);
    ref.read(habitTickProvider.notifier).state++;
    _toast(
      '${h.name} 已打卡 · 连续 ${after?.streak ?? 0} 天 · 计入周报与目标（L7）',
    );
  }

  Future<void> _avoid(Habit h, HabitData d) async {
    if (_dayOff != 0 || h.isArchived) return;
    final k = dayKey(_today);
    if (d.okOn(h, k)) {
      _toast('今天已计入未触发');
      return;
    }
    final repo = ref.read(habitRepositoryProvider);
    await repo.upsertEntry(
      h.id,
      day: k,
      checked: true,
      origin: HabitEntry.oManual,
      checkAt: hhmm(DateTime.now()),
    );
    final after = await repo.habitById(h.id);
    ref.read(habitTickProvider.notifier).state++;
    _toast('未触发 +1 · 已连续 ${after?.streak ?? 0} 天守住');
  }

  /// 方块视图历史合格格就地打卡/撤销（§3.2）。
  /// 用一张宽限（原型 hbFreeze 守卫链 + §5-6：frozen 只保连续不算达成）。
  Future<void> _freeze(Habit h, HabitData d) async {
    final repo = ref.read(habitRepositoryProvider);
    final left = d.graceOf[h.id] ?? 0;
    if (left <= 0) {
      _toast('本月宽限次数已用完');
      return;
    }
    final tKey = dayKey(_today);
    if (d.okOn(h, tKey)) {
      _toast('今天已打卡 · 无需宽限');
      return;
    }
    await repo.useFreeze(h, day: tKey);
    final after = await repo.habitById(h.id);
    ref.read(habitTickProvider.notifier).state++;
    _toast('已用一张宽限 · 连续 ${after?.streak ?? h.streak} 天未中断 · 本月剩 ${left - 1} 张');
  }

  Future<void> _dotTap(Habit h, DateTime day, HabitData d) async {
    if (h.isArchived) return;
    final k = dayKey(day);
    final repo = ref.read(habitRepositoryProvider);
    if (d.okOn(h, k)) {
      await repo.deleteEntry(h.id, k);
    } else {
      await repo.upsertEntry(
        h.id,
        day: k,
        checked: !h.isNeg,
        origin: HabitEntry.oManual,
        checkAt: k == dayKey(_today) ? hhmm(DateTime.now()) : null,
      );
    }
    ref.read(habitTickProvider.notifier).state++;
  }
}

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
