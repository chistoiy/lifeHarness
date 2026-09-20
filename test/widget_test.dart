import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('启动渲染今天页 + 可配置底栏，点待办可切页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          themeRegistryProvider.overrideWithValue(registry),
        ],
        child: const LifeHarnessApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 今天页问候卡与底栏五个栏目（原型保真版）。
    expect(find.text('今天'), findsWidgets);
    expect(find.textContaining('今天有'), findsOneWidget);
    expect(find.textContaining('第 '), findsOneWidget); // 副标题记录天数
    for (final label in ['今天', '待办', '时间', '日记', '我的']) {
      expect(find.text(label), findsWidgets, reason: '底栏应含 $label');
    }

    // 切到待办页（V1.27：顶行 ⇄ 视图切换 + 漏斗 + 搜索，FAB 进类型二选一）。
    await tester.tap(find.text('待办').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('btn-view-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-filter')), findsOneWidget);
    // 漏斗面板打开（不依赖 DB 数据；四象限看板内容在 todo_page_test 有真实库守护）
    await tester.tap(find.byKey(const ValueKey('btn-filter')));
    await tester.pumpAndSettle();
    expect(find.textContaining('智能筛选'), findsOneWidget);

    // 切到我的/设置：首屏资料卡 + 滚动到主题预览网格。
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('本地模式 · 无账号'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('🎨 主题风格'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('海洋深蓝'), findsOneWidget);
  });
}
