import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/domain/book_toc.dart';
import 'package:lifeharness/features/read/presentation/book_detail.dart';
import 'package:lifeharness/features/read/presentation/quotes_lib_page.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';

/// AI批4-C · 阅读模块接线（目录 AI 补全 + 摘录感想生成）。
/// 独立文件防 isolate 污染；MockClient 零真实网络。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  late Database db;
  late ReadRepository repo;
  late int calls;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    calls = 0;
  });
  tearDown(() => db.close());

  final now = DateTime.now();
  int ms(int daysAgo) => now.millisecondsSinceEpoch - daysAgo * 86400000;

  Book bk(String id, String t) => Book(
      id: id,
      title: t,
      author: '作者$t',
      state: Book.kStateReading,
      pages: 100,
      readPages: 50,
      lastReadAt: ms(1),
      createdAt: ms(30),
      updatedAt: ms(1));

  /// 端点应答：OpenAI 兼容 choices[0].message.content。
  http.Response openAi(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'content': content}
          }
        ]
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'});

  Future<Widget> shell(Widget home,
      {required bool tocCap,
      required bool insightCap,
      Future<http.Response> Function(http.Request)? handler}) async {
    SharedPreferences.setMockInitialValues({
      'ai.master': true,
      'ai.caps': jsonEncode({
        'read.toc': tocCap,
        'read.quote_insight': insightCap,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
          path: '/read/book/:id',
          builder: (_, s) => BookDetailPage(bookId: s.pathParameters['id']!)),
      GoRoute(
          path: '/read/info/:id',
          builder: (_, s) => const SizedBox.shrink()),
      GoRoute(
          path: '/read/log/:id',
          builder: (_, s) => const SizedBox.shrink()),
    ]);
    return ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiPromptPackProvider.overrideWithValue(pack),
        aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory(apiKey: 'sk-t')),
        aiClientProvider.overrideWithValue(AiClient(
          client: MockClient(handler ??
              (req) async {
                calls++;
                throw StateError('测试未配置应答');
              }),
        )),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// 轮询等 finder 出现（每帧推进假时钟；圈中有进度动画时不可 pumpAndSettle）。
  Future<void> until(WidgetTester tester, Finder f,
      {int times = 40, String reason = ''}) async {
    for (var i = 0; i < times; i++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(f, findsOneWidget, reason: reason);
  }

  Future<void> clearSnacks(WidgetTester tester) => clearToasts(tester);

  /// 审阅弹层（DraggableScrollableSheet）内的「允许发送」钮位于折叠线以下，
  /// tester.ensureVisible/多 Scrollable 均不可靠 → 直接对按钮 element 走
  /// Scrollable.ensureVisible 静态法（沿祖先链滚动）后再点。
  Future<void> tapSend(WidgetTester tester) async {
    final f = find.byKey(const ValueKey('ai-review-send'));
    await tester.pumpAndSettle(); // 等弹层开启动画落位
    await Scrollable.ensureVisible(tester.element(f),
        alignment: 0.5, duration: const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pump();
  }

  group('AI批4-C 目录 AI 补全', () {
    Future<void> seedBookWithToc() async {
      await repo.addBook(bk('a', '原则'));
      final p = ParsedTocPart('旧部');
      p.sections.add('旧节');
      await repo.replaceToc('a', [p]);
    }

    testWidgets('能力关 → 点「AI 补全」→ 审阅后发送被拒 · MockClient 计数 0',
        (tester) async {
      await seedBookWithToc();
      await useSurface(tester);
      await tester.pumpWidget(await shell(
        const BookDetailPage(bookId: 'a'),
        tocCap: false,
        insightCap: true,
      ));
      await settle5(tester);
      await until(tester, find.byKey(const ValueKey('toc-ai')));
      await tester.ensureVisible(find.byKey(const ValueKey('toc-ai')));
      await tester.tap(find.byKey(const ValueKey('toc-ai')));
      // 发送前审阅弹层（原则 4）：能力关也先审、发送时才三重门控拒绝。
      await until(tester, find.text('发送给 AI · 目录 AI 补全'));
      await tapSend(tester);
      await until(
          tester,
          find.textContaining('该能力未授权（目录 AI 补全）'),
          reason: 'AiDenied 归因 toast');
      await clearSnacks(tester);
      expect(calls, 0, reason: '能力关＝零网络请求');
      // 目录未被触碰：仍是导入前的「旧节」。
      final nodes = await repo.tocOf('a');
      expect(nodes.map((n) => n.title), ['旧部', '旧节']);
    });

    testWidgets('能力开 → 合法 chapters → 进既有目录预览＋确认替换路径写入',
        (tester) async {
      await seedBookWithToc();
      await useSurface(tester);
      final chapters = jsonEncode({
        'chapters': [
          {
            'part': '第一部分 原则',
            'title': '1. 我的历程',
            'sections': ['工作原则', '生活原则']
          },
          {'part': null, 'title': '2. 过一种原则的生活', 'sections': null},
        ]
      });
      await tester.pumpWidget(await shell(
        const BookDetailPage(bookId: 'a'),
        tocCap: true,
        insightCap: true,
        handler: (req) async {
          calls++;
          return openAi(chapters);
        },
      ));
      await settle5(tester);
      await until(tester, find.byKey(const ValueKey('toc-ai')));
      await tester.ensureVisible(find.byKey(const ValueKey('toc-ai')));
      await tester.tap(find.byKey(const ValueKey('toc-ai')));
      await until(tester, find.text('发送给 AI · 目录 AI 补全'));
      // 审阅内容含书名/作者渲染（vars 注入 user 模板）。
      expect(
          find.byWidgetPredicate((w) =>
              w is SelectableText && (w.data ?? '').contains('书名：原则')),
          findsOneWidget);
      await tapSend(tester);
      // AI 结果进既有导入弹层（预览＝N 部分/M 节），确认前不落库。
      await until(tester, find.text('AI 目录补全 · 《原则》'),
          reason: '复用导入弹层');
      await tester.pumpAndSettle(); // 等弹层滑入落位（防半程坐标）
      expect(find.text('1 个部分 · 4 节'), findsOneWidget);
      final ctl =
          tester.widget<TextField>(find.byKey(const ValueKey('toe-text'))).controller!;
      expect(ctl.text, contains('1. 我的历程'), reason: '章题回填预览文本可再编辑');
      expect((await repo.tocOf('a')).map((n) => n.title), ['旧部', '旧节'],
          reason: '确认前绝不覆盖目录');
      await tester.ensureVisible(find.byKey(const ValueKey('toe-ok')));
      await tester.tap(find.byKey(const ValueKey('toe-ok'))); // 确认替换
      expect(await pollText(tester, '目录已导入 · 1 部分/4 节'), isTrue);
      await clearSnacks(tester);
      expect(calls, 1);
      final nodes = await repo.tocOf('a');
      expect(nodes.map((n) => n.title),
          ['第一部分 原则', '1. 我的历程', '工作原则', '生活原则', '2. 过一种原则的生活']);
    });

    testWidgets('空目录态钮（toc-empty-ai）同走 AI 补全接线', (tester) async {
      await repo.addBook(bk('e', '空目录书'));
      await useSurface(tester);
      await tester.pumpWidget(await shell(
        const BookDetailPage(bookId: 'e'),
        tocCap: false,
        insightCap: true,
      ));
      await settle5(tester);
      await until(tester, find.byKey(const ValueKey('toc-empty-ai')));
      await tester.ensureVisible(find.byKey(const ValueKey('toc-empty-ai')));
      await tester.tap(find.byKey(const ValueKey('toc-empty-ai')));
      await until(tester, find.text('发送给 AI · 目录 AI 补全'));
      await tapSend(tester);
      await until(tester, find.textContaining('该能力未授权（目录 AI 补全）'));
      await clearSnacks(tester);
      expect(calls, 0);
    });
  });

  group('AI批4-C 摘录感想生成', () {
    testWidgets('未选中只提示不发起；选中→审阅→确认写入 thought 字段与 tags',
        (tester) async {
      await repo.addBook(bk('qa', '书甲'));
      final qid = await repo.addQuote(BookQuote(
        bookId: 'qa',
        kind: BookQuote.kKindMark,
        body: '痛苦 + 反思 = 进步。',
        createdAt: ms(2),
        updatedAt: ms(2),
      ));
      await useSurface(tester);
      final out = jsonEncode({
        'insight': '这段提醒我把每次复盘写下来，进步才可累积。',
        'tags': ['方法论', '复盘']
      });
      await tester.pumpWidget(await shell(
        const QuotesLibPage(),
        tocCap: true,
        insightCap: true,
        handler: (req) async {
          calls++;
          return openAi(out);
        },
      ));
      await settle5(tester);
      await until(tester, find.byKey(ValueKey('ql-q-$qid')));

      // 未选中：只 toast 提示先选，不发起任何调用。
      await tester.ensureVisible(find.byKey(const ValueKey('qlx-ai')));
      await tester.tap(find.byKey(const ValueKey('qlx-ai')));
      expect(await pollText(tester, '先长按选择要生成感想的摘录'), isTrue);
      await clearSnacks(tester);
      expect(calls, 0);

      // 长按选中 → 「AI 感想生成」。
      await tester.ensureVisible(find.byKey(ValueKey('ql-q-$qid')));
      await tester.longPress(find.byKey(ValueKey('ql-q-$qid')));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget,
          reason: '多选选中态可视');
      await tester.ensureVisible(find.byKey(const ValueKey('qlx-ai')));
      await tester.tap(find.byKey(const ValueKey('qlx-ai')));
      await until(tester, find.text('发送给 AI · 摘录感想生成'));
      await tapSend(tester);
      // 结果确认层：写入前展示 AI 原文 + AI 标识。
      await until(tester, find.text('写入摘录感想 · 《书甲》'));
      expect(find.text('AI 生成 · 写入前请确认'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('ai-confirm-ok')));
      await tester.tap(find.byKey(const ValueKey('ai-confirm-ok')));
      expect(await pollText(tester, '已生成 1 条感想'), isTrue);
      await clearSnacks(tester);
      expect(calls, 1);

      final saved = (await repo.allQuotes()).single;
      expect(saved.id, qid);
      expect(saved.thought, '这段提醒我把每次复盘写下来，进步才可累积。');
      expect(saved.tags, containsAll(['方法论', '复盘']));
    });

    testWidgets('已有感想走追加不覆盖；点「放弃」不写库', (tester) async {
      await repo.addBook(bk('qa', '书甲'));
      final qid = await repo.addQuote(BookQuote(
        bookId: 'qa',
        kind: BookQuote.kKindMark,
        body: '你只是 fall to the level of your systems。',
        thought: '我自己的旧想法',
        createdAt: ms(2),
        updatedAt: ms(2),
      ));
      await useSurface(tester);
      await tester.pumpWidget(await shell(
        const QuotesLibPage(),
        tocCap: true,
        insightCap: true,
        handler: (req) async {
          calls++;
          return openAi(jsonEncode({'insight': '系统与目标要分开检视。', 'tags': []}));
        },
      ));
      await settle5(tester);
      await until(tester, find.byKey(ValueKey('ql-q-$qid')));
      await tester.ensureVisible(find.byKey(ValueKey('ql-q-$qid')));
      await tester.longPress(find.byKey(ValueKey('ql-q-$qid')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('qlx-ai')));
      await tester.tap(find.byKey(const ValueKey('qlx-ai')));
      await until(tester, find.text('发送给 AI · 摘录感想生成'));
      await tapSend(tester);
      await until(tester, find.text('写入摘录感想 · 《书甲》'));
      await tester.tap(find.text('放弃')); // 不确认写入
      await settle5(tester);
      final kept = (await repo.allQuotes()).single;
      expect(kept.thought, '我自己的旧想法', reason: '放弃＝原样保留');
      expect(calls, 1);
      await clearSnacks(tester);

      // 再来一次并确认：旧感想保留、AI 感变换行追加。
      await tester.ensureVisible(find.byKey(const ValueKey('qlx-ai')));
      await tester.tap(find.byKey(const ValueKey('qlx-ai')));
      await until(tester, find.text('发送给 AI · 摘录感想生成'));
      await tapSend(tester);
      await until(tester, find.text('写入摘录感想 · 《书甲》'));
      await tester.ensureVisible(find.byKey(const ValueKey('ai-confirm-ok')));
      await tester.tap(find.byKey(const ValueKey('ai-confirm-ok')));
      expect(await pollText(tester, '已生成 1 条感想'), isTrue);
      await clearSnacks(tester);
      final merged = (await repo.allQuotes()).single;
      expect(merged.thought, '我自己的旧想法\n系统与目标要分开检视。');
    });
  });
}
