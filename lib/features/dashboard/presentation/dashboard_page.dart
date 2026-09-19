import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/nav/nav_module.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';

/// 模块6 仪表盘（今日首页，V0.1 骨架）。
///
/// 已呈现：品牌 hero、日期概览、全模块宫格快捷入口（含未入底栏模块）。
/// 主页卡片自由编排（拖拽）在 M0 后段接入。
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final bundle = ref.watch(currentThemeBundleProvider);
    final now = DateTime.now();
    final dateStr =
        '${now.month}月${now.day}日 星期${_weekdays[now.weekday - 1]}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('今天'),
        actions: [
          IconButton(
            tooltip: '我的 / 设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(NavModule.settings.path),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: tokens.gradient,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              boxShadow: tokens.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  'LifeHarness · 你的生活，一处尽览',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'V0.1 骨架已启动 ｜ 当前主题：${bundle.meta.name}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '全部模块',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          _ModuleGrid(modules: NavModule.values),
        ],
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({required this.modules});

  final List<NavModule> modules;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        const columns = 4;
        const spacing = 10.0;
        final itemW = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final m in modules)
              SizedBox(
                width: itemW,
                child: _ModuleTile(module: m),
              ),
          ],
        );
      },
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final NavModule module;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      onTap: () => context.go(module.path),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: context.cardDecoration,
        child: Column(
          children: [
            Icon(module.icon, color: tokens.accent),
            const SizedBox(height: 6),
            Text(
              module.label,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
