import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/ai/token_stats.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/ai_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// AI token 用量台账（真机反馈 2026-09-26：「增加一个 token 使用情况查看」）。
/// 引擎口径 + AI 增强页卡片两端都钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  late SharedPreferences prefs;

  Future<void> seedPrefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
  }

  group('AiTokenStats 引擎', () {
    setUp(() => seedPrefs());

    test('record 累加：同日同能力点合并，日/能力点两级键', () async {
      final d = DateTime(2026, 9, 26, 10);
      await AiTokenStats.record(prefs, 'read.toc',
          inTok: 170, outTok: 1200, latencyMs: 5000, at: d);
      await AiTokenStats.record(prefs, 'read.toc',
          inTok: 3, outTok: 7, latencyMs: 100, at: d.add(const Duration(minutes: 5)));
      await AiTokenStats.record(prefs, 'inbox.triage',
          inTok: 10, outTok: 20, latencyMs: 900, at: d);
      final table = AiTokenStats.load(prefs);
      expect(table.keys, ['2026-09-26']);
      final toc = table['2026-09-26']!['read.toc']!;
      expect(toc[AiTokenStats.fIn], 173);
      expect(toc[AiTokenStats.fOut], 1207);
      expect(toc[AiTokenStats.fCalls], 2);
      expect(toc[AiTokenStats.fMs], 5100);
      expect(table['2026-09-26']!['inbox.triage']![AiTokenStats.fCalls], 1);
    });

    test('失败/取消：计次并计失败数，token 不编造', () async {
      await AiTokenStats.record(prefs, 'read.toc', failed: true);
      final cell = AiTokenStats.load(prefs)['2026-09-26']!['read.toc']!;
      expect(cell[AiTokenStats.fCalls], 1);
      expect(cell[AiTokenStats.fFails], 1);
      expect(cell[AiTokenStats.fIn], 0);
      expect(cell[AiTokenStats.fOut], 0);
    });

    test('跨天聚合与总量：aggregate 合日、total 出平均耗时', () async {
      await AiTokenStats.record(prefs, 'read.toc',
          inTok: 100, outTok: 200, latencyMs: 1000, at: DateTime(2026, 9, 25));
      await AiTokenStats.record(prefs, 'read.toc',
          inTok: 50, outTok: 50, latencyMs: 3000, at: DateTime(2026, 9, 26));
      final table = AiTokenStats.load(prefs);
      final agg = AiTokenStats.aggregate(table.values);
      final t = AiTokenStats.total(agg);
      expect(t.inTok, 150);
      expect(t.outTok, 250);
      expect(t.calls, 2);
      expect(t.avgMs, 2000, reason: '总耗时 4000ms / 2 次');
      // 近 7 天窗口只含两日；单日窗口只含当日。
      expect(
          AiTokenStats
              .total(AiTokenStats.aggregate([table['2026-09-26']!, const {}]))
              .outTok,
          50);
    });

    test('超过保留天数：按最旧整日丢弃', () async {
      for (var i = 0; i < AiTokenStats.keepDays + 5; i++) {
        await AiTokenStats.record(prefs, 'read.toc',
            inTok: 1, at: DateTime(2026, 9, 26).subtract(Duration(days: i)));
      }
      final days = AiTokenStats.load(prefs).keys.toList()..sort();
      expect(days.length, AiTokenStats.keepDays);
      expect(days.first, isNot('2026-09-26'), reason: '最新的必须留下');
      expect(days.last, '2026-09-26');
    });

    test('脏数据整键弃用；clear 清空明细', () async {
      await prefs.setString(AiTokenStats.prefsKey, '{坏 JSON');
      expect(AiTokenStats.load(prefs), isEmpty);
      await prefs.setString(
          AiTokenStats.prefsKey, jsonEncode({'2026-09-26': 'x'}));
      expect(AiTokenStats.load(prefs), isEmpty);
      await AiTokenStats.record(prefs, 'read.toc', inTok: 5);
      expect(AiTokenStats.load(prefs), isNotEmpty);
      await AiTokenStats.clear(prefs);
      expect(AiTokenStats.load(prefs), isEmpty);
    });
  });

  group('AI 增强页 · Token 使用卡', () {
    Future<void> boot(WidgetTester tester, Map<String, Object> values) async {
      await seedPrefs(values);
      final router = GoRouter(
        routes: [
          GoRoute(
              path: '/',
              builder: (_, _) => const AiSettingsPage(),
              routes: [
                GoRoute(
                    path: 'settings/ai',
                    builder: (_, _) => const AiSettingsPage()),
              ]),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          aiPromptPackProvider.overrideWithValue(pack),
          aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory(apiKey: 'sk-t')),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await settle5(tester);
      await useSurface(tester, const Size(900, 2600));
      await settle5(tester);
    }

    testWidgets('有用量：三档合计 + 按能力点行（显示能力点中文名）', (tester) async {
      final today = AiTokenStats.dayKey(DateTime.now());
      await boot(tester, {
        AiTokenStats.prefsKey: jsonEncode({
          today: {
            'read.toc': {
              AiTokenStats.fIn: 173,
              AiTokenStats.fOut: 4216,
              AiTokenStats.fCalls: 2,
              AiTokenStats.fFails: 1,
              AiTokenStats.fMs: 20000,
            },
            'inbox.triage': {
              AiTokenStats.fIn: 7,
              AiTokenStats.fOut: 33,
              AiTokenStats.fCalls: 1,
              AiTokenStats.fFails: 0,
              AiTokenStats.fMs: 900,
            },
          },
        }),
      });
      expect(find.text('Token 使用'), findsOneWidget);
      // 今日合计＝入(173+7) + 出(4216+33) ＝ 4429（今日/近7天/累计三档同值）。
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ai-token-今日'))).data,
        '4429',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('ai-token-累计'))).data,
        '4429',
      );
      expect(find.text('阅读 · 目录 AI 补全'), findsOneWidget,
          reason: '行名＝模块前缀 + 能力点名（取提示词包），不裸露 read.toc');
      final tocRow = tester
          .widget<Text>(
              find.byKey(const ValueKey('ai-token-row-read.toc')))
          .data!;
      expect(tocRow, contains('173 / 4216'), reason: '入 / 出');
      expect(tocRow, contains('2 次 · 失败 1'));
      expect(find.textContaining('收集箱'), findsWidgets);
    });

    testWidgets('零调用：空态文案 + 清理钮置灰', (tester) async {
      await boot(tester, const {});
      expect(find.text('还没有发出的调用'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byKey(const ValueKey('ai-token-clear'))).onPressed,
        isNull,
      );
    });

    testWidgets('清理：二次确认后 prefs 明细清空并即时回空态', (tester) async {
      final today = AiTokenStats.dayKey(DateTime.now());
      await boot(tester, {
        AiTokenStats.prefsKey: jsonEncode({
          today: {
            'read.toc': {
              AiTokenStats.fIn: 1,
              AiTokenStats.fOut: 2,
              AiTokenStats.fCalls: 1,
              AiTokenStats.fFails: 0,
              AiTokenStats.fMs: 10,
            },
          },
        }),
      });
      await tester.tap(find.byKey(const ValueKey('ai-token-clear')));
      await settle5(tester);
      expect(find.text('确认清理'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-token-clear-ok')));
      await settle5(tester);
      expect(AiTokenStats.load(prefs), isEmpty);
      expect(find.text('还没有发出的调用'), findsOneWidget);
      await clearToasts(tester);
    });
  });
}
