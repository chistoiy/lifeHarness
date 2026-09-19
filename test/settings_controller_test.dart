import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/nav/nav_module.dart';
import 'package:lifeharness/core/providers.dart';
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

    test('固定项不可关闭；开启第 6 个栏目被拒', () async {
      await boot();
      final c = container.read(settingsControllerProvider.notifier);
      expect(await c.toggleNav(NavModule.today), isFalse);
      expect(await c.toggleNav(NavModule.settings), isFalse);

      // 先关一个可选项，再开 inbox → 成功；此时再开 notes 类不在枚举内，测满 5 拒绝：
      expect(await c.toggleNav(NavModule.journal), isTrue);
      expect(await c.toggleNav(NavModule.inbox), isTrue);
      // 当前 5 个：today todo calendar inbox settings，已达上限
      expect(await c.toggleNav(NavModule.journal), isFalse);
      expect(
          container.read(settingsControllerProvider).navIds.length, 5);
    });
  });
}
