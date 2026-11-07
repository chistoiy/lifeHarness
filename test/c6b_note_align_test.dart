/// C 案批6b · 笔记 N1/N4/N5/N6/N7 对齐常驻守护（2026-11-07）。
/// 规格＝`docs/handoff/交棒话术-20261107-记录四模块拆分C案批1路由与底栏池.md` §14 裁定记录。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('① N1 多选底条悬浮圆角卡（横外距＋圆角＋阴影，去顶描边）', () {
    final s = File('lib/features/journal/presentation/note_tab.dart')
        .readAsStringSync();
    expect(s, contains("margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),"),
        reason: '悬浮卡外距被摘除');
    expect(s, isNot(contains("border: Border(top: BorderSide(color: tokens.cardBorder))")),
        reason: '贴底顶描边形态复活');
  });

  test('② N4 空态 dashed＋文案带指引后缀', () {
    final s = File('lib/features/journal/presentation/note_tab.dart')
        .readAsStringSync();
    expect(s, contains('dashed: true'), reason: '空态虚线框未启用');
    expect(s, contains('该来源下暂无笔记 · 换个来源试试'), reason: '来源空态文案回退');
    final k = File('lib/shared/widgets/ui_kit.dart').readAsStringSync();
    expect(k, contains('class _DashBorderPainter'), reason: '虚线画笔被摘除');
    expect(k, contains('this.dashed = false'), reason: 'dashed 参数被摘除');
  });

  test('③ N5 多选计数数字品牌色高亮', () {
    final s = File('lib/features/journal/presentation/note_tab.dart')
        .readAsStringSync();
      expect(s, contains(r"Text('${sel.length}',"), reason: '计数字段被合并回整句');
  });

  test('④ N6 笔记 FAB 图标 ✎（Icons.edit）', () {
    final s = File('lib/features/journal/presentation/journal_page.dart')
        .readAsStringSync();
    expect(s, contains('_open ? Icons.close : Icons.edit'), reason: 'FAB 回退 add');
  });

  test('⑤ N7 三处文案口径（本地文件/FAB 三选/撤销带标题）', () {
    final t = File('lib/features/journal/presentation/note_toolbar_actions.dart')
        .readAsStringSync();
    expect(t, contains("'本地文件'"), reason: '来源筛选文案回退');
    final j = File('lib/features/journal/presentation/journal_page.dart')
        .readAsStringSync();
    expect(j, contains("'添加富文本', 'rich'"), reason: 'FAB 三选文案回退');
    expect(j, isNot(contains('添加富文本笔记')), reason: '旧文案复活');
    final n = File('lib/features/journal/presentation/note_tab.dart')
        .readAsStringSync();
    expect(n, contains("已移入回收站 · \${n.title} · 30 天内可恢复"),
        reason: '撤销 toast 不带笔记名');
  });
}
