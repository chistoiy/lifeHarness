import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/nav/nav_module.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_controller.dart'
    show NavToggleResult, settingsControllerProvider;
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
  }

  group('SettingsController', () {
    test('默认设置：minimal 主题 / 跟随系统 / 5 栏底导航含今天与我的', () async {
      await boot();
      final s = container.read(settingsControllerProvider);
      expect(s.themeId, 'minimal');
      expect(s.mode, ThemeModeOption.system);
      expect(s.navIds, containsAll(['today', 'settings']));
      expect(s.navIds.length, lessThanOrEqualTo(5));
    });

    test('setTheme / setMode 持久化并可重载', () async {
      await boot();
      final c = container.read(settingsControllerProvider.notifier);
      await c.setTheme('ocean');
      await c.setMode(ThemeModeOption.dark);
      final reloaded = SettingsRepository(prefs).load();
      expect(reloaded.themeId, 'ocean');
      expect(reloaded.mode, ThemeModeOption.dark);
    });

    test('M1批2e setWeatherCity 持久化（编码 name|lat|lon · 重载可解）', () async {
      await boot();
      final c = container.read(settingsControllerProvider.notifier);
      await c.setWeatherCity('杭州|30.29|120.16');
      final reloaded = SettingsRepository(prefs).load();
      expect(reloaded.weatherCity, '杭州|30.29|120.16');
    });

    test('「今天」「我的」可关其一但不能都关；开启第 6 个栏目被拒', () async {
      await boot();
      final c = container.read(settingsControllerProvider.notifier);
      // 默认 5 个：today todo calendar journal settings。
      // 2026-10-15 产品改口：锚栏目不再「常开不可点」，可关其一。
      expect(await c.toggleNav(NavModule.today), NavToggleResult.ok);
      expect(container.read(settingsControllerProvider).navIds,
          isNot(contains('today')));
      // 再关掉另一个锚 ⇒ 底栏一个锚都不剩 ⇒ 拒。
      expect(await c.toggleNav(NavModule.settings), NavToggleResult.needAnchor);
      expect(container.read(settingsControllerProvider).navIds,
          contains('settings'), reason: '被拒时不得改动偏好');
      // 关回来的那个可以再开。
      expect(await c.toggleNav(NavModule.today), NavToggleResult.ok);

      // 上限：当前 5 个，再开 inbox 被拒。
      expect(await c.toggleNav(NavModule.inbox), NavToggleResult.maxReached);
      // 先关一个非锚项，腾出位置后就能开。
      expect(await c.toggleNav(NavModule.journal), NavToggleResult.ok);
      expect(await c.toggleNav(NavModule.inbox), NavToggleResult.ok);
      expect(container.read(settingsControllerProvider).navIds.length, 5);
    });
  });
}
