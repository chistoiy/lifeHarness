// 深色模式三档（LH-K38 `SegRow` 首个落点 · 2026-10-07 产品令）。
// 钉四件事：
//  ① 默认档＝跟随系统，且**系统深浅当场切换就当场变**（不重进、不锁死）；
//  ② 锁浅色／锁深色后系统切换不越权；三档点选都真落库（重读 SettingsRepository 复验）；
//  ③ 强制深色主题（赛博朋克）下三档整条置灰、点下去不改值，并给一行「为什么不可选」的副注；
//  ④ 形态守护：档位不许再藏回「副标小字点击」，深色行必须是可见分段（源码闸）。
// 独立文件防 isolate 污染；主题注册表吃真实 assets（7 套），不造假令牌。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/features/settings/presentation/settings_page.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

const _segSrc =
    'lib/features/settings/presentation/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late ThemeRegistry registry;
  late SettingsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    registry = await const ThemeRepository().loadAll();
    repo = SettingsRepository(prefs);
  });

  /// 主题切换带 ThemeAnimationStyle 插值：只 pump 一帧会读到**上一档的亮度**
  /// （首跑 ①② 两条假红即此因），所以每步都 settle 到动画落定再断言。
  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
    await settleFrames(t);
  }

  /// 真实生效链：MaterialApp 的 theme/darkTheme/themeMode 全吃 app 侧 provider，
  /// 所以断言「页面此刻渲染出的亮度」＝断言整条链，而不是断 provider 读数。
  Widget wrap() => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      themeRegistryProvider.overrideWithValue(registry),
    ],
    child: Consumer(
      builder: (context, ref, _) => MaterialApp(
        theme: ref.watch(lightThemeProvider),
        darkTheme: ref.watch(darkThemeProvider),
        themeMode: ref.watch(appThemeModeProvider),
        home: const AppearanceSettingsPage(),
      ),
    ),
  );

  Future<void> open(WidgetTester t) async {
    await useSurface(t, const Size(420, 900));
    await t.pumpWidget(wrap());
    await step(t, times: 3);
    final seg = find.byKey(const ValueKey('dark-mode-seg'));
    expect(seg, findsOneWidget, reason: '外观屏必须有可见的深色三档分段');
    await t.scrollUntilVisible(seg, -220,
        scrollable: find.byType(Scrollable).first, maxScrolls: 8);
    await step(t);
  }

  Brightness rendered(WidgetTester t) =>
      Theme.of(t.element(find.text('深色模式'))).brightness;

  /// 只设 testValue 不派发通知＝框架看不见变化（① 首跑就是这么假红了）；
  /// 必须 handlePlatformBrightnessChanged 走一遍真通知链。
  Future<void> systemBrightness(WidgetTester t, Brightness b) async {
    t.binding.platformDispatcher.platformBrightnessTestValue = b;
    t.binding.handlePlatformBrightnessChanged(); // 同步派发（返回 void，别 await）
    await step(t);
  }

  /// 当前高亮档＝字重 w800 的那一枚（未选 w600）。
  List<String> selectedLabels(WidgetTester t) => ['跟随系统', '浅色', '深色']
      .where((l) =>
          t.widget<Text>(find.text(l)).style?.fontWeight == FontWeight.w800)
      .toList();

  group('深色模式三档 · 外观屏', () {
    testWidgets('① 默认跟随系统：系统浅＝浅、系统深＝深，副注报出当前态', (t) async {
      addTearDown(() => t.binding.platformDispatcher.clearPlatformBrightnessTestValue());
      await systemBrightness(t, Brightness.light);
      await open(t);
      expect(rendered(t), Brightness.light);
      expect(selectedLabels(t), ['跟随系统']);
      expect(find.textContaining('跟随系统 · 现在是浅色'), findsOneWidget);
      // 系统当场转深→页面当场跟（不设「重进才生效」的口子）
      await systemBrightness(t, Brightness.dark);
      expect(rendered(t), Brightness.dark,
          reason: '跟随系统档下系统切深必须当场转深');
      expect(find.textContaining('跟随系统 · 现在是深色'), findsOneWidget);
      expect(selectedLabels(t), ['跟随系统'], reason: '跟随时长不许自己跳档');
    });

    testWidgets('② 锁浅色／锁深色：系统切换不越权，且每档都真落库', (t) async {
      addTearDown(() => t.binding.platformDispatcher.clearPlatformBrightnessTestValue());
      await systemBrightness(t, Brightness.dark);
      await open(t);
      // 系统此刻是深，锁浅→必须转浅
      await t.tap(find.byKey(const ValueKey('dark-mode-light')));
      await step(t);
      expect((await repo.load()).mode, ThemeModeOption.light,
          reason: '档位必须落盘（冷启动仍是这一档）');
      // 断的是整条链：MaterialApp 收到的 themeMode／theme 本体／页面读到的亮度三者一致。
      final appW = t.widget<MaterialApp>(find.byType(MaterialApp));
      expect(appW.themeMode, ThemeMode.light);
      expect(appW.theme!.brightness, Brightness.light);
      expect(rendered(t), Brightness.light, reason: '锁浅后当场转浅');
      expect(find.textContaining('已锁定浅色'), findsOneWidget);
      // 锁深→转深
      await t.tap(find.byKey(const ValueKey('dark-mode-dark')));
      await step(t);
      expect(rendered(t), Brightness.dark);
      expect(find.textContaining('已锁定深色'), findsOneWidget);
      expect((await repo.load()).mode, ThemeModeOption.dark);
      // 锁定档下系统再翻面也不许越权
      await systemBrightness(t, Brightness.light);
      expect(rendered(t), Brightness.dark, reason: '锁深色时系统转浅不许改写');
      // 回跟随系统→立刻交还系统态
      await t.tap(find.byKey(const ValueKey('dark-mode-system')));
      await step(t);
      expect(rendered(t), Brightness.light);
      expect((await repo.load()).mode, ThemeModeOption.system);
    });

    testWidgets('③ 强制深色主题：三档置灰点不动，副注说清原因', (t) async {
      addTearDown(() => t.binding.platformDispatcher.clearPlatformBrightnessTestValue());
      await systemBrightness(t, Brightness.light);
      await repo.save(const UserSettings(
        themeId: 'cyber',
        // 种子档故意留 system：若置灰失效，点「浅色」会把 system 改掉——
        // 首版这里写的是 light，点 light 本就无变化＝空闸（变异刀1 当场露出）。
        mode: ThemeModeOption.system,
        navIds: ['today', 'todo', 'calendar', 'journal', 'settings'],
      ));
      await open(t);
      expect(rendered(t), Brightness.dark, reason: '赛博朋克强制深色');
      expect(find.textContaining('当前主题强制深色 · 三档暂不可选'), findsOneWidget);
      final row = t.widget<Opacity>(
        find.descendant(
          of: find.byKey(const ValueKey('dark-mode-seg')),
          matching: find.byType(Opacity),
        ),
      );
      expect(row.opacity, lessThan(1), reason: '置灰要有可见读数');
      // 点它没反应：不许静默改档
      await t.tap(find.byKey(const ValueKey('dark-mode-light')));
      await step(t);
      expect((await repo.load()).mode, ThemeModeOption.system,
          reason: '置灰档点下去不许改设置（也不许改成功再假装没动）');
      expect(rendered(t), Brightness.dark);
    });

    testWidgets('④ 形态守护：档位不许藏回副标文字点击，深色行必须是可见分段', (t) async {
      final src = File(_segSrc).readAsStringSync();
      expect(src, contains("keyPrefix: 'dark-mode'"),
          reason: '深色三档必须走 LH-K38 SegRow（枚举一次看全）');
      for (final banned in ['点此跟随系统', '点此锁定/解锁']) {
        expect(src, isNot(contains(banned)),
            reason: '「$banned」＝把某一档藏进小字点击的旧形态，不许回归');
      }
      // Switch 控深色＝旧形态（两态装不下三档），本屏不许再出现
      final segRow = src.indexOf('深色模式三档');
      final block = src.substring(segRow, segRow + 2400);
      expect(block, isNot(contains('Switch(')),
          reason: '深色档位在分段里选，不用 Switch 硬凑三态');
    });
  });
}
