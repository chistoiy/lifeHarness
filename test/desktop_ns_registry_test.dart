import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart';
import 'package:lifeharness/core/platform/module_tiles.dart';

/// ns 常量表守护（冻结档 B17/C19 · `test/desktop_ns_registry_test.dart`）。
///
/// 三条：① `nfc` 在表内可放行；② 表外 ns 按未知 path 走兜底；
/// ③ **动作表 Scheme 列与常量表逐条一致**（禁散落字面量）。
void main() {
  test('nfc 在表内：nfc/<cardId> 放行并原样透传', () {
    expect(kDesktopNamespaces.contains('nfc'), isTrue);
    expect(resolveLaunchPath('nfc/aB3xY9zQ1m2K'), 'nfc:aB3xY9zQ1m2K');
  });

  test('表外 ns 一律按未知 path 处理（B17/C19）', () {
    for (final ns in <String>['evil', 'unknown', 'ln', 'lhv2', 'https', 'market']) {
      expect(resolveLaunchPath('$ns/today'), isNull, reason: '$ns 不该被放行');
    }
  });

  test('Scheme 列与 ns 常量表逐条一致（禁散落字面量）', () {
    for (final a in kDesktopActions) {
      expect(kDesktopNamespaces.contains(a.ns), isTrue,
          reason: '${a.id} 的 ns 不在常量表');
      final u = Uri.parse(a.scheme);
      expect(u.scheme, 'lh', reason: '${a.id} scheme 前缀错');
      expect(u.host, a.ns, reason: '${a.id} 的 host 必须等于声明的 ns');
    }
  });

  test('白名单每条的 path 首段都在 ns 表内', () {
    for (final key in kLaunchPathWhitelist.keys) {
      final ns = key.split('/').first;
      expect(kDesktopNamespaces.contains(ns), isTrue,
          reason: '白名单 $key 的 ns 未登记（扩容须走 C19 流程）');
    }
  });

  test('新增 ns 的正确姿势：加常量表 + 加 ns 前缀动作，禁塞进既有 ns', () {
    // 口径自证：动作表里每个 ns 至少被一条动作、白名单或系统寻址段覆盖（无孤儿子）。
    final usedByAction = kDesktopActions.map((a) => a.ns).toSet();
    final usedByPath =
        kLaunchPathWhitelist.keys.map((k) => k.split('/').first).toSet();
    // 2026-10-18：settings 是**系统寻址段** ns（小组件失效三态的「点此设置」），
    // 不属于用户动作、也不进白名单（白名单每条都要求能查回动作表），故单列一张表。
    final usedBySystem =
        kSystemLaunchPaths.keys.map((k) => k.split('/').first).toSet();
    // nfc 由 NFC 模块消费，批 1 无动作条目 —— 它靠白名单外的 nfc/* 形态放行。
    final orphan = kDesktopNamespaces
        .difference(usedByAction)
        .difference(usedByPath)
        .difference(usedBySystem)
        .where((ns) => ns != 'nfc');
    expect(orphan, isEmpty, reason: '常量表里有孤儿子 ns：$orphan');
  });

  test('系统寻址段：段即 id、能查到路由，且**不进**用户动作表', () {
    for (final e in kSystemLaunchPaths.entries) {
      expect(resolveLaunchPath(e.key), e.key, reason: '${e.key} 必须按段即 id 放行');
      expect(LaunchRoute(action: e.key).route, e.value);
      expect(desktopActionById.containsKey(e.key), isFalse,
          reason: '系统寻址段禁混进动作表（会污染三张用户可勾选清单）');
    }
    // 反例：表外同 ns 段一律 null（不能靠「ns 对」蹭过白名单）。
    expect(resolveLaunchPath('settings/ghost'), isNull);
    expect(resolveLaunchPath('modules/ghost'), isNull);
  });

  test('系统寻址段的导航语义：设置二级页 push，壳内模块瓦片 go', () {
    // 2026-10-18 批C：modules/* 分两族——壳内 tab 必须 go（push 会把底栏顶掉、
    // 用户「回到底栏页」的返回语义也变了），全屏栈页必须 push（go 会换掉栈底壳页
    // ⇒ 返回黑屏·V1.67 真机伤）。设置二级页仍是 push。
    expect(LaunchRoute(action: 'settings/desktop').fullScreen, isTrue);
    for (final e in kSystemLaunchPaths.entries) {
      if (!e.key.startsWith('modules/')) continue;
      expect(LaunchRoute(action: e.key).fullScreen,
          !kShellLaunchSegs.contains(e.key),
          reason: '${e.key} 的 go/push 与 kShellLaunchSegs 不一致');
    }
  });

  test('nfc 不在动作表里（本模块只放行不解释，C36）', () {
    expect(kDesktopActions.any((a) => a.ns == 'nfc'), isFalse,
        reason: 'nfc 业务归 NFC 模块，桌面模块不得给 nfc 建动作条目');
  });
}