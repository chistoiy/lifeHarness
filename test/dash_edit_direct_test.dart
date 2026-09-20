import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全 app 场景 pumpAndSettle 可能不收敛：5s 上限快速失败并暴露现场。
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5));

void main() {
  testWidgets('V1.27 P3 设置页「主页编排直达」→ 今天页直接进入编排模式',
      (tester) async {
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
    await settle(tester);

    await tester.tap(find.text('我的').last);
    await settle(tester);

    final btn = find.textContaining('主页编排直达');
    for (var i = 0; i < 12 && btn.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(btn);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(btn);
    // 350ms 事件总线延时 + 进编辑态：有界轮询，不进无界 pumpAndSettle
    for (var i = 0;
        i < 20 && find.textContaining('编排模式：拖动卡片').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('编排模式：拖动卡片调整顺序'), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-done-btn')), findsOneWidget);
  });
}
