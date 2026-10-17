import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_review.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart';

import 'helpers.dart';

/// 真机缺陷回归：AI 请求发出后「黑屏卡死」。
/// 根因=「AI 生成中…」弹层 push 在根 Navigator，关闭却用页面所属 ShellRoute
/// 分支 Navigator.pop → 屏障永挂。本测以同款双层 Navigator 拓扑钉死：
/// 请求完成/失败后弹层必关、分支页可继续交互。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 每条用例独立看日志（AppLog 是全局环形缓冲）。
  setUp(AppLog.reset);
  tearDown(AppLog.reset);

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  Future<void> boot(WidgetTester tester,
      {required Future<http.Response> Function(http.Request) handler}) async {
    SharedPreferences.setMockInitialValues({
      'ai.master': true,
      'ai.caps': jsonEncode({'inbox.triage': true}),
      'ai.base_url': 'https://example.test/v1',
      'ai.model': 'm',
    });
    final prefs = await SharedPreferences.getInstance();
    final rootKey = GlobalKey<NavigatorState>(debugLabel: 'testRoot');
    // 同款拓扑：ShellRoute（内建分支 Navigator）+ 壳层 Scaffold 底栏；
    // 入口页挂在分支里 → Navigator.of(pageContext) ≠ 根。
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/inbox',
      routes: [
      ShellRoute(
        builder: (_, _, child) => Scaffold(
          appBar: AppBar(title: const Text('壳')),
          body: child,
          bottomNavigationBar: const SizedBox(
              height: 70, child: ColoredBox(color: Colors.blueGrey)),
        ),
        routes: [
          GoRoute(
              path: '/inbox',
              builder: (_, _) => const _TriageStub()),
        ],
      ),
      ],
    );
    await useSurface(tester, const Size(800, 1600));
    useAiRootNav(tester, rootKey);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiPromptPackProvider.overrideWithValue(pack),
        aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory(apiKey: 'sk-t')),
        aiClientProvider.overrideWithValue(AiClient(client: MockClient(handler))),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapSend(WidgetTester tester) async {
    final f = find.byKey(const ValueKey('ai-review-send'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(f),
        alignment: 0.5, duration: const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pump();
  }

  /// 请求在途的进度弹层里有 CircularProgressIndicator：每帧都排度，
  /// `pumpAndSettle` 永不自愈（表现为「pumpAndSettle timed out」）→ 逐帧小步推进。
  Future<void> drainProgress(WidgetTester tester) async {
    for (var i = 0;
        i < 20 && find.text('AI 生成中…').evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('成功应答：进度弹层必关，回到分支页且底栏未被误弹', (tester) async {
    final done = CompleterDone();
    await boot(tester, handler: (req) async {
      // 端点总要有点延迟：让「AI 生成中…」真的被看到（MockClient 即刻回
      // 会让弹层在同一帧内开合，测不到在途态）。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      done.called = true;
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      jsonEncode({'target': 'todo', 'reason': 'r', 'draft': 'd'})
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await tester.tap(find.byKey(const ValueKey('stub-triage')));
    await settle5(tester); // 审阅弹层
    expect(find.textContaining('发送给 AI'), findsOneWidget);
    await tapSend(tester);

    // 请求在途：进度弹层在场（屏障盖住底栏属预期）。
    expect(find.text('AI 生成中…'), findsOneWidget);
    await drainProgress(tester);

    expect(done.called, isTrue);
    expect(find.text('AI 生成中…'), findsNothing,
        reason: '旧 bug：分支 pop 关不掉根弹层 → 屏障永挂黑屏');
    expect(find.text('结果:todo'), findsOneWidget);
    expect(find.text('壳'), findsOneWidget, reason: '分支页未被误 pop');
    // 成功也要留痕（耗时+token 用量），日志页才有「所有 AI 调用可查」的能力。
    expect(AppLog.lines.last.text, contains('AI 调用成功（inbox.triage）'));
    expect(AppLog.lines.last.text, contains('tokens'));
    // 底栏仍在原位（分支栈没被动过）。
    expect(find.byType(Scaffold), findsWidgets);
    await settleLogTimer(tester);
  });

  testWidgets('失败应答：弹层同样关闭并 toast 归因', (tester) async {
    await boot(tester, handler: (req) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return http.Response('{"error":{"message":"boom"}}', 401);
    });
    await tester.tap(find.byKey(const ValueKey('stub-triage')));
    await settle5(tester);
    await tapSend(tester);
    expect(find.text('AI 生成中…'), findsOneWidget);
    await drainProgress(tester);
    expect(find.text('AI 生成中…'), findsNothing);
    expect(find.textContaining('AI 调用失败'), findsWidgets);
    expect(find.text('结果:null'), findsOneWidget);
    // 真机反馈③：AI 失败必须同时进日志（旧写法只 toast，日志页永远查不到）。
    final errLine = AppLog.lines.last;
    expect(errLine.level, LhLevel.error);
    expect(errLine.text, contains('AI 调用失败（inbox.triage）'));
    expect(errLine.text, contains('unauthorized'),
        reason: '日志侧要带失败归类，比 toast 文案更可诊断');
    await settleLogTimer(tester);
  });

  testWidgets('同一帧即失败（局域网端点/即刻报错）：屏障也不许留', (tester) async {
    // 复现旧 race：showDialog 的 push 同步入栈、builder 要等下一帧；
    // 请求在这一帧内就 return 时 progressCtx 还没赋值 → 旧 pop 静默失效，
    // 黑色屏障永挂（真机表现同样是黑屏）。
    await boot(tester,
        handler: (req) async => http.Response(
            '{"error":{"message":"no model"}}', 404));
    await tester.tap(find.byKey(const ValueKey('stub-triage')));
    await settle5(tester);
    await tapSend(tester);
    await tester.pump(); // 只推进一帧：弹层可能从未 build
    expect(find.text('AI 生成中…'), findsNothing,
        reason: '未建帧分支必须从宿主栈弹顶路由拆屏障');
    expect(await pollText(tester, '结果:null'), isTrue);
    await settleLogTimer(tester);
  });

  testWidgets('等待中点「取消」：屏障立拆、迟到应答不写库', (tester) async {
    // 真机反馈②「点击 ai 生成后无法返回」：旧弹层 barrierDismissible:false +
    // PopScope(canPop:false) 且没有出口，端点慢就是死等。
    final done = CompleterDone();
    await boot(tester, handler: (req) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      done.called = true;
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      jsonEncode({'target': 'todo', 'reason': 'r', 'draft': 'd'})
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await tester.tap(find.byKey(const ValueKey('stub-triage')));
    await settle5(tester);
    await tapSend(tester);
    expect(find.text('AI 生成中…'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-progress-cancel')));
    await tester.pump(); // 取消胜出 → 拆屏障
    expect(find.text('AI 生成中…'), findsNothing,
        reason: '取消必须立刻关掉进度弹层');
    expect(find.text('结果:null'), findsOneWidget,
        reason: '取消回 null，调用方不得写入');

    // 迟到的应答：把 3s 排干，既不写库也不改日志尾部（避免 pending timer 误报）。
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(AppLog.lines.last.text, contains('AI 调用已取消（inbox.triage）'));
    expect(AppLog.lines.last.level, LhLevel.warn);
    expect(find.text('结果:null'), findsOneWidget);
    await settleLogTimer(tester);
  });

  testWidgets('等待中按系统返回：等同取消（不锁死用户）', (tester) async {
    await boot(tester, handler: (req) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await tester.tap(find.byKey(const ValueKey('stub-triage')));
    await settle5(tester);
    await tapSend(tester);
    expect(find.text('AI 生成中…'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    expect(find.text('AI 生成中…'), findsNothing,
        reason: '系统返回也要拆掉屏障，不能把用户困在等待里');
    expect(find.text('结果:null'), findsOneWidget);
    expect(AppLog.lines.last.text, contains('AI 调用已取消（inbox.triage）'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await settleLogTimer(tester);
  });
}

class CompleterDone {
  bool called = false;
}

/// 分支页替身：走与收集箱同一条 aiRunWithReview 通道。
class _TriageStub extends ConsumerStatefulWidget {
  const _TriageStub();

  @override
  ConsumerState<_TriageStub> createState() => _TriageStubState();
}

class _TriageStubState extends ConsumerState<_TriageStub> {
  String? _target;
  bool _ran = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
            key: const ValueKey('stub-triage'),
            onPressed: _ran
                ? null
                : () async {
                    _ran = true;
                    final res = await aiRunWithReview(context, ref,
                        taskId: 'inbox.triage',
                        vars: {'content': '买牛奶'});
                    if (!mounted) return;
                    setState(() => _target = '${res?.json?['target']}');
                    _ran = false;
                  },
            child: const Text('分流'),
          ),
          Text('结果:${_target ?? '未跑'}'),
        ]),
      ),
    );
  }
}
