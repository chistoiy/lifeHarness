import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5));

void main() {
  testWidgets('G1 复现：今天页 handlePopRoute 首次应出提醒 SnackBar 而非退出',
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

    final popResult = await tester.binding.handlePopRoute();
    await tester.pump(); // 触发 onPopInvokedWithResult
    final snackFound =
        find.text('再按一次返回键退出 LifeHarness').evaluate().isNotEmpty;
    // ignore: avoid_print
    print('G1PROBE popResult=$popResult snack=$snackFound');
    expect(snackFound, isTrue, reason: '首次返回应提醒而非直接退出');
  });
}
