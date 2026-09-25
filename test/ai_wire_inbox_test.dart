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
import 'package:lifeharness/features/inbox/data/inbox_dao.dart';
import 'package:lifeharness/features/inbox/domain/inbox_item.dart';
import 'package:lifeharness/features/inbox/presentation/inbox_page.dart';
import 'package:lifeharness/features/inbox/presentation/inbox_providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// AI批4-B · 收集箱「AI 一键分流」接线（inbox.triage）。
/// MockClient 零真实网络；页/库装配抄 test/inbox_test.dart。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  late Database db;
  late InboxDao inbox;
  late TodoRepository todoRepo;
  late EventBus bus;
  late int requests;

  Future<void> pumpInbox(WidgetTester tester, {
    required Map<String, Object> prefsMap,
    Future<http.Response> Function(http.Request)? handler,
  }) async {
    SharedPreferences.setMockInitialValues(prefsMap);
    final prefs = await SharedPreferences.getInstance();
    requests = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        inboxDaoProvider.overrideWithValue(inbox),
        todoRepositoryProvider.overrideWithValue(todoRepo),
        journalRepositoryProvider.overrideWithValue(JournalRepository(JournalDao(db))),
        noteDaoProvider.overrideWithValue(NoteDao(db)),
        readRepositoryProvider.overrideWithValue(ReadRepository(db)),
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiPromptPackProvider.overrideWithValue(pack),
        aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory(apiKey: 'sk-t')),
        aiClientProvider.overrideWithValue(AiClient(
          client: MockClient(handler ??
              (req) async {
                requests++;
                return aiReply(jsonEncode({
                  'target': 'todo',
                  'reason': '有明确行动项',
                  'draft': '买牛奶',
                }));
              }),
        )),
      ],
      child: const MaterialApp(home: InboxPage()),
    ));
    await settle5(tester);
  }

  /// 有界轮询等 SnackBar 文案出现（pollText 的 textContaining 版·铁律：不先 pumpAndSettle）。
  Future<bool> pollContains(WidgetTester tester, String text) async {
    for (var i = 0; i < 20; i++) {
      if (find.textContaining(text).evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 80));
    }
    return find.textContaining(text).evaluate().isNotEmpty;
  }

  /// 审阅弹层「允许发送」钮（弹层可滚动，先 ensureVisible）。
  Future<void> tapSend(WidgetTester tester) async {
    final send = find.byKey(const ValueKey('ai-review-send'));
    await tester.ensureVisible(send);
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
  }

  final capsOn = <String, Object>{
    'ai.master': true,
    'ai.caps': '{"inbox.triage":true}',
  };
  final capsOff = <String, Object>{
    'ai.master': true,
    'ai.caps': '{"inbox.triage":false}',
  };

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    inbox = InboxDao(db);
    todoRepo = TodoRepository(TodoDao(db), bus);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('收集箱 AI 一键分流（inbox.triage 接线）', () {
    testWidgets('能力关：点按钮→审阅弹层→允许发送→MockClient 计数 0 + 未授权 toast',
        (tester) async {
      await useSurface(tester);
      await inbox.insert(InboxItem(rawText: '买牛奶', createdAt: DateTime.now()));
      await pumpInbox(tester, prefsMap: capsOff);

      await tester.tap(find.byKey(const ValueKey('ai-triage')));
      await tester.pumpAndSettle();
      expect(find.textContaining('发送给 AI'), findsOneWidget);

      await tapSend(tester);
      expect(await pollContains(tester, '该能力未授权'), isTrue);
      expect(requests, 0);
      // 未授权即中止：条目原样保留
      expect(await inbox.listPending(), hasLength(1));
    });

    testWidgets('能力开：审阅弹层→允许发送→分流结果卡（去向/理由/草稿）→采纳后走既有转待办',
        (tester) async {
      await useSurface(tester);
      await inbox.insert(InboxItem(rawText: '突然想到要去超市买牛奶啦', createdAt: DateTime.now()));
      await pumpInbox(tester, prefsMap: capsOn, handler: (req) async {
        requests++;
        return aiReply(jsonEncode({
          'target': 'todo',
          'reason': '含行动项',
          'draft': '去超市买牛奶',
        }));
      });

      await tester.tap(find.byKey(const ValueKey('ai-triage')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-review-send')), findsOneWidget);

      await tapSend(tester);
      await settle5(tester);
      // 结果卡出现：target + reason + draft
      expect(find.text('AI 分流建议'), findsOneWidget);
      expect(find.text('去向：待办'), findsOneWidget);
      expect(find.textContaining('含行动项'), findsOneWidget);
      expect(find.text('建议正文：去超市买牛奶'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai-triage-adopt')));
      await settle5(tester);

      final todos = await todoRepo.list();
      expect(todos.single.title, '去超市买牛奶'); // 采纳 draft 清洗正文
      expect(todos.single.quadrant, Quadrant.q2);
      expect(todos.single.tag, '收集箱');
      expect(await inbox.listPending(), isEmpty);
      expect(requests, 1);
    });

    testWidgets('审阅弹层点取消：零请求、条目保留、整轮中止', (tester) async {
      await useSurface(tester);
      await inbox.insert(InboxItem(rawText: '写周报模板', createdAt: DateTime.now()));
      await pumpInbox(tester, prefsMap: capsOn);

      await tester.tap(find.byKey(const ValueKey('ai-triage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await settle5(tester);

      expect(requests, 0);
      expect(find.text('AI 分流建议'), findsNothing);
      expect(await inbox.listPending(), hasLength(1));
    });
  });
}

/// OpenAI 兼容 200 响应（content=模型回复原文）。
http.Response aiReply(String content) => http.Response.bytes(
    utf8.encode(jsonEncode({
      'choices': [
        {
          'message': {'content': content}
        }
      ],
      'usage': {'prompt_tokens': 10, 'completion_tokens': 20}
    })),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});
