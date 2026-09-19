import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nav/nav_module.dart';
import '../../../core/providers.dart';
import '../../../core/settings/user_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/linkage_events.dart';

/// 我的/设置（V0.1 骨架）：主题风格、深色模式、底部导航栏目配置。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsControllerProvider);
    final registry = ref.watch(themeRegistryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: '主题风格',
            subtitle: '设计令牌换肤，实时生效（与原型 themes/ 同构，共 ${registry.ids.length} 套）',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in registry.all)
                  ChoiceChip(
                    label: Text(b.meta.name),
                    avatar: CircleAvatar(
                      backgroundColor: b.dark.accent,
                      radius: 7,
                    ),
                    selected: settings.themeId == b.id,
                    onSelected: (_) {
                      ref.read(settingsControllerProvider.notifier)
                          .setTheme(b.id);
                      ref.read(eventBusProvider).publish(
                          ThemeChangedEvent(b.id));
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: '深色模式',
            subtitle: '与主题风格正交，可叠加（强制深色主题除外）',
            child: SegmentedButton<ThemeModeOption>(
              segments: const [
                ButtonSegment(value: ThemeModeOption.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeModeOption.light, label: Text('浅色')),
                ButtonSegment(value: ThemeModeOption.dark, label: Text('深色')),
              ],
              selected: {settings.mode},
              onSelectionChanged: (s) => ref
                  .read(settingsControllerProvider.notifier)
                  .setMode(s.first),
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: '底部导航栏目',
            subtitle: '今天/我的固定，最多 5 个（需求 V1.5）',
            child: Column(
              children: [
                for (final m in NavModule.values)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.label),
                    value: settings.navIds.contains(m.id),
                    onChanged: (m == NavModule.today || m == NavModule.settings)
                        ? null
                        : (_) async {
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await ref
                                .read(settingsControllerProvider.notifier)
                                .toggleNav(m);
                            if (!ok) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('底部导航最多 5 个栏目')),
                              );
                            }
                          },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: '关于',
            subtitle: null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LifeHarness V0.1（M0 骨架）',
                    style: TextStyle(color: tokens.accent, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                  '纯本地 · 无账号 · 离线可用。数据库 sqflite（4 核心表 + 预留表 + plugin_* 规范）'
                  '已随启动建库；宿主能力 API 基线 v0（模块注册表/挂载点/事件总线）已预埋。',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
