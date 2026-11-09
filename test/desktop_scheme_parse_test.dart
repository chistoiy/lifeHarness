import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart';

/// `lh://` 解析守护（冻结档 §4.3 白名单 / B4 兜底 / B5 非法参数）。
///
/// 对应原生侧 `MainActivity.handle()` 的 `lh://` 分支——**两边判定必须一致**，
/// 故本测试直接钉 Dart 侧 [resolveLaunchPath] 的口径，原生侧由 `desktop_intent_shape_test`
/// 与 kotlin_check 兜。
void main() {
  group('白名单七条各命中正确动作 id（§4.3 冻结全集）', () {
    const cases = <String, String>{
      'inbox/new': 'inbox',
      'todo/new': 'todo',
      'journal/edit': 'journal',
      'ledger/add': 'ledger',
      'items/new': 'items',
      'habit/check': 'habit',
      'today': 'today',
    };
    cases.forEach((path, id) {
      test('lh://$path → $id', () {
        expect(resolveLaunchPath(path), id);
      });
    });
  });

  group('未知与非法一律 null（交给 B4 兜底，不炸 GoException）', () {
    test('白名单外的 key → null', () {
      expect(resolveLaunchPath('ledger/delete-all'), isNull);
      expect(resolveLaunchPath('inbox/new/extra/deep'), isNull);
    });

    test('表外 ns → null（B17/C19）', () {
      expect(resolveLaunchPath('evil/x'), isNull);
      expect(resolveLaunchPath('unknown/today'), isNull);
    });

    test('空 path / 只有 ns → null', () {
      expect(resolveLaunchPath(''), isNull);
      expect(resolveLaunchPath('/'), isNull);
      expect(resolveLaunchPath('today'), isNotNull, reason: 'today 是无 key 的合法导航类');
      expect(resolveLaunchPath('ledger'), isNull, reason: '只有 ns 没有 key 不算白名单条目');
      expect(resolveLaunchPath('inbox'), isNull);
    });
  });

  group('nfc 透传（只放行不解释 · C36/B35）', () {
    test('nfc/<cardId> 原样透传，业务含义归 NFC 模块', () {
      expect(resolveLaunchPath('nfc/aB3xY9zQ1m2K'), 'nfc:aB3xY9zQ1m2K');
      final r = LaunchRoute(action: resolveLaunchPath('nfc/aB3xY9zQ1m2K')!);
      expect(r.isNfc, isTrue);
      // 本模块**不解释** cardId：route 不该解析成 App 内路由
      expect(r.route, kUnknownRouteFallback);
    });

    test('cardId 为空 → null', () {
      expect(resolveLaunchPath('nfc'), isNull);
    });
  });

  group('B5 非法参数被忽略但动作仍落地', () {
    test('amount 非数 → 参数丢弃，路由仍正确', () {
      // 带参解析在原生侧完成（queryParameters 原样透传），Dart 侧只判动作：
      final r = LaunchRoute(
        action: resolveLaunchPath('ledger/add')!,
        args: const <String, String>{'amount': 'abc'},
      );
      // 非数参数不进路由判定；提交校验归目标页，本层不炸。
      expect(r.route, '/ledger/add');
      expect(r.args['amount'], 'abc');
    });

    test('未知动作 id 的 LaunchRoute 走兜底路由而非抛错', () {
      final r = LaunchRoute(action: 'ghost');
      expect(r.route, kUnknownRouteFallback);
    });
  });

  group('解析与动作表同源（禁两份真相）', () {
    test('白名单每条都能在动作表里查到对应 scheme', () {
      for (final entry in kLaunchPathWhitelist.entries) {
        final a = desktopActionOf(entry.value);
        expect(a, isNotNull, reason: '白名单 ${entry.key} 指向不存在动作');
        expect(a!.scheme, 'lh://${entry.key}');
        expect(resolveLaunchPath(entry.key), entry.value);
      }
    });
  });
}