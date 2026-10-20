/// L2 日志批验收钉桩（docs/日志覆盖工单-20260929.md §三·L2）：
/// core/notifications、core/ai、core/media 的降级链与失败路径必须落日志，
/// 且**来源归类**正确（日志页按「通知 / AI / 图片」筛得出来）。
/// 口径同 L1：只加日志零行为改动，本文件只钉「有没有留痕」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_config.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_service.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/media/media_usage_scanner.dart';
import 'package:lifeharness/core/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AiPromptPack packFromAssets() =>
    AiPromptPack.decode(File('assets/ai_prompts/prompts.json').readAsStringSync());

/// UTF-8 安全的响应构造（http.Response(String) 走 Latin1，含中文会抛）。
http.Response jresp(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(body is String ? body : jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

bool logged(String contains, {String? level}) => AppLog.lines.any((l) =>
    l.text.contains(contains) && (level == null || l.level.name == level));

/// 含关键字的行必须全部归到同一来源（日志页筛选口径＝产品定位问题的入口）。
void srcOf(String contains, String want) {
  for (final l in AppLog.lines.where((l) => l.text.contains(contains))) {
    expect(l.src, want, reason: '${l.text} 归到了 ${l.src}，应为 $want');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();
  final pack = packFromAssets();

  setUp(AppLog.reset);
  tearDown(AppLog.reset);

  group('通知（core/notifications）', () {
    test('无平台通道环境：降级链留痕且来源＝通知', () async {
      await NotificationService.init();
      expect(NotificationService.ready, isFalse,
          reason: '测试环境没有通知插件实现，必须判为未就绪');
      expect(
          logged('通知初始化', level: 'error') ||
              logged('通知初始化', level: 'warn'),
          isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      // 时区取不到时另有 warn（两条都可能命中，来源归类一并核对）。
      srcOf('通知', '通知');
    });

    test('未就绪时排程为 no-op，不产生排程成功日志', () async {
      NotificationService.ready = false;
      await NotificationService.scheduleTodo(
          id: 1, title: '测试待办', remindAt: DateTime.now().add(const Duration(days: 1)));
      await NotificationService.syncDaily(
          inboxClean: true, diaryReview: true, diaryTime: '21:00');
      expect(logged('已排程'), isFalse,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
    });
  });

  group('AI（core/ai）', () {
    Future<AiService> svc({
      Map<String, Object> prefsValues = const {},
      String? apiKey,
      required Future<http.Response> Function(http.Request) handler,
    }) async {
      SharedPreferences.setMockInitialValues(prefsValues);
      return AiService(
        configRepo: AiConfigRepository(await SharedPreferences.getInstance()),
        keyVault: AiKeyVault.inMemory(apiKey: apiKey),
        client: AiClient(client: MockClient(handler)),
        pack: pack,
      );
    }

    const okPrefs = <String, Object>{
      'ai.master': true,
      'ai.caps': '{"todo.quadrant":true}',
    };

    test('三重门控拒绝 → warn 留痕（零请求也要看得见）', () async {
      final s = await svc(
        apiKey: 'k',
        handler: (_) async => jresp({'error': '不该被调用'}),
      );
      await expectLater(
          s.request('todo.quadrant', {'title': 'x'}), throwsA(isA<AiDenied>()));
      expect(logged('零请求被拒', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('AI', 'AI');
    });

    test('端点 5xx → error 留痕并带归因', () async {
      final s = await svc(
        prefsValues: okPrefs,
        apiKey: 'k',
        handler: (_) async => http.Response('{"detail":"boom"}', 500),
      );
      await expectLater(
          s.request('todo.quadrant', {'title': '写周报'}),
          throwsA(isA<AiException>()));
      expect(logged('AI 调用失败', level: 'error'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect(logged('server'), isTrue, reason: '归因需带失败类型');
      srcOf('AI 调用失败', 'AI');
    });

    test('应答不合约定 → warn 留痕（结构问题不是网络问题）', () async {
      final s = await svc(
        prefsValues: okPrefs,
        apiKey: 'k',
        handler: (_) async => jresp({
          'choices': [
            {
              'message': {'content': '这里没有 JSON'},
              'finish_reason': 'stop'
            }
          ],
          'usage': {'prompt_tokens': 3, 'completion_tokens': 2},
        }),
      );
      await expectLater(
          s.request('todo.quadrant', {'title': '写周报'}),
          throwsA(isA<AiBadOutput>()));
      expect(logged('输出不合约定', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
    });

    test('端点验证失败 → error 留痕', () async {
      final s = await svc(
        handler: (_) async => http.Response('nope', 401),
      );
      await expectLater(
          s.verifyEndpoint(
              baseUrl: 'https://x.example/v1',
              model: 'm',
              apiKey: 'k',
              prompt: 'ping'),
          throwsA(isA<AiException>()));
      expect(logged('端点验证失败', level: 'error'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
    });

    test('服务商列表脏数据 → warn 并回落预置', () async {
      SharedPreferences.setMockInitialValues({'ai.providers': '{坏 JSON'});
      final repo =
          AiConfigRepository(await SharedPreferences.getInstance());
      final cfg = repo.load();
      expect(cfg.providers, isNotEmpty, reason: '脏数据应回落预置端点而不是清空能力');
      expect(logged('服务商列表解码失败', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
    });
  });

  group('图片（core/media）', () {
    late Directory tmp;
    late Directory outsideDir;
    late String root;
    late Database db;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('lh_l2media_');
      outsideDir = Directory.systemTemp.createTempSync('lh_l2outside_');
      root = tmp.path;
      Directory('$root${Platform.pathSeparator}note_images')
          .createSync(recursive: true);
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    });
    tearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      if (outsideDir.existsSync()) outsideDir.deleteSync(recursive: true);
    });

    test('引用列读不到 → warn（孤儿判定会偏多，不能静默）', () async {
      final sc = MediaUsageScanner(db: db, mediaDirs: [root]);
      await sc.referenceText();
      expect(logged('媒体引用列读取失败', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('媒体引用列读取失败', '图片');
    });

    test('扫描汇总落 key 行；越界删除被拒并留痕', () async {
      File('$root${Platform.pathSeparator}note_images${Platform.pathSeparator}orphan.jpg')
          .writeAsBytesSync(List.filled(2048, 7));
      final sc = MediaUsageScanner(db: db, mediaDirs: ['$root${Platform.pathSeparator}note_images']);
      final r = await sc.scan();
      expect(r.orphans.length, 1);
      expect(logged('媒体扫描：'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      // 越界路径：护栏拒绝删除，且必须留一行可查证据。
      final outside = File('${outsideDir.path}${Platform.pathSeparator}outside.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      expect(sc.deleteOrphans([outside.path]), 0);
      expect(outside.existsSync(), isTrue, reason: '越界路径绝不能被删');
      expect(logged('媒体清理越界拒绝', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect(logged('媒体清理完成'), isTrue);
      srcOf('媒体清理', '图片');
      expect(AppLog.lines.any((l) => l.key && l.text.startsWith('媒体扫描：')),
          isTrue,
          reason: '汇总行按关键路径落盘（warn/key 即时刷）');
    });
  });
}
