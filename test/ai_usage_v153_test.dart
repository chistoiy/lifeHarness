import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_call_store.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_config.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_service.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/ai_usage_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// V1.53 · AI 使用记录（表 `ai_calls`，DB v26）。
/// A 组＝存储层筛选/删除/保留/占用；B 组＝落库下沉到 AiService 的各出口；
/// C 组＝全屏页交互（三胶囊弹选项 · 行内展开 · 复制 · 两段式删除 · 记录设置）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  late Database db;
  late AiCallStore store;
  late SharedPreferences prefs;

  Future<SharedPreferences> mockPrefs([Map<String, Object> v = const {}]) async {
    SharedPreferences.setMockInitialValues(v);
    return SharedPreferences.getInstance();
  }

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    store = AiCallStore(db);
    prefs = await mockPrefs();
  });
  tearDown(() async => db.close());

  AiCallRecord rec({
    int? id,
    required int ts,
    String taskId = 'todo.quadrant',
    String module = '待办',
    String name = 'AI 判象限',
    String status = AiCallStore.statusOk,
    int inTok = 10,
    int outTok = 5,
    int ms = 800,
    String sys = '你是象限判定助手',
    String usr = '今晚交周报',
    String out = '{"quadrant":1}',
    String err = '',
  }) =>
      AiCallRecord(
        id: id,
        ts: ts,
        taskId: taskId,
        module: module,
        name: name,
        status: status,
        inTok: inTok,
        outTok: outTok,
        ms: ms,
        sys: sys,
        usr: usr,
        out: out,
        err: err,
      );

  final now = DateTime.now();
  int dayAgo(int d) => now.subtract(Duration(days: d, minutes: 5)).millisecondsSinceEpoch;

  group('A · AiCallStore 查询与维护', () {
    test('AI 使用记录表在 v26 建库与迁移里都存在', () async {
      final t = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='ai_calls'");
      expect(t, hasLength(1));
      expect(DbSchema.version, 26);
      expect(DbSchema.migrations.containsKey(25), isTrue,
          reason: '老库升级必须带 ai_calls 迁移步');
    });

    test('筛选：时间/状态/模块/关键词四条件与倒序', () async {
      await store.insert(rec(ts: dayAgo(0), usr: '今晚交周报'));
      await store.insert(rec(ts: dayAgo(1), module: '日记', name: '复盘生成', usr: '今天很累'));
      await store.insert(rec(ts: dayAgo(9), status: AiCallStore.statusFail, err: '限流'));
      await store.insert(rec(ts: dayAgo(40), module: '阅读', name: '目录补全', taskId: 'read.toc'));

      expect((await store.query(const AiCallFilter())).length, 4);
      expect((await store.query(const AiCallFilter(sinceDays: 0))).length, 1);
      expect((await store.query(const AiCallFilter(sinceDays: 7))).length, 2);
      expect(
          (await store.query(const AiCallFilter(status: AiCallStore.statusFail)))
              .single
              .err,
          '限流');
      expect(
          (await store.query(const AiCallFilter(module: '阅读'))).single.taskId,
          'read.toc');
      final kw = await store.query(const AiCallFilter(keyword: '很累'));
      expect(kw.single.module, '日记');
      // 关键词跨正文与原因：四条的种子 sys 都是「你是象限判定助手」，故全命中。
      expect((await store.query(const AiCallFilter(keyword: '象限判定助手'))).length,
          4);
      // 倒序：最新在前。
      final all = await store.query(const AiCallFilter());
      expect(all.first.usr, '今晚交周报');
      expect(all.last.module, '阅读');
    });

    test('统计与模块候选集（胶囊里的「模块 条数」）', () async {
      await store.insert(rec(ts: dayAgo(0)));
      await store.insert(rec(ts: dayAgo(1), status: AiCallStore.statusCancel));
      await store.insert(rec(ts: dayAgo(2), module: '日记', name: '复盘生成'));
      await store.insert(rec(ts: dayAgo(30), module: '阅读', name: '目录补全', taskId: 'read.toc'));
      final sum = await store.sumOf(const AiCallFilter());
      expect(sum.n, 4);
      expect(sum.tokens, 4 * 15);
      expect(sum.bad, 1, reason: '取消计入未成功；拒绝/成功不计');
      final mods = await store.moduleCounts(7);
      // 近 7 天：待办 2 条（今天 + 昨天）、日记 1 条；30 天前的阅读那条不在窗口内。
      expect(mods.map((m) => m.$1).toSet(), {'待办', '日记'});
      expect(mods.firstWhere((m) => m.$1 == '待办').$2, 2);
      expect(mods.firstWhere((m) => m.$1 == '日记').$2, 1);
    });

    test('删除：本条 / 按筛选（与查询同一 where）/ 清空', () async {
      final a = await store.insert(rec(ts: dayAgo(0), usr: 'A'));
      final b = await store.insert(rec(ts: dayAgo(1), usr: 'B', module: '日记'));
      await store.deleteOne(a);
      expect((await store.query(const AiCallFilter())).single.usr, 'B');
      await store.insert(rec(ts: dayAgo(0), usr: 'C'));
      expect(await store.deleteFiltered(const AiCallFilter(sinceDays: 0)), 1);
      expect((await store.query(const AiCallFilter())).length, 1);
      expect(await store.clearAll(), 1);
      expect(b, isNonZero);
    });

    test('清除正文保留用量；保留天数按超期整批丢弃；占用字节可读', () async {
      await store.insert(rec(ts: dayAgo(0)));
      await store.insert(rec(ts: dayAgo(45)));
      expect(await store.bodyBytes(), greaterThan(0));
      expect(await store.clearBodies(), 2);
      final left = await store.query(const AiCallFilter());
      expect(left.every((r) => r.hasBody), isFalse);
      expect(left.first.inTok, 10, reason: '用量列不受清正文影响');
      expect(await store.prune(30), 1);
      expect((await store.query(const AiCallFilter())).length, 1);
      expect(await store.prune(0), 0, reason: '不限＝不裁剪');
    });
  });

  group('B · 落库下沉到 AiService 出口', () {
    const gated = <String, Object>{
      'ai.master': true,
      'ai.caps': '{"todo.quadrant":true}',
    };

    Future<AiService> svc({
      Map<String, Object> values = gated,
      String? apiKey,
      required Future<http.Response> Function(http.Request) handler,
      bool useStore = true,
    }) async {
      prefs = await mockPrefs(values);
      return AiService(
        configRepo: AiConfigRepository(prefs),
        keyVault: AiKeyVault.inMemory(apiKey: apiKey ?? 'sk-t'),
        client: AiClient(client: MockClient(handler)),
        pack: pack,
        calls: useStore ? store : null,
      );
    }

    http.Response ok(String content) => http.Response.bytes(
        utf8.encode(jsonEncode({
          'choices': [
            {
              'message': {'content': content}
            }
          ],
          'usage': {'prompt_tokens': 11, 'completion_tokens': 7}
        }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'});

    test('成功调用落一行：能力点·状态·token·耗时·三段正文', () async {
      final s = await svc(handler: (_) async => ok('{"quadrant":1,"reason":"今晚"}'));
      await s.request('todo.quadrant', {'title': '今晚交周报'});
      final row = (await store.query(const AiCallFilter())).single;
      expect(row.status, AiCallStore.statusOk);
      expect(row.taskId, 'todo.quadrant');
      expect(row.module, '待办', reason: 'module 取提示词包，新增能力零改表');
      expect(row.inTok, 11);
      expect(row.outTok, 7);
      expect(row.usr, contains('今晚交周报'));
      expect(row.out, contains('quadrant'));
      expect(row.cut, isFalse);
    });

    test('端点失败也落一行：原因可读且发送内容仍在', () async {
      final s = await svc(handler: (_) async => http.Response('{"e":1}', 429));
      await expectLater(
          s.request('todo.quadrant', {'title': 't'}), throwsA(isA<AiException>()));
      final row = (await store.query(const AiCallFilter())).single;
      expect(row.status, AiCallStore.statusFail);
      expect(row.err, contains('限流'));
      expect(row.usr, isNotEmpty);
      expect(row.inTok, 0, reason: '没拿到应答就没有 usage，不编造');
    });

    test('输出不合约定＝失败行并带原因', () async {
      final s = await svc(handler: (_) async => ok('这不是 JSON'));
      await expectLater(
          s.request('todo.quadrant', {'title': 't'}), throwsA(isA<AiBadOutput>()));
      final row = (await store.query(const AiCallFilter())).single;
      expect(row.status, AiCallStore.statusFail);
      expect(row.err, isNotEmpty);
      expect(row.out, '这不是 JSON', reason: '原始回复仍要能回看');
    });

    test('门控拒绝记 denied 且零请求（request 与入口 pre-check 各一条不重复）',
        () async {
      var sent = 0;
      final s = await svc(
          values: {'ai.master': true, 'ai.caps': '{}'},
          handler: (_) async {
            sent++;
            return ok('{"quadrant":1,"reason":"r"}');
          });
      await expectLater(
          s.request('todo.quadrant', {'title': 't'}), throwsA(isA<AiDenied>()));
      expect(sent, 0);
      final denied = (await store.query(const AiCallFilter())).single;
      expect(denied.status, AiCallStore.statusDenied);
      expect(denied.err, contains('该能力未授权'));
      expect(denied.usr, isEmpty, reason: '没发出去就没有发送内容');

      await s.recordDenied('todo.quadrant', '入口预检拒绝');
      final rows = await store.query(const AiCallFilter());
      expect(rows.length, 2, reason: '入口预检与 request 各自记账，互不重复');
    });

    test('用户取消：应答迟到记 cancel 而不是成功', () async {
      final token = AiCancelToken();
      final s = await svc(handler: (_) async {
        token.cancelled = true; // 模拟应答回来前用户已点取消
        return ok('{"quadrant":2,"reason":"r"}');
      });
      await s.request('todo.quadrant', {'title': 't'}, cancel: token);
      final row = (await store.query(const AiCallFilter())).single;
      expect(row.status, AiCallStore.statusCancel);
      expect(row.outTok, 7, reason: 'token 已消耗，用量照记');
    });

    test('停记正文：只落用量，原因仍保留', () async {
      final s = await svc(
          values: {...gated, 'ai.record_body': false},
          handler: (_) async => http.Response('{"e":1}', 401));
      await expectLater(
          s.request('todo.quadrant', {'title': 't'}), throwsA(isA<AiException>()));
      final row = (await store.query(const AiCallFilter())).single;
      expect(row.usr, isEmpty);
      expect(row.sys, isEmpty);
      expect(row.status, AiCallStore.statusFail);
      expect(row.err, contains('Key 无效'), reason: '失败原因不属于「正文」，停记也要能查');
    });

    test('正文超 8000 字截断并标 cut', () async {
      final long = 'x' * 9000;
      final s = await svc(
          values: {
            ...gated,
            'ai.prompt.todo.quadrant': jsonEncode({'user': '{{title}}'}),
          },
          handler: (_) async => ok('{"quadrant":1,"reason":"r"}'));
      await s.request('todo.quadrant', {'title': long});
      final row = (await store.query(const AiCallFilter())).single;
      expect(row.usr.length, AiCallStore.maxBodyChars);
      expect(row.cut, isTrue);
    });

    test('无库环境（store=null）不影响调用结果', () async {
      final s = await svc(useStore: false, handler: (_) async => ok('{"quadrant":1,"reason":"r"}'));
      final r = await s.request('todo.quadrant', {'title': 't'});
      expect(r.requireJson()['quadrant'], 1);
    });

    test('连通性验证也入账（module 取能力点自带模块）', () async {
      final s = await svc(handler: (_) async => ok('连接成功'));
      await s.verifyEndpoint(
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-flash',
          apiKey: 'sk-t',
          prompt: 'ping');
      final row = (await store.query(const AiCallFilter())).single;
      expect(row.taskId, 'tool.verify');
      expect(row.name, 'AI 端点验证');
      expect(row.out, contains('连接成功'));
    });
  });

  group('C · AI 使用记录全屏页', () {
    late ProviderContainer container;

    Future<void> pumpPage(WidgetTester tester,
        {List<AiCallRecord> seed = const [],
        Map<String, Object> initialPrefs = const {}}) async {
      for (final r in seed) {
        await store.insert(r);
      }
      prefs = await mockPrefs(initialPrefs);
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiPromptPackProvider.overrideWithValue(pack),
        aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory()),
        aiCallStoreProvider.overrideWithValue(store),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: const MaterialApp(home: AiUsagePage())));
      await settle5(tester);
    }

    testWidgets('统计行 + 三胶囊 + 默认今日范围', (tester) async {
      await useSurface(tester, const Size(420, 900));
      await pumpPage(tester, seed: [
        rec(ts: dayAgo(0), usr: '今晚交周报'),
        rec(ts: dayAgo(3), module: '日记', name: '复盘生成', usr: '今天很累'),
      ]);
      expect(find.byKey(const ValueKey('ai-usage-sum')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('ai-usage-sum'))).data,
          contains('筛选 1 条'),
          reason: '默认时间范围＝今日，只出今天那条');
      expect(find.byKey(const ValueKey('ai-usage-pill-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-usage-pill-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-usage-pill-module')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-usage-row-none')), findsNothing);
    });

    testWidgets('点时间胶囊横向弹选项 · 选「7 天」列表随之变多', (tester) async {
      await useSurface(tester, const Size(420, 900));
      await pumpPage(tester, seed: [
        rec(ts: dayAgo(0)),
        rec(ts: dayAgo(3), module: '日记', name: '复盘生成'),
      ]);
      await tester.tap(find.byKey(const ValueKey('ai-usage-pill-time')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai-usage-options')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-usage-opt-time-7 天')));
      await settle5(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('ai-usage-sum'))).data,
          contains('筛选 2 条'));
      // 选完自动收起（同时只开一组）。
      expect(find.byKey(const ValueKey('ai-usage-options')), findsNothing);
    });

    testWidgets('关键词跨正文搜索 + 点行展开三段全文', (tester) async {
      await useSurface(tester, const Size(420, 900));
      await pumpPage(tester, seed: [
        rec(ts: dayAgo(0), usr: '今晚交周报', out: '{"quadrant":1}'),
        rec(ts: dayAgo(0), module: '日记', name: '复盘生成', usr: '今天很累'),
      ]);
      await tester.tap(find.byKey(const ValueKey('ai-usage-pill-time')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ai-usage-opt-time-全部')));
      await settle5(tester);
      await tester.enterText(find.byKey(const ValueKey('ai-usage-kw')), '很累');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle5(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('ai-usage-sum'))).data,
          contains('筛选 1 条'));

      final id = (await store.query(const AiCallFilter(keyword: '很累'))).single.id;
      await tester.tap(find.byKey(ValueKey('ai-usage-head-$id')));
      await tester.pump();
      expect(find.text('User · 本次输入'), findsOneWidget);
      expect(find.text('输出'), findsOneWidget);
      expect(find.byKey(ValueKey('ai-usage-copy-out-$id')), findsOneWidget);
      expect(find.textContaining('今天很累'), findsWidgets);
    });

    testWidgets('删除筛选结果走二次确认，取消不动数据', (tester) async {
      await useSurface(tester, const Size(420, 900));
      await pumpPage(tester, seed: [rec(ts: dayAgo(0))]);
      await tester.tap(find.byKey(const ValueKey('ai-usage-del-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-usage-confirm-ok')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect((await store.query(const AiCallFilter())).length, 1);

      await tester.tap(find.byKey(const ValueKey('ai-usage-del-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-usage-confirm-ok')));
      await settle5(tester);
      expect((await store.query(const AiCallFilter())), isEmpty);
      expect(find.textContaining('该范围暂无 AI 调用记录'), findsOneWidget);
    });

    testWidgets('记录设置：停记正文写 prefs · 保留天数即刻裁剪', (tester) async {
      await useSurface(tester, const Size(420, 1400));
      await pumpPage(tester, seed: [
        rec(ts: dayAgo(0)),
        rec(ts: dayAgo(40), module: '阅读', name: '目录补全'),
      ]);
      await tester.tap(find.byKey(const ValueKey('ai-usage-cfg')));
      await tester.pumpAndSettle();
      expect(find.text('AI 记录设置'), findsOneWidget);
      expect(find.textContaining('当前占用'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai-cfg-body')));
      await settle5(tester);
      expect(prefs.getBool('ai.record_body'), isFalse);

      await tester.tap(find.byKey(const ValueKey('ai-cfg-keep-7')));
      await settle5(tester);
      expect(prefs.getInt('ai.call_keep_days'), 7);
      // 打开页面时按 30 天保留裁过一条（40 天前那条已被丢弃）。
      expect((await store.query(const AiCallFilter())).length, 1);
      expect(find.byKey(const ValueKey('ai-cfg-clear-all')), findsOneWidget);
    });

    testWidgets('空筛选条件不炸：无记录时给引导空态', (tester) async {
      await useSurface(tester, const Size(420, 900));
      await pumpPage(tester);
      expect(find.textContaining('还没有 AI 调用记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
