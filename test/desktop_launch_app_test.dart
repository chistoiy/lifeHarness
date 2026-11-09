import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/ai/ai_review.dart' show aiRootNavKey;
import 'package:lifeharness/core/platform/desktop_actions.dart'
    show kDefaultMenuActionIds;
import 'package:lifeharness/core/platform/launch_route.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_add_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// 桌面模块批1 · 冷启动 `lh://` 全链复现（B15/B16）。
///
/// 铁律（helpers.dart）：**全 app（LifeHarnessApp）用例一个文件一个**——
/// 同 isolate 多个会互相污染挂死。故本文件只放这一例。
void main() {
  testWidgets('冷启动 lh://ledger/add 应直达 /ledger/add（不落今天页）',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();

    // 门禁复位：同 isolate 内其它用例可能把全局闸门置过 true。
    debugResetLaunchGate();

    // 原生队列桩：模拟 MainActivity.pendingLaunch——**读到即清空**（单次消费 B16）。
    Map<String, Object?>? pending = <String, Object?>{
      'action': 'ledger',
      'args': <String, String>{},
    };
    const channel = MethodChannel('lh/launch');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method != 'takeLaunchRoute') return null;
        final r = pending;
        pending = null;
        return r;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    // 快捷方式桥桩：首启播种（C2/B1/F1-2）必须调到这里。
    final deskCalls = <MethodCall>[];
    const deskChannel = MethodChannel('lh/desktop');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      deskChannel,
      (call) async {
        deskCalls.add(call);
        if (call.method == 'syncShortcuts') {
          return ((call.arguments as Map)['actions'] as List).length;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(deskChannel, null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
      ],
      child: const LifeHarnessApp(),
    ));
    await settle5(tester);
    await drainLogTimer(tester);

    // 现场取证：读当前 location（也顺带证明 GoRouter.of(navCtx) 这条取用姿势可用）。
    final ctx = aiRootNavKey.value?.currentState?.context;
    final loc = ctx == null
        ? '<navCtx=null>'
        : GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.toString();

    expect(find.byType(LedgerAddPage), findsOneWidget,
        reason: '冷启动必须由 lh://ledger/add 直达记一笔页（B15 不丢弃 + B16 单次消费）');
    // 全屏栈路由必须 push ⇒ 栈底仍留着壳页（今天页）。
    // 这条正是 V1.67 真机伤（日记返回黑屏）的守护：`go` 会把壳页一起换掉，
    // 页内 pop 无处可去 ⇒ 黑屏且退不出去。
    expect(find.byType(DashboardPage, skipOffstage: false), findsOneWidget,
        reason: 'push 语义：栈底必须留着壳页，返回才有去处（下层路由 offstage，须 skipOffstage:false）');
    // 返回一步：必须落回今天页，而不是黑屏/空栈。
    await tester.binding.handlePopRoute();
    await settle5(tester);
    expect(find.byType(LedgerAddPage), findsNothing, reason: '返回应弹出记一笔页');
    expect(find.byType(DashboardPage), findsOneWidget,
        reason: '返回后必须落回今天页（不得黑屏）');
    // ignore: avoid_print
    print('DESKAPP cold-launch location=$loc  pop→今天页 OK  deskCalls=${deskCalls.map((c) => c.method).toList()}');

    // ===== 首启播种动态快捷方式（C2/B1/F1-2）=====
    // 冻结档三处口径：App 首启以默认 4 枚 setDynamicShortcuts。只写在设置页里
    // 会让「没打开过设置页」的用户长按图标没有菜单（真机门直接判不合格）。
    final sync = deskCalls.where((c) => c.method == 'syncShortcuts').toList();
    expect(sync, hasLength(1),
        reason: '首启必须且只播种一次（一次性副作用，重建不重复）');
    expect(((sync.single.arguments as Map)['actions'] as List).cast<String>(),
        kDefaultMenuActionIds,
        reason: '播种内容＝默认 4 枚（与设置页同一读口，禁另造默认值）');
  });
}
