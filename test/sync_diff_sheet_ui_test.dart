/// Task 18 · S3 差异半屏 + S4 进度半屏 + S2 连接验证 widget 用例
/// （对照原型 index-sync.html s-diff / s-syncprog / s-svc-verify）。
///
/// 纪律：服务层全 fake（同 sync_page_ui_test 注入模式）；本地极简 GoRouter；
/// 下载路径的目录创建仅落系统临时目录（tearDown 清理），网络层零真实请求；
/// 另含 s3_store.dart 携带修复（SK 缺失 fail-fast / apiUrl 不静默回落）的
/// 单元断言。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/sync/credential_vault.dart';
import 'package:lifeharness/core/sync/http_gate.dart';
import 'package:lifeharness/core/sync/remote_store.dart';
import 'package:lifeharness/core/sync/s3_store.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:lifeharness/core/sync/sync_orchestrator.dart';
import 'package:lifeharness/core/sync/sync_providers.dart';
import 'package:lifeharness/features/settings/presentation/sync_history_page.dart';
import 'package:lifeharness/features/settings/presentation/sync_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'sync_page_ui_test.dart'
    show FakeRemoteStore, FakeSnapshotService, fakeBackupService;

/// 四态清单（字节取整数 MB 便于合计断言）：
/// 仅本地 3（log 4MB + sync 快照 8MB + cloud 侧忽略）/ 仅云端 2（3MB + 1MB 残留）
/// / 已修改 1（本机 2MB vs 云端 1MB）/ 一致 2。
void seedInventory(FakeRemoteStore fake, FakeSnapshotService snap) {
  fake.files = [
    FileEntry(relativePath: 'modified.bin', size: 1048576, etag: 'r-mod'),
    FileEntry(relativePath: 'cloud_only.bin', size: 3145728),
    FileEntry(relativePath: 'cloud_stale.bin', size: 1048576),
    FileEntry(relativePath: 'synced_1.bin', size: 100, etag: 'e1'),
    FileEntry(relativePath: 'synced_2.bin', size: 100, etag: 'e2'),
  ];
  snap.inventory = [
    FileEntry(relativePath: 'logs/2026-09-24.log', size: 4194304),
    FileEntry(relativePath: 'sync_20260925_080000.lhbak', size: 8388608),
    FileEntry(relativePath: 'modified.bin', size: 2097152),
    FileEntry(relativePath: 'synced_1.bin', size: 100, etag: 'e1'),
    FileEntry(relativePath: 'synced_2.bin', size: 100, etag: 'e2'),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late CredentialVault vault;
  late FakeRemoteStore fake;
  late FakeSnapshotService snap;
  late SyncOrchestrator orch;
  late Directory tmpDocs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    vault = CredentialVault.inMemory();
    fake = FakeRemoteStore();
    tmpDocs = Directory.systemTemp.createTempSync('lh_t18_docs_');
    snap = FakeSnapshotService(
        backup: fakeBackupService(), prefs: prefs, docsDir: () => tmpDocs.path);
    orch = SyncOrchestrator(
      snapshotService: snap,
      prefs: prefs,
      activeConfig: () => readActiveService(SyncConfigStore(prefs, vault: vault)),
      storeFactory: (c) => fake,
    );
  });

  tearDown(() {
    orch.dispose();
    try {
      tmpDocs.deleteSync(recursive: true);
    } catch (_) {
      // Windows 偶发句柄未放：临时目录残留可忽略。
    }
  });

  void seedServices({String activeId = 'svcW'}) {
    prefs.setString('sync_services', jsonEncode({
      'services': [
        {
          'id': 'svcW',
          'provider': 'webdav',
          'apiUrl': 'https://dav.jianguoyun.com/dav/',
          'account': 'me@example.com',
          'cloudDirName': 'sync',
          'requestIntervalMs': 300,
        },
        {
          'id': 'svcS',
          'provider': 's3',
          'apiUrl': 'https://s3.bitiful.net',
          'account': 'AKIA-TEST',
          'region': 'cn-east-1',
          'bucket': 'photo',
          'cloudDirName': 'sync',
          'requestIntervalMs': 300,
        },
      ],
      'activeId': activeId,
    }));
  }

  void seedLedgerStale() {
    prefs.setString('sync_ledger_svcW|sync',
        '{"cloud_stale.bin":{"etag":"","size":1048576,"ts":1}}');
  }

  Future<void> boot(WidgetTester tester) async {
    final router = GoRouter(initialLocation: '/sync', routes: [
      GoRoute(path: '/sync', builder: (_, _) => const SyncPage()),
      GoRoute(path: '/sync/history', builder: (_, _) => const SyncHistoryPage()),
      GoRoute(
          path: '/log',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('LOG-STUB')))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        credentialVaultProvider.overrideWithValue(vault),
        remoteStoreFactoryProvider.overrideWithValue((c) => fake),
        snapshotServiceProvider.overrideWithValue(snap),
        syncOrchestratorProvider.overrideWithValue(orch),
        backupServiceProvider.overrideWithValue(fakeBackupService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
  }

  Future<void> openDiffSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sync-diff-entry')));
    await settle5(tester);
  }

  /// 弹层内点击：先滚入视口（widget 测试纪律：tap 前 ensureVisible）。
  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle5(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle5(tester);
  }

  group('S3 差异半屏（s-diff）', () {
    testWidgets('四态分组 · 合计行 · 一致组折叠 · staleHint 角标 · 勾选联动',
        (tester) async {
      seedServices();
      seedLedgerStale();
      seedInventory(fake, snap);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openDiffSheet(tester);

      // 四态分组标题。
      expect(find.text('仅本地'), findsOneWidget);
      expect(find.text('仅云端'), findsOneWidget);
      expect(find.text('已修改'), findsOneWidget);
      expect(find.text('一致'), findsOneWidget);

      // 行渲染：仅本地 3 含快照与日志；已修改双侧字节展示；残留角标。
      expect(find.text('logs/2026-09-24.log'), findsOneWidget);
      expect(find.text('sync_20260925_080000.lhbak'), findsOneWidget);
      expect(find.textContaining('两端内容不同 · 本机 2 MB / 云端 1 MB'), findsOneWidget);
      expect(find.textContaining('残留 · 台账记本机曾上传'), findsOneWidget);

      // 一致组默认折叠（本例 2 条），展开后可见。
      expect(find.text('synced_1.bin'), findsNothing);
      await tapKey(tester, 'diff-same-header');
      expect(find.text('synced_1.bin'), findsOneWidget);

      // 默认全勾选：上传 3 · 下载 2 · 共 18 MB。
      expect(find.text('上传 3 · 下载 2 · 共 18 MB'), findsOneWidget);

      // 取消勾选一条上传 → 合计联动。
      await tapKey(tester, 'diff-chk-logs/2026-09-24.log');
      expect(find.text('上传 2 · 下载 2 · 共 14 MB'), findsOneWidget);

      // 全选上传恢复。
      await tapText(tester, '全选上传');
      expect(find.text('上传 3 · 下载 2 · 共 18 MB'), findsOneWidget);
    });

    testWidgets('勾选→同步→S4 出现 · fake store 收到对应 put（快照最后）· 台账留痕',
        (tester) async {
      seedServices();
      seedInventory(fake, snap);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openDiffSheet(tester);

      // 只执行上传段：取消勾选两条仅云端。
      await tapKey(tester, 'diff-chk-cloud_only.bin');
      await tapKey(tester, 'diff-chk-cloud_stale.bin');
      expect(find.text('上传 3 · 下载 0 · 共 14 MB'), findsOneWidget);

      await tapKey(tester, 'btn-diff-sync');

      // S4 进度半屏出现并跑完（fake put 即刻成功）。
      expect(find.text('同步结束'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(
          await pollText(tester, '同步完成 · 上传 3 · 下载 0 · 失败 0'), isTrue);
      await clearToasts(tester);

      // 执行顺序钉死：非快照先、`.lhbak` 快照最后（批量原子性口径）。
      expect(fake.putCalls,
          ['logs/2026-09-24.log', 'modified.bin', 'sync_20260925_080000.lhbak']);
      expect(fake.getCalls, isEmpty);

      // 续传台账逐文件留痕 + 历史落 prefs。
      final ledger = jsonDecode(prefs.getString('sync_ledger_svcW|sync')!) as Map;
      expect(ledger.keys, containsAll(['logs/2026-09-24.log', 'modified.bin', 'sync_20260925_080000.lhbak']));
      expect(prefs.getString('sync_history'), contains('svcW'));
    });

    testWidgets('仅云端行「下载」→ fake get · 绝不自动导入（引导行可见）',
        (tester) async {
      seedServices();
      seedInventory(fake, snap);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openDiffSheet(tester);

      await tapKey(tester, 'diff-get-cloud_only.bin');
      expect(find.text('同步结束'), findsOneWidget);
      expect(
          await pollText(tester, '同步完成 · 上传 0 · 下载 1 · 失败 0'), isTrue);
      await clearToasts(tester);
      expect(fake.getCalls, ['cloud_only.bin']);
      expect(find.byKey(const ValueKey('sync-import-guide')), findsOneWidget);
      expect(find.textContaining('未自动导入，请经「备份导出/导入」发起恢复'), findsOneWidget);
    });
  });

  group('S2 连接验证（s-svc-verify）三态 · 文案随协议', () {
    Future<void> openVerify(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('btn-verify-svc')));
      await settle5(tester);
    }

    testWidgets('通过态：探针行 + 「连接通过」（WebDAV 口径）', (tester) async {
      seedServices();
      await vault.write('svcW', 'apppw-9');
      fake.verifyResult = VerifyResult(true);
      await useSurface(tester, const Size(800, 2000));
      await boot(tester);
      await openVerify(tester);
      expect(find.text('连接验证'), findsOneWidget);
      expect(find.textContaining('探针 PROPFIND Depth:0'), findsOneWidget);
      expect(find.text('连接通过'), findsOneWidget);
      expect(find.textContaining('207'), findsOneWidget);
      expect(fake.verifyCount, 1);
    });

    testWidgets('凭据错误态：WebDAV 文案提示应用密码（非登录密码）', (tester) async {
      seedServices();
      await vault.write('svcW', 'apppw-9');
      fake.verifyResult = VerifyResult(
          false, '认证失败（401）：账户请填注册邮箱 + 应用密码（不是登录密码）。网页端 → 账户信息 → 安全选项 → 添加应用密码');
      await useSurface(tester, const Size(800, 2000));
      await boot(tester);
      await openVerify(tester);
      expect(find.text('凭据错误'), findsOneWidget);
      expect(find.textContaining('应用密码'), findsWidgets);
      expect(find.text('重新验证'), findsOneWidget);
    });

    testWidgets('网络失败态：store 抛异常 → 「网络失败」+ 原因', (tester) async {
      seedServices();
      await vault.write('svcW', 'apppw-9');
      fake.verifyError = Exception('连接超时 30s · 无法解析 dav.jianguoyun.com');
      await useSurface(tester, const Size(800, 2000));
      await boot(tester);
      await openVerify(tester);
      expect(find.text('网络失败'), findsOneWidget);
      expect(find.textContaining('超时'), findsOneWidget);
    });

    testWidgets('S3 凭据缺失：本地预检直出（零请求）· 文案提示子账户 AK/SK+桶权限',
        (tester) async {
      seedServices(activeId: 'svcS');
      fake.verifyResult = VerifyResult(true);
      await useSurface(tester, const Size(800, 2000));
      await boot(tester);
      await openVerify(tester);
      expect(find.text('凭据错误'), findsOneWidget);
      expect(find.textContaining('子账户'), findsOneWidget);
      expect(find.textContaining('桶权限'), findsOneWidget);
      expect(fake.verifyCount, 0, reason: '凭据缺失绝不发探针');
    });

    testWidgets('apiUrl 配置错误经 S2 显示（探针异常 = 不再回落缺省 host）',
        (tester) async {
      seedServices();
      // svcW 地址改坏（模拟手滑粘贴非 URL）。
      final store = SyncConfigStore(prefs, vault: vault);
      final snap2 = store.load();
      snap2.services.first.apiUrl = 'not a url';
      await store.save(snap2);
      await vault.write('svcW', 'apppw-9');
      // fake store 模拟真实分发行为：坏地址抛 StateError（对应下方单测）。
      fake.verifyError = StateError('服务地址无效：apiUrl="not a url"'
          '（需含 http(s):// 方案与主机名，不再回落缺省 host）');
      await useSurface(tester, const Size(800, 2000));
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('btn-verify-svc')));
      await settle5(tester);
      expect(find.text('网络失败'), findsOneWidget);
      expect(find.textContaining('服务地址无效'), findsOneWidget);
    });
  });

  group('携带修复：s3_store fail-fast（纯单元）', () {
    ServiceConfig cfgS3({String apiUrl = 'https://s3.bitiful.net', String id = 'svcS3'}) =>
        ServiceConfig(
          id: id,
          provider: StoreProviderKind.s3,
          apiUrl: apiUrl,
          account: 'AKIA-TEST',
          region: 'cn-east-1',
          bucket: 'photo',
          cloudDirName: 'sync',
          requestIntervalMs: 0,
        );

    S3Store storeWith(CredentialVault v) => S3Store(
          gate: HttpGate(sleeper: (_) async {}),
          vault: v,
          client: () => MockClient((_) async => http.Response('<x/>', 200)),
        );

    test('SK 缺失拒绝空钥签名：list 即抛 StateError（Secret Key 人话文案）', () async {
      final store = storeWith(CredentialVault.inMemory());
      Object? err;
      try {
        await store.list(cfgS3(), 'sync');
      } catch (e) {
        err = e;
      }
      expect(err, isStateError);
      expect('$err', contains('Secret Key'));
      store.close();
    });

    test('apiUrl 解析失败/缺 scheme：抛配置错误，不再静默回落 https://s3.bitiful.net',
        () async {
      final v = CredentialVault.inMemory();
      await v.write('svcS3', 'sk-1');
      final store = storeWith(v);
      for (final bad in ['not a url', '', 'ftp://example.com']) {
        Object? err;
        try {
          await store.list(cfgS3(apiUrl: bad), 'sync');
        } catch (e) {
          err = e;
        }
        expect(err, isStateError, reason: 'apiUrl="$bad" 应 fail-fast');
        expect('$err', contains('服务地址无效'));
      }
      store.close();
    });
  });
}
