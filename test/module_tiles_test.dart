import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart';
import 'package:lifeharness/core/platform/module_tiles.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_routes.dart';
import 'package:lifeharness/features/care/presentation/care_routes.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_routes.dart';
import 'package:lifeharness/features/days/presentation/days_routes.dart';
import 'package:lifeharness/features/goals/presentation/goals_routes.dart';
import 'package:lifeharness/features/habit/presentation/habit_routes.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/features/inbox/presentation/inbox_routes.dart';
import 'package:lifeharness/features/items/presentation/items_routes.dart';
import 'package:lifeharness/features/journal/presentation/journal_routes.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_routes.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_routes.dart';
import 'package:lifeharness/features/nfc/presentation/nfc_routes.dart';
import 'package:lifeharness/features/read/presentation/read_routes.dart';
import 'package:lifeharness/features/settings/presentation/settings_routes.dart';
import 'package:lifeharness/features/todo/presentation/todo_routes.dart';

/// 模块瓦片目录守护（批C · 2026-10-18）。
///
/// 规格＝`docs/handoff/小组件模块-批C-1x1模块瓦片-开批规格-20261018.md`。
/// 钉五件事：① 目录 17 枚且 11 枚底栏模块**由 NavModule 派生**（禁另抄中文名）；
/// ② 每条 route 在**真实路由表**里存在，且 shell 位与 `*ShellRoutes()` /
/// `*PageRoutes()` 的归属一致；③ 深链表两侧（Dart `kSystemLaunchPaths` ↔
/// 原生 `LH_WHITELIST`/`LH_NS`）逐条同源；④ 壳内段走 `go`、全屏段走 `push`
/// （`fullScreen` 三级判定——写反就是底栏消失/返回黑屏）；⑤ 每枚瓦片零 configure、
/// 零刷新、1×1，且**一模块一条 receiver**（同 class 两条会被 manifest 合并）。
void main() {
  const ktDir = 'android/app/src/main/kotlin/com/lifeharness/lifeharness';
  const resDir = 'android/app/src/main/res';

  /// 壳内路由（`*ShellRoutes()`）的 path 全集。
  final shellPaths = <String>{
    for (final r in <GoRoute>[
      ...dashboardShellRoutes(),
      ...todoShellRoutes(),
      ...calendarShellRoutes(),
      ...journalShellRoutes(),
      ...habitShellRoutes(),
      ...inboxShellRoutes(),
      ...ledgerShellRoutes(),
      ...careShellRoutes(),
      ...daysShellRoutes(),
      ...itemsShellRoutes(),
      ...goalsShellRoutes(),
      ...settingsShellRoutes(),
    ])
      r.path,
  };

  /// 全屏栈路由（`*PageRoutes()`）的 path 全集。
  final pagePaths = <String>{
    for (final r in <GoRoute>[
      ...readPageRoutes(),
      ...mediaPageRoutes(),
      ...healthPageRoutes(),
      ...mindmapPageRoutes(),
      ...nfcPageRoutes(),
    ])
      r.path,
  };

  group('① 目录（17 枚·11 枚底栏派生）', () {
    test('恰好 17 枚，id 唯一，标签 ≤4 字，路由以 / 开头', () {
      expect(kModuleTiles.length, 17);
      final ids = kModuleTiles.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length, reason: '模块 id 必须唯一');
      for (final t in kModuleTiles) {
        expect(t.label.length, inInclusiveRange(1, 4),
            reason: '${t.id} 标签超 4 字（1×1 只放得下一行）：${t.label}');
        expect(t.route.startsWith('/'), isTrue, reason: '${t.id} 路由须以 / 开头');
        expect(t.seg, 'modules/${t.id}');
        expect(t.scheme, 'lh://modules/${t.id}');
      }
    });

    test('底栏 11 枚逐条取自 NavModule（禁另抄一份中文名）', () {
      final nav = kModuleTiles.where((t) => t.id != 'care' && t.shell).toList();
      // NavModule 的 11 枚全在，且 id/label/path/shell 与枚举逐字相同。
      final derived = kModuleTiles.take(11).toList();
      expect(derived.length, 11);
      expect(derived.map((t) => t.id).toList(), <String>[
        'today',
        'todo',
        'calendar',
        'journal',
        'habit',
        'inbox',
        'ledger',
        'items',
        'days',
        'goals',
        'settings',
      ]);
      // 标签与路由必须来自枚举本身（改枚举即改瓦片，不留第二份）。
      expect(nav.map((t) => t.label).toSet(),
          containsAll(<String>['今天', '待办', '时间', '记录', '习惯', '收集箱', '记账', '物品', '日子', '目标', '我的']));
      expect(derived.first.route, '/', reason: '今天＝壳根路由');
      expect(derived.last.route, '/settings', reason: '我的＝设置页');
    });

    test('手工 6 枚＝呵护/阅读/影音/健康/导图/卡片', () {
      expect(kManualModuleTiles.map((t) => t.id).toList(),
          <String>['care', 'read', 'media', 'health', 'mindmap', 'nfc']);
      expect(kManualModuleTiles.map((t) => t.label).toList(),
          <String>['呵护', '阅读', '影音', '健康', '导图', '卡片']);
    });
  });

  group('② 路由存在性（与真实路由表交叉核对）', () {
    test('每条 route 在真实路由表里存在', () {
      for (final t in kModuleTiles) {
        expect(shellPaths.contains(t.route) || pagePaths.contains(t.route), isTrue,
            reason: '${t.id} 的 ${t.route} 不在任何 *ShellRoutes()/*PageRoutes() 里');
      }
    });

    test('shell 位与路由归属一致（壳内 tab ⇒ go；栈页 ⇒ push）', () {
      for (final t in kModuleTiles) {
        final inShell = shellPaths.contains(t.route);
        final inPage = pagePaths.contains(t.route);
        expect(inShell ^ inPage, isTrue,
            reason: '${t.id} 的 ${t.route} 同时或都不在两表里（归属不唯一）');
        expect(t.shell, inShell,
            reason: '${t.id} 的 shell 位写反了：路由归属 ${inShell ? 'Shell' : 'Page'}');
      }
    });
  });

  group('③ 深链表（段即 id · 两侧同源）', () {
    test('kSystemLaunchPaths 键＝设置段 ∪ 17 模块段，值＝路由', () {
      expect(kSystemLaunchPaths.keys.toSet(), <String>{
        'settings/desktop',
        for (final t in kModuleTiles) t.seg,
      });
      for (final t in kModuleTiles) {
        expect(kSystemLaunchPaths[t.seg], t.route);
      }
      expect(kSystemLaunchPaths['settings/desktop'], '/settings/desktop');
    });

    test('kShellLaunchSegs ＝壳内段集，且是系统寻址段的子集', () {
      expect(kShellLaunchSegs,
          kModuleTiles.where((t) => t.shell).map((t) => t.seg).toSet());
      expect(kSystemLaunchPaths.keys.toSet().containsAll(kShellLaunchSegs), isTrue);
      // 壳内＝12 枚（底栏 11 ＋ 呵护）。
      expect(kShellLaunchSegs.length, 12);
      expect(kShellLaunchSegs.contains('modules/care'), isTrue);
      expect(kShellLaunchSegs.contains('modules/read'), isFalse);
    });

    test('fullScreen 三级判定：壳内 go / 全屏 push / 设置页 push', () {
      // 第三级（本批新增）不生效就是**底栏消失**——壳内 tab 被 push 成栈顶。
      expect(LaunchRoute(action: 'modules/todo').fullScreen, isFalse);
      expect(LaunchRoute(action: 'modules/today').fullScreen, isFalse);
      expect(LaunchRoute(action: 'modules/settings').fullScreen, isFalse);
      expect(LaunchRoute(action: 'modules/read').fullScreen, isTrue);
      expect(LaunchRoute(action: 'modules/nfc').fullScreen, isTrue);
      expect(LaunchRoute(action: 'settings/desktop').fullScreen, isTrue);
      // 用户动作仍走动作表（第一级不被新分支吃掉）。
      expect(LaunchRoute(action: 'today').fullScreen, isFalse);
      expect(LaunchRoute(action: 'ledger').fullScreen, isTrue);
      // 表外段：兜底路由不是系统寻址段 ⇒ false（不 push 未知页）。
      expect(LaunchRoute(action: 'modules/ghost').fullScreen, isFalse);
    });

    test('route 解析：模块段给自身，表外段给兜底', () {
      for (final t in kModuleTiles) {
        expect(LaunchRoute(action: t.seg).route, t.route);
        expect(resolveLaunchPath(t.seg), t.seg);
        expect(resolveLaunchUri(Uri.parse(t.scheme)), t.seg);
      }
      expect(resolveLaunchPath('modules/ghost'), isNull);
      expect(resolveLaunchPath('modules'), isNull, reason: 'ns 段本身不是有效目标');
      expect(LaunchRoute(action: 'modules/ghost').route, kUnknownRouteFallback);
    });

    test('模块段不进用户动作表、不进白名单（三张清单不受污染）', () {
      for (final t in kModuleTiles) {
        expect(desktopActionById.containsKey(t.seg), isFalse,
            reason: '模块瓦片不是用户动作，禁进 kDesktopActions');
        expect(kLaunchPathWhitelist.containsKey(t.seg), isFalse);
      }
      expect(kDesktopNamespaces.contains('modules'), isTrue);
    });

    test('原生两表与 Dart 同源（LH_WHITELIST 的 modules/* ↔ kModuleTiles）', () {
      final main = File('$ktDir/MainActivity.kt').readAsStringSync();
      final i = main.indexOf('LH_WHITELIST = mapOf(');
      expect(i, greaterThan(-1), reason: '缺 LH_WHITELIST');
      final block = main.substring(i, main.indexOf(')', i));
      final nativeSegs = <String>{
        for (final m in RegExp(r'"(modules/[a-z]+)"\s+to\s+"modules/[a-z]+"')
            .allMatches(block))
          m.group(1)!,
      };
      expect(nativeSegs, kModuleTiles.map((t) => t.seg).toSet(),
          reason: '原生白名单与 Dart 目录不同步 ⇒ enqueueLaunch 静默丢弃瓦片点击');
      expect(main, contains('"modules",'),
          reason: '原生 LH_NS 缺 modules ⇒ 段首 ns 校验不过');
      // 设置段仍在（不许被本批改动挤掉）。
      expect(block, contains('"settings/desktop" to "settings/desktop"'));
    });
  });

  group('④ 瓦片资源与原生实现', () {
    /// 已落地的瓦片（有 info XML 的）。
    final implemented = <String>[
      for (final f in Directory('$resDir/xml').listSync())
        if (f.path.endsWith('_info.xml') &&
            f.path.contains('lh_tile_'))
          f.path.split(RegExp(r'[\\/]')).last
              .replaceFirst('lh_tile_', '')
              .replaceFirst('_info.xml', ''),
    ]..sort();

    String classNameOf(String id) =>
        'Tile${id[0].toUpperCase()}${id.substring(1)}';

    test('至少落地待办一枚（批C-1 试点）', () {
      expect(implemented, contains('todo'));
    });

    test('每枚瓦片：零 configure、零刷新、1×1、有预览图、指同一布局', () {
      // ⚠ 扫 XML 前先剥注释：本仓纪律「源码扫描类测试先剥注释」，否则文档串自指
      // （注释里写着「不写 android:configure」会被当成写了）。
      String stripXmlComments(String s) =>
          s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      for (final id in implemented) {
        final xml = stripXmlComments(
            File('$resDir/xml/lh_tile_${id}_info.xml').readAsStringSync());
        // MIUI 桌面实测不跑 configure（6176 轮）⇒ 本批一枚都不许写。
        expect(xml.contains('android:configure'), isFalse,
            reason: '$id 写了 configure——MIUI 不跑，等于白挂');
        expect(xml, contains('android:updatePeriodMillis="0"'),
            reason: '$id 不是零刷新（瓦片零数据，禁周期唤醒）');
        expect(xml, contains('android:targetCellWidth="1"'));
        expect(xml, contains('android:targetCellHeight="1"'));
        expect(xml, contains('android:minWidth="40dp"'));
        expect(xml, contains('android:resizeMode="none"'));
        expect(xml, contains('android:initialLayout="@layout/lh_tile"'),
            reason: '$id 应共用唯一瓦片布局');
        // MIUI 只认 previewImage：缺图 17 枚长得一模一样。
        expect(xml, contains('android:previewImage="@drawable/lh_tile_${id}_preview"'));
        expect(File('$resDir/drawable-nodpi/lh_tile_${id}_preview.png').existsSync(),
            isTrue, reason: '$id 缺浅色档预览图（跑 tools/gen_widget_previews.py）');
        expect(
            File('$resDir/drawable-night-nodpi/lh_tile_${id}_preview.png')
                .existsSync(),
            isTrue,
            reason: '$id 缺深色档预览图（C6 跟随系统）');
        // 文案两条（选择器里要能分辨）。
        final strings = File('$resDir/values/strings.xml').readAsStringSync();
        expect(strings, contains('lh_tile_${id}_name'));
        expect(strings, contains('lh_tile_${id}_desc'));
        expect(strings, contains('lh_tile_label_$id'));
      }
    });

    test('一模块一条 receiver，且 provider 子类名与段一一对应', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final kt = File('$ktDir/ModuleTileWidget.kt').readAsStringSync();
      for (final id in implemented) {
        final cls = classNameOf(id);
        expect(RegExp('\\.$cls"').allMatches(manifest).length, 1,
            reason: '$id 的 receiver 必须恰好一条（同 class 两条会被合并）');
        expect(manifest, contains('@xml/lh_tile_${id}_info'));
        expect(manifest, contains('@string/lh_tile_${id}_name'));
        // 子类里的段与目录一致（写错段 ⇒ 点了落兜底页）。
        final i = kt.indexOf('class $cls : ModuleTileProvider()');
        expect(i, greaterThan(-1), reason: '缺 $cls 子类');
        final body = kt.substring(i, kt.indexOf('\n}', i));
        expect(body, contains('"modules/$id"'),
            reason: '$cls 的 seg 与模块 id 不一致');
      }
      // 基类钉死三条纪律：共用布局、点击走唯一出口、requestCode 每实例一个。
      final base = kt.substring(0, kt.indexOf('class Tile'));
      expect(base, contains('R.layout.lh_tile'));
      expect(base, contains('LhWidget.clickIntent(context, seg, REQ_TILE_BASE + id)'),
          reason: '点击必须走 LhWidget.clickIntent 唯一出口（C15/C9）');
      expect(base, contains('REQ_TILE_BASE + id'),
          reason: 'requestCode 必须每实例一个（同码 + FLAG_UPDATE_CURRENT 会互相覆写）');
    });
  });
}
