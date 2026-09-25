import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/day_calc.dart';
import '../domain/day_models.dart';
import 'days_kit.dart';
import 'days_providers.dart';

/// P8c 到期提醒中心（需求 V1.42 模块11 · 原型 renderRemind/remindSnooze 4012-4050 对译）。
///
/// 口径：四 tab 分段条（全部带未处理计数）；未处理在前按 effectiveDate 升序；
/// 逾期/≤7 天 rose、其余 amber 全实算；「延后处理 → 转待办」reminderToTodo
/// （提醒不消隐仅 toast 去向，联动 L3）；「改提醒日」弹层内嵌三滚轮（月/日/时）
/// 实时预览；「已处理」静默归档保留审计；证件手动建档。
class DayRemindPage extends ConsumerWidget {
  const DayRemindPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('到期提醒中心'),
            Text('证件 · 订阅 · 保修',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: const _RemindBody(),
    );
  }
}

class _RemindBody extends ConsumerStatefulWidget {
  const _RemindBody();

  @override
  ConsumerState<_RemindBody> createState() => _RemindBodyState();
}

class _RemindBodyState extends ConsumerState<_RemindBody> {
  String _tab = '全部';

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(daysClockProvider)();
    final async = ref.watch(daysDataProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (d) {
        final unhandledCount = d.reminders.where((r) => !r.handled).length;
        final list = [...d.reminders]..sort((a, b) {
            if (a.handled != b.handled) return a.handled ? 1 : -1;
            return a.effectiveDate.compareTo(b.effectiveDate);
          });
        final shown = _tab == '全部'
            ? list
            : list.where((r) => r.kindLabel == _tab).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Row(
              children: [
                Expanded(child: _tabs(unhandledCount)),
                const SizedBox(width: 8),
                MiniBtn(
                  key: const ValueKey('d-rem-add-cert'),
                  icon: Icons.add,
                  label: '证件',
                  onTap: _addCert,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final r in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _itemCard(r, now),
              ),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('暂无条目',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: kDaysMuted)),
              ),
            const SizedBox(height: 4),
            Container(
              key: const ValueKey('d-rem-note'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.tokens.accent.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                '数据来源与联动：订阅续费由记账周期账单自动生成 · 保修到期由物品档案汇入 · '
                '证件手动建档可设多级提醒。\n「延后处理」生成待办并写入提醒日；'
                '「已处理」静默归档保留审计。',
                style: TextStyle(fontSize: 11, height: 1.7),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 四 tab 分段条（原型 remindTabs seg-on）。
  Widget _tabs(int unhandledCount) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final t in const ['全部', '证件', '订阅', '保修'])
            Expanded(
              child: GestureDetector(
                key: ValueKey('d-remind-tab-$t'),
                onTap: () => setState(() => _tab = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: _tab == t ? tokens.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    t == '全部' ? '全部($unhandledCount)' : t,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: _tab == t ? tokens.accent : kDaysMuted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemCard(ReminderItem r, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final diff = dayDiff(now, r.effectiveDate);
    final status = diff < 0
        ? '已过期 ${-diff} 天'
        : '$diff 天后';
    final statusColor =
        diff < 0 || diff <= 7 ? kDaysRose : kDaysAmber;
    return Opacity(
      opacity: r.handled ? .5 : 1,
      child: Container(
        key: ValueKey('d-rem-${r.id}'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(reminderIconOf(r.iconId), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r.title}${r.handled ? ' · 已处理' : ''}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                            style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                                height: 1.5),
                            children: [
                              TextSpan(
                                  text:
                                      '${r.kindLabel} · 到期 ${fmtDateYmd(r.dueDate)}'),
                              if (r.snoozeDate != null) ...[
                                const TextSpan(text: ' · '),
                                TextSpan(
                                    text:
                                        '已改提醒 ${_snoozeText(r)}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: context.tokens.accent)),
                              ],
                              if (r.meta != null && r.meta!.isNotEmpty)
                                TextSpan(text: ' · ${r.meta}'),
                            ]),
                      ),
                      if (r.tip != null && r.tip!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              const Icon(Icons.tips_and_updates_outlined,
                                  size: 12, color: kDaysAmber),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(r.tip!,
                                    style: const TextStyle(
                                        fontSize: 10, color: kDaysAmber)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(status,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: statusColor)),
              ],
            ),
            if (!r.handled)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: MiniBtn(
                        key: ValueKey('d-rem-todo-${r.id}'),
                        label: '延后处理 → 转待办',
                        onTap: () => _todo(r, now),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: MiniBtn(
                        key: ValueKey('d-rem-snooze-${r.id}'),
                        label: '改提醒日',
                        onTap: () => _snooze(r),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: MiniBtn(
                        key: ValueKey('d-rem-done-${r.id}'),
                        label: '已处理 ✓',
                        bg: const Color(0x2610B981),
                        fg: const Color(0xFF059669),
                        onTap: () => _done(r),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _snoozeText(ReminderItem r) =>
      '${r.snoozeDate!.month}月${r.snoozeDate!.day}日 ${daysP2(r.snoozeHour ?? 9)}:00';

  Future<void> _todo(ReminderItem r, DateTime now) async {
    await reminderToTodo(ref, r, now);
    if (!mounted) return;
    daysTouch(ref);
    // 原型 remindTodo 不标 done：提醒不消隐，只 toast 去向。
    AppToast.show(context, '已生成待办「${r.title}」· 重要不紧急（联动 L3）');
  }

  Future<void> _done(ReminderItem r) async {
    await ref.read(daysRepositoryProvider).markHandled(r.id!);
    if (!mounted) return;
    daysTouch(ref);
    AppToast.show(context, '已标记处理 · 静默归档保留审计');
  }

  Future<void> _snooze(ReminderItem r) async {
    final res = await showDaysSheet<(DateTime, int)>(
      context,
      title: '改提醒日',
      builder: (bc) => _SnoozeSheet(item: r),
    );
    if (res == null || !mounted) return;
    final (date, hour) = res;
    await ref
        .read(daysRepositoryProvider)
        .setSnooze(r.id!, date, hour);
    if (!mounted) return;
    daysTouch(ref);
    AppToast.show(context,
        '「${r.title}」提醒日已改为 ${date.month}月${date.day}日 ${daysP2(hour)}:00');
  }

  Future<void> _addCert() async {
    final res = await showDaysSheet<Map<String, Object?>>(
      context,
      title: '新增证件提醒',
      builder: (bc) => const _CertSheet(),
    );
    if (res == null || !mounted) return;
    await ref.read(daysRepositoryProvider).addCertReminder(
        title: res['title']! as String,
        due: res['due']! as DateTime,
        tip: res['tip'] as String?);
    if (!mounted) return;
    daysTouch(ref);
    AppToast.show(context,
        '已添加证件提醒「${res['title']}」· 到期 ${fmtDateYmd(res['due']! as DateTime)}');
  }
}

/// 改提醒日弹层内容：小字头 + 三列内嵌滚轮（月=自今起 12 个月 / 日 1..31 / 时 0..23）
/// + 实算预览行 + 保存钮（原型 sheetRemindPick，禁两段式）。
class _SnoozeSheet extends StatefulWidget {
  const _SnoozeSheet({required this.item});

  final ReminderItem item;

  @override
  State<_SnoozeSheet> createState() => _SnoozeSheetState();
}

class _SnoozeSheetState extends State<_SnoozeSheet> {
  /// 自今天起 12 个月的滚动窗口（首元素=本月）。
  late final List<DateTime> _months = [
    for (var i = 0; i < 12; i++)
      DateTime(_base.year, _base.month + i)
  ];
  late final DateTime _base = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();

  late int _mi = _initialMonthIndex();
  late int _day = _initialDay();
  late int _hour = widget.item.snoozeHour ?? 9;

  int _initialMonthIndex() {
    final t = widget.item.effectiveDate;
    final idx =
        (t.year - _base.year) * 12 + (t.month - _base.month);
    return idx.clamp(0, 11);
  }

  int _initialDay() {
    final t = widget.item.effectiveDate;
    return t.day.clamp(1, 31);
  }

  DateTime get _pickedMonth => _months[_mi];

  /// 日号随所选月份收敛（如 2 月无 30 日）。
  int get _clampedDay =>
      _day.clamp(1, DateTime(_pickedMonth.year, _pickedMonth.month + 1, 0).day);

  @override
  Widget build(BuildContext context) {
    final occ = DateTime(_pickedMonth.year, _pickedMonth.month, _clampedDay);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            '当前提醒：${widget.item.title} · 原定 ${fmtDateYmd(widget.item.dueDate)} · 上下滑动选择',
            style: const TextStyle(fontSize: 10.5, color: kDaysMuted)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CWheel(
                key: const ValueKey('d-snooze-m'),
                labels: [for (final m in _months) '${m.month}月'],
                initialIndex: _mi,
                onSelect: (i) => setState(() => _mi = i),
              ),
            ),
            Expanded(
              child: CWheel(
                key: const ValueKey('d-snooze-d'),
                labels: [for (var d = 1; d <= 31; d++) '$d日'],
                initialIndex: _clampedDay - 1,
                onSelect: (i) => setState(() => _day = i + 1),
              ),
            ),
            Expanded(
              child: CWheel(
                key: const ValueKey('d-snooze-h'),
                labels: [for (var h = 0; h < 24; h++) '${daysP2(h)}时'],
                initialIndex: _hour,
                onSelect: (i) => setState(() => _hour = i),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
            '将于 ${_pickedMonth.month}月$_clampedDay 日 ${daysP2(_hour)}:00 提醒 · 多级提前提醒按此日倒推',
            key: const ValueKey('d-snooze-hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        GradButton(
          key: const ValueKey('d-snooze-save'),
          label: '保存提醒日',
          onTap: () => Navigator.pop(context, (occ, _hour)),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// 证件建档弹层内容：标题 + 就地三列日期滚轮 + 可选提示行。
class _CertSheet extends StatefulWidget {
  const _CertSheet();

  @override
  State<_CertSheet> createState() => _CertSheetState();
}

class _CertSheetState extends State<_CertSheet> {
  final _titleCtl = TextEditingController();
  final _tipCtl = TextEditingController();
  late DateTime _due = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 30);
  }();

  @override
  void dispose() {
    _titleCtl.dispose();
    _tipCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('d-cert-title'),
          controller: _titleCtl,
          decoration: InputDecoration(
            hintText: '名称，如：护照',
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 6),
        InlineDateWheel(
          key: const ValueKey('d-cert-date-wheel'),
          value: _due,
          onChanged: (v) => setState(() => _due = v),
          height: 100,
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('d-cert-tip'),
          controller: _tipCtl,
          decoration: InputDecoration(
            hintText: '提示（可选），如：办理周期约 10 个工作日',
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        GradButton(
          key: const ValueKey('d-cert-save'),
          label: '建档',
          onTap: () {
            final t = _titleCtl.text.trim();
            if (t.isEmpty) {
              AppToast.show(context, '先填标题');
              return;
            }
            Navigator.pop(context, {
              'title': t,
              'due': _due,
              if (_tipCtl.text.trim().isNotEmpty) 'tip': _tipCtl.text.trim(),
            });
          },
        ),
      ],
    );
  }
}
