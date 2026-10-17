import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_page.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// AI批4-A · 待办 AI 判象限接线（todo_edit_sheet × core/ai 通用通道）。
/// 装配抄 todo_page_test（TodoPage + FAB → 普通待办 打开新建弹层），
/// AI 侧走 MockClient 注入，零真实网络。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  late Database db;
  late TodoRepository repo;
  late EventBus bus;
  late int sent;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    repo = TodoRepository(TodoDao(db), bus);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  /// 装配 prefs/AI providers 并打开「新建待办」弹层。
  Future<void> openAddSheet(
    WidgetTester tester, {
    required Map<String, Object> prefsInit,
    String? apiKey,
    Future<http.Response> Function(http.Request)? handler,
  }) async {
    sent = 0;
    SharedPreferences.setMockInitialValues(prefsInit);
    final prefs = await SharedPreferences.getInstance();
    final client = AiClient(
      client: MockClient(handler ?? (req) async {
        sent++;
        // 钉住能力调用走 OpenAI 兼容端点 + Bearer Key。
        expect(req.url.path, endsWith('/chat/completions'));
        expect(req.headers['Authorization'], 'Bearer sk-t');
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"quadrant":1,"reason":"截止今晚"}'}
                }
              ],
              'usage': {'prompt_tokens': 9, 'completion_tokens': 8}
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(overrides: [
        todoRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiPromptPackProvider.overrideWithValue(pack),
        aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory(apiKey: apiKey)),
        aiClientProvider.overrideWithValue(client),
      ]),
      child: const MaterialApp(home: TodoPage()),
    ));
    await settle5(tester);
    await tester.tap(find.byIcon(Icons.add).last); // FAB → 类型二选一
    await settle5(tester);
    await tester.tap(find.text('普通待办'));
    await settle5(tester);
    expect(find.text('新建待办'), findsOneWidget);
  }

  Future<void> tapAiBtn(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('ai-quadrant-btn')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-quadrant-btn')));
    await tester.pump();
  }

  /// 审阅弹层按钮位于滚轮层底部：入场动画收敛后拖内部 ListView 滚出再点。
  Future<void> tapReviewBtn(WidgetTester tester, Finder btn) async {
    await settle5(tester);
    await tester.dragUntilVisible(
      btn,
      find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(ListView)),
      const Offset(0, -240),
      maxIteration: 15,
    );
    await tester.tap(btn);
    await tester.pump();
  }

  testWidgets('标题为空：只提示填标题，不进入审阅、零请求', (tester) async {
    await useSurface(tester);
    await openAddSheet(tester, prefsInit: {
      'ai.master': true,
      'ai.caps': '{"todo.quadrant":true}',
    }, apiKey: 'sk-t');

    await tapAiBtn(tester);
    expect(await pollText(tester, 'AI 判象限：请先输入任务标题'), isTrue);
    expect(find.text('发送给 AI · AI 判象限'), findsNothing);
    expect(sent, 0);
  });

  testWidgets('能力未授权（prefs 无 ai.caps）：入口即刻拦截——不进审阅、零请求',
      (tester) async {
    await useSurface(tester);
    await openAddSheet(tester, prefsInit: {'ai.master': true}, apiKey: 'sk-t');
    await tester.enterText(find.byType(TextField).first, '今晚交报告');
    await tapAiBtn(tester);
    // 门控前移到入口：未授权不弹审阅层，直接 toast 归因。
    expect(
        await pollText(tester,
            'AI 未启用：该能力未授权（AI 判象限）：请在 AI 增强页的能力矩阵中开启'),
        isTrue);
    expect(find.text('发送给 AI · AI 判象限'), findsNothing);
    expect(sent, 0);
    await clearToasts(tester);
  });

  testWidgets('授权后：审阅弹层含标题注入 → 允许发送 → 象限选中 Q1 + toast，保存落库',
      (tester) async {
    await useSurface(tester);
    await openAddSheet(tester, prefsInit: {
      'ai.master': true,
      'ai.caps': '{"todo.quadrant":true}',
    }, apiKey: 'sk-t');
    await tester.enterText(find.byType(TextField).first, '今晚交报告');
    await tapAiBtn(tester);

    expect(find.text('发送给 AI · AI 判象限'), findsOneWidget);
    // V1.53.4③：审阅内容默认折叠——点开 User 段才渲染正文（复用既有滚动点按助手）。
    await tapReviewBtn(tester, find.byKey(const ValueKey('ai-review-usr')));
    // user 模板注入标题（SelectableText → RichText，findRichText 才可见）。
    expect(
        find.textContaining('待办标题：今晚交报告', findRichText: true),
        findsOneWidget);

    await tapReviewBtn(tester, find.byKey(const ValueKey('ai-review-send')));
    expect(await pollText(tester, 'AI 判定：Q1 · 截止今晚（保存后生效）'), isTrue);
    expect(sent, 1);

    // 象限选中态：两问卡全部点亮为「是 ✓」+ 落点预览 Q1。
    expect(find.text('是 ✓'), findsNWidgets(2));
    expect(find.text('保存后进入「重要且紧急」象限'), findsOneWidget);
    // 尚未保存（「保存后生效」）。
    expect(await repo.list(), isEmpty);

    await clearToasts(tester);
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await settle5(tester);
    final saved = await repo.list();
    expect(saved.single.quadrant, Quadrant.q1);
  });

  testWidgets('审阅弹层点取消：零请求，弹层关闭，象限不变', (tester) async {
    await useSurface(tester);
    await openAddSheet(tester, prefsInit: {
      'ai.master': true,
      'ai.caps': '{"todo.quadrant":true}',
    }, apiKey: 'sk-t');
    await tester.enterText(find.byType(TextField).first, '今晚交报告');
    await tapAiBtn(tester);
    expect(find.text('发送给 AI · AI 判象限'), findsOneWidget);

    await tapReviewBtn(tester, find.descendant(
        of: find.byType(DraggableScrollableSheet), matching: find.text('取消')));
    await settle5(tester);
    expect(sent, 0);
    expect(find.text('发送给 AI · AI 判象限'), findsNothing);
    expect(find.text('是 ✓'), findsNothing); // 两问仍未答
  });
}
