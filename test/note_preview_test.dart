import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/domain/note_preview.dart';

/// 批7 A1（2026-11-08 · 评估件 A1）· 卡片摘要清洗常驻用例。
///
/// 锁的是**需求口径**而不是当前实现：真机三视图（2 列 / 3 列 / 列表）的摘要里
/// 不允许出现裸 Markdown 结构标记——`#`、`**`、`- `、围栏、表格竖线、`[ ]`，
/// 也不允许把「首行标题」重复成第二遍。
void main() {
  group('notePreviewText · 裸标记清零', () {
    test('标题 / 加粗 / 列表符都不进摘要', () {
      const body = '## **开篇总纲**\n\n'
          '- 学习→复述→输出→反馈的闭环。\n'
          '- **可套用**到读书摘录流程。';
      final p = notePreviewText(body);
      expect(p, isNot(contains('#')));
      expect(p, isNot(contains('*')));
      expect(p, isNot(contains('\n')));
      expect(p, startsWith('开篇总纲'));
      expect(p, contains('可套用到读书摘录流程'));
    });

    test('去掉与标题同文的首行标题（不重复同一句）', () {
      const body = '# App 命名候选清单\n\nLifeHarness / 日子值 / 每一天';
      final p = notePreviewText(body, title: 'App 命名候选清单');
      expect(p, 'LifeHarness / 日子值 / 每一天');
    });

    test('首行不是标题时，即使与标题同文也保留（防误删正文）', () {
      const body = 'App 命名候选清单\n后面还有正文';
      final p = notePreviewText(body, title: 'App 命名候选清单');
      expect(p, startsWith('App 命名候选清单'));
      expect(p, contains('后面还有正文'));
    });

    test('围栏代码块整块不进摘要', () {
      const body = '前文\n```dart\nfinal a = 1;\n```\n后文';
      expect(notePreviewText(body), '前文 后文');
    });

    test('图片留 alt，无 alt 交「图片」', () {
      expect(notePreviewText('![封面](assets/x.png)'), '封面');
      expect(notePreviewText('![](assets/x.png)'), '图片');
    });

    test('链接只留文字', () {
      expect(notePreviewText('[官方博客](https://example.com)'), '官方博客');
    });

    test('表格竖线与分割线不进摘要', () {
      const body = '| 模式 | 用途 |\n| --- | --- |\n| 写作 | 沉浸式 |';
      final p = notePreviewText(body);
      expect(p, '模式 用途 写作 沉浸式');
    });

    test('待办勾选框不进摘要', () {
      expect(notePreviewText('- [ ] 买菜'), '买菜');
      expect(notePreviewText('- [x] 已买牛奶'), '已买牛奶');
    });

    test('多空行 / CRLF 压成单空格', () {
      expect(notePreviewText('第一段\r\n\r\n\r\n第二段'), '第一段 第二段');
    });

    test('空正文回落占位', () {
      expect(notePreviewText('   \n\n  '), kNotePreviewBlank);
      expect(notePreviewText('```\ncode\n```'), kNotePreviewBlank);
    });

    test('超长截断到上限并加省略号', () {
      final p = notePreviewText('甲' * 100);
      expect(p.runes.length, kNotePreviewMax + 1);
      expect(p.endsWith('…'), isTrue);
    });
  });

  group('Note.preview · 三视图同一读数', () {
    Note make(String content, {String kind = 'plain', String title = ''}) =>
        Note(
          title: title,
          content: content,
          kind: kind,
          createdAt: DateTime(2026, 11, 8),
          updatedAt: DateTime(2026, 11, 8),
        );

    test('富文本仍先展开 Delta JSON，再清洗', () {
      final n = make(
        jsonEncode([
          {
            'insert': '## 富文本第一段\n'
          },
          {
            'insert': {'image': 'a.png'}
          },
        ]),
        kind: 'rich',
      );
      expect(n.preview, contains('富文本第一段'));
      expect(n.preview, contains('图片'));
      expect(n.preview, isNot(contains('{')));
      expect(n.preview, isNot(contains('#')));
    });

    test('同一笔记反复取摘要逐字节一致（卡片 / 列表 / 搜索共用）', () {
      final n = make('## 小标题\n- 甲\n- 乙');
      expect(n.preview, n.preview);
      expect(n.preview, notePreviewText(n.displayBody, title: n.title));
    });
  });
}
