import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// V1.65 底栏手势三设置项（模型 round-trip / 越界收敛 / 落盘重载）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> boot([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('V1.65 底栏手势设置项', () {
    test('默认值：手势关 / 线索 A 细握把 / 距底 16（产品拍板「默认关」）', () {
      const s = UserSettings.defaults;
      expect(s.navGestureOn, isFalse);
      expect(s.navLineStyle, 'a');
      expect(s.navLineGap, kNavLineGapDefault);
      expect(kNavLineGapDefault, 16);
    });

    test('toMap/fromMap round-trip 三字段', () {
      const s = UserSettings(
        themeId: 'minimal',
        mode: ThemeModeOption.system,
        navIds: ['today', 'settings'],
        navGestureOn: true,
        navLineStyle: 'b',
        navLineGap: 40,
      );
      final back = UserSettings.fromMap(s.toMap());
      expect(back.navGestureOn, isTrue);
      expect(back.navLineStyle, 'b');
      expect(back.navLineGap, 40);
    });

    test('fromMap 脏值收敛：距底越界夹到档位、形态未知回落 a', () {
      expect(UserSettings.fromMap({'navLineGap': 0}).navLineGap, kNavLineGapMin);
      expect(UserSettings.fromMap({'navLineGap': 999}).navLineGap, kNavLineGapMax);
      expect(UserSettings.fromMap({'navLineStyle': 'zzz'}).navLineStyle, 'a');
      expect(UserSettings.fromMap({'navGestureOn': null}).navGestureOn, isFalse);
    });

    test('控制器写入三字段 → 落盘 → 重载可解（不动其它项）', () async {
      final c = await boot();
      final ctl = c.read(settingsControllerProvider.notifier);
      await ctl.setNavGesture(true);
      await ctl.setNavLineStyle('b');
      await ctl.setNavLineGap(40);

      final prefs = await SharedPreferences.getInstance();
      final r = SettingsRepository(prefs).load();
      expect(r.navGestureOn, isTrue);
      expect(r.navLineStyle, 'b');
      expect(r.navLineGap, 40);
      // 没动过的项保持默认（防「写一个新键把别的冲掉」）
      expect(r.themeId, 'minimal');
      expect(r.mode, ThemeModeOption.system);
    });

    test('控制器侧也收敛：setNavLineGap 越界夹到档位、setNavLineStyle 未知回落 a',
        () async {
      final c = await boot();
      final ctl = c.read(settingsControllerProvider.notifier);

      await ctl.setNavLineGap(0);
      expect(c.read(settingsControllerProvider).navLineGap, kNavLineGapMin);
      await ctl.setNavLineGap(999);
      expect(c.read(settingsControllerProvider).navLineGap, kNavLineGapMax);

      await ctl.setNavLineStyle('nope');
      expect(c.read(settingsControllerProvider).navLineStyle, 'a');
    });

    test('盘上只有底栏手势键时不被 defaults 吞（load 判据已纳入三键）', () async {
      final c = await boot(const {
        'lh.nav_gesture_on': true,
        'lh.nav_line_style': 'b',
        'lh.nav_line_gap': 32,
      });
      final s = c.read(settingsControllerProvider);
      expect(s.navGestureOn, isTrue,
          reason: '只落了底栏手势三键时，load 必须仍走 fromMap 而不是回落 defaults');
      expect(s.navLineStyle, 'b');
      expect(s.navLineGap, 32);
    });
  });
}
