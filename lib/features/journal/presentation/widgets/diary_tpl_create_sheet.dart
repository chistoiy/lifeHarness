import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart' show AppToast;
import '../../data/diary_template_dao.dart';
import '../../domain/diary_template.dart';

/// 日记模板「新建」弹层（原型 `sheetDiaryTplEdit`）：名称 + 分节增删。
///
/// 从 `diary_edit_page.dart` 抽出（思维导图批2 面5 · 2026-10-13）：
/// 该页已登记 size_budget 1370 行且「只许减不许增」，卡片接线要加行，
/// 故先把这枚自足弹层搬成同目录独立件——**格面行为零改动**，
/// 只把三个宿主依赖改成参数：[dao]（读 provider 改传参）、
/// [onCreated]（原 `_pickTemplate`）、[onListChanged]（原 `_tplListKey++` ＋ invalidate）。
///
/// 返回：新建成功时 [onCreated] 已同步应用模板，本函数只负责收尾通知。
Future<void> showDiaryTplCreateSheet(
  BuildContext context, {
  required DiaryTemplateDao dao,
  required void Function(DiaryTemplate) onCreated,
  VoidCallback? onListChanged,
}) async {
  final nameCtl = TextEditingController();
  final secTitle = [TextEditingController(), TextEditingController()];
  final secPh = [TextEditingController(), TextEditingController()];
  final tokens = context.tokens;
  var addTick = 0;
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (bc) => StatefulBuilder(
      builder: (bc2, setLocal) => Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16,
            24 + MediaQuery.viewInsetsOf(bc2).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新建模板',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('tpl-name'),
              controller: nameCtl,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                  isDense: true, hintText: '模板名称，如：每日三省'),
            ),
            const SizedBox(height: 10),
            Text('分节',
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tokens.accent)),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < secTitle.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        key: ValueKey('tpl-sec-$i-$addTick'),
                        children: [
                          Expanded(
                            child: TextField(
                              controller: secTitle[i],
                              style: const TextStyle(fontSize: 12.5),
                              decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '分节 ${i + 1} 标题，如：今日高光'),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              if (secTitle.length <= 1) return;
                              setLocal(() {
                                secTitle[i].dispose();
                                secPh[i].dispose();
                                secTitle.removeAt(i);
                                secPh.removeAt(i);
                                addTick++;
                              });
                            },
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('tpl-add-sec'),
                    onPressed: () => setLocal(() {
                      secTitle.add(TextEditingController());
                      secPh.add(TextEditingController());
                      addTick++;
                    }),
                    child: const Text('＋ 添加分节',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.of(bc2).pop(false),
                      child: const Text('取消')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    key: const ValueKey('tpl-save'),
                    onTap: () async {
                      final name = nameCtl.text.trim();
                      final secs = [
                        for (var i = 0; i < secTitle.length; i++)
                          if (secTitle[i].text.trim().isNotEmpty)
                            TemplateSection(
                                title: secTitle[i].text.trim(),
                                placeholder: secPh[i].text.trim().isEmpty
                                    ? null
                                    : secPh[i].text.trim()),
                      ];
                      if (name.isEmpty || secs.isEmpty) {
                        AppToast.show(bc2, '请填写模板名称与至少一个分节',
                            ms: 1400);
                        return;
                      }
                      final id = await dao
                          .create(DiaryTemplate(name: name, sections: secs));
                      if (!bc2.mounted) return;
                      Navigator.of(bc2).pop(true);
                      if (bc2.mounted) {
                        AppToast.show(bc2, '模板已创建 · $name', ms: 1400);
                      }
                      // 直接应用新模板
                      final all = await dao.list();
                      final created2 = all.firstWhere((t) => t.id == id);
                      onCreated(created2);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                          gradient: tokens.gradient,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Text('保存模板',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  nameCtl.dispose();
  for (final c in secTitle) {
    c.dispose();
  }
  for (final c in secPh) {
    c.dispose();
  }
  if (created == true) onListChanged?.call();
}