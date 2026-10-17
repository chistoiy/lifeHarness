import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/nav/nav_collapse.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/router/app_router.dart' show shellBottomSlack;
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/core/widgets/grad_fab.dart';
import 'package:lifeharness/shared/linkage/timer_bar_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// V1.65 底栏收起态壳层守护。
///
/// **全 app（LifeHarnessApp）用例一个文件一个**（helpers 铁律：同 isolate 多例会互踩挂死），
/// 所以四件事（默认关零影响 / 张开收起 / 捏合还原 / 线索形态与悬浮球不落底）写在同一个
/// testWidgets 里，靠运行时改设置项切换场景，而不是拆成四个用例。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 双指手势：起始两指在 x=180/220（间距 40）。dx>0＝张开、dx<0＝捏合。
  ///
  /// 只移动不消费——壳层是 [Listener] 观察，子级列表/卡片不受影响。
  Future<void> twoFinger(WidgetTester t, double dx) async {
    const y = 300.0;
    final a = await t.startGesture(const Offset(180, y));
    final b = await t.startGesture(const Offset(220, y));
    await t.pump(const Duration(milliseconds: 16));
    await a.moveTo(Offset(180 - dx, y));
    await b.moveTo(Offset(220 + dx, y));
    await t.pump(const Duration(milliseconds: 16));
    await a.up();
    await b.up();
    await t.pump(const Duration(milliseconds: 16));
  }

  // 张开：间距 40 → 160（比值 4）＝收起；捏合：40 → 4（比值 0.1）＝还原。
  Future<void> spread(WidgetTester t) => twoFinger(t, 60);
  Future<void> pinch(WidgetTester t) => twoFinger(t, -18);

  testWidgets('双指张开收起底栏 / 捏合还原；线索与悬浮球符合拍板', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      themeRegistryProvider.overrideWithValue(registry),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const LifeHarnessApp()));
    await settle5(tester);

    const h = 600.0; // 默认测试视口高（无系统安全区 inset）
    // 底栏槽位真实高度＝nav 内容 70 ＋ Container 的 1px 上描边（u1 用例同口径）。
    const navSlotH = kShellNavHeight + 1;
    double slotH() =>
        tester.getSize(find.byKey(const ValueKey('shell-nav-slot'))).height;
    double pageBottom() => tester.getRect(find.byType(TimerBarOverlay)).bottom;
    final line = find.byKey(const ValueKey('shell-nav-line'));

    // 出厂态：手势总开关默认关 → 底栏在位、没有线索。
    expect(slotH(), navSlotH);
    expect(line, findsNothing);
    expect(pageBottom(), closeTo(h - navSlotH - shellBottomSlack, 1.5));

    // 悬浮球在屏上的落点（要它全程不动）。
    final circle = find
        .descendant(of: find.byType(GradFab), matching: find.byType(InkWell))
        .first;
    final fabY0 = tester.getCenter(circle).dy;

    // ① 总开关关着：双指张开＝什么都不该发生（「默认关」＝对老用户零行为变化）。
    await spread(tester);
    await tester.pumpAndSettle();
    expect(slotH(), navSlotH, reason: '开关关着时不许收底栏');
    expect(line, findsNothing);

    // ② 打开总开关。
    await c.read(settingsControllerProvider.notifier).setNavGesture(true);
    await tester.pumpAndSettle();

    // ③ 双指张开＝收起底栏：槽位收干净（不留位）、内容通底、线索出现（默认 A 细握把）。
    await spread(tester);
    await tester.pumpAndSettle();
    expect(slotH(), 0, reason: '收起＝底栏整条不占位（内容才通底）');
    expect(pageBottom(), closeTo(h - kNavCollapsedSlack, 1.5),
        reason: '收起后底留白＝kNavCollapsedSlack（原型 .page.safe-pb 28px）');
    expect(line, findsOne, reason: '收起必须给一条可见线索，防「底栏去哪了」');
    expect(find.byType(NavLineGrip), findsOne);
    expect(find.byType(NavLineCapsule), findsNothing);
    expect(h - tester.getRect(find.byType(NavLineGrip)).bottom, closeTo(16, 1.0),
        reason: '线索默认距屏幕底部 16px');

    // 悬浮球**不落底**：屏幕上位置钉住不动。
    expect(tester.getCenter(circle).dy, closeTo(fabY0, 1.5),
        reason: '底栏收起不该让悬浮球往下掉（产品拍板「不落底」）');

    // ④ 双指捏合＝还原。
    await pinch(tester);
    await tester.pumpAndSettle();
    expect(slotH(), navSlotH);
    expect(line, findsNothing);
    expect(tester.getCenter(circle).dy, closeTo(fabY0, 1.5));

    // ⑤ 线索换 B（胶囊折角）＋距底 40：收起后按新形态/新距离渲染。
    await c.read(settingsControllerProvider.notifier).setNavLineStyle('b');
    await c.read(settingsControllerProvider.notifier).setNavLineGap(40);
    await tester.pumpAndSettle();
    await spread(tester);
    await tester.pumpAndSettle();
    expect(slotH(), 0);
    expect(find.byType(NavLineCapsule), findsOne);
    expect(find.byType(NavLineGrip), findsNothing);
    expect(
        h - tester.getRect(find.byType(NavLineCapsule)).bottom, closeTo(40, 1.0),
        reason: '距底档位（设置滑杆）要真的生效');

    // ⑥ 关掉总开关＝立刻展开（不残留收起态，两态不打架）。
    await c.read(settingsControllerProvider.notifier).setNavGesture(false);
    await tester.pumpAndSettle();
    expect(slotH(), navSlotH);
    expect(line, findsNothing);

    await drainLogTimer(tester);
  });
}
