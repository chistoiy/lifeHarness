import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/share_card.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/days_repository.dart';
import '../domain/day_calc.dart';
import '../domain/day_models.dart';
import 'days_kit.dart';
import 'days_providers.dart';

/// P8a 日子详情（需求 V1.42 模块11 · 原型 renderDayDetail 3916-3964 对译）。
///
/// 口径：渐变 hero（倒数实算）→ 多级提前提醒只读 chips → 准备事项就地勾选
/// （首勾 dayPrepToTodo 联动 L3）→ 关联当年日记（联动 L5，diaryForDay 实查）→
/// 归档态恢复/彻底删除（二次确认）；非归档态编辑/分享卡/置顶 + 归档钮。
class DayDetailPage extends ConsumerWidget {
  const DayDetailPage({super.key, required this.dayId});

  final int dayId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(daysClockProvider)();
    final async = ref.watch(daysDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('日子详情'),
            if (async.hasValue)
              Text(
                async.value!.days
                        .where((x) => x.id == dayId)
                        .map((x) => x.title)
                        .firstOrNull ??
                    '',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.normal),
              ),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final day = d.days.where((x) => x.id == dayId).firstOrNull;
          if (day == null) {
            return const Center(
                child: Text('该日子已不存在',
                    style: TextStyle(fontSize: 12, color: kDaysMuted)));
          }
          return _body(context, ref, day, now);
        },
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, DayEntry day, DateTime now) {
    final dd = countdownDays(day, now);
    final occ = nextOccurrence(day, now);
    final scheme = Theme.of(context).colorScheme;
    final tokensAccent = context.tokens.accent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        // —— 渐变 hero ——
        Container(
          key: const ValueKey('d-detail-hero'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: dayGradientOf(day.colorKey),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -6,
                bottom: -10,
                child: Icon(dayIconOf(day.iconId),
                    size: 84, color: Colors.white.withValues(alpha: .18)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  if (dd >= 0)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('$dd',
                            style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        Text(' 天后 · ${occurrenceDateText(occ)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ],
                    )
                  else
                    Text('已过去 ${-dd} 天',
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('${occurrenceLabel(day, now)} · ${day.repeat.label}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: .88))),
                  if (day.note != null && day.note!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(day.note!,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: .82))),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // —— 多级提前提醒（只读） ——
        SectionCard(
          key: const ValueKey('d-detail-rem'),
          title: '多级提前提醒',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in kDayRemOffsets)
                    PillChip(
                      key: ValueKey('d-detail-rem-$v'),
                      label: v == 0
                          ? '当天${day.remOffsets.contains(v) ? ' ✓' : ''}'
                          : '提前 $v 天${day.remOffsets.contains(v) ? ' ✓' : ''}',
                      selected: day.remOffsets.contains(v),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('提醒写入系统通知 · 免打扰时段顺延',
                  style: TextStyle(fontSize: 10, color: kDaysMuted)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // —— 准备事项（勾选即转待办 · 联动 L3） ——
        Container(
          key: const ValueKey('d-detail-prep'),
          padding: const EdgeInsets.all(12),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('准备事项（勾选即转待办 · 联动 L3）',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                  MiniBtn(
                    key: const ValueKey('d-detail-prep-all'),
                    label: '全部转待办',
                    onTap: () => _prepAll(context, ref, day, now),
                  ),
                ],
              ),
              if (day.preps.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('暂无准备事项',
                      style: TextStyle(fontSize: 11, color: kDaysMuted)),
                ),
              for (final p in day.preps)
                GestureDetector(
                  key: ValueKey('d-prep-${p.id}'),
                  onTap: () => _togglePrep(context, ref, day, p, now),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        _CheckBox(on: p.done),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p.text,
                            style: TextStyle(
                              fontSize: 12.5,
                              decoration:
                                  p.done ? TextDecoration.lineThrough : null,
                              color: p.done ? kDaysMuted : null,
                            ),
                          ),
                        ),
                        if (p.todoId != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('已入待办',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: tokensAccent)),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // —— 关联当年日记（联动 L5） ——
        if (day.linkDiary) ...[
          const SizedBox(height: 12),
          _DiaryEchoCard(key: const ValueKey('d-detail-diary'), day: day),
        ],
        const SizedBox(height: 12),
        if (day.archived) ...[
          Container(
            key: const ValueKey('d-detail-arch-bar'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              '此日子已归档 · 不再出现在列表与倒数卡，提醒已解除',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: kDaysMuted),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GradButton(
                  key: const ValueKey('d-detail-restore'),
                  label: '恢复到列表',
                  onTap: () => _setArchived(context, ref, day, false,
                      toast: '已恢复到日子列表'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RoseOutlineButton(
                  key: const ValueKey('d-detail-purge'),
                  label: '彻底删除',
                  onTap: () => _purge(context, ref, day),
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: _LifeBtn(
                  key: const ValueKey('d-detail-edit'),
                  label: '编辑',
                  onTap: () async {
                    // T10：改走命名路由（深链可达·未知路由兜底盖得到；
                    // 编辑页删除带 'purged' 回来，与本屏连退的口径不变）
                    final r = await context.push<String>(
                        '/days/edit?id=${day.id}');
                    if (r == 'purged' && context.mounted) {
                      Navigator.pop(context); // 日子已删：详情连退
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LifeBtn(
                  key: const ValueKey('d-detail-share'),
                  label: '分享卡',
                  onTap: () async {
                    final echoes = day.linkDiary
                        ? await ref
                            .read(daysRepositoryProvider)
                            .diaryForDay(day, now)
                        : const <DiaryEcho>[];
                    if (!context.mounted) return;
                    await showShareCardSheet(context,
                        _shareDayCard(day, now, dd, echoes),
                        src: '日子');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LifeBtn(
                  key: const ValueKey('d-detail-pin'),
                  label: day.pinned ? '已置顶' : '置顶',
                  filled: day.pinned,
                  onTap: () => _togglePin(context, ref, day),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const ValueKey('d-detail-archive'),
              onPressed: () => _setArchived(context, ref, day, true,
                  toast: '已归档「${day.title}」· 到「日子 · 已归档」可恢复', pop: true),
              child: const Text('归档此日子（可在「已归档」恢复）›',
                  style:
                      TextStyle(fontSize: 11, color: kDaysMuted)),
            ),
          ),
        ],
      ],
    );
  }

  /// 倒数日分享卡（原型 scData('day') 同构：剩余天数大数字+三格+准备事项+备注+历年日记）。
  ShareCardModel _shareDayCard(
      DayEntry day, DateTime now, int dd, List<DiaryEcho> echoes) {
    const repLabel = {
      'once': '一次性倒数',
      'solar-year': '每年（公历循环）',
      'lunar': '每年（农历自动换算）',
      'monthly': '每月循环',
    };
    String two(int n) => n.toString().padLeft(2, '0');
    return ShareCardModel(
      file: '倒数日-${day.title}',
      eyebrow: 'LifeHarness · 重要日子',
      title: day.title,
      line:
          '${occurrenceLabel(day, now)} · ${repLabel[day.repeat.wire] ?? day.repeat.label}',
      big: '${dd.abs()}',
      unit: dd >= 0 ? '天后' : '天前',
      tiles: [
        ShareCardTile('类别', day.category),
        ShareCardTile('提醒', day.remOffsets.isEmpty
            ? '无'
            : [for (final o in day.remOffsets) o == 0 ? '当天' : '前$o天']
                .join('/')),
        ShareCardTile('准备', '${day.preps.length} 项'),
      ],
      sections: [
        ShareCardSection(head: '准备事项', rows: [
          for (final p in day.preps) ShareCardRow(p.text, p.done ? '已完成' : '待办'),
        ]),
        if ((day.note ?? '').isNotEmpty)
          ShareCardSection(head: '备注', rows: [ShareCardRow(day.note!)]),
        if (echoes.isNotEmpty)
          ShareCardSection(head: '历年关联日记', rows: [
            for (final e in echoes)
              ShareCardRow('${e.date.year}-${two(e.date.month)}-${two(e.date.day)} '
                  '${e.text.length > 24 ? '${e.text.substring(0, 24)}…' : e.text}'),
          ]),
      ],
    );
  }

  Future<void> _togglePrep(
      BuildContext context, WidgetRef ref, DayEntry day, DayPrep p, DateTime now) async {
    final repo = ref.read(daysRepositoryProvider);
    if (!p.done) {
      final todoId = await dayPrepToTodo(ref, day, p, now);
      await repo.togglePrep(p.id!, true);
      if (context.mounted && todoId != null) {
        AppToast.show(context, '「${p.text}」已生成待办（联动 L3）');
      }
    } else {
      await repo.togglePrep(p.id!, false);
    }
    if (context.mounted) daysTouch(ref);
  }

  Future<void> _prepAll(
      BuildContext context, WidgetRef ref, DayEntry day, DateTime now) async {
    if (day.preps.isEmpty) {
      AppToast.show(context, '先添加准备事项');
      return;
    }
    final n = await dayPrepsAllToTodo(ref, day, now);
    if (!context.mounted) return;
    daysTouch(ref);
    AppToast.show(
        context, n == 0 ? '准备事项均已入待办' : '$n 条准备事项已全部转为待办（联动 L3）');
  }

  Future<void> _togglePin(
      BuildContext context, WidgetRef ref, DayEntry day) async {
    await ref.read(daysRepositoryProvider).setPinned(day.id!, !day.pinned);
    if (!context.mounted) return;
    daysTouch(ref);
    AppToast.show(context,
        day.pinned ? '已取消置顶' : '已置顶 · 仪表盘倒数卡排第一');
  }

  Future<void> _setArchived(BuildContext context, WidgetRef ref, DayEntry day,
      bool archived,
      {required String toast, bool pop = false}) async {
    await ref
        .read(daysRepositoryProvider)
        .setArchived(day.id!, archived);
    if (!context.mounted) return;
    daysTouch(ref);
    AppToast.show(context, toast);
    if (pop) Navigator.pop(context);
  }

  Future<void> _purge(
      BuildContext context, WidgetRef ref, DayEntry day) async {
    final ok = await daysConfirm(context,
        '彻底删除「${day.title}」？关联待办与日记引用不受影响');
    if (!ok || !context.mounted) return;
    await ref.read(daysRepositoryProvider).purgeDay(day.id!);
    if (!context.mounted) return;
    daysTouch(ref);
    AppToast.show(context, '已彻底删除');
    Navigator.pop(context);
  }
}

/// 方勾选框（原型 .chk / .chk-on）。
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: on ? tokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
            color: on ? tokens.accent : kDaysMuted, width: 1.5),
      ),
      child: on
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : null,
    );
  }
}

/// 原型 .life-btn（灰底三行钮；置顶选中=accent 底白字）。
class _LifeBtn extends StatelessWidget {
  const _LifeBtn(
      {super.key, required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: filled ? tokens.accent : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: filled ? Colors.white : scheme.onSurface)),
      ),
    );
  }
}

/// 关联当年日记卡（联动 L5）：diaryForDay 实查，own state 避免逐帧重建 future。
class _DiaryEchoCard extends ConsumerStatefulWidget {
  const _DiaryEchoCard({super.key, required this.day});

  final DayEntry day;

  @override
  ConsumerState<_DiaryEchoCard> createState() => _DiaryEchoCardState();
}

class _DiaryEchoCardState extends ConsumerState<_DiaryEchoCard> {
  late Future<List<DiaryEcho>> _future = _fetch();

  Future<List<DiaryEcho>> _fetch() {
    final now = ref.read(daysClockProvider)();
    return ref.read(daysRepositoryProvider).diaryForDay(widget.day, now);
  }

  @override
  void didUpdateWidget(_DiaryEchoCard old) {
    super.didUpdateWidget(old);
    if (old.day.id != widget.day.id ||
        old.day.targetDate != widget.day.targetDate ||
        old.day.lunarMonth != widget.day.lunarMonth ||
        old.day.lunarDay != widget.day.lunarDay ||
        old.day.monthDay != widget.day.monthDay) {
      _future = _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '关联当年日记（联动 L5）',
      child: FutureBuilder<List<DiaryEcho>>(
        future: _future,
        builder: (bc, snap) {
          final rows = snap.data ?? const <DiaryEcho>[];
          if (rows.isEmpty) {
            return const Text('该日子尚无历史日记关联',
                style: TextStyle(fontSize: 11, color: kDaysMuted));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in rows)
                GestureDetector(
                  key: ValueKey('d-diary-${fmtDateYmd(e.date)}'),
                  onTap: () => AppToast.show(bc, '已打开当年日记'),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      e.text.isEmpty
                          ? fmtDateYmd(e.date)
                          : '${fmtDateYmd(e.date)} · ${_trunc(e.text)}',
                      style: const TextStyle(fontSize: 11, height: 1.4),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _trunc(String t) {
    final flat = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 40 ? flat : '${flat.substring(0, 40)}…';
  }
}
