import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/habit.dart';
import '../domain/habit_template.dart';
import 'habit_providers.dart';
import 'habit_sheets.dart';
import 'widgets/habit_kit.dart';

/// 批5 自动化弹层组（原型 sheetHabitSrc / sheetHabitPend / sheetHabitTpl /
/// sheetHabitShare）。自动达成一律走 [HabitRepository.autoIngest]（§5-8）。

// ---- 自动达成源（sheetHabitSrc）----

const kHabitSrcs = ['待办勾选', '番茄完成', '阅读计时', '日程事件', '手动打卡'];

const _srcDesc = {
  '待办勾选': '勾选待办即打卡',
  '番茄完成': '番茄跑满即打卡',
  '阅读计时': '计时满目标分钟即打卡',
  '日程事件': '日程结束即打卡',
  '手动打卡': '手动点按',
};

class _SrcSheet extends ConsumerWidget {
  const _SrcSheet();

  Future<void> _sim(BuildContext context, WidgetRef ref) async {
    final d = ref.read(habitDataProvider).requireValue;
    final bound = [
      for (final h in d.book)
        if (h.sourceKinds.any((s) => s != '手动打卡')) h,
    ];
    if (!context.mounted) return;
    final m = ScaffoldMessenger.of(context);
    if (bound.isEmpty) {
      messengerToast(m, '没有绑定自动达成源的习惯');
      return;
    }
    final h = bound.first;
    final src = h.sourceKinds.firstWhere((s) => s != '手动打卡');
    final msg = await ref.read(habitRepositoryProvider).autoIngest(h, src: src);
    if (!context.mounted) return;
    ref.read(habitTickProvider.notifier).state++;
    messengerToast(m, msg ?? '已模拟一次「$src」达成');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final d = ref.watch(habitDataProvider).valueOrNull;
    if (d == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        key: const ValueKey('hb-src-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('自动达成源', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            '满足任一来源即自动打卡；来源明细可点进对应模块',
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in kHabitSrcs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: hCardDeco(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        d.book
                                                .where(
                                                  (h) =>
                                                      h.sourceKinds.contains(s),
                                                )
                                                .isNotEmpty
                                            ? '绑定 ${d.book.where((h) => h.sourceKinds.contains(s)).length} 个习惯'
                                            : '未绑定习惯',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _srcDesc[s] ?? '',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            ...[
                              for (final h in d.book.where(
                                (x) => x.sourceKinds.contains(s),
                              ))
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.pop(context);
                                        context.push('/habit/${h.id}');
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color: scheme.outlineVariant,
                                          ),
                                        ),
                                        child: Text(
                                          h.name,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (d.autoMode == 1)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const ValueKey('btn-hs-sim'),
                  onPressed: () => _sim(context, ref),
                  style: TextButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '模拟一次自动达成',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurface,
                backgroundColor: scheme.onSurface.withValues(alpha: .05),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '完成',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showHabitSrcSheet(BuildContext context) =>
    hBottomSheet(context, (_) => const _SrcSheet());

// ---- 待确认打卡（sheetHabitPend · 计划 §5-8：需我确认只进 habit_pend）----

class _PendSheet extends ConsumerWidget {
  const _PendSheet();

  Future<void> _ok(
    BuildContext context,
    WidgetRef ref,
    Habit h,
    Map<String, Object?> p,
  ) async {
    final m = ScaffoldMessenger.of(context);
    await ref.read(habitRepositoryProvider).confirmPend(p);
    ref.read(habitTickProvider.notifier).state++;
    messengerToast(m, '已确认「${h.name}」· 来源 ${p['src']}');
  }

  Future<void> _no(BuildContext context, WidgetRef ref, Map<String, Object?> p) async {
    final m = ScaffoldMessenger.of(context);
    await ref.read(habitRepositoryProvider).ignorePend(p['id'] as int);
    ref.read(habitTickProvider.notifier).state++;
    messengerToast(m, '已忽略 · 来源 ${p['src']} 未计入打卡');
  }

  Future<void> _all(
    BuildContext context,
    WidgetRef ref,
    List<(Habit, List<Map<String, Object?>>)> groups,
  ) async {
    final m = ScaffoldMessenger.of(context);
    if (groups.isEmpty) {
      messengerToast(m, '没有待确认项');
      return;
    }
    final repo = ref.read(habitRepositoryProvider);
    for (final (_, ps) in groups) {
      for (final p in ps) {
        await repo.confirmPend(p);
      }
    }
    ref.read(habitTickProvider.notifier).state++;
    messengerToast(
      m,
      '已确认 ${groups.length} 个习惯的自动打卡',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final d = ref.watch(habitDataProvider).valueOrNull;
    if (d == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final byId = {for (final h in d.habits) h.id: h};
    final groups = <(Habit, List<Map<String, Object?>>)>[];
    for (final p in d.pends) {
      final h = byId[p['habit_id']];
      if (h == null) continue;
      final i = groups.indexWhere((g) => g.$1.id == h.id);
      if (i >= 0) {
        groups[i] = (h, [...groups[i].$2, p]);
      } else {
        groups.add((h, [p]));
      }
    }
    Widget btn(String label, Key key, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        key: const ValueKey('hb-pend-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('待确认打卡', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            '自动达成源已满足条件 · 逐条确认后才计入统计',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (groups.isEmpty)
                    Container(
                      decoration: hCardDeco(context),
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      alignment: Alignment.center,
                      child: Text(
                        '没有待确认的自动打卡',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final (h, ps) in groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        key: ValueKey('hp-card-${h.id}'),
                        decoration: hCardDeco(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: context.tokens.accent.withValues(
                                      alpha: .12,
                                    ),
                                  ),
                                  child: Icon(
                                    HIcons.resolve(h.icon),
                                    size: 14,
                                    color: context.tokens.accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        h.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        ps.map((p) {
                                          final at = p['created_at'] as int?;
                                          final t = at == null
                                              ? ''
                                              : ' · ${_pendAt(at)}';
                                          final v =
                                              (p['value'] as num?)?.toDouble();
                                          return '${p['src']}$t${v != null && v > 0 ? ' · 量 ${v % 1 == 0 ? v.toInt() : v}' : ''}';
                                        }).join(' / '),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                btn(
                                  '确认打卡',
                                  ValueKey('hp-ok-${h.id}'),
                                  () => _ok(context, ref, h, ps.first),
                                ),
                                const SizedBox(width: 8),
                                btn(
                                  '忽略',
                                  ValueKey('hp-no-${h.id}'),
                                  () => _no(context, ref, ps.first),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const ValueKey('btn-hp-all'),
                  onPressed: () => _all(context, ref, groups),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    backgroundColor: scheme.onSurface.withValues(alpha: .05),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '全部确认',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showHabitPendSheet(BuildContext context) =>
    hBottomSheet(context, (_) => const _PendSheet());

// ---- 习惯模板库（sheetHabitTpl · 资源包 assets/habit_templates）----

String _pendAt(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _TplSheet extends StatefulWidget {
  const _TplSheet({required this.tpls});

  final List<HabitTemplate> tpls;

  @override
  State<_TplSheet> createState() => _TplSheetState();
}

class _TplSheetState extends State<_TplSheet> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        key: const ValueKey('hb-tpl-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('习惯模板', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            '选一个自动填好名称、分类、频率与目标量，可再修改',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final t in widget.tpls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        key: ValueKey('ht-${t.name}'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(context, t),
                        child: Container(
                          decoration: hCardDeco(context),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: t.type == Habit.kNeg
                                      ? HK.rose500.withValues(alpha: .1)
                                      : tokens.accent.withValues(alpha: .1),
                                ),
                                child: Icon(
                                  HIcons.resolve(t.icon),
                                  size: 15,
                                  color: t.type == Habit.kNeg
                                      ? HK.rose500
                                      : tokens.accent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${t.type == Habit.kPos ? '正向' : '负向'} · ${t.cat} · '
                                      '${switch (t.cycle) { Habit.kWeek => '每周', Habit.kMonth => '每月', _ => '每天' }}'
                                      '${t.isGroup ? ' · 组 · ${t.subs.length} 项' : '${HabitSubChips.n(t.goal ?? t.target?.toDouble() ?? 0)}${t.unit ?? '次'}'}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '填充',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurface,
                backgroundColor: scheme.onSurface.withValues(alpha: .05),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '返回',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 打开模板库；选中返回模板，返回 null＝未选。
Future<HabitTemplate?> showHabitTplSheet(
  BuildContext context, {
  AssetBundle? bundle,
}) async {
  final tpls = await loadHabitTemplates(bundle: bundle);
  if (!context.mounted) return null;
  return hBottomSheet<HabitTemplate>(
    context,
    (_) => _TplSheet(tpls: tpls),
  );
}

// ---- 分享长图（sheetHabitShare · 数据快照由统计页装配）----

class HabitShareRow {
  const HabitShareRow({
    required this.icon,
    required this.name,
    required this.cnt,
    required this.right,
  });

  final String icon;
  final String name;
  final int cnt;

  /// 右端加粗摘要（正向：达成%；负向：守住 x/7 天）。
  final String right;
}

class HabitShareSnapshot {
  const HabitShareSnapshot({
    required this.title,
    required this.rangeTxt,
    required this.cnt,
    required this.rate,
    required this.rec,
    required this.pos,
    required this.neg,
    required this.habitCntLines,
  });

  final String title; // '本周打卡报告'
  final String rangeTxt; // '09-14 ~ 09-20 · 共 5 个习惯'
  final int cnt;
  final int rate;
  final int rec;
  final List<HabitShareRow> pos;
  final List<HabitShareRow> neg;

  /// 文字版逐正向习惯行（'名：N 次'）。
  final List<String> habitCntLines;

  String get copyText => [
    '${title.replaceFirst('打卡报告', '')}习惯报告',
    '打卡 $cnt 次 · 达成率 $rate% · 数值记录 $rec 条',
    ...habitCntLines,
  ].join('\n');
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.s});

  final HabitShareSnapshot s;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        key: const ValueKey('hb-share-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '分享长图',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '预览',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [tokens.accent, const Color(0xFFD946EF)],
                        ),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LifeHarness · 习惯报告',
                            style: TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.rangeTxt,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _stat('打卡次数', '${s.cnt}'),
                              _stat('达成率', '${s.rate}%'),
                              _stat('数值记录', '${s.rec}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '达成靠前',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (s.pos.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                '暂无正向习惯',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          for (final (i, r) in s.pos.indexed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    HIcons.resolve(r.icon),
                                    size: 13,
                                    color: tokens.accent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      r.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Text(
                                    '${r.cnt} 次',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    r.right,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: tokens.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (s.neg.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              '负向控制',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            for (final r in s.neg)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    Text(
                                      '触发 ${r.cnt} 次',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: HK.rose500,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      r.right,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: HK.teal500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '数据仅存本机 · 导出不含账号信息',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const ValueKey('btn-hsh-copy'),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: s.copyText),
                    );
                    if (context.mounted) habitToast(context, '文字版已复制');
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    backgroundColor: scheme.onSurface.withValues(alpha: .05),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '复制文字版',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  key: const ValueKey('btn-hsh-save'),
                  onPressed: () => habitToast(context, '已保存到相册（模拟）'),
                  style: TextButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '保存图片',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String lab, String v) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            v,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            lab,
            style: const TextStyle(fontSize: 9, color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

Future<void> showHabitShareSheet(
  BuildContext context,
  HabitShareSnapshot s,
) => hBottomSheet(context, (_) => _ShareSheet(s: s));
