import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_dict.dart';
import 'habit_aux_sheets.dart';
import 'habit_providers.dart';
import 'habit_sheets.dart';
import 'widgets/habit_kit.dart';

/// 打卡设置整页（原型 p-habitSet · HB_SET_ITEMS 13 项 · 计划 §6）。
/// 影响统计口径的键写 `habit.*` settings KV（不散落 SharedPreferences）。
class HabitSettingsPage extends ConsumerStatefulWidget {
  const HabitSettingsPage({super.key});

  @override
  ConsumerState<HabitSettingsPage> createState() => _HabitSettingsPageState();
}

class _HabitSettingsPageState extends ConsumerState<HabitSettingsPage> {
  /// KV 键 → 当前值（bool 存 'true'/'false'，seg 存下标字符串）。
  final Map<String, String> _v = {};
  bool _loading = true;

  // 与原型 HB_SET 初始值一致（§6 键表）。
  static const _defs = {
    'spanFromStart': 'true',
    'autoChk': 'true',
    'remindAll': 'true',
    'rateBase': '0',
    'weekStart': '0',
    'grace': '1',
    'autoMode': '0',
    'nightRemind': 'true',
    'nightAt': '1',
    'dnd': '1',
  };

  static String _key(String k) => 'habit.$k';

  /// (键, 标题, 说明, 分段选项=null 表示开关行, 是否跳转行)。
  static const List<(String, String, String, List<String>?, bool)> _items = [
    (
      'spanFromStart',
      '日均按开始跟踪日起算',
      '统计里的日均与达成率只计入习惯开始之后的天数 · 年中新增不会被全年摊薄',
      null,
      false,
    ),
    (
      'autoChk',
      '自动达成源直接打卡',
      '番茄 / 阅读计时 / 日程满足条件即记为已打卡，流水标注「自动」',
      null,
      false,
    ),
    (
      'remindAll',
      '允许提醒',
      '关闭后所有习惯提醒静默，打卡与统计照常',
      null,
      false,
    ),
    (
      'rateBase',
      '达成率口径',
      '按应打卡天数或按周期总天数计算达成率',
      ['应打卡天数', '周期天数'],
      false,
    ),
    (
      'weekStart',
      '周起始日',
      '影响日历与周统计的分列方式',
      ['周一', '周日'],
      false,
    ),
    (
      'grace',
      '每月宽限次数',
      '断签时用一张宽限保住连续 · 一天抵消一次',
      ['不用', '1 张', '2 张', '3 张'],
      false,
    ),
    (
      'autoMode',
      '自动达成方式',
      '番茄 / 阅读计时 / 日程达成后的处理',
      ['直接打卡', '需我确认'],
      false,
    ),
    (
      'nightRemind',
      '晚间未打卡提醒',
      '到点仍未打卡时补一次提醒',
      null,
      false,
    ),
    (
      'nightAt',
      '晚间提醒时间',
      '仅在开启晚间提醒时生效',
      ['18:00', '20:00', '21:30', '22:30'],
      false,
    ),
    (
      'dnd',
      '免打扰时段',
      '该区间内不推送任何习惯提醒',
      ['关闭', '22:00-08:00', '23:00-07:00'],
      false,
    ),
    (
      'arch',
      '已归档习惯',
      '归档纪录仍保留 · 点击进入归档筛选',
      null,
      true,
    ),
    (
      'catMgr',
      '分类管理',
      '自定义习惯分类 · 改名 / 排序 / 删除前迁移',
      null,
      true,
    ),
    (
      'unitMgr',
      '单位管理',
      '自定义记录量单位 · 同步到习惯与组内子项',
      null,
      true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(habitRepositoryProvider);
    final m = <String, String>{};
    for (final e in _defs.entries) {
      m[e.key] = await repo.kv(_key(e.key)) ?? e.value;
    }
    if (!mounted) return;
    setState(() {
      _v.addAll(m);
      _loading = false;
    });
  }

  /// 写 KV + tick（其余页面经 habitDataProvider 同帧刷新），toast 原型口径。
  Future<void> _set(String k, String val, {String? toastName}) async {
    await ref.read(habitRepositoryProvider).setKv(_key(k), val);
    if (!mounted) return;
    setState(() => _v[k] = val);
    ref.read(habitTickProvider.notifier).state++;
    if (const ['remindAll', 'nightRemind', 'nightAt', 'dnd'].contains(k)) {
      await _syncNotif();
    }
    if (!mounted) return;
    habitToast(
      context,
      '已更新设置 · ${toastName ?? _items.firstWhere((x) => x.$1 == k).$2}',
    );
  }

  /// 提醒类键变更 → 全局提醒服务重排（未就绪时 NotificationService 全程 no-op）。
  Future<void> _syncNotif() async {
    final repo = ref.read(habitRepositoryProvider);
    final all = await repo.kvBool('habit.remindAll', true);
    final dnd = await repo.kvInt('habit.dnd', 1);
    final at = kHabitNightAts[
        (await repo.kvInt('habit.nightAt', 1)).clamp(0, kHabitNightAts.length - 1)];
    await NotificationService.syncHabitNightly(
      on: all && await repo.kvBool('habit.nightRemind', true) && !habitInDnd(dnd, at),
      at: at,
    );
    for (final h in await repo.allHabits()) {
      await NotificationService.registerHabitReminder(
        habitId: h.id,
        title: h.name,
        hhmm: h.remindAt,
        enabled: all &&
            !h.isArchived &&
            (h.remindAt?.isNotEmpty ?? false) &&
            !habitInDnd(dnd, h.remindAt ?? ''),
      );
    }
  }

  Future<void> _reset() async {
    // 原型 hbSetReset：口径、提醒、周起始日回初始值（宽限/自动方式/晚间提醒不动）。
    final repo = ref.read(habitRepositoryProvider);
    for (final k in ['spanFromStart', 'autoChk', 'remindAll']) {
      await repo.setKv(_key(k), 'true');
    }
    for (final k in ['weekStart', 'rateBase']) {
      await repo.setKv(_key(k), '0');
    }
    if (!mounted) return;
    setState(() {
      _v['spanFromStart'] = 'true';
      _v['autoChk'] = 'true';
      _v['remindAll'] = 'true';
      _v['weekStart'] = '0';
      _v['rateBase'] = '0';
    });
    ref.read(habitTickProvider.notifier).state++;
    await _syncNotif();
    if (!mounted) return;
    habitToast(context, '已更新设置 · 日均按开始跟踪日起算');
  }

  Future<void> _nav(String k) async {
    if (k == 'arch') {
      final d = await ref.read(habitDataProvider.future);
      await ref
          .read(habitRepositoryProvider)
          .setKv(kHabitSegKey, 'arch');
      ref.read(habitTickProvider.notifier).state++;
      if (!mounted) return;
      context.go('/habits');
      habitToast(context, '已切到归档筛选 · 共 ${d.archived.length} 个');
    } else {
      await showHabitMgrSheet(
        context,
        k == 'catMgr' ? HabitDict.kCat : HabitDict.kUnit,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('打卡设置'),
            Text(
              '口径 · 提醒 · 归档与字典',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    '影响统计口径 · 提醒与日历分列 · 本机生效',
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                ),
                for (final it in _items) ...[
                  _row(scheme, it),
                  const SizedBox(height: 8),
                ],
                Container(
                  decoration: hCardDeco(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '恢复默认设置',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '口径、提醒、周起始日回到初始值',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _reset,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('恢复', style: TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '设置仅作用于习惯模块',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _row(
    ColorScheme scheme,
    (String, String, String, List<String>?, bool) it,
  ) {
    final (k, title, desc, segs, isNav) = it;
    final titleW = Text(
      title,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
    );
    final descW = Text(
      desc,
      style: TextStyle(fontSize: 10, height: 1.4, color: scheme.onSurfaceVariant),
    );
    if (isNav) {
      return InkWell(
        key: ValueKey('hset-nav-$k'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => _nav(k),
        child: Container(
          decoration: hCardDeco(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleW, const SizedBox(height: 2), descW],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: hCardDeco(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: segs != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleW,
                const SizedBox(height: 4),
                descW,
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final (i, s) in segs.indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: _segBtn(
                          scheme,
                          s,
                          _v[k] == '$i',
                          () => _set(k, '$i', toastName: title),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [titleW, const SizedBox(height: 2), descW],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  key: ValueKey('hset-sw-$k'),
                  value: _v[k] == 'true',
                  onChanged: (on) =>
                      _set(k, on ? 'true' : 'false', toastName: title),
                ),
              ],
            ),
    );
  }

  Widget _segBtn(
    ColorScheme scheme,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        key: ValueKey('hset-$label'),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: on ? context.tokens.accent.withValues(alpha: .12) : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? context.tokens.accent : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: on ? context.tokens.accent : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
