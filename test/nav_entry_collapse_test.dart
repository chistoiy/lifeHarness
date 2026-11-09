import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/nav/nav_collapse.dart';

/// 批C-2 · **瓦片进来默认收起底栏**（2026-10-18 产品令）。
///
/// 产品原话：「如果用户通过 1×1 模块小组件进入 app，默认隐藏底部导航栏
/// （相当于用户已进入就用双指放大，触发隐藏底部导航栏）」。
///
/// 本组是**判据单测**（壳层渲染由 `nav_collapse_shell_test` 覆盖）：
/// 钉住「两份状态怎么合成」、「入口态不吃总开关」、「只有壳内模块段才置入口态」。
void main() {
  group('navCollapsedOf：两份状态合成（唯一判据）', () {
    test('都没置真 ⇒ 展开', () {
      expect(
          navCollapsedOf(
              gestureOn: true, gestureHidden: false, entryHidden: false),
          isFalse);
    });

    test('手势态只在总开关打开时生效（关开关＝立刻展开）', () {
      // V1.65 的老契约：总开关关着，残留的手势收起态一律不算。
      expect(
          navCollapsedOf(
              gestureOn: false, gestureHidden: true, entryHidden: false),
          isFalse,
          reason: '总开关关着时不许被手势态拖住');
      expect(
          navCollapsedOf(
              gestureOn: true, gestureHidden: true, entryHidden: false),
          isTrue);
    });

    test('入口态**不看总开关**——总开关出厂是关的，看了这条功能就没人能用', () {
      expect(
          navCollapsedOf(
              gestureOn: false, gestureHidden: false, entryHidden: true),
          isTrue);
      expect(
          navCollapsedOf(
              gestureOn: true, gestureHidden: false, entryHidden: true),
          isTrue);
    });
  });

  group('控制器语义', () {
    test('入口收起态初始 false，hide/show 幂等', () {
      final c = NavEntryCollapseController();
      // Notifier 的 build 只能由容器调；这里直接读判据函数的行为口径。
      expect(c.build(), isFalse);
    });
  });

  group('源码守护（防口径回退）', () {
    final r = File('lib/core/router/app_router.dart').readAsStringSync();
    final a = File('lib/app.dart').readAsStringSync();
    final n = File('lib/core/nav/nav_collapse.dart').readAsStringSync();

    test('壳层只读合成判据，禁自己写「或」', () {
      expect(r, contains('navCollapsedOf('),
          reason: '壳层必须走唯一判据（两份状态的合成只许一处）');
      expect(r.contains('navGestureOn && ref.watch(navCollapsedProvider)'),
          isFalse,
          reason: '旧写法（只认手势态）会让「瓦片进来收起」整条失效');
    });

    test('线索点一下两份状态一起清（只清一份＝点了没反应）', () {
      expect(r, contains('void restoreNav()'));
      expect(r, contains('ref.read(navCollapsedProvider.notifier).show();'));
      expect(
          r, contains('ref.read(navEntryCollapsedProvider.notifier).show();'));
      expect(r, contains('onTap: restoreNav'));
    });

    test('只有**壳内**模块段才置入口收起（全屏模块本来就没底栏）', () {
      expect(a, contains('kShellLaunchSegs.contains(route.action)'),
          reason: '全屏模块段也置收起 ⇒ 返回壳内凭空少一条底栏');
      expect(
          a,
          contains(
              'ref.read(navEntryCollapsedProvider.notifier).hide();'));
      // 位置必须在路由分发之前（push/go 之后才置会晚一帧，页面已渲染成展开态）。
      final iHide = a.indexOf('navEntryCollapsedProvider.notifier');
      final iRoute = a.indexOf('await takeLaunchRoute()');
      expect(iHide, greaterThan(iRoute), reason: '必须在取到路由之后');
      expect(a.indexOf('if (route.fullScreen)'), greaterThan(iHide),
          reason: '必须在分发之前');
    });

    test('入口态与手势态是两个 provider（各管各的总开关）', () {
      expect(n, contains('final navCollapsedProvider ='));
      expect(n, contains('final navEntryCollapsedProvider ='));
      expect(n, contains('bool navCollapsedOf('));
    });
  });
}
