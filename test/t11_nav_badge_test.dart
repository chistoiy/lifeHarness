import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/core/nav/nav_badge.dart';

/// 交互整改 T11（底栏角标）常驻用例 · 纯函数与源码守护段。
///
/// 版式事实源＝壳原型 `.navbadge`（2026-10-05 产品过门「照修后版式接」）。
/// 整 app 的显隐与「进入即清」在 `test/t11_nav_badge_shell_test.dart`
/// （全 app 用例按仓库规矩单独成文件，防 isolate 污染挂死）。
void main() {
  group('1 · 角标口径（与原型一字不差）', () {
    test('未登记数据源的栏目恒为 0', () {
      expect(navBadgeCount('/ledger', sources: {'/todo': 3}, seen: {}), 0);
    });

    test('登记了且没进过＝显读数', () {
      expect(navBadgeCount('/todo', sources: {'/todo': 3}, seen: {}), 3);
    });

    test('进过该栏目＝清零（清标记，不动数据源本身）', () {
      final sources = {'/todo': 3};
      expect(navBadgeCount('/todo', sources: sources, seen: {'/todo'}), 0);
      expect(sources['/todo'], 3, reason: '数据源必须原样留着，冷启动还要再显');
    });

    test('>99 收敛成 99+，99 本身不收敛', () {
      expect(navBadgeText(99), '99');
      expect(navBadgeText(100), '99+');
      expect(navBadgeText(1234), '99+');
    });
  });

  group('2 · 源码守护（防两条实测缺陷回潮）', () {
    final src = File('lib/core/nav/nav_badge.dart').readAsStringSync();

    test('配色钉在过 AA 的那一档（亮 #E11D48 白字 4.70／深 #FB7185 深字 6.63）', () {
      expect(src, contains('0xFFE11D48'), reason: '亮色胶囊：旧值 #F43F5E 白字只有 3.67');
      expect(src, contains('0xFFFB7185'), reason: '深色胶囊');
      expect(src, contains('0xFF0F172A'), reason: '深色档数字必须压深字（白字只有 2.69）');
      expect(src, isNot(contains('0xFFF43F5E')), reason: '旧亮色档不许回来');
    });

    test('数字必须正体（原型容器写成 <i> 被斜体化，是本轮抓到的缺陷）', () {
      // 断**代码行**而不是词：文档注释里也提到 FontStyle.normal，只断词会被注释喂饱（变异实测漏红过一次）
      expect(src, contains('fontStyle: FontStyle.normal,'),
          reason: '角标数字的正体声明必须落在样式里，不许只写在注释上');
    });

    test('壳层接线三处齐备：数据源表／进入即清／传参', () {
      final shell =
          File('lib/core/router/app_router.dart').readAsStringSync();
      expect(shell, contains('overdueCountProvider'), reason: '待办枚＝逾期实算');
      expect(shell, contains('_navSeen.add(currentPath)'),
          reason: '切栏即清，漏了就会一直挂着');
      expect(shell, contains('navBadgeCount(navModules[i].path'),
          reason: '每枚按自己的路径取数');
      expect(shell, contains("ValueKey('navbadge-\${module.id}')"),
          reason: '测试与真机走查锚点不许改名');
    });
  });
}
