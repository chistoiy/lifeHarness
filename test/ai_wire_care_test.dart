import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';
import 'package:lifeharness/features/care/presentation/care_providers.dart';
import 'package:lifeharness/features/care/presentation/cycle_stats_page.dart';

/// AI批4-D · 呵护「AI 周期解读」接线用例（p-cycleStats）。
/// 独立文件防 isolate 污染；MockClient 零真实网络。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  late Database db;
  late CareRepository repo;

  final today = DateTime.now().withoutTimeCare();

  /// 播种一个经期：startBack 天前开始，连 flowLen 天（p1 + p）。
  Future<void> seedRun(int startBack, int flowLen,
      {List<String> syms = const []}) async {
    for (var i = 0; i < flowLen; i++) {
      final d = today.subtract(Duration(days: startBack - i));
      await repo.saveCycleDay(CycleDay(
        day: careDayKey(d),
        state: i == 0 ? 'p1' : 'p',
        flow: '中',
        syms: i == 0 ? syms : const [],
      ));
    }
  }

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = CareRepository(db);
    // 经期起始 88/60/30/2 天前 → 周期长度序列 28、30、28；症状：痛经×2、头痛×1。
    await seedRun(88, 5);
    await seedRun(60, 4, syms: ['痛经']);
    await seedRun(30, 5);
    await seedRun(2, 5, syms: ['痛经', '头痛']);
  });

  tearDown(() => db.close());

  /// 装配页面 + AI 依赖（生产同构 override；handler 计数并回 OpenAI 形态）。
  Future<void> pump(WidgetTester tester,
      {required Map<String, Object> aiPrefs,
      required Future<http.Response> Function(http.Request) handler}) async {
    SharedPreferences.setMockInitialValues(aiPrefs);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      aiPromptPackProvider.overrideWithValue(pack),
      aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory(apiKey: 'sk-t')),
      aiClientProvider.overrideWithValue(AiClient(client: MockClient(handler))),
      careRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CycleStatsPage()),
    ));
    await settle5(tester);
  }

  /// SnackBar/异步浮层轮询：小步 pump（禁 pumpAndSettle），支持子串匹配。
  Future<bool> pollHas(WidgetTester tester, String sub,
      {int times = 25, int ms = 80}) async {
    for (var i = 0; i < times; i++) {
      if (find.textContaining(sub).evaluate().isNotEmpty) return true;
      await tester.pump(Duration(milliseconds: ms));
    }
    return find.textContaining(sub).evaluate().isNotEmpty;
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    final f = find.byKey(key);
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 100));
  }

  http.Response openAi(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {'message': {'content': content}}
        ],
        'usage': {'prompt_tokens': 60, 'completion_tokens': 40}
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'});

  testWidgets('能力关：审阅后允许发送仍被门控拦下——零请求 + 未授权 toast',
      (tester) async {
    await useSurface(tester, const Size(800, 2400));
    var calls = 0;
    await pump(tester, aiPrefs: {
      'ai.master': true, // ai.caps 缺省 = care.cycle_insight 未授权
    }, handler: (_) async {
      calls++;
      return openAi('不应到达这里');
    });
    await tapKey(tester, const ValueKey('ai-cycle-insight'));
    expect(await pollHas(tester, '发送给 AI'), isTrue);
    await tapKey(tester, const ValueKey('ai-review-send'));
    expect(await pollHas(tester, '该能力未授权'), isTrue);
    expect(calls, 0);
    expect(find.textContaining('AI 生成 · 基于聚合统计'), findsNothing);
  });

  testWidgets('能力开：审阅弹层含聚合数字 → 发送 → 结果卡展示 + AI 标注',
      (tester) async {
    await useSurface(tester, const Size(800, 2400));
    var calls = 0;
    String? sentUser;
    await pump(tester, aiPrefs: {
      'ai.master': true,
      'ai.caps': '{"care.cycle_insight":true}',
    }, handler: (req) async {
      calls++;
      final body = jsonDecode(req.body) as Map;
      sentUser = ((body['messages'] as List).last as Map)['content'] as String;
      return openAi('近 4 次经期起始推导周期长度 28 至 30 天，均值约 28.7 天，'
          '波动较小。本摘要不构成医学诊断，如有不适请咨询医生。');
    });
    await tapKey(tester, const ValueKey('ai-cycle-insight'));
    expect(await pollHas(tester, '发送给 AI'), isTrue);
    // 审阅弹层天然展示将要发送的聚合统计（红线取证：仅数字，无日期级记录）。
    expect(find.textContaining('周期长度序列：28、30、28'), findsOneWidget);
    expect(sentUser, isNull);
    await tapKey(tester, const ValueKey('ai-review-send'));
    expect(await pollHas(tester, '不构成医学诊断'), isTrue);
    expect(calls, 1);
    expect(sentUser, contains('连续周期 4 个'));
    expect(sentUser, isNot(contains(careDayKey(today)))); // 原始日记键不出本机
    // 结果卡：头部小字标注 + 正文。
    expect(find.textContaining('AI 生成 · 基于聚合统计 · 不构成医学建议'),
        findsOneWidget);
    expect(find.textContaining('波动较小'), findsOneWidget);
  });

  testWidgets('返回缺免责句：校验失败 toast，无结果卡', (tester) async {
    await useSurface(tester, const Size(800, 2400));
    var calls = 0;
    await pump(tester, aiPrefs: {
      'ai.master': true,
      'ai.caps': '{"care.cycle_insight":true}',
    }, handler: (_) async {
      calls++;
      return openAi('你的周期长度整体平稳，波动处于常见区间之内，请继续记录。');
    });
    await tapKey(tester, const ValueKey('ai-cycle-insight'));
    expect(await pollHas(tester, '发送给 AI'), isTrue);
    await tapKey(tester, const ValueKey('ai-review-send'));
    expect(await pollHas(tester, '缺医疗免责句'), isTrue);
    expect(calls, 1);
    expect(find.textContaining('AI 生成 · 基于聚合统计'), findsNothing);
  });
}
