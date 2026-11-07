import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/router/app_router.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// 交互整改 T11 · 底栏角标的整 app 行为（全 app 用例按仓库规矩单独成文件）。
///
/// 断三件事：① 有待办逾期时「待办」那一枚挂数字胶囊；② 进过该栏目即清，
/// 离开再回来也不复现（清的是已读标记）；③ 复位＝冷启动后重新显。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('角标随逾期读数出现→进待办清零→离开不复现→复位后回来', (tester) async {
    HomeShell.resetNavBadgeSeenForTest();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();
    Future<int> badgeSource() async => 3;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
        overdueCountProvider.overrideWith((ref) => badgeSource()),
      ],
      child: const LifeHarnessApp(),
    ));
    await settle5(tester);

    final badge = find.byKey(const ValueKey('navbadge-todo'));
    expect(badge, findsOneWidget, reason: '逾期 3 条＝待办枚该挂角标');
    expect(
        find.descendant(of: badge, matching: find.text('3')), findsOneWidget);

    final router = GoRouter.of(tester.element(find.text('今天').first));
    router.go('/todo');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(badge, findsNothing, reason: '进入该栏目＝清零');

    router.go('/');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(badge, findsNothing, reason: '离开后不许复现（读数没变，变的是已读标记）');

    // 复位＋让壳层带新读数重建＝冷启动等价：原型 navSeen 是内存对象，重启后角标要回来。
    // （不选「切到别的栏目再切回」当复位，别的栏目页要真库，本用例不建库；
    //  也不重挂 ProviderScope——元素复用下壳层不会重建，实测拿不到角标。）
    HomeShell.resetNavBadgeSeenForTest();
    ProviderScope.containerOf(tester.element(find.text('今天').first),
            listen: false)
        .invalidate(overdueCountProvider);
    await settle5(tester);
    expect(badge, findsOneWidget, reason: '复位后按同一读数重新显');
    await settle5(tester);
  });
}
