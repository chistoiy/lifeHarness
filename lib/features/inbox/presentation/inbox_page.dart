import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

/// 模块5 收集箱（V0.1 骨架占位，四向分流：待办/日程/笔记/日记）。
class InboxPage extends StatelessWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context) => const ModulePlaceholderPage(
        title: '收集箱',
        icon: Icons.inbox_outlined,
        summary: '随手捕捉，稍后四向分流到待办 / 日程 / 笔记 / 日记，降低记录摩擦。',
        todos: [
          '快速捕捉未分类条目',
          '四向分流与目标回填',
          '与悬浮球快捷记录联动',
          'AI 智能分流（M3，关机时零网络）',
        ],
      );
}
