/// G2「已上线模块的假死入口」接线钉桩（2026-09-30 缺口盘点批 · 源码级守门）。
///  ① 阅读统计「看账本」按原型 `index-bookshelf.html:5501` 的 `navTo('p-finance')`
///     真跳记账主页 `/ledger`，不再是「账本模块规划中（V1.x）」占位 toast；
///  ② 仪表盘「全部功能」里 笔记/阅读 两格按原型 `D.grid`（三格同为 p-records）
///     接记录页 `/journal`，不再挂 `V0.5` 灰标与「规划」toast；
///  ③ 两个目标路由确实在册（防把死字符串换个地方写）。
///
/// 纯源码断言，不起 widget、不建库，故不引 `helpers.dart`（引了不用会成 analyze 新增告警）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String src(String p) => File(p).readAsStringSync();

  group('G2 假死入口接线', () {
    test('阅读统计「看账本」真跳 /ledger · 占位文案与过期注释归零', () {
      // 高保真批6c·刀2（2026-10-16）：「看账本」钮随统计卡群拆 part 迁入同库件。拆后
      // go_router import 留库根 read_stat_page.dart、路由调用随卡群迁入同库 part
      // read_stat_page_cards.dart（part 文件不得自带 import），扫描面改双件合检。
      const root = 'lib/features/read/presentation/stats/read_stat_page.dart';
      const part = 'lib/features/read/presentation/stats/read_stat_page_cards.dart';
      expect(src(root), contains("import 'package:go_router/go_router.dart';"));
      expect(
        src(part),
        contains("onTap: () => context.go('/ledger'),"),
        reason: '看账本仍是指向别处或未接',
      );
      final both = src(root) + src(part);
      expect(both, isNot(contains('账本模块规划中')));
      expect(
        both,
        isNot(contains('/finance 路由未就绪')),
        reason: '记账路由实为 /ledger，该「未就绪」注释已过期',
      );
    });

    test('仪表盘「全部功能」阅读格已接记录页并带段参 · V0.5 灰标归零', () {
      const f = 'lib/features/dashboard/presentation/dashboard_page.dart';
      final s = src(f);
      // V1.58 反馈轮5：日记/笔记两枚下架（与记录页 ⇄ 段重复），
      // 阅读枚改带 `?tab=book` 深链，点击自动切到阅读视图。
      // 顺带修存量红（批6c·刀2 闸面清零）：仪表盘「全部功能」格子由 emoji 字面量改
      // IconData 后本条字面量过期（语义未变：阅读枚仍接 /journal?tab=book、无 V0.5 角标）。
      expect(s, contains("(Icons.menu_book_outlined, '阅读', '/journal?tab=book', null),"));
      expect(s, isNot(contains("'笔记', '/journal'")));
      expect(s, isNot(contains("'日记', '/journal'")));
      expect(s, isNot(contains("'V0.5'")), reason: '笔记/阅读早已上线，不得再挂规划角标');
    });

    test('目标路由在册（/journal 与 /ledger 均已注册）', () {
      expect(
        src('lib/features/journal/presentation/journal_routes.dart'),
        contains("path: '/journal'"),
      );
      expect(
        src('lib/features/ledger/presentation/ledger_routes.dart'),
        contains("GoRoute(path: '/ledger'"),
      );
    });
  });
}
