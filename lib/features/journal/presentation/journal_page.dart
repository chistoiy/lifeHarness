import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

/// 模块3 日记（V0.1 纯文本日记占位，M1 升级富文本/图片/心情/INS 卡片流）。
class JournalPage extends StatelessWidget {
  const JournalPage({super.key});

  @override
  Widget build(BuildContext context) => const ModulePlaceholderPage(
        title: '日记',
        icon: Icons.book_outlined,
        summary: 'V0.1 提供纯文本日记；M1 起升级心情、标签、月度概览与 INS 卡片流。',
        todos: [
          '纯文本日记的记与读',
          '心情打卡与迷你月历',
          '日记列表筛选 / 时间线卡片',
          '富文本与图片附件（M1）',
        ],
      );
}
