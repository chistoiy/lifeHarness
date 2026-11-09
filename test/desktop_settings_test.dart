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
  late List<String> pinWidgetCalls;

  setUp(() {
    syncCalls = <List<String>>[];
    pinCalls = <String>[];
    pinWidgetCalls = <String>[];
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
        case 'pinWidget':
          pinWidgetCalls.add(m['widget']! as String);
          return true;
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

  testWidgets('桌面不支持「钉快捷方式」时，整块「铺到桌面」不画（不留废行占屏）', (tester) async {
    // 2026-10-16 产品令：本机（MIUI）`isRequestPinShortcutSupported` 为 false，
    // 7 项全显示「本机不支持」＝废的还占屏。改为**按设备能力决定画不画**：
    // 不支持就不画（不是删功能，支持的桌面照旧显示）。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    debugSetPinSupported(false);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: DesktopSettingsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('铺到桌面'), findsNothing, reason: '不支持时整块不画');
    expect(find.text('本机不支持'), findsNothing, reason: '连「本机不支持」的废行也不该有');
    // 副标也不该再提「用下方『铺到桌面』」（下方已经没有那块了）。
    expect(find.textContaining('更多入口请用下方'), findsNothing);
    // 但长按菜单那块本身要还在（它跟钉桌面无关）。
    expect(find.text('长按图标菜单'), findsOneWidget);
    expect(find.textContaining('长按桌面图标弹出的快捷菜单最多'), findsOneWidget);

    // 支持时（默认桩）该块照旧显示，能力不丢。
    // ⚠ 必须先 pump 一个别的树把旧 State 丢掉：`_pinSupported` 只在 initState 读一次，
    // 直接重 pump 同类型 widget 会复用 State，读到的还是旧值（本用例踩过）。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugSetPinSupported(true);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: DesktopSettingsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('铺到桌面'), findsWidgets, reason: '支持的桌面必须照旧显示');
  });

  testWidgets('小组件三开关持久化', (tester) async {
    useTallSurface(tester);
    await pump(tester);
    // 2026-10-15 产品改口：前两枚由 Switch 改为「勾选框 + 样式预览」整卡可点，
    // 只有「隐藏金额」仍是 Switch ⇒ 本屏 Switch 数为 1（禁再多/再少，形态漂移即回归）。
    expect(find.byType(Switch), findsNWidgets(1));

    // 点整卡 = 切勾选：默认开 → 点后关，且立即落偏好。
    await tester.tap(find.byKey(const ValueKey('wg-summary')));
    await tester.pumpAndSettle();
    expect(SettingsRepository(await SharedPreferences.getInstance())
        .loadDesktopWidgetSummary(), isFalse);
    // 未勾选 ⇒ 预览淡出（一眼看出「关掉就没有」）。
    final dimmed = tester.widget<Opacity>(find.descendant(
        of: find.byKey(const ValueKey('wg-summary')), matching: find.byType(Opacity)));
    expect(dimmed.opacity, lessThan(1.0), reason: '未勾选时预览应淡出');

    await tester.tap(find.byKey(const ValueKey('wg-quick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wg-hide-amount')));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byKey(const ValueKey('wg-hide-amount'))).value, isTrue,
        reason: '默认关（B7），点后应开');
    // 落盘：与控件态一致（禁「界面翻了但偏好没存」）
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.loadDesktopWidgetSummary(), isFalse);
    expect(repo.loadDesktopWidgetQuick(), isFalse);
    expect(repo.loadDesktopHideAmount(), isTrue);
  });

  
  testWidgets('四枚小组件预览卡都在，且勾选落偏好', (tester) async {
    useTallSurface(tester);
    await pump(tester);
    // 批3：新增待办 2×2 与记账 2×2 ⇒ 预览卡共四枚（缺一枚＝用户在设置页看不到它）。
    for (final k in <String>['wg-summary', 'wg-quick', 'wg-todo-list', 'wg-ledger']) {
      expect(find.byKey(ValueKey<String>(k)), findsOneWidget, reason: '缺预览卡：$k');
    }
    // 点一下待办卡 ⇒ 总开关落盘。
    await tester.tap(find.byKey(const ValueKey('wg-todo-list')));
    await tester.pumpAndSettle();
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.loadDesktopWidgetTodoList(), isFalse);
    // 未勾选的行会淡出（用户得看得出「关掉就不添加」）。
    final dim = tester.widget<Opacity>(find.descendant(
        of: find.byKey(const ValueKey('wg-todo-list')), matching: find.byType(Opacity)));
    expect(dim.opacity, lessThan(1.0));
  });

  testWidgets('每张小组件卡自带「添加到桌面」：点哪枚发哪枚，且不吃掉卡片的启用切换', (tester) async {
    // 2026-10-15 产品改口：删掉右上角全局按钮 + App 自己那个原生选择框，
    // 改成每张卡自带按钮（用户原话：那个框「太丑」，且「勾选与否不是添加到桌面的意思」）。
    useTallSurface(tester);
    await pump(tester);
    pinWidgetCalls.clear();

    const want = <String, String>{
      'overview': '今日概览（2×2）',
      'quick': '快捷记录（4×1）',
      'todo': '今日待办（2×2）',
      'ledger': '记账概览（2×2）',
    };
    for (final e in want.entries) {
      final f = find.byKey(ValueKey<String>('widget-pin-${e.key}'));
      expect(f, findsOneWidget, reason: '${e.value} 缺「添加到桌面」按钮');
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }
    expect(pinWidgetCalls, <String>['overview', 'quick', 'todo', 'ledger'],
        reason: '点哪枚就该发哪枚（顺序＝点击顺序，禁错位）');

    // 「添加到桌面」文案只应出现在四张卡里 —— 右上角那个全局按钮已退役。
    expect(find.text('添加到桌面'), findsNWidgets(4),
        reason: '多了就是全局按钮复活，少了就是某张卡漏了按钮');

    // ⚠ 关键：按钮必须吃掉点击，不能连带触发整卡的启用/停用
    //（否则「想添加」会变成「把小组件停用」，是反向操作）。
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.loadDesktopWidgetSummary(), isTrue, reason: '点按钮不该把卡片切成停用');
    expect(repo.loadDesktopWidgetQuick(), isTrue);
    expect(repo.loadDesktopWidgetTodoList(), isTrue);
    expect(repo.loadDesktopWidgetLedger(), isTrue);
  });

  testWidgets('隐藏金额默认关', (tester) async {
    await pump(tester);
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.loadDesktopHideAmount(), isFalse);
  });
}