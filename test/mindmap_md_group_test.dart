import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/md_parse.dart';

/// 思维导图批P · md 单层标题并入中心主题守护（工单 §7 P2）。
/// 纯 Dart 级：判定在解析层、并根在域函数，两处都不碰 DAO，故可离界面单测。
void main() {
  group('单层标题判定', () {
    test('全 H1 文档 ⇒ singleLevel', () {
      final r = parseMdOutline('# 甲\n# 乙\n# 丙\n');
      expect(r.roots.map((n) => n.title), ['甲', '乙', '丙']);
      expect(r.singleLevel, isTrue);
    });

    test('有 H2 存在 ⇒ 不是单层', () {
      final r = parseMdOutline('# 甲\n## 甲的子\n# 乙\n');
      expect(r.singleLevel, isFalse);
    });

    test('单根不算单层（单根本来就有中心，无从「并入」）', () {
      final r = parseMdOutline('# 只有一根\n');
      expect(r.roots, hasLength(1));
      expect(r.singleLevel, isFalse);
    });

    test('空行分段的两枚并列根（无标题通道）也是单层', () {
      // 无 # 无缩进走空行通道：空行分段，每段一枚根。
      final r = parseMdOutline('甲\n\n乙\n');
      expect(r.roots.map((n) => n.title), ['甲', '乙']);
      expect(r.singleLevel, isTrue);
      // 反证：同段两行合并成一枚根 ⇒ 只有一根，不算「单层」（CLI 侧口径）。
      final one = parseMdOutline('甲\n乙\n');
      expect(one.roots, hasLength(1));
      expect(one.singleLevel, isFalse);
    });
  });

  group('并入中心主题', () {
    test('并根后只剩一枚根，原并列项成其第一层', () {
      final r = parseMdOutline('# 甲\n# 乙\n# 丙\n');
      final joined = mmMdJoinUnderCenter(r.roots, '晨间流程清单');
      expect(joined, hasLength(1));
      expect(joined.single.title, '晨间流程清单');
      expect(joined.single.children.map((n) => n.title), ['甲', '乙', '丙']);
      for (final c in joined.single.children) {
        expect(c.children, isEmpty, reason: '单层文档的项本身没有子级');
      }
    });

    test('空标题回落「中心主题」；不改入参', () {
      final r = parseMdOutline('# 甲\n# 乙\n');
      final joined = mmMdJoinUnderCenter(r.roots, '  ');
      expect(joined.single.title, '中心主题');
      expect(r.roots, hasLength(2), reason: '返回新列表，入参不动');
    });

    test('并根后整体重新拍平：0/1 两档、无孤立项', () {
      final r = parseMdOutline('# 甲\n# 乙\n# 丙\n');
      final flat = flattenMdTree(mmMdJoinUnderCenter(r.roots, '中心'));
      expect(flat, [('中心', 0), ('甲', 1), ('乙', 1), ('丙', 1)]);
    });

    test('不并根时拍平就是原来的 N 并列根', () {
      final r = parseMdOutline('# 甲\n# 乙\n');
      expect(flattenMdTree(r.roots), [('甲', 0), ('乙', 0)]);
    });
  });

  // 2026-10-29 补（产品报障两条）：
  // ①「二级 head 不是顶格就不被识别」——标题正则改为允许 0~3 前导空格；
  // ②「md 导入后正文没进去」——标题通道改吃列表项（列表是内容不是层级信号）。
  group('缩进标题与列表（2026-10-29）', () {
    test('前导空白的标题仍是标题（2 空格/4 空格都认·原整篇掉进缩进通道）', () {
      final r = parseMdOutline('# 一\n  ## 一·甲\n');
      expect(r.roots.map((n) => n.title), ['一']);
      expect(r.roots.single.children.map((n) => n.title), ['一·甲'],
          reason: '前导 2 空格的标题仍是标题，不是缩进行');
      // 4 空格：CommonMark 会当代码块，但笔记/剪贴板来源的 md 里它就是标题
      // （刻意宽于规范，见 `md_parse.dart` 头注）。
      final deep = parseMdOutline('# 一\n    ## 一·乙\n');
      expect(deep.roots.single.children.map((n) => n.title), ['一·乙']);
    });

    test('整体带缩进的文档照样分得出层级', () {
      final r = parseMdOutline('  ## 甲\n  - 甲一\n  ## 乙\n');
      expect(r.roots.map((n) => n.title), ['甲', '乙']);
      expect(r.roots.first.children.map((n) => n.title), ['甲一'],
          reason: '列表项挂当前标题下（缩进只决定它在标题下的第几层）');
    });

    test('标题通道吃列表项：笔记/收集箱 md 的主体形态', () {
      final r = parseMdOutline('## 一\n- 甲\n- 乙\n## 二\n- 丙\n');
      expect(r.roots.map((n) => n.title), ['一', '二']);
      expect(r.roots[0].children.map((n) => n.title), ['甲', '乙']);
      expect(r.roots[1].children.map((n) => n.title), ['丙']);
    });

    test('列表缩进每 2 空格再深一层', () {
      final r = parseMdOutline('## 一\n- 甲\n  - 甲一\n');
      final a = r.roots.single.children;
      expect(a.map((n) => n.title), ['甲']);
      expect(a.single.children.map((n) => n.title), ['甲一']);
    });
  });
}
