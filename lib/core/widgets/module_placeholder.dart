import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 模块占位页（V0.1 骨架）：统一的品牌 hero 卡 + 待建说明。
///
/// 各 feature 页在 M0 阶段复用此组件占位，后续里程碑以真实业务 UI 替换 body。
class ModulePlaceholderPage extends StatelessWidget {
  const ModulePlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.summary,
    this.todos = const [],
  });

  final String title;
  final IconData icon;
  final String summary;
  final List<String> todos;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: tokens.gradient,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              boxShadow: tokens.cardShadow,
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    summary,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: context.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本模块为 V0.1 骨架占位',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                for (final t in todos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('· ', style: TextStyle(color: tokens.accent)),
                        Expanded(
                          child: Text(
                            t,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
