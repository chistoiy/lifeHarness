import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'baby_view.dart';
import 'care_providers.dart';
import 'cycle_view.dart';

/// 呵护模块顶层壳（原型 p-care / p-baby 两整屏 · TITLES 头同构）。
///
/// 红线 2：周期/宝宝点左上角标题互切、均无返回键、互切不堆返回栈——
/// 实现为同一路由 /care 内的 [careViewProvider] 状态切换；退出走底部导航。
/// 红线 3：「照护汇总」钮仅宝宝视图显示。
class CarePage extends ConsumerWidget {
  const CarePage({super.key});

  static const cycleTitle = ['呵护 · 周期', '生理周期 · 排卵预测'];
  static const babyTitle = ['呵护 · 宝宝', '照护记录 · 事件速记'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(careViewProvider);
    final baby = view == 'baby';
    final t = baby ? babyTitle : cycleTitle;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false, // 无返回键（红线 2）
        title: GestureDetector(
          key: const ValueKey('care-swap'),
          onTap: () => ref
              .read(careViewProvider.notifier)
              .state = baby ? 'cycle' : 'baby',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t[0]),
              Text(
                t[1],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (baby)
            IconButton(
              key: const ValueKey('care-stats-btn'),
              tooltip: '照护汇总',
              icon: const Icon(Icons.insights_rounded, size: 22),
              onPressed: () => context.push('/care/stats'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: baby ? const CareBabyView() : const CareCycleView(),
    );
  }
}
