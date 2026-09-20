import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/nav/nav_module.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/stats_providers.dart';

/// 模块6 今日仪表盘（M0 · 对齐原型 p-dashboard）。
/// 真数据：待办数/进度环/今日日程数/收集箱未整理/连续记录天。
/// 占位（灰显/提示）：心情打卡、时间分布、持有成本、主页编排、全局搜索——随模块上线替换。
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final hour = now.hour;
    final greet = hour < 11 ? '早上好' : hour < 14 ? '中午好' : hour < 18 ? '下午好' : '晚上好';
    final emoji = hour < 18 ? '☀️' : '🌙';
    final streak = ref.watch(streakDaysProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('今天'),
            Text(
              '${now.month}月${now.day}日 周${_weekdays[now.weekday - 1]} · 第 $streak 天记录',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '全局搜索（M1 上线）',
            icon: const Icon(Icons.search),
            onPressed: () => _toast(context, '全局搜索框架 M1 接入'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _HeroCard(greet: '$greet，CHIST $emoji'),
          const SizedBox(height: 14),
          const _MoodCard(),
          const SizedBox(height: 14),
          const _TodayScheduleCard(),
          const SizedBox(height: 14),
          const _InboxBar(),
          const SizedBox(height: 14),
          const _TimeDistCard(),
          const SizedBox(height: 14),
          const _AllModulesCard(),
          Center(
            child: Text(
              'LifeHarness · 纯本地 · 离线可用',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1500)));
}

/// 问候卡：今日待办/安排真数 + 进度环 + 持有成本与编排占位。
class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.greet});

  final String greet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final todos = ref.watch(todosProvider).valueOrNull ?? const [];
    final todayEvents = ref.watch(todayEventCountProvider).valueOrNull ?? 0;

    final pending = todos.where((t) => !t.done).toList();
    final doneToday = todos.where((t) => t.done).length;
    final total = todos.length;
    final ratio = total == 0 ? 0.0 : doneToday / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: tokens.gradient,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        boxShadow: tokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greet, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              const Text('今天有 ',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              Text('${pending.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
              const Text(' 个待办 · ',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              Text('$todayEvents',
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
              const Text(' 场安排',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniGlass(
                  label: '今日待办',
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: ratio,
                              strokeWidth: 4.5,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                            Text('${(ratio * 100).round()}%',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('已完成',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniGlass(
                  label: '今日持有成本',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('¥ —',
                          style: TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      Text('物品模块 V1.0 上线',
                          style: TextStyle(color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text('主页卡片可自由编排顺序',
                    style: TextStyle(color: Colors.white70, fontSize: 10.5)),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _toast(context, '主页编排 M0 末接入（挂载点已就绪）'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('⇄ 编排',
                      style: TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniGlass extends StatelessWidget {
  const _MiniGlass({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// 今日心情（占位：随日记模块 M0 末接入 journal.mood）。
class _MoodCard extends StatelessWidget {
  const _MoodCard();

  static const _moods = ['😄', '😌', '😐', '', '😰', '', '😡'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('今日心情', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final m in _moods)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _toast(context, '心情打卡随日记模块上线（M0 末）'),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(m, style: const TextStyle(fontSize: 24)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('点一下，记录今天的心情（待接入）',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ),
        ],
      ),
    );
  }
}

/// 今日日程（数据随日程模块接入，当前空态 + 查看全部）。
class _TodayScheduleCard extends ConsumerWidget {
  const _TodayScheduleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(todayEventCountProvider).valueOrNull ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('今日日程',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              TextButton(
                onPressed: () => context.go(NavModule.calendar.path),
                child: Text('查看全部 ›',
                    style: TextStyle(
                        fontSize: 12,
                        color: context.tokens.accent,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              count == 0 ? '今天还没有安排 · 点右下角 ＋ 记录这段时间' : '今日 $count 项安排',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}

/// 收集箱快捷条（真实未整理计数）。
class _InboxBar extends ConsumerWidget {
  const _InboxBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(inboxPendingCountProvider).valueOrNull ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.go(NavModule.inbox.path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('⚡', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('收集箱 · $pending 条未整理',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text('快速记下，稍后再分类',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            const Text('›', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// 本周时间分布（占位卡：统计随 M2 上线）。
class _TimeDistCard extends StatelessWidget {
  const _TimeDistCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本周时间分布',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  value: 0,
                  strokeWidth: 14,
                  color: Colors.grey.shade200,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  '工作学习 / 睡眠休息 / 运动健康 / 娱乐休闲\n\n数据积累后自动绘制（M2 统计上线）',
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 全部功能宫格：已建可点，未建灰显 + 版本角标（原型规范）。
class _AllModulesCard extends StatelessWidget {
  const _AllModulesCard();

  static const _mods = <(String, IconData, String?, String?)>[
    ('待办', Icons.check_circle_outline, '/todo', null),
    ('时间', Icons.schedule, '/calendar', null),
    ('日记', Icons.book_outlined, '/journal', null),
    ('收集箱', Icons.inbox_outlined, '/inbox', null),
    ('我的', Icons.person_outline, '/settings', null),
    ('笔记', Icons.edit_note_outlined, null, 'V0.5'),
    ('阅读', Icons.menu_book_outlined, null, 'V0.5'),
    ('记账', Icons.payments_outlined, null, 'V0.5'),
    ('物品', Icons.inventory_2_outlined, null, 'V1.0'),
    ('日子', Icons.cake_outlined, null, 'V1.0'),
    ('健康', Icons.monitor_heart_outlined, null, 'V1.0'),
    ('目标', Icons.flag_outlined, null, 'V1.0'),
    ('习惯', Icons.local_fire_department_outlined, null, 'V1.0'),
    ('工具', Icons.construction_outlined, null, 'V1.x'),
    ('母婴', Icons.child_care_outlined, null, 'V1.x'),
    ('插件', Icons.extension_outlined, null, 'V1.x'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('全部功能', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              const cols = 4;
              const gap = 8.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (label, icon, route, ver) in _mods)
                    SizedBox(
                      width: w,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: route == null
                            ? () => _toast(context, '「$label」计划 $ver 上线')
                            : () => context.go(route),
                        child: Opacity(
                          opacity: route == null ? .45 : 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Icon(icon,
                                        size: 24,
                                        color: route == null ? Colors.grey : tokens.accent),
                                    if (ver != null)
                                      Positioned(
                                        right: -14,
                                        top: -6,
                                        child: Text(ver,
                                            style: const TextStyle(
                                                fontSize: 7.5, color: Colors.grey)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(label,
                                    style: TextStyle(fontSize: 11, color: scheme.onSurface)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
