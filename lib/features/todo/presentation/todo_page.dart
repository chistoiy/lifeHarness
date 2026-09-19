import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

/// 模块2 待办 + 四象限（V0.1 骨架占位，M0 后段填充基础 CRUD）。
class TodoPage extends StatelessWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context) => const ModulePlaceholderPage(
        title: '待办',
        icon: Icons.check_circle_outline,
        summary: '四象限为核心交互：清单 + 紧急/重要矩阵，体现时间管理理念（ADR D3）。',
        todos: [
          '任务增删改与勾选完成',
          '四象限视图与拖拽换象限',
          '引导式判象限录入',
          '到期 / 提醒字段（M1 接入通知）',
        ],
      );
}
