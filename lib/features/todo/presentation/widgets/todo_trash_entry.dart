import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/trash/trash_models.dart';
import '../../../../shared/trash/trash_providers.dart';

/// 待办页底部回收站入口（原型 p-todo 末卡 · V1.60 改道）。
///
/// 旧态＝push 待办自有垃圾箱专屏（`/todo/trash`，本批随统一屏落地已下架）；
/// 现态＝直达全局回收站并落「待办」分段，计数与屏内 chips、记录管理行同源。
class TodoTrashEntry extends ConsumerWidget {
  const TodoTrashEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(trashCountsProvider).byKind[TrashKind.todo] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: InkWell(
        key: const ValueKey('todo-trash-entry'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/settings/trash?seg=todo'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: context.cardDecoration,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFF64748B)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('回收站',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('待办 $n 项 · 保留期内可恢复',
                        key: const ValueKey('todo-trash-meta'),
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
              const Text('›',
                  style: TextStyle(fontSize: 16, color: Color(0xFFCBD5E1))),
            ],
          ),
        ),
      ),
    );
  }
}
