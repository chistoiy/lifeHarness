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
}
