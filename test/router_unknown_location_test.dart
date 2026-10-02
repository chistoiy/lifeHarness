/// R3-1（真机轮3 P0）· 未知 location 兜底与冷启动路由通路掐断的守护用例。
///  ① 行为：go 一个未注册 location → 不落 GoException 工程错误页，
///     回已注册首页 + 一条可读 toast（用生产同款 unknownRouteFallback）；
///  ② 接线：生产 GoRouter 配置必须挂着该 errorBuilder（源码级钉）；
///  ③ 根因侧：release 清单必须钉住 `flutter_deeplinking_enabled=false`
///     （embedding 冷启动把 VIEW intent 的 data 当初始路由、热启动
///     pushRouteInformation 的通路总开关，掐掉才不再复现）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lifeharness/core/router/app_router.dart'
    show unknownRouteFallback;

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      errorBuilder: unknownRouteFallback,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Text('首页桩')),
        ),
      ],
    );
    await tester.pumpWidget(
        MaterialApp.router(routerConfig: router));
    await tester.pump();
    return router;
  }

  testWidgets('① 未知 location 不落错误页：回首页 + 可读提示', (tester) async {
    final router = await pumpRouter(tester);
    router.go(
        '/content://com.android.providers.downloads.documents/document/999');
    // 一帧建 fallback（initState 只登记 postFrame），再推一帧让 postFrame
    // 真正执行 toast+go('/')；禁 pumpAndSettle 前先看住错误文案没进树。
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('no routes for location'), findsNothing,
        reason: 'GoException 工程错误页文案不得出现在界面上');
    expect(find.textContaining('GoException'), findsNothing);
    expect(await pollText(tester, '页面不存在，已回到首页'), isTrue,
        reason: '兜底提示没弹出 = fallback 没跑到');
    await tester.pump(const Duration(milliseconds: 400));
    // 转场未收时新旧两个 '/' 页会同时在树里：推平再断言只剩一枚。
    await settleFrames(tester);
    expect(find.text('首页桩'), findsOneWidget,
        reason: '没落回已注册首页');
    expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation, '/');
    await clearToasts(tester);
  });

  test('② 生产路由挂着 errorBuilder 兜底（防接线被摘）', () {
    final s = File('lib/core/router/app_router.dart').readAsStringSync();
    expect(s, contains('errorBuilder: unknownRouteFallback'),
        reason: 'GoRouter 摘掉兜底 = 未知路由又把工程异常甩给用户');
  });

  test('③ 清单钉住 deeplink 路由总开关关闭（冷/热启动同一闸）', () {
    final s = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(s, contains('flutter_deeplinking_enabled'));
    expect(s, contains('android:value="false"'),
        reason: '开关缺失/置真 = intent data 又会当初始路由灌进 go_router');
  });
}
