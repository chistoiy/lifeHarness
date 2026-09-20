import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/shared/linkage/linkage_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('V1.27 P3 事件总线 EnterDashEditEvent → 今天页进入编排模式',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      themeRegistryProvider.overrideWithValue(registry),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DashboardPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('编排模式'), findsNothing);
    container.read(eventBusProvider).publish(const EnterDashEditEvent());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('编排模式：拖动卡片调整顺序'), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-done-btn')), findsOneWidget);
  });
}
