import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/providers.dart';
import '../../../core/settings/user_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/stats_providers.dart';

/// 提醒通知二级页（原型 p-sub-notify）：
/// 日程与任务提醒 / 日记复盘 / 收集箱清理 为真实排程；习惯提醒与免打扰为存储位。
class NotifySettingsPage extends ConsumerWidget {
  const NotifySettingsPage({super.key});

  Future<void> _apply(WidgetRef ref, NotifySettings n) async {
    await ref.read(settingsControllerProvider.notifier).setNotify(n);
    if (n.todoEvent || n.inboxClean || n.diaryReview) {
      await NotificationService.ensurePermission();
    }
    NotificationService.todoEnabled = n.todoEvent;
    await NotificationService.syncDaily(
        inboxClean: n.inboxClean,
        diaryReview: n.diaryReview,
        diaryTime: n.diaryTime);
    // 待办提醒全量重排/撤销（开关与提前量变化时保持一致）。
    final todos = await ref.read(todoRepositoryProvider).list();
    for (final t in todos) {
      await NotificationService.scheduleTodo(
          id: t.id!, title: t.title, remindAt: (!t.done && n.todoEvent) ? t.remindAt : null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final n = ref.watch(settingsControllerProvider.select((s) => s.notify));
    final enabledCount =
        [n.todoEvent, n.diaryReview, n.inboxClean].where((e) => e).length;

    return Scaffold(
      appBar: AppBar(title: const Text('提醒通知')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            enabledCount == 0 ? '未开启' : '$enabledCount 类提醒已开启 · 全部本地调度',
            style: TextStyle(
                fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          _card(context, child: Column(
            children: [
              _row(context, '📅 日程与任务提醒', n.todoEvent,
                  (v) => _apply(ref, n.copyWith(todoEvent: v))),
              _selectRow(context, '默认提前量', '${n.leadMin} 分钟',
                  const ['10 分钟', '30 分钟', '1 小时'],
                  (v) => _apply(ref,
                      n.copyWith(leadMin: v == '1 小时' ? 60 : int.parse(v.split(' ').first)))),
              _row(context, '逾期任务升级提醒', n.overdueEscalate,
                  (v) => _apply(ref, n.copyWith(overdueEscalate: v)),
                  small: true),
            ],
          )),
          const SizedBox(height: 12),
          _card(context, child: Column(
            children: [
              _row(context, '📔 日记复盘', n.diaryReview,
                  (v) => _apply(ref, n.copyWith(diaryReview: v))),
              _selectRow(context, '晚间复盘提醒时间', n.diaryTime,
                  const ['21:00', '21:30', '22:00', '22:30'],
                  (v) => _apply(ref, n.copyWith(diaryTime: v))),
            ],
          )),
          const SizedBox(height: 12),
          _card(context, child: Column(
            children: [
              _row(context, '⚡ 收集箱清理', n.inboxClean,
                  (v) => _apply(ref, n.copyWith(inboxClean: v))),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('每天 21:00 · 每条 10 秒分流完成',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
            ],
          )),
          const SizedBox(height: 12),
          _card(context, child: Column(
            children: [
              _row(context, '🔁 习惯提醒', n.habits,
                  (v) => _apply(ref, n.copyWith(habits: v))),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('习惯模块上线后可逐条设置提醒时间 · 规划 V0.5',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
            ],
          )),
          const SizedBox(height: 12),
          _card(context, child: Column(
            children: [
              _row(context, '⛔ 免打扰时段', n.dnd,
                  (v) => _apply(ref, n.copyWith(dnd: v))),
              ListTile(
                contentPadding: const EdgeInsets.only(left: 0),
                title: Text('23:00 – 07:00 · 仅逾期紧急项可穿透',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                trailing: TextButton(
                  onPressed: () => _toast(context, '免打扰时段编辑 · 规划 V0.5'),
                  child: const Text('设置', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          )),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
        boxShadow: tokens.cardShadow,
      ),
      child: child,
    );
  }

  Widget _row(BuildContext context, String title, bool on, ValueChanged<bool> onChanged,
      {bool small = false}) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: on,
      onChanged: onChanged,
      title: Text(title,
          style: TextStyle(
              fontSize: small ? 12.5 : 13.5,
              fontWeight: FontWeight.w700,
              color: small ? scheme.onSurfaceVariant : scheme.onSurface)),
    );
  }

  Widget _selectRow(
      BuildContext context, String label, String value, List<String> options, ValueChanged<String> onPick) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
        DropdownButton<String>(
          value: options.contains(value) ? value : options.first,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface),
          items: [
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) {
            if (v != null) onPick(v);
          },
        ),
      ],
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1500)));
  }
}
