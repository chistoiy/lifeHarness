import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart';
import 'package:lifeharness/core/platform/desktop_shortcuts.dart';
import 'package:lifeharness/core/platform/launch_route.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/settings/presentation/desktop_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面设置页守护（冻结档 §6.4 · `test/desktop_settings_test.dart`）。
///
/// 覆盖：勾选上限 4（第 5 项被拒且不落偏好）／改动即时落偏好并重建快捷方式／
/// 铺桌面降级（B2）／小组件开关持久化。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 原生桥桩：记录 syncShortcuts 调用，并回报 pin 支持态。
  late List<List<String>> syncCalls;
  late bool pinOk;
  late List<String> pinCalls;

  setUp(() {
    syncCalls = <List<String>>[];
    pinCalls = <String>[];
    pinOk = true;
    debugSetPinSupported(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lh/desktop'), (call) async {
      final m = call.arguments as Map<Object?, Object?>;
      switch (call.method) {
        case 'syncShortcuts':
          final acts = (m['actions']! as List).cast<String>();
          syncCalls.add(acts);
          return acts.length;
        case 'requestPinShortcut':
          pinCalls.add(m['action']! as String);
          return pinOk;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lh/desktop'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lh/launch'), null);
    debugResetLaunchGate();
  });

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: DesktopSettingsPage()),
    ));
    await tester.pumpAndSettle();
  }

  /// 设置页内容较长，默认 600px 测试视口装不下三卡 —— 统一放到 1400px 高再操作。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('默认勾选 4 枚，计数显示 4/4', (tester) async {
    await pump(tester);
    expect(find.text('已选 4/4'), findsOneWidget);
    for (final id in kDefaultMenuActionIds) {
      final cb = tester.widget<Checkbox>(find.byKey(ValueKey('menu-$id')));
      expect(cb.value, isTrue, reason: '$id 应默认勾选');
    }
  });

  testWidgets('第 5 项被拒：置灰不可点且不落偏好', (tester) async {
    await pump(tester);
    // 先取消一枚腾出空位，再勾第 5 枚
    await tester.tap(find.byKey(const ValueKey('menu-inbox')));
    await tester.pumpAndSettle();
    expect(find.text('已选 3/4'), findsOneWidget);

    // 恢复成 4 枚（inbox 勾回），此时 habit 之外再点 journal 应被拦
    await tester.tap(find.byKey(const ValueKey('menu-inbox')));
    await tester.pumpAndSettle();
    expect(find.text('已选 4/4'), findsOneWidget);

    // 满 4 枚时，未选项的 checkbox onChanged 必须为 null（置灰）
    final jn = tester.widget<Checkbox>(find.byKey(const ValueKey('menu-journal')));
    expect(jn.onChanged, isNull, reason: '已满 4 枚时空位项须置灰');
  });

  testWidgets('改动即时落偏好并重建快捷方式', (tester) async {
    await pump(tester);
    final before = syncCalls.length;
    // 默认已满 4 枚（journal 处于置灰态），先取消 todo 腾出空位再勾 journal
    await tester.tap(find.byKey(const ValueKey('menu-todo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-journal')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(prefs);
    expect(repo.loadDesktopMenu(), contains('journal'));
    expect(syncCalls.length, greaterThan(before), reason: 'F1-2/F1-4：改动须即时重建');
    expect(syncCalls.last, contains('journal'));
  });

  testWidgets('铺到桌面成功 → 记为已铺态', (tester) async {
    await pump(tester);
    pinOk = true;
    await tester.ensureVisible(find.byKey(const ValueKey('pin-ledger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pin-ledger')));
    await tester.pumpAndSettle();
    expect(pinCalls, contains('ledger'));
    expect(find.text('已铺'), findsWidgets);

    final prefs = await SharedPreferences.getInstance();
    expect(SettingsRepository(prefs).loadDesktopPinned(), contains('ledger'));
  });

  testWidgets('铺到桌面被系统拒绝 → 提示且不记已铺（B2）', (tester) async {
    await pump(tester);
    pinOk = false;
    await tester.ensureVisible(find.byKey(const ValueKey('pin-items')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pin-items')));
    await tester.pumpAndSettle();
    expect(find.text('已铺'), findsNothing);
    expect(find.text('这台设备不支持铺到桌面'), findsOneWidget);
  });

  testWidgets('不支持铺桌面时按钮禁用并改文案', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    debugSetPinSupported(false);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: DesktopSettingsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本机不支持'), findsWidgets);
    final btn = tester.widget<TextButton>(find.ancestor(
        of: find.text('本机不支持').first, matching: find.byType(TextButton)));
    expect(btn.onPressed, isNull, reason: 'B2：不支持时须禁用');
  });

  testWidgets('小组件三开关持久化', (tester) async {
    useTallSurface(tester);
    await pump(tester);
    final sw = find.byType(Switch);
    expect(sw, findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('wg-summary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wg-hide-amount')));
    await tester.pumpAndSettle();

    // 控件态：被点的两枚翻了（summary/quick 默认开 → 关；hideAmount 默认关 → 开），
    // 未动的 wg-quick 保持默认开。
    expect(tester.widget<Switch>(find.byKey(const ValueKey('wg-summary'))).value, isFalse,
        reason: '默认开，点后应关');
    expect(tester.widget<Switch>(find.byKey(const ValueKey('wg-hide-amount'))).value, isTrue,
        reason: '默认关（B7），点后应开');
    expect(tester.widget<Switch>(find.byKey(const ValueKey('wg-quick'))).value, isTrue,
        reason: '未动的开关应保持默认开');
    // 落盘：与控件态一致（禁「界面翻了但偏好没存」）
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.loadDesktopWidgetSummary(), isFalse);
    expect(repo.loadDesktopHideAmount(), isTrue);
    expect(repo.loadDesktopWidgetQuick(), isTrue);
  });

  testWidgets('隐藏金额默认关', (tester) async {
    await pump(tester);
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.loadDesktopHideAmount(), isFalse);
  });
}