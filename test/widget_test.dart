import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/features/settings/presentation/settings_page.dart'
    show SettingsPage;
import 'package:shared_preferences/shared_preferences.dart';

/// 全 app shell 场景下 pumpAndSettle 可能不收敛（事件总线/动画），
/// 统一用带 5s 上限的 settle，失败快速暴露而非拖满框架超时。
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5));

void main() {
  testWidgets('启动渲染今天页 + 可配置底栏，点待办可切页', (tester) async {
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

    // 今天页问候卡与底栏五个栏目（原型保真版）。
    expect(find.text('今天'), findsWidgets);
    expect(find.textContaining('今天有'), findsOneWidget);
    expect(find.textContaining('第 '), findsOneWidget); // 副标题记录天数
    for (final label in ['今天', '待办', '时间', '记录', '我的']) {
      expect(find.text(label), findsWidgets, reason: '底栏应含 $label');
    }

    // 切到待办页（V1.27：顶行 ⇄ 视图切换 + 漏斗 + 搜索，FAB 进类型二选一）。
    await tester.tap(find.text('待办').last);
    await settle(tester);
    expect(find.byKey(const ValueKey('btn-view-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-filter')), findsOneWidget);
    // 漏斗面板打开（不依赖 DB 数据；四象限看板内容在 todo_page_test 有真实库守护）
    await tester.tap(find.byKey(const ValueKey('btn-filter')));
    await settle(tester);
    expect(find.textContaining('智能筛选'), findsOneWidget);

    // 切到我的/设置：首屏资料卡 + 滚动到「外观」二级页入口（V1.27 P2 收拢）。
    await tester.tap(find.text('我的').last);
    await settle(tester);
    expect(find.textContaining('本地模式 · 无账号'), findsOneWidget);

    final entry = find.byKey(const ValueKey('entry-appearance'));
    final settingsList = find.descendant(
        of: find.byType(SettingsPage), matching: find.byType(Scrollable));
    // 先滚到已构建，再 ensureVisible 拉进视口（避免 tap 落空 warnIfMissed）
    for (var i = 0; i < 12 && entry.evaluate().isEmpty; i++) {
      await tester.drag(settingsList.first, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(entry);
    await settle(tester);
    expect(find.text('🎨 主题风格'), findsNothing); // 已收进二级页
    await tester.tap(entry);
    await settle(tester);
    expect(find.text('🎨 主题风格'), findsOneWidget);
    expect(find.text('海洋深蓝'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // V1.29批A4：「记录管理」二级页入口（外观卡下方一行）。
    final recmg = find.byKey(const ValueKey('entry-recmg'));
    for (var i = 0; i < 12 && recmg.evaluate().isEmpty; i++) {
      await tester.drag(settingsList.first, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(recmg);
    await settle(tester);
    await tester.tap(recmg);
    await settle(tester);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('记录管理')),
        findsOneWidget); // AppBar 标题
    for (var i = 0;
        i < 8 && find.text('回收站自动清理').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('回收站自动清理'), findsOneWidget);
  });
}
