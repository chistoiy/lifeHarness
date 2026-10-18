import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_routes.dart';
import 'package:lifeharness/features/habit/presentation/habit_routes.dart';
import 'package:lifeharness/features/inbox/presentation/inbox_routes.dart';
import 'package:lifeharness/features/items/presentation/items_routes.dart';
import 'package:lifeharness/features/journal/presentation/journal_routes.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_routes.dart';
import 'package:lifeharness/features/todo/presentation/todo_routes.dart';

/// 动作表守护（冻结档 §6.4 · `test/desktop_actions_test.dart`）。
///
/// 钉三件事：① 7 条动作 id 唯一且 path 非空；② 默认 4 枚＝inbox/todo/ledger/habit；
/// ③ 上限常量 4。**禁从实现反推断言**——期望值全部取自冻结档 §2.0 原文。
void main() {
  group('动作表（§2.0 冻结全集）', () {
    test('恰好 7 条，id 唯一', () {
      expect(kDesktopActions.length, 7);
      final ids = kDesktopActions.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length, reason: '动作 id 必须唯一');
    });

    test('每条都有非空路由与 lh:// 原值', () {
      for (final a in kDesktopActions) {
        expect(a.path, isNotEmpty, reason: '${a.id} 缺路由');
        expect(a.path.startsWith('/'), isTrue, reason: '${a.id} 路由须以 / 开头');
        expect(a.scheme, startsWith('lh://'), reason: '${a.id} scheme 形态错');
        expect(a.label.length, greaterThanOrEqualTo(2));
        // 桌面侧短标签 ≤6 字（§4.1 标签≤6 字）
        expect(a.shortLabel.length, lessThanOrEqualTo(6),
            reason: '${a.id} 短标签超 6 字：${a.shortLabel}');
      }
    });

    test('七条 scheme 逐字等于冻结档 §2.0', () {
      const expectMap = <String, String>{
        'inbox': 'lh://inbox/new',
        'todo': 'lh://todo/new',
        'journal': 'lh://journal/edit',
        'ledger': 'lh://ledger/add',
        'items': 'lh://items/new',
        'habit': 'lh://habit/check',
        'today': 'lh://today',
      };
      expect(desktopActionById.keys.toSet(), expectMap.keys.toSet());
      expectMap.forEach((id, sc) {
        expect(desktopActionOf(id)!.scheme, sc, reason: '$id scheme 与冻结档不符');
      });
    });

    test('默认 4 枚＝inbox/todo/ledger/habit（§2.0）', () {
      expect(kDefaultMenuActionIds,
          <String>['inbox', 'todo', 'ledger', 'habit']);
      expect(kDefaultMenuActionIds.length, kMenuMax);
    });

    test('系统硬限 4（§4.1）', () {
      expect(kMenuMax, 4);
    });

    test('按 id 与按 scheme 查表一致（禁两份映射）', () {
      for (final a in kDesktopActions) {
        expect(desktopActionByScheme[a.scheme]!.id, a.id);
        expect(desktopActionOf(a.id)!.scheme, a.scheme);
      }
      expect(desktopActionOf('not-exist'), isNull);
    });
  });

  group('C18 带参三级分级', () {
    test('today 是导航类，其余写入类只预填', () {
      expect(desktopActionOf('today')!.grade, LaunchArgGrade.nav);
      for (final id in ['inbox', 'todo', 'ledger', 'items', 'habit', 'journal']) {
        expect(desktopActionOf(id)!.grade, LaunchArgGrade.writePrefill,
            reason: '$id 应为写入类');
      }
    });

    test('导航类带参直接进 URI；写入类带参也只作预填参数', () {
      final nav = desktopLaunchUri('today', args: <String, String>{'q': 'x'});
      expect(nav.toString(), 'lh://today?q=x');
      final w = desktopLaunchUri('ledger', args: <String, String>{'amount': '38.5'});
      expect(w.toString(), startsWith('lh://ledger/add'));
      expect(w.queryParameters['amount'], '38.5');
    });

    test('未知动作 id 抛 ArgumentError（禁静默拼错 URI）', () {
      expect(() => desktopLaunchUri('nope'), throwsArgumentError);
    });
  });

  group('ns 常量表（C19/B17）', () {
    test('九个 ns 全在表内', () {
      // 2026-10-18：新增 settings（系统寻址段专用·小组件「点此设置」），
      // 它不进动作表，只在 kSystemLaunchPaths 下有条目（见 desktop_ns_registry_test）。
      expect(kDesktopNamespaces,
          containsAll(<String>['inbox', 'todo', 'journal', 'ledger', 'items', 'habit', 'today', 'nfc', 'settings']));
    });

    test('每条动作的 ns 都在常量表内（禁散落字面量）', () {
      for (final a in kDesktopActions) {
        expect(kDesktopNamespaces.contains(a.ns), isTrue,
            reason: '${a.id} 的 ns=${a.ns} 不在常量表');
        // scheme 必须是 lh://<ns> 或 lh://<ns>/<key>（today 是无 key 的导航类）
        expect(a.scheme == 'lh://${a.ns}' || a.scheme.startsWith('lh://${a.ns}/'),
            isTrue,
            reason: '${a.id} scheme 与 ns 不自洽：${a.scheme} vs ${a.ns}');
      }
    });
  });

  group('全屏栈标记 fullScreen（V1.67 真机伤·返回黑屏的取值依据）', () {
    test('与真实路由表交叉核对：注册在 *PageRoutes() ⇒ fullScreen', () {
      // 期望值来自**路由表本身**（不是从实现反推）：壳内路由在 *ShellRoutes()、
      // 全屏栈路由在 *PageRoutes()。标记写错 ⇒ 深链用 go 掉栈底的壳页 ⇒
      // 页内 pop 无处可去 ⇒ 返回黑屏且退不出去（真机报障·日记编辑页）。
      final shell = <String>{
        for (final r in <GoRoute>[
          ...dashboardShellRoutes(),
          ...inboxShellRoutes(),
          ...todoShellRoutes(),
          ...habitShellRoutes(),
          ...itemsShellRoutes(),
          ...journalShellRoutes(),
          ...ledgerShellRoutes(),
        ])
          r.path,
      };
      final page = <String>{
        for (final r in <GoRoute>[
          ...journalPageRoutes(),
          ...ledgerPageRoutes(),
        ])
          r.path,
      };
      for (final a in kDesktopActions) {
        expect(shell.contains(a.path) || page.contains(a.path), isTrue,
            reason: '${a.id} 的目标 ${a.path} 在路由表里找不到');
        expect(a.fullScreen, page.contains(a.path),
            reason: '${a.id}（${a.path}）fullScreen 必须等于「注册在 *PageRoutes()」');
        expect(a.fullScreen, isNot(shell.contains(a.path)),
            reason: '${a.id} 壳内路由不得标全屏');
      }
      // 冻结事实：本批只有记一笔与写日记是全屏栈路由（各自 `context.go` / `pop` 语义不同）。
      expect(
          kDesktopActions
              .where((a) => a.fullScreen)
              .map((a) => a.id)
              .toSet(),
          <String>{'ledger', 'journal'});
    });

    test('LaunchRoute.fullScreen 由动作表派生（未知动作回落 false）', () {
      for (final a in kDesktopActions) {
        expect(LaunchRoute(action: a.id).fullScreen, a.fullScreen,
            reason: '${a.id} 派生值必须与动作表一致');
      }
      expect(LaunchRoute(action: 'ghost').fullScreen, isFalse,
          reason: '未知动作走兜底，不得按全屏 push');
    });
  });
}