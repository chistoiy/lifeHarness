import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// U2（UX 审计真机批 · 2026-10-05 产品拍板）**「今天」是唯一根出口**：
/// 任何非今天页按返回都不许直接退 app——宫格/`go` 进的模块主页一次返回回今天；
/// 底栏点进的栏目与今天页才走「提醒→二次退出」。
///
/// 本批真机定性（写在这里免得下会话重走一遍）：Dart 侧这套判定早就与拍板一致
/// （雷电 720x1280 实测宫格 7 条全部「一次返回→今天」），真机（HyperOS ·
/// targetSdk 36）却 7/7 直接退 app——logcat 铁证 `MIUIInput: OnBackInvokedCallback
/// is enabled, drop Back Key Event` ＋ `deliverResultForFinishActivity`：
/// Android 15+ 把返回改走 OnBackInvoked 通道，`AndroidManifest` 缺
/// `android:enableOnBackInvokedCallback="true"` 时 Flutter 不注册回调，系统按默认
/// 动作 finish activity，Dart 侧 PopScope 根本没被调用（侧滑手势与注入 keyevent
/// 同现象，非探针假信号）。修复＝清单声明该属性；**真机门判据＝back_probe 宫格 7 条
/// 翻绿＋今天页首次返回出提醒条**，本用例只钉语义逻辑（widget 层复现不了平台通道差异）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(WidgetTester, GoRouter, int Function())> pumpAppWithPopCounter(
      WidgetTester tester) async {
    var popCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') popCalls++;
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
      ],
      child: const LifeHarnessApp(),
    ));
    await settle5(tester);
    final router = GoRouter.of(tester.element(find.text('今天').first));
    return (tester, router, () => popCalls);
  }

  Future<void> frames(WidgetTester tester) async {
    // 只推帧不推时间：二次退出靠 2 秒窗口判定，settle 会把假时间推过去。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  String locationOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

  testWidgets('宫格/go 进的模块主页：一次返回＝回今天，七条链路都不退 app',
      (tester) async {
    final (t, router, pops) = await pumpAppWithPopCounter(tester);
    // 与壳原型宫格 `_mods` 同源的模块主页链路。`/journal`（记录 tab）**不进这条循环**：
    // 它的日记段 build 时 `ref.read` 要 AppDatabase 实例，widget 环境没开库会抛
    // `Bad state: AppDatabase 尚未初始化`——与返回语义无关，那条腿由真机 back_probe 判。
    for (final path in ['/ledger', '/days', '/goals', '/items', '/habits', '/care', '/inbox']) {
      router.go(path);
      await frames(t);
      await t.binding.handlePopRoute();
      await t.pump();
      await frames(t);
      expect(pops(), 0, reason: '$path 首次返回不得退 app');
      expect(locationOf(router), '/', reason: '$path 返回必须落今天页');
    }
    await drainLogTimer(t);
  });
  // 「今天页首次提醒→2 秒内二次才退」与「切栏清零计时窗口」**不在本文件**：
  // 已由常驻 `test/t10_back_window_test.dart`（拦 SystemNavigator.pop 计数）与
  // `test/g1_back_probe_test.dart` 钉住，纯函数面另有 `test/shell_back_test.dart`。
  // 本批试过在此重复一条：进到 /todo 后 FakeAsync 空转到超时（待办页有周期 Timer），
  // 覆盖又是重复的——按「非必要流程砍掉」直接删，别在下批再写一遍。
}
