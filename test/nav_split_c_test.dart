/// C 案批1 常驻守护：底栏目录／路由拆分／桌面瓦片不扩散／入口改道。
/// 规格＝`docs/handoff/交棒话术-20261107-记录四模块拆分C案批1路由与底栏池.md`。
/// 纯逻辑与源码级断言，不起 widget、不建库（widget 侧在 `journal_deeplink_test.dart`）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/nav/nav_module.dart';
import 'package:lifeharness/core/platform/module_tiles.dart';
import 'package:lifeharness/features/journal/presentation/journal_routes.dart';

void main() {
  group('① 底栏目录拆四', () {
    test('journal 改标「笔记」落 /notes，保留 id 兼容老 navIds', () {
      expect(NavModule.journal.id, 'journal');
      expect(NavModule.journal.label, '笔记');
      expect(NavModule.journal.path, '/notes');
      expect(NavModule.fromId('journal'), NavModule.journal);
    });

    test('三枚新栏目在册且路径避开 /read/* 与 /media/* 全屏前缀', () {
      expect(NavModule.diary.label, '日记');
      expect(NavModule.diary.path, '/diary');
      expect(NavModule.read.label, '阅读');
      expect(NavModule.read.path, '/readhub');
      expect(NavModule.media.label, '影音游');
      expect(NavModule.media.path, '/mediahub');
      for (final p in [NavModule.read.path, NavModule.media.path]) {
        expect(p.startsWith('/read/') || p.startsWith('/media/'), isFalse,
            reason: '$p 撞全屏栈路由前缀会让 go_router 归属歧义');
      }
    });

    test('底栏池共 14 项·三枚新栏目默认不入栏·默认 5 项', () {
      expect(NavModule.values.length, 14);
      expect(NavModule.defaultNav.length, 5);
      expect(NavModule.defaultNav.map((m) => m.id).toList(),
          <String>['today', 'todo', 'calendar', 'journal', 'settings']);
      for (final m in <NavModule>[
        NavModule.diary,
        NavModule.read,
        NavModule.media
      ]) {
        expect(NavModule.defaultNav, isNot(contains(m)),
            reason: '${m.label} 默认不占底栏格，只在设置页池里待选');
      }
    });
  });

  group('② 路由拆分', () {
    test('旧深链五态映射（单一纯函数）', () {
      expect(journalLegacyTarget('diary'), '/diary');
      expect(journalLegacyTarget('note'), '/notes');
      expect(journalLegacyTarget('book'), '/readhub');
      expect(journalLegacyTarget('media'), '/mediahub');
      expect(journalLegacyTarget(null), '/notes');
      expect(journalLegacyTarget('chat'), '/notes');
    });

    test('四条独立页在册·/journal 是 redirect-only', () {
      final paths = journalShellRoutes().map((r) => r.path).toList();
      for (final p in <String>[
        '/notes',
        '/diary',
        '/readhub',
        '/mediahub',
        '/journal'
      ]) {
        expect(paths, contains(p), reason: '$p 未在册');
      }
      final old = journalShellRoutes().firstWhere((r) => r.path == '/journal');
      expect(old.redirect, isNotNull);
      expect(old.builder, isNull, reason: '/journal 不得再构建四段记录页');
    });

    test('独立页构造用 standalone＋section，旧 ⇄ 菜单由守卫包住', () {
      final s = File('lib/features/journal/presentation/journal_routes.dart')
          .readAsStringSync();
      for (final seg in <String>['note', 'diary', 'book', 'media']) {
        expect(s, contains("section: '$seg', standalone: true"));
      }
      final page = File('lib/features/journal/presentation/journal_page.dart')
          .readAsStringSync();
      expect(page, contains('if (!widget.standalone)'),
          reason: '⇄ 切换菜单必须只在旧四段兼容类上画');
      expect(page, contains('widget.standalone'),
          reason: '标题前缀与段锁定都要走 standalone 分支');
    });
  });

  group('③ 桌面瓦片不扩散', () {
    test('仍 17 枚·壳内段仍 12 枚·新三栏目的路径不进目录', () {
      expect(kModuleTiles.length, 17);
      expect(kShellLaunchSegs.length, 12);
      // 按「路由」判而非按 id：手工瓦片本就有 read/media 两枚，指向
      // /read/shelf 与 /media/shelf 全屏栈页，与本批新增栏目同名不同物。
      final routes = kModuleTiles.map((t) => t.route).toSet();
      for (final p in <String>['/diary', '/readhub', '/mediahub']) {
        expect(routes, isNot(contains(p)),
            reason: '$p 未落原生资源前列进瓦片目录会与 LH_WHITELIST 失配');
      }
      expect(routes, containsAll(<String>['/read/shelf', '/media/shelf']),
          reason: '两枚既有手工瓦片不得被本批挤掉');
    });

    test('派生白名单恰 11 枚·各在 NavModule 目录里·不含新三栏目', () {
      expect(kTileNavIds.length, 11);
      final all = NavModule.values.map((m) => m.id).toSet();
      for (final id in kTileNavIds) {
        expect(all, contains(id));
      }
      for (final id in <String>['diary', 'read', 'media']) {
        expect(kTileNavIds, isNot(contains(id)),
            reason: '$id 尚无原生瓦片资源，不得自动派生');
      }
    });
  });

  group('④ 入口改道与约束回归', () {
    test('仪表盘阅读格直达 /readhub·DB 概览两条改新路径', () {
      final d = File('lib/features/dashboard/presentation/dashboard_page.dart')
          .readAsStringSync();
      expect(d,
          contains("(Icons.menu_book_outlined, '阅读', '/readhub', null),"));
      final o = File('lib/features/settings/presentation/db_overview_page.dart')
          .readAsStringSync();
      expect(o, contains("'笔记': '/notes'"));
      expect(o, contains("'日记': '/diary'"));
      expect(o, contains("'/notes',"));
      expect(o, contains("'/diary',"));
    });

    test('设置页底栏池遍历 NavModule.values（新栏目自动可配）', () {
      final s = File('lib/features/settings/presentation/settings_page.dart')
          .readAsStringSync();
      expect(s, contains('for (final m in NavModule.values)'));
    });
  });
}
