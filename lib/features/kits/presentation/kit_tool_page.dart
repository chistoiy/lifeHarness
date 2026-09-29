import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/kit_models.dart';
import 'tools/kit_comp_page.dart';
import 'tools/kit_datec_page.dart';
import 'tools/kit_dist_page.dart';
import 'tools/kit_imgz_page.dart';
import 'tools/kit_pick_page.dart';
import 'tools/kit_ping_page.dart';
import 'tools/kit_rand_page.dart';
import 'tools/kit_ruler_page.dart';
import 'tools/kit_speed_page.dart';
import 'tools/kit_wheel_page.dart';

/// 工具屏容器（原型 `#p-toolDetail`）。
///
/// 外壳统一（标题 + 主体 + 隐私页脚）；主体由各工具屏文件提供，
/// [kitToolBody] 是唯一的登记面——批2 起逐批把占位替换为真实屏。
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
          child: Text(
            '该工具不在内置清单内',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
        ),
      );
    }
    final body = kitToolBody(toolKey);
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tool.name),
            Text(
              '小工具合集 · ${tool.cat.label}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
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
            child: body ??
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(tool.icon, size: 26, color: tokens.accent),
                    const SizedBox(height: 8),
                    Text(
                      tool.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '工具主体随批2 / 批3 实装',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              tool.privacy,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

/// 已实装的工具屏主体（未实装返回 null → 外壳显示占位）。
Widget? kitToolBody(String key) => switch (key) {
      kitToolKeyDatec => const KitDatecBody(),
      kitToolKeyRand => const KitRandBody(),
      kitToolKeyWheel => const KitWheelBody(),
      kitToolKeyPick => const KitPickBody(),
      kitToolKeyComp => const KitCompBody(),
      kitToolKeyPing => const KitPingBody(),
      kitToolKeySpeed => const KitSpeedBody(),
      kitToolKeyRuler => const KitRulerBody(),
      kitToolKeyDist => const KitDistBody(),
      kitToolKeyImgz => const KitImgzBody(),
      _ => null,
    };
