import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全 app 场景 pumpAndSettle 可能不收敛：5s 上限快速失败并暴露现场。
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5));

void main() {
  testWidgets('V1.28⑥ 编排态返回=退出编排并保存（不误退 app）+ ⠿ 把手拖动生效',
      (tester) async {
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

    // 长按卡片进入编排模式
    await tester.longPress(find.byKey(const ValueKey('card-press-mood')));
    for (var i = 0;
        i < 20 && find.textContaining('编排模式：拖动卡片').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('编排模式：拖动卡片调整顺序'), findsOneWidget);

    // ⠿ 把手 = 按下即拖：把 mood 卡拖到 events 之后
    final grip = find.byKey(const ValueKey('grip-mood'));
    await tester.ensureVisible(grip);
    await settle(tester);
    final g = await tester.startGesture(tester.getCenter(grip));
    await tester.pump();
    await g.moveBy(const Offset(0, 140));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await g.moveBy(const Offset(0, 140));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await settle(tester);

    // 返回键（编排态）：退出编排并保存，出现保存 toast，而非「再按一次退出」
    final popResult = await tester.binding.handlePopRoute();
    // 「退出编排」toast 需等旧 snack 退场动画完成才排入展示：有界轮询代替单帧。
    var toastSeen = false;
    for (var i = 0; i < 15 && !toastSeen; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      toastSeen =
          find.text('主页布局已保存 · 下次启动保持此顺序').evaluate().isNotEmpty;
    }
    expect(find.textContaining('编排模式：拖动卡片'), findsNothing,
        reason: '返回应结束编排态（popResult=$popResult）');
    expect(toastSeen, isTrue, reason: '退出编排应出保存 toast（全局同款风格）');
    expect(find.text('再按一次返回键退出 LifeHarness'), findsNothing);

    // 顺序已落库：mood 不再是第 2 位（默认序 greeting,mood,events,...）
    final saved = (prefs.getString('lh.home_order') ?? '').split(',');
    expect(saved, hasLength(UserSettings.kHomeCardIds.length));
    expect(saved.first, 'greeting');
    expect(saved.indexOf('mood'), greaterThan(1),
        reason: '拖动排序应已保存：$saved');

    // G1 语义不回归：非编排态再次返回 → 仍是二次退出提醒
    await settle(tester);
    await tester.binding.handlePopRoute();
    var remindSeen = false;
    for (var i = 0; i < 15 && !remindSeen; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      remindSeen = find
          .text('再按一次返回键退出 LifeHarness')
          .evaluate()
          .isNotEmpty;
    }
    expect(remindSeen, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
