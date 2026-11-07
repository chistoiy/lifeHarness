import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// T10 挂账修复常驻用例：切栏目必须清零「再按一次返回退出」的计时窗口。
///
/// 缺陷原状：`HomeShell._lastBackAt` 只在 goToday/exit/endEdit 分支清零，
/// **切栏不重置**——今天页按一次返回（出提醒）后切到别的栏目、2 秒内再切回
/// 今天按返回，会被判成「第二次按」而直接退 app。
/// 判定主信号＝拦 `SystemNavigator.pop` 平台通道调用次数（提醒条会跨步残留，
/// 只断文案有假绿风险）；整条序列的 fake 时间压在 ~200ms，远小于 2 秒窗口，
/// 所以「窗口自然过期」不可能替修复遮丑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('今天页提醒→切栏→切回→再按返回：仍是提醒，不退出 app', (tester) async {
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

    // ① 今天页第一次返回＝提醒（不退出）
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(popCalls, 0, reason: '首次返回只该提醒');
    expect(find.text('再按一次返回键退出 LifeHarness'), findsOneWidget);

    // ② 切栏 → 切回：只推几帧让 HomeShell 带新 currentPath 重建，
    //    不 settle（settle 会把 fake 时间推过 2 秒窗口，测试就废了）
    router.go('/todo');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    router.go('/');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // ③ 再按一次返回：修好后仍走「提醒」分支（旧代码在此直接退 app）
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(popCalls, 0, reason: '切过栏目＝重新计数，这一次返回不该退 app');
    expect(find.text('再按一次返回键退出 LifeHarness'), findsOneWidget);
    await clearToasts(tester);
    await drainLogTimer(tester);
  });
}
