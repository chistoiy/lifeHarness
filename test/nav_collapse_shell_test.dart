import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/nav/nav_collapse.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart'
    show calendarTickerProvider;
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
    // ⚠ 本用例收尾必须让 pumpAndSettle 把世界跑够**一整个周期**：全 app 起来后
    //   `sysPillSyncProvider` 会挂一条 1s 周期流，只排空日志节流那条 timer 不够，
    //   留下一条 1s periodic 就会以「A Timer is still pending」判红。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      themeRegistryProvider.overrideWithValue(registry),
      // sysPillSync 会 watch 秒级心跳；真实 `Stream.periodic` 在 fake_async 里
      // **永不排空**（periodic 不会被 pumpAndSettle 耗尽）⇒ 收尾判「A Timer is still
      // pending」。与本仓其余全 app 用例同口径：心跳换成空流
      // （`read_f2_nav_test` / `read_pill_fab_test` / `read_timer_bar_test` 同）。
      calendarTickerProvider.overrideWith((ref) => const Stream.empty()),
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

    // ⑥ 关掉总开关＝立刻展开（不残留手势收起态，两态不打架）。
    await c.read(settingsControllerProvider.notifier).setNavGesture(false);
    await tester.pumpAndSettle();
    expect(slotH(), navSlotH);
    expect(line, findsNothing);

    // ⑦ 批C-2：线索**可点还原**（原来是 IgnorePointer 死件——产品原话
    //    「箭头或短线没有实际功能」）。总开关已关 ⇒ 这是唯一能回来的路。
    c.read(navEntryCollapsedProvider.notifier).hide();
    await tester.pumpAndSettle();
    expect(slotH(), 0, reason: '入口态不看总开关：瓦片进来默认收起');
    expect(line, findsOne);
    // 命中区比图形大（细握把只有 4dp 高），点的位置可以偏开图形本身。
    expect(tester.getSize(find.byKey(const ValueKey('shell-nav-line-tap'))),
        const Size(120, 44));
    // （常量值同上：命中区 120×44，见 nav_collapse 的 kNavCueHitWidth/Height）
    // 图形仍贴命中区底边 ⇒ 距屏幕底部的视觉位置与二修口径逐像素相同。
    expect(h - tester.getRect(find.byType(NavLineCapsule)).bottom,
        closeTo(40, 1.0),
        reason: '命中区只许向上长，图形位置不能动');
    await tester.tap(find.byKey(const ValueKey('shell-nav-line-tap')));
    await tester.pumpAndSettle();
    expect(slotH(), navSlotH, reason: '点线索＝还原底栏');
    expect(line, findsNothing);

    // ⑧ 线索给了无障碍语义（读屏能念出「显示底部导航栏」）。
    c.read(navEntryCollapsedProvider.notifier).hide();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell-nav-line-tap')), findsOneWidget);
    // 用源码守护而不是 widget 树断言：`Semantics(button:, label:)` 与
    // GestureDetector 会各自插一个 Semantics 节点，按位置取外层/内层都会随 SDK
    // 实现细节漂；这里钉的是「有没有写这三样」。
    final src = File('lib/core/router/app_router.dart').readAsStringSync();
    expect(src, contains("label: '显示底部导航栏'"), reason: '线索缺无障碍文案');
    expect(src, contains('button: true'), reason: '线索没标成按钮');
    expect(src, contains("ValueKey('shell-nav-line-tap')"),
        reason: '线索缺可点命中区');
    expect(src.contains('IgnorePointer('), isFalse,
        reason: '线索不再是死件——别再套回 IgnorePointer');

    // 收尾：还原底栏 → 排空日志节流 → 让世界跑够 1 个整轮再收（见文件头注释）。
    await tester.tap(find.byKey(const ValueKey('shell-nav-line-tap')));
    await tester.pumpAndSettle();
    await drainLogTimer(tester);
    // 世界跑够一整个周期（见用例头注释：sysPillSync 那条 1s periodic 流）。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}
