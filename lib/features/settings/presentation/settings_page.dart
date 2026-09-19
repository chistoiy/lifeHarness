import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nav/nav_module.dart';
import '../../../core/providers.dart';
import '../../../core/settings/user_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../../../shared/linkage/stats_providers.dart';

/// 我的/设置（M0 · 对齐原型 p-profile）。
/// 真数据：完成任务数/连续记录天/主题/深色/底栏配置。
/// 占位入口：数据与同步(M1)/提醒通知(M1)/AI(M3)/小工具(V1.x)/插件中心(M4)/主题市场/字号。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsControllerProvider);
    final registry = ref.watch(themeRegistryProvider);
    final streak = ref.watch(streakDaysProvider).valueOrNull ?? 0;
    final doneTasks = ref.watch(doneTaskCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 资料卡
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, gradient: tokens.gradient),
                child: const Text('L',
                    style: TextStyle(
                        color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LifeHarness',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('本地模式 · 无账号 🔒 · 已记录 $streak 天',
                        style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _toast(context, '编辑资料（随用户体系评估）'),
                child: Text('编辑',
                    style: TextStyle(
                        color: tokens.accent, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 统计三宫格
          Row(
            children: [
              _StatCell(value: '$doneTasks', label: '完成任务', color: tokens.accent),
              const SizedBox(width: 10),
              _StatCell(value: '$streak', label: '连续记录天', color: const Color(0xFF2DD4BF)),
              const SizedBox(width: 10),
              const _StatCell(value: '0', label: '在册书籍', color: Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 14),
          // 二级入口列表（占位）
          Container(
            decoration: context.cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _EntryRow(
                    emoji: '☁️',
                    bg: const Color(0xFF10B981).withValues(alpha: .12),
                    title: '数据与同步',
                    sub: 'WebDAV · 备份 · 加密 · 同步历史',
                    trailing: '未配置',
                    onTap: () => _toast(context, '数据与同步 M1 上线')),
                _EntryRow(
                    emoji: '🔔',
                    bg: const Color(0xFF6366F1).withValues(alpha: .12),
                    title: '提醒通知',
                    sub: '日程 · 任务 · 收集箱清理',
                    trailing: 'M1',
                    onTap: () => _toast(context, '提醒通知 M1 上线（remind_at 已入库）')),
                _EntryRow(
                    emoji: '🤖',
                    bg: const Color(0xFF8B5CF6).withValues(alpha: .12),
                    title: 'AI 增强',
                    sub: '服务商 · Key · 能力矩阵',
                    trailing: '默认关闭',
                    onTap: () => _toast(context, 'AI 增强 M3 上线')),
                _EntryRow(
                    emoji: '🧰',
                    bg: Colors.grey.withValues(alpha: .12),
                    title: '小工具合集',
                    sub: '本地工具 · 插件拓展',
                    trailing: 'V1.x',
                    onTap: () => _toast(context, '小工具合集 V1.x 上线')),
                _EntryRow(
                    emoji: '🧩',
                    bg: Colors.grey.withValues(alpha: .12),
                    title: '插件中心',
                    sub: '大模块按需安装 · 更新 · 回滚',
                    trailing: 'M4',
                    last: true,
                    onTap: () => _toast(context, '插件中心 M4（宿主 API v0 已预埋）')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 主题风格卡
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('🎨 主题风格',
                            style:
                                TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                    TextButton(
                      onPressed: () => _toast(context, '主题市场（GitHub 热加载）V1.x 上线'),
                      child: Text('🛍 更多主题 ›',
                          style: TextStyle(
                              fontSize: 11,
                              color: tokens.accent,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                Text('${registry.ids.length} 套内置 · 配置文件热加载 · 与深色模式正交 · 赛博朋克强制深色',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 10),
                _ThemeGrid(registry: registry, selectedId: settings.themeId),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🌙 深色模式',
                              style: TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text(
                            settings.mode == ThemeModeOption.system
                                ? '当前：跟随系统'
                                : settings.mode == ThemeModeOption.dark
                                    ? '当前：强制深色'
                                    : '当前：强制浅色',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(settingsControllerProvider.notifier)
                          .setMode(ThemeModeOption.system),
                      child: const Text('跟随系统', style: TextStyle(fontSize: 11)),
                    ),
                    Switch(
                      value: _isDarkNow(context, settings),
                      onChanged: (v) => ref
                          .read(settingsControllerProvider.notifier)
                          .setMode(v ? ThemeModeOption.dark : ThemeModeOption.light),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(
                        child: Text('Aa 字体大小',
                            style:
                                TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    SizedBox(
                      width: 120,
                      child: Slider(
                        value: 1,
                        max: 3,
                        onChanged: (_) =>
                            _toast(context, '字号调节 V1.x（无障碍）上线'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 底部导航自定义卡
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('🧭 底部导航栏自定义',
                            style:
                                TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                    Text(
                      '已启用 ${settings.navIds.length}/5',
                      style: TextStyle(
                          fontSize: 11,
                          color: tokens.accent,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const Text('开启的栏目实时出现在底部导航；「今天」「我的」固定',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 6),
                _NavToggleGrid(settings: settings),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _toast(context, '主页编排 M0 末接入'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: tokens.accent.withValues(alpha: .06),
                      foregroundColor: tokens.accent,
                      side: BorderSide(color: tokens.accent.withValues(alpha: .3)),
                    ),
                    child: const Text('🧩 主页编排直达 ›',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 关于卡
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: context.cardDecoration,
            child: const Text(
              '关于\n\nLifeHarness V0.1（M0）· 需求 V1.18 基线\n'
              '仅中文 ｜ 纯本地无账号 ｜ Android 8.0+ ｜ 离线优先 ｜ AI 能力可选增强\n'
              '数据库 sqflite（v2）· 7 套主题设计令牌 · 宿主能力 API v0 已预埋',
              style: TextStyle(fontSize: 11.5, height: 1.7, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isDarkNow(BuildContext context, UserSettings s) {
    if (s.mode == ThemeModeOption.dark) return true;
    if (s.mode == ThemeModeOption.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1500)));
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: child,
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: context.cardDecoration,
        child: Column(
          children: [
            Text(value,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.emoji,
    required this.bg,
    required this.title,
    required this.sub,
    required this.trailing,
    this.last = false,
    required this.onTap,
  });

  final String emoji;
  final Color bg;
  final String title;
  final String sub;
  final String trailing;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: Color(0x14000000))),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Text(emoji, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Text(trailing, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            const Text(' ›', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// 主题预览缩略卡 3 列（原型 themeStyleRow）。
class _ThemeGrid extends ConsumerWidget {
  const _ThemeGrid({required this.registry, required this.selectedId});

  final ThemeRegistry registry;
  final String selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        const cols = 3;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final b in registry.all)
              SizedBox(
                width: w,
                child: _ThemeTile(
                  bundle: b,
                  selected: b.id == selectedId,
                  onTap: () {
                    ref.read(settingsControllerProvider.notifier).setTheme(b.id);
                    ref.read(eventBusProvider).publish(ThemeChangedEvent(b.id));
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.bundle, required this.selected, required this.onTap});

  final ThemeBundle bundle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = bundle.pick(Theme.of(context).brightness == Brightness.dark);
    final darkBg =
        ThemeData.estimateBrightnessForColor(t.card) == Brightness.dark;
    final labelColor = darkBg ? Colors.white70 : Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? t.accent : t.cardBorder, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                  gradient: t.gradient, borderRadius: BorderRadius.circular(5)),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                    child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: .35),
                            borderRadius: BorderRadius.circular(3)))),
                const SizedBox(width: 3),
                Expanded(
                    child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                            color: t.page,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: t.cardBorder)))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(bundle.meta.name,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected ? t.accent : labelColor),
                      overflow: TextOverflow.ellipsis),
                ),
                if (selected) Icon(Icons.check_circle, size: 13, color: t.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏栏目两列开关网格。
class _NavToggleGrid extends ConsumerWidget {
  const _NavToggleGrid({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = {NavModule.today.id, NavModule.settings.id};
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [
            for (final m in NavModule.values)
              SizedBox(
                width: w,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pinned.contains(m.id) ? '${m.label}（固定）' : m.label,
                        style: const TextStyle(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Switch(
                      value: settings.navIds.contains(m.id),
                      onChanged: pinned.contains(m.id)
                          ? null
                          : (_) async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await ref
                                  .read(settingsControllerProvider.notifier)
                                  .toggleNav(m);
                              if (!ok) {
                                messenger.showSnackBar(
                                    const SnackBar(content: Text('底部导航最多 5 个栏目')));
                              }
                            },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
