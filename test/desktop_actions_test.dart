import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart';

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
    test('八个 ns 全在表内', () {
      expect(kDesktopNamespaces,
          containsAll(<String>['inbox', 'todo', 'journal', 'ledger', 'items', 'habit', 'today', 'nfc']));
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
}