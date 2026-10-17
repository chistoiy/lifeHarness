import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// V1.29轮9 返回策略：批量多选态下返回=先退出多选（不导航、不进二次退出判定）。
void main() {
  testWidgets('多选态 handlePopRoute → 清空 noteSelProvider 且不出「再按一次」提醒',
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
    await tester.pumpAndSettle(
        const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5));

    final container =
        ProviderScope.containerOf(tester.element(find.byType(LifeHarnessApp)));
    container.read(noteSelProvider.notifier).state = {999};

    await tester.binding.handlePopRoute();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(container.read(noteSelProvider), isEmpty,
        reason: '返回应优先退出批量多选');
    expect(find.text('再按一次返回键退出 LifeHarness'), findsNothing,
        reason: '退多选那次返回不应触发退出提醒');

    // 多选已空后再返回：回到既有 G1 语义（今天页二次退出提醒）
    await tester.binding.handlePopRoute();
    var remindSeen = false;
    for (var i = 0; i < 15 && !remindSeen; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      remindSeen = find
          .text('再按一次返回键退出 LifeHarness')
          .evaluate()
          .isNotEmpty;
    }
    expect(remindSeen, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
