import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

/// 模块1 日程 + 时间块（V0.1 骨架占位，M0 后段填充日/周/月与格子标记）。
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) => const ModulePlaceholderPage(
        title: '日程',
        icon: Icons.calendar_month_outlined,
        summary: '日/周/月视图 + 格子时间块标记，进行中事项两态流实时记录（需求 V1.12）。',
        todos: [
          '日视图格子（1-60 分钟粒度）',
          '按住拖选多格 → 标记着色',
          '▶ 开始 / ■ 结束 两态流 + 悬浮计时条',
          '日历智能折叠为周行 + 滑动切天',
        ],
      );
}
