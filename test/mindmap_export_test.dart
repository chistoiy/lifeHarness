import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_export.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';

/// 批2 F4-5 · 导出序列化层（工单 §4c.3 ②）。纯 Dart 零 Flutter 依赖。
/// HTML 硬口径（冻结方案 §4.10）全在本文件钉死——含变异刀1 的隐私默认关。
void main() {
  List<MindmapNode> sampleRows() {
    var t = 1000;
    MindmapNode mk(int id, int? pid, String title, {int sort = 0}) =>
        MindmapNode(
          id: id,
          mapId: 1,
          parentId: pid,
          title: title,
          sort: sort,
          createdAt: t++,
          updatedAt: t,
        );
    return [
      mk(1, null, '根A'),
      mk(2, 1, '子A1', sort: 0),
      mk(3, 1, '子A2', sort: 1),
      mk(4, 2, '孙A1a'),
      mk(5, null, '根B'),
    ];
  }

  group('md 导出（缩进通道 round-trip 保真）', () {
    test('两空格一级缩进、兄弟按 sort、多根各成顶层行', () {
      final md = mmExportMarkdown(sampleRows());
      final lines = md.trim().split('\n');
      expect(lines, [
        '根A',
        '  子A1',
        '    孙A1a',
        '  子A2',
        '根B',
      ]);
    });

    test('导出件零 `#`（再导入必走缩进通道＝round-trip 保真的前提）', () {
      expect(mmExportMarkdown(sampleRows()), isNot(contains('#')));
    });

    test('标题内换行折成空格（单行大纲语义）', () {
      final rows = [
        MindmapNode(
          id: 1,
          mapId: 1,
          title: '一行\n两行',
          createdAt: 1,
          updatedAt: 1,
        ),
      ];
      expect(mmExportMarkdown(rows).trim(), '一行 两行');
    });
  });

  group('opml 导出', () {
    test('嵌套 outline 结构＋text 属性＋XML 转义', () {
      final rows = sampleRows();
      rows[0] = MindmapNode(
        id: 1,
        mapId: 1,
        parentId: null,
        title: '根<名>&"引"',
        note: '备注&<x>',
        sort: 0,
        createdAt: 1,
        updatedAt: 1,
      );
      final opml = mmExportOpml('我的<图>', rows);
      expect(opml, contains('<opml version="2.0">'));
      expect(opml, contains('<title>我的&lt;图&gt;</title>'));
      expect(opml, contains('text="根&lt;名&gt;&amp;&quot;引&quot;"'));
      expect(opml, contains('_note="备注&amp;&lt;x&gt;"'));
      // 嵌套层级：孙在子内
      final sunIdx = opml.indexOf('孙A1a');
      final a2Idx = opml.indexOf('子A2');
      expect(sunIdx, greaterThan(opml.indexOf('子A1')));
      expect(a2Idx, greaterThan(sunIdx));
    });
  });

  group('HTML 导出（§4.10 冻结规格）', () {
    late Map<int, Offset> baseline;
    late Map<int, Size> sizes;

    setUp(() {
      baseline = {
        1: const Offset(0, 0),
        2: const Offset(24, 46),
        3: const Offset(24, 92),
      };
      sizes = {
        1: const Size(120, 36),
        2: const Size(100, 36),
        3: const Size(140, 36),
      };
    });

    List<MmExportNode> exportNodes({
      bool withBody = false,
      String title = '测试图',
    }) =>
        [
          MmExportNode(
            id: 1,
            parentId: null,
            displayTitle: '根A',
            noteTitle: '笔记标题快照',
            noteBody: withBody ? '笔记正文内容' : null,
          ),
          MmExportNode(id: 2, parentId: 1, displayTitle: '子A1'),
          MmExportNode(
            id: 3,
            parentId: 1,
            displayTitle: '子A2',
            note: '节点备注',
            folded: true,
          ),
        ];

    String html({bool withBody = false}) => mmExportHtml(
          mapTitle: '测试图',
          nodes: exportNodes(withBody: withBody),
          baseline: baseline,
          sizes: sizes,
          boundsWidth: 300,
          boundsHeight: 200,
          landscapePreset: false,
          exportedAt: '2026-10-12 22:00',
        );

    test('单文件自包含：零外链（无 http 引用/CDN/import 语句）', () {
      final h = html();
      expect(h.startsWith('<!doctype html>'), isTrue);
      expect(h, isNot(contains('http://')));
      expect(h, isNot(contains('https://')));
      expect(h, isNot(contains('@import')));
      expect(h, isNot(contains('<link')));
      // CSS/JS 都内联
      expect(h, contains('<style>'));
      expect(h, contains('<script>'));
    });

    test('深浅两套令牌内联（prefers-color-scheme）', () {
      final h = html();
      expect(h, contains('prefers-color-scheme:dark'));
      expect(h, contains('--bg:'));
    });

    test('挂载只导标题：默认不带正文（§4.10 隐私硬口径·变异刀1 钉点）', () {
      final h = html();
      expect(h, contains('笔记标题快照'), reason: '标题快照恒导出');
      expect(h, isNot(contains('笔记正文内容')), reason: '正文默认不进文件');
      // 带正文的形态只在调用侧显式传 noteBody 时出现
      final hb = html(withBody: true);
      expect(hb, contains('笔记正文内容'));
    });

    test('DATA 注入：坐标/尺寸/折叠态/标题齐全，`<` 已转义', () {
      final h = html();
      expect(h, contains('var DATA={'));
      expect(h, contains('"t":"根A"'));
      expect(h, contains('"x":0'));
      expect(h, contains('"fold":true'));
      expect(h, contains('测试图'));
      // 标题含 </script> 不断内联 script：`<` 已全转 \u003c。
      // 模板自身恰有两个 </script>（DATA 块＋主脚本块）＝不多不少。
      final evil = mmExportHtml(
        mapTitle: 'x</script><script>alert(1)</script>',
        nodes: exportNodes(),
        baseline: baseline,
        sizes: sizes,
        boundsWidth: 10,
        boundsHeight: 10,
        landscapePreset: false,
        exportedAt: 'now',
      );
      expect('</script>'.allMatches(evil).length, 2,
          reason: '恶意标题转义后，收尾标签只剩模板自身的两个');
    });

    test('横向预设位与导出时间在文件里', () {
      final h = html();
      expect(h, contains('exportedAt'));
      final hl = mmExportHtml(
        mapTitle: '横图',
        nodes: exportNodes(),
        baseline: baseline,
        sizes: sizes,
        boundsWidth: 300,
        boundsHeight: 200,
        landscapePreset: true,
        exportedAt: '2026-10-12',
      );
      expect(hl, contains('"landscape":true'));
    });

    test('折叠节点在 DATA 标 fold（HTML 侧初始折叠）', () {
      final h = html();
      expect(h, contains('"fold":true'));
    });
  });
}
