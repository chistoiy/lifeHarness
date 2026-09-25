import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
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
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/journal/data/diary_template_dao.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/diary_edit_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// AI批4-B · 日记编辑页「AI 生成反思草稿」接线（journal.reflect）。
/// MockClient 零真实网络；页/库装配抄 test/journal_test.dart。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  const draftText =
      '回顾这一天，评审会前把结论前置的讲法很顺，值得延续；明早补一条待办跟进纪要里的存疑项。';

  late Database db;
  late JournalRepository jrepo;
  late TodoRepository trepo;
  late EventBus bus;
  late int requests;

  Future<void> pumpDiary(WidgetTester tester, {
    required Map<String, Object> prefsMap,
    Future<http.Response> Function(http.Request)? handler,
  }) async {
    SharedPreferences.setMockInitialValues(prefsMap);
    final prefs = await SharedPreferences.getInstance();
    requests = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        journalRepositoryProvider.overrideWithValue(jrepo),
        todoRepositoryProvider.overrideWithValue(trepo),
        diaryTemplateDaoProvider.overrideWithValue(DiaryTemplateDao(db)),
        eventRepositoryProvider
            .overrideWithValue(EventRepository(EventDao(db), bus)),
        readRepositoryProvider.overrideWithValue(ReadRepository(db)),
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiPromptPackProvider.overrideWithValue(pack),
        aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory(apiKey: 'sk-t')),
        aiClientProvider.overrideWithValue(AiClient(
          client: MockClient(handler ??
              (req) async {
                requests++;
                return aiReply(draftText);
              }),
        )),
      ],
      child: MaterialApp(home: DiaryEditPage(key: UniqueKey(), day: DateTime.now())),
    ));
    await settle5(tester);
  }

  Future<bool> pollContains(WidgetTester tester, String text) async {
    for (var i = 0; i < 20; i++) {
      if (find.textContaining(text).evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 80));
    }
    return find.textContaining(text).evaluate().isNotEmpty;
  }

  /// 展开「今日概览草稿」卡并点「AI 生成反思草稿」。
  Future<void> openReflectFlow(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('diary-sum-head')));
    await tester.pumpAndSettle();
    final btn = find.byKey(const ValueKey('diary-ai-reflect'));
    await tester.ensureVisible(btn);
    await tester.pump();
    await tester.tap(btn);
    await tester.pumpAndSettle();
  }

  Future<void> tapSend(WidgetTester tester) async {
    final send = find.byKey(const ValueKey('ai-review-send'));
    await tester.ensureVisible(send);
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
  }

  QuillEditor richCtl(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byKey(const ValueKey('diary-rich-editor')));

  final capsOn = <String, Object>{
    'ai.master': true,
    'ai.caps': '{"journal.reflect":true}',
  };
  final capsOff = <String, Object>{
    'ai.master': true,
    'ai.caps': '{"journal.reflect":false}',
  };

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    jrepo = JournalRepository(JournalDao(db));
    trepo = TodoRepository(TodoDao(db), bus);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('日记编辑页 AI 反思草稿（journal.reflect 接线）', () {
    testWidgets('内容为空：toast 提示先写内容，零请求不发起', (tester) async {
      await useSurface(tester);
      await pumpDiary(tester, prefsMap: capsOn);

      await openReflectFlow(tester);
      expect(find.byKey(const ValueKey('ai-review-send')), findsNothing);
      expect(await pollContains(tester, '先写下今天的所见所感'), isTrue);
      expect(requests, 0);
    });

    testWidgets('能力关：点钮即拦截——不进审阅、MockClient 计数 0 + 未授权 toast',
        (tester) async {
      await useSurface(tester);
      await pumpDiary(tester, prefsMap: capsOff);
      richCtl(tester).controller.replaceText(
          0, 0, '今天定下了排期评审的讲法', const TextSelection.collapsed(offset: 12));
      await tester.pump();
      await settle5(tester); // 让防抖自动存先落库

      await openReflectFlow(tester);
      expect(await pollContains(tester, '该能力未授权'), isTrue);
      expect(find.textContaining('发送给 AI'), findsNothing);
      expect(requests, 0);
    });

    testWidgets('能力开：审阅弹层→允许发送→写入确认→草稿进正文并标注可编辑',
        (tester) async {
      await useSurface(tester);
      await pumpDiary(tester, prefsMap: capsOn);
      richCtl(tester).controller.replaceText(
          0, 0, '今天把评审讲法定成了先结论后过程',
          const TextSelection.collapsed(offset: 16));
      await tester.pump();
      await settle5(tester);

      await openReflectFlow(tester);
      expect(find.byKey(const ValueKey('ai-review-send')), findsOneWidget);

      await tapSend(tester);
      await settle5(tester);
      expect(requests, 1);
      // aiConfirmWrite 写库前确认弹层
      expect(find.text('写入反思草稿'), findsOneWidget);
      expect(find.textContaining('AI 生成 · 写入前请确认'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-confirm-ok')));
      await settle5(tester);

      // 草稿进入自由书写正文（编辑区），带「AI 生成 · 可编辑」标注
      final plain = richCtl(tester).controller.document.toPlainText();
      expect(plain, contains('AI 生成 · 可编辑'));
      expect(plain, contains('值得延续'));
      expect(await pollContains(tester, 'AI 反思草稿已写入'), isTrue);
    });
  });
}

/// OpenAI 兼容 200 响应（content=模型回复原文·text 能力点直接回文本）。
http.Response aiReply(String content) => http.Response.bytes(
    utf8.encode(jsonEncode({
      'choices': [
        {
          'message': {'content': content}
        }
      ],
      'usage': {'prompt_tokens': 10, 'completion_tokens': 40}
    })),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});
