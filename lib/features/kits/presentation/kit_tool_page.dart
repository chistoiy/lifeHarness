import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/kit_models.dart';

/// 工具屏容器（原型 `#p-toolDetail`）。
///
/// 批0 只提供统一外壳（标题 + 主体插槽 + 隐私页脚）；13 个工具主体
/// 随批2（计算/随机/色彩）与批3（网络/长度/图片/编码/演示）逐个实装。
class KitToolPage extends ConsumerWidget {
  const KitToolPage({super.key, required this.toolKey});

  final String toolKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = kitToolOf(toolKey);
    if (tool == null) {
      return Scaffold(
        appBar: AppBar(centerTitle: true, title: const Text('工具未登记')),
        body: const Center(
            child: Text('该工具不在内置清单内',
                style: TextStyle(fontSize: 12.5, color: Colors.grey))),
      );
    }
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tool.name),
            Text('小工具合集 · ${tool.cat.label}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            key: ValueKey('kit-body-$toolKey'),
            padding: const EdgeInsets.all(16),
            decoration: context.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tool.icon, size: 26, color: tokens.accent),
                const SizedBox(height: 8),
                Text(tool.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('工具主体随批2 / 批3 实装',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(tool.privacy,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
