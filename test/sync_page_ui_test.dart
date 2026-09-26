/// Task 18 · P1 /sync 主页 widget 用例（对照原型 index-sync.html p-sync /
/// p-synchist / s-svc-edit / s-throttle）。
///
/// 纪律：①服务层全 fake——store/orchestrator/vault/config 全部经 Riverpod
/// override 注入（SyncConfigStore 用 mock prefs + 内存保险箱真实实现，逻辑零
/// 网络）；②本地极简 GoRouter（照 log_page_test 模式，不拉全 app）；
/// ③SnackBar 断言一律 pollText 命中后再走 + clearToasts 清场；④禁真实
/// I/O（SnapshotService.localInventory 覆写为内存清单、build 覆写为计数
/// fake——终审修复波 Critical-1 触发点断言）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/sync/credential_vault.dart';
import 'package:lifeharness/core/sync/remote_store.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:lifeharness/core/sync/snapshot_service.dart';
import 'package:lifeharness/core/sync/sync_orchestrator.dart';
import 'package:lifeharness/core/sync/sync_providers.dart';
import 'package:lifeharness/features/settings/presentation/sync_history_page.dart';
import 'package:lifeharness/features/settings/presentation/sync_page.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

// ---------- 服务层 fake ----------

/// 两个 fake 共用的动作序记录（'build' / 'list'）：钉死终审 Critical-1
/// 「快照 build 生产触发点存在、且先于 compare 的网络 list」。各用例 setUp 清空。
final List<String> syncActionOrder = <String>[];

/// 测试用假备份服务（快照 build 已被 [FakeSnapshotService] 覆写、永不触达；
/// 仅供构造满足 super 形参）。
BackupService fakeBackupService() =>
    BackupService(exportDir: () => '', db: () => throw UnimplementedError());

String _fakeDocsDir() => '';

Future<bool> _fakeCareExcluded() async => false;

class FakeRemoteStore implements RemoteStore {
  FakeRemoteStore({this.quotaResult});

  List<FileEntry> files = const [];
  CloudQuota? quotaResult;
  VerifyResult verifyResult = VerifyResult(true);
  Object? verifyError;
  final putCalls = <String>[];
  final getCalls = <String>[];
  int verifyCount = 0;

  /// 非空时 list() 挂起至 complete——模拟 compare 前置网络长 await（可 30s+），
  /// 供防重入用例钉死「挂起期间二次 tap 不再触发 compare」。
  Completer<void>? listGate;
  Object? listError;
  int listCount = 0;

  @override
  Future<CloudListing> list(ServiceConfig c, String cloudDirName,
          {bool force = false}) async {
    listCount++;
    syncActionOrder.add('list');
    await listGate?.future;
    if (listError != null) throw listError!;
    return CloudListing(files);
  }

  @override
  Future<void> put(ServiceConfig c, String localPath, String cloudRelative) async {
    putCalls.add(cloudRelative);
  }

  @override
  Future<void> get(
      ServiceConfig c, String cloudRelative, String localPath) async {
    getCalls.add(cloudRelative);
  }

  @override
  Future<void> ensureDirectory(ServiceConfig c, String cloudRelativeDir) async {}

  @override
  Future<void> move(ServiceConfig c, String fromRel, String toRel) async {}

  @override
  Future<void> delete(ServiceConfig c, String cloudRelative) async {}


  @override
  Future<VerifyResult> verify(ServiceConfig c) async {
    verifyCount++;
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }

  @override
  Future<CloudQuota> quota(ServiceConfig c, {bool force = false}) async =>
      quotaResult ?? CloudQuota();

  @override
  void close() {}
}

/// 内存清单版 SnapshotService（覆写 localInventory/build，禁真实 I/O；
/// build 记 [syncActionOrder] 与次数，供终审 Critical-1 断言）。
class FakeSnapshotService extends SnapshotService {
  FakeSnapshotService({
    required super.backup,
    required super.prefs,
    super.docsDir = _fakeDocsDir,
    super.careExcluded = _fakeCareExcluded,
  });

  List<FileEntry> inventory = const [];
  int buildCount = 0;

  @override
  Future<SyncSnapshotResult> build({int? keepN, bool force = false}) async {
    buildCount++;
    syncActionOrder.add('build');
    return SyncSnapshotResult(
      file: File('fake_sync_snapshot.lhbak'),
      manifest: LhBakManifest(
        dbVersion: 0,
        appVersion: 'test',
        createdAt: DateTime(2026, 9, 25),
        tables: const {},
        excludedTables: const [],
        encrypted: false,
        members: const [],
      ),
      pruned: const [],
    );
  }

  @override
  Future<List<FileEntry>> localInventory() async => inventory;
}

// ---------- 数据种子 ----------

/// 两条服务：svcW（坚果云 WebDAV）+ svcS（缤纷云 S3），缺省激活 svcW。
void seedServices(SharedPreferences prefs,
    {String activeId = 'svcW', int intervalW = 300}) {
  prefs.setString('sync_services', jsonEncode({
    'services': [
      {
        'id': 'svcW',
        'provider': 'webdav',
        'apiUrl': 'https://dav.jianguoyun.com/dav/',
        'account': 'me@example.com',
        'cloudDirName': 'sync',
        'requestIntervalMs': intervalW,
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

void seedHistory(SharedPreferences prefs,
    {int ts = 0, int up = 3, int down = 2, int bytes = 18874368, bool ok = true}) {
  prefs.setString('sync_history', jsonEncode([
    {
      'ts': ts == 0 ? DateTime.now().millisecondsSinceEpoch : ts,
      'serviceId': 'svcW',
      'dir': 'sync',
      'up': up,
      'down': down,
      'bytes': bytes,
      'ok': ok,
      if (!ok) 'error': 'x: boom',
    },
  ]));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late CredentialVault vault;
  late FakeRemoteStore fake;
  late FakeSnapshotService snap;
  late SyncOrchestrator orch;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    vault = CredentialVault.inMemory();
    fake = FakeRemoteStore();
    snap = FakeSnapshotService(backup: fakeBackupService(), prefs: prefs);
    syncActionOrder.clear();
    orch = SyncOrchestrator(
      snapshotService: snap,
      prefs: prefs,
      activeConfig: () => readActiveService(SyncConfigStore(prefs, vault: vault)),
      storeFactory: (c) => fake,
    );
    // 每用例恰 dispose 一次（boot 内注册会随重复 boot 双释放到期报错）。
    addTearDown(orch.dispose);
  });

  Future<void> boot(WidgetTester tester, {String initial = '/sync'}) async {
    final router = GoRouter(initialLocation: initial, routes: [
      GoRoute(path: '/sync', builder: (_, _) => const SyncPage()),
      GoRoute(path: '/sync/history', builder: (_, _) => const SyncHistoryPage()),
      GoRoute(
          path: '/log',
          builder: (_, _) => Scaffold(
              appBar: AppBar(title: const Text('LOG')),
              body: const Center(child: Text('LOG-STUB')))),
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

  Future<void> openSheetVia(WidgetTester tester, String entryKey) async {
    await tester.tap(find.byKey(ValueKey(entryKey)), warnIfMissed: false);
    await settle5(tester);
  }

  SyncConfigSnapshot loaded() => SyncConfigStore(prefs, vault: vault).load();

  group('P1 当前服务卡 · 容量三态（R9）', () {
    testWidgets('①有配额：已用/共 + 百分比 + 进度条', (tester) async {
      seedServices(prefs);
      fake.quotaResult =
          CloudQuota(quotaBytes: 3221225472, usedBytes: 1288490189); // 3 GB / 1.2 GB
      await useSurface(tester, const Size(800, 2000));
      await boot(tester);
      expect(find.text('坚果云 · WebDAV'), findsWidgets);
      expect(find.text('WebDAV'), findsWidgets); // 协议徽标（文字）
      expect(find.text('已激活'), findsOneWidget);
      expect(find.byKey(const ValueKey('svc-cap')), findsOneWidget);
      expect(find.text('已用 1.2 GB / 共 3 GB'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.byKey(const ValueKey('quota-bar')), findsOneWidget);
    });

    testWidgets('②仅已用：无配额概念文本行 · 不渲染进度条', (tester) async {
      seedServices(prefs, activeId: 'svcS');
      fake.quotaResult = CloudQuota(usedBytes: 23142); // 22.6 KB
      await useSurface(tester, const Size(800, 2000));
      await boot(tester);
      expect(find.text('已用 22.6 KB'), findsOneWidget);
      expect(find.text('桶级求和 · 无配额概念'), findsOneWidget);
      expect(find.byKey(const ValueKey('quota-bar')), findsNothing);
    });

    testWidgets('③全 null：整行容量区不渲染', (tester) async {
      seedServices(prefs);
      fake.quotaResult = CloudQuota();
      await useSurface(tester, const Size(800, 2000));
      await boot(tester);
      expect(find.byKey(const ValueKey('svc-cap')), findsNothing);
      expect(find.textContaining('已用'), findsNothing);
    });
  });

  group('P1 入口行 · 摘要 · 切换服务', () {
    testWidgets('入口齐备（日志行已外移到设置）· 摘要=历史首条 · 点击历史行跳 /log',
        (tester) async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      seedServices(prefs);
      seedHistory(prefs, ts: ts, up: 3, down: 2, bytes: 18874368);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);

      expect(find.text('立即同步'), findsOneWidget);
      expect(find.text('差异对比'), findsOneWidget);
      expect(find.text('备份导出/导入'), findsOneWidget);
      expect(find.text('控流'), findsOneWidget);
      expect(find.text('同步历史'), findsOneWidget);
      // 2026-09-26：日志唯一入口在「设置 → 运行日志」，同步页不再挂日志行。
      expect(find.text('日志'), findsNothing);
      expect(find.textContaining('最近同步 今天'), findsOneWidget);
      expect(find.textContaining('上传 3 · 下载 2 · 18 MB · 成功'), findsOneWidget);

      // 切换服务单选 activeId。
      expect(find.byKey(const ValueKey('svc-switch-svcS')), findsOneWidget);
      await openSheetVia(tester, 'svc-switch-svcS');
      expect(loaded().activeId, 'svcS');
      expect(await pollText(tester, '已切换激活服务 · 缤纷云 · S3'), isTrue);
      await clearToasts(tester);

      // 回切后进历史页 → 点击行 → /log。
      await openSheetVia(tester, 'svc-switch-svcW');
      await clearToasts(tester);
      await openSheetVia(tester, 'sync-history-entry');
      expect(find.text('同步历史'), findsWidgets);
      expect(find.textContaining('上传 3 · 下载 2 · 18 MB · 成功'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('hist-row-$ts')));
      await settle5(tester);
      expect(find.text('LOG-STUB'), findsOneWidget);
    });
  });

  group('S1 服务配置编辑（s-svc-edit）', () {
    testWidgets('新增态 provider 切 S3 表单标签联动「账户/应用密码」→「Access Key/Secret Key」',
        (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      // 协议切换只在「新增服务」态可用（编辑态锁协议——R2⑤b），故走常驻添加钮。
      await openSheetVia(tester, 'btn-add-svc-persistent');

      // WebDAV 形态初始态。
      expect(find.text('服务配置'), findsOneWidget);
      expect(find.text('账户'), findsOneWidget);
      expect(find.text('应用密码'), findsOneWidget);
      expect(find.text('Access Key'), findsNothing);

      // 评审修复轮1 Minor-3：新增态先填 WebDAV 邮箱再切协议——
      // 邮箱与 Access Key 语义不同，切协议必须清空账户防串显。
      await tester.enterText(
          find.byKey(const ValueKey('edit-account')), 'me@example.com');
      await settle5(tester);

      // 切 S3：标签全换 + Region/Bucket 出现 + 地址联动 bitiful。
      await tester.tap(find.byKey(const ValueKey('edit-pill-s3')));
      await settle5(tester);
      expect(find.text('Access Key'), findsOneWidget);
      expect(find.text('Secret Key'), findsOneWidget);
      expect(find.text('Endpoint'), findsOneWidget);
      expect(find.text('Region'), findsOneWidget);
      expect(find.text('Bucket'), findsOneWidget);
      expect(find.text('账户'), findsNothing);
      expect(find.text('应用密码'), findsNothing);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('edit-account')))
              .controller!
              .text,
          isEmpty,
          reason: '新增态切协议清空账户：邮箱不串显成 Access Key');

      // 切回 WebDAV：标签还原；Access Key 侧填入再切回同样被清。
      await tester.enterText(
          find.byKey(const ValueKey('edit-account')), 'AKIA-TEST');
      await tester.tap(find.byKey(const ValueKey('edit-pill-webdav')));
      await settle5(tester);
      expect(find.text('账户'), findsOneWidget);
      expect(find.text('应用密码'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('edit-account')))
              .controller!
              .text,
          isEmpty,
          reason: '反方向同样清空，防 Access Key 串显成邮箱');
    });

    testWidgets('凭据保存走 CredentialVault · 明文侧无 authCode · 重开见状态点',
        (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openSheetVia(tester, 'btn-edit-svc');
      await tester.enterText(find.byKey(const ValueKey('edit-secret')), 'apppw-9');
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      expect(
          await pollText(tester, '已保存 · 凭据已存入本机加密区'), isTrue);
      await settle5(tester);
      expect(await vault.read('svcW'), 'apppw-9');
      expect(prefs.getString('sync_services'), contains('svcW'));
      expect(prefs.getString('sync_services'), isNot(contains('authCode')));
      await clearToasts(tester);

      // 重开 S1：保险箱状态点行「已存入本机加密区」。
      await openSheetVia(tester, 'btn-edit-svc');
      expect(find.text('已存入本机加密区'), findsOneWidget);
    });

    testWidgets('vault 写失败 → 不保存 · 原凭据原配置保留（R11）', (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openSheetVia(tester, 'btn-edit-svc');
      vault.failNextWrite = true;
      await tester.enterText(find.byKey(const ValueKey('edit-secret')), 'bad-write');
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      expect(await pollText(tester, '保险箱写入失败 · 原凭据与原配置已保留'), isTrue);
      expect(await vault.read('svcW'), isNull);
      expect(prefs.getString('sync_services'), contains('dav.jianguoyun.com'));
      // 弹层未关闭（保存未成功不放行）。
      expect(find.byKey(const ValueKey('edit-save')), findsOneWidget);
      await clearToasts(tester);
    });

    testWidgets('删除服务清 vault + 台账键（D1/D3 无孤儿）', (tester) async {
      seedServices(prefs);
      await vault.write('svcW', 'apppw-9');
      prefs.setString('sync_ledger_svcW|sync',
          '{"a.bin":{"etag":"","size":1,"ts":1}}');
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openSheetVia(tester, 'btn-edit-svc');
      await tester.tap(find.byKey(const ValueKey('edit-delete')));
      expect(await pollText(tester, '已删除服务 · 密钥与台账已清除'), isTrue);
      await settle5(tester);
      expect(await vault.read('svcW'), isNull);
      expect(prefs.getString('sync_ledger_svcW|sync'), isNull);
      final snap = loaded();
      expect(snap.services.map((c) => c.id), isNot(contains('svcW')));
      // activeId 悬空回落第一条（svcS）。
      expect(snap.activeId, 'svcS');
    });

    testWidgets('R2⑤a 编辑态回填 SK：默认掩码有值 · 眼睛钮切显隐 · 保存后 vault 不变',
        (tester) async {
      seedServices(prefs);
      await vault.write('svcW', 'apppw-9');
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openSheetVia(tester, 'btn-edit-svc');

      final sk = find.byKey(const ValueKey('edit-secret'));
      expect(sk, findsOneWidget);
      var field = tester.widget<TextField>(sk);
      expect(field.controller!.text, 'apppw-9', reason: '编辑态从 vault 回填密钥');
      expect(field.obscureText, isTrue, reason: '默认掩码');

      // 点眼睛 → 变可见。
      await tester.tap(find.byKey(const ValueKey('edit-secret-eye')));
      await settle5(tester);
      field = tester.widget<TextField>(sk);
      expect(field.obscureText, isFalse, reason: '切显隐后不再掩码');

      // 保存（未改动密钥）→ 仍成功，vault 值不变（非空即写回同值）。
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      expect(await pollText(tester, '已保存 · 凭据已存入本机加密区'), isTrue);
      expect(await vault.read('svcW'), 'apppw-9');
    });

    testWidgets('R2⑤a 新增服务无回填（SK 空）', (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openSheetVia(tester, 'btn-add-svc-persistent');
      final field = tester.widget<TextField>(find.byKey(const ValueKey('edit-secret')));
      expect(field.controller!.text, isEmpty, reason: '新增态无历史密钥可回填');
    });

    testWidgets('R6 验证连接：S2 盖在 S1 上 · 关掉 S2 后 S1 仍在可继续编辑',
        (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openSheetVia(tester, 'btn-edit-svc');
      await tester.tap(find.byKey(const ValueKey('edit-verify')));
      expect(await pollText(tester, '连接验证'), isTrue,
          reason: 'S2 结果层已浮出');
      expect(find.byKey(const ValueKey('verify-state')), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-save')), findsOneWidget,
          reason: 'S1 不因验证而关闭');
      // 点遮罩关掉 S2 → 回到 S1，表单仍在原地可继续改。
      await tester.tapAt(const Offset(10, 10));
      await settle5(tester);
      expect(find.byKey(const ValueKey('verify-state')), findsNothing);
      expect(find.byKey(const ValueKey('edit-save')), findsOneWidget,
          reason: '验证后编辑弹层保留（失败可原地改配置重验）');
      await clearToasts(tester);
    });

    testWidgets('R2⑤b 编辑态协议 pill 置灰不可点（无切换）· 新增态可切换',
        (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      // 编辑态：初始 WebDAV（标签「账户」），点 S3 pill 无反应。
      await openSheetVia(tester, 'btn-edit-svc');
      expect(find.text('账户'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('edit-pill-s3')),
          warnIfMissed: false);
      await settle5(tester);
      expect(find.text('Access Key'), findsNothing,
          reason: '编辑态协议锁定，点 S3 pill 不切换');
      expect(find.text('账户'), findsOneWidget);
      final s3pill = tester.widget<PillChip>(
          find.byKey(const ValueKey('edit-pill-s3')));
      expect(s3pill.enabled, isFalse, reason: '编辑态 pill 置灰');
    });

    testWidgets('R2⑤c 两服务时切换列表显两条 + 常驻「添加服务」钮存在',
        (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      expect(find.byKey(const ValueKey('svc-switch-svcW')), findsOneWidget);
      expect(find.byKey(const ValueKey('svc-switch-svcS')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-add-svc-persistent')), findsOneWidget);
      // 点常驻钮 → 新增服务弹层打开。
      await openSheetVia(tester, 'btn-add-svc-persistent');
      expect(find.text('服务配置'), findsOneWidget);
      final webdavPill = tester.widget<PillChip>(
          find.byKey(const ValueKey('edit-pill-webdav')));
      expect(webdavPill.enabled, isTrue, reason: '新增态协议可选');
    });

    testWidgets('R2⑤d 键盘弹出（模拟 viewInsets）后 SK 输入框仍在可见区',
        (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openSheetVia(tester, 'btn-add-svc-persistent');
      expect(find.text('服务配置'), findsOneWidget);

      // 收窄到手机高 + 模拟软键盘占掉下半屏（弹层已开，不受 ListView 懒建影响）。
      await tester.binding.setSurfaceSize(const Size(360, 560));
      tester.view.viewInsets = FakeViewPadding(bottom: 360);
      await tester.pump();
      await settle5(tester);

      final sk = find.byKey(const ValueKey('edit-secret'));
      expect(sk, findsOneWidget);
      // 聚焦：ensureVisible 不抛；随后 finder.hitTestable() 命中（内容经
      // viewInsets Padding 抬到键盘上方，未被遮）。
      await tester.ensureVisible(sk);
      await settle5(tester);
      expect(sk.hitTestable(), findsOneWidget,
          reason: 'viewInsets 兜底使 SK 框不被键盘遮住');
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('立即同步防重入（评审修复轮1）', () {
    /// 取某 key 子树内唯一 InkWell（入口钮/入口行均为 InkWell 包 Material）。
    InkWell inkWellOf(WidgetTester tester, String key) => tester.widget<InkWell>(
        find.descendant(
            of: find.byKey(ValueKey(key)), matching: find.byType(InkWell)));

    testWidgets('compare 挂起时二次 tap 不叠第二层弹层 · 两入口置灰禁用', (tester) async {
      seedServices(prefs);
      // 一条仅本地 → compare 完成后 actionable 非空，正常会进 S4。
      snap.inventory = [
        FileEntry(relativePath: 'logs/2026-09-25.log', size: 4194304),
      ];
      fake.listGate = Completer<void>(); // compare 卡在网络 list（模拟 30s+ await）
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);

      await tester.tap(find.byKey(const ValueKey('btn-sync-now')));
      await settle5(tester);
      expect(fake.listCount, 1);

      // 挂起期间：两入口禁用态存在（onTap null + 置灰 Opacity .35，
      // 工程惯例 habit_kit 同口径；btn 的 key 在内层 Container 上，
      // 故置灰断言用全页谓词：恰两处 0.35）。
      expect(inkWellOf(tester, 'btn-sync-now').onTap, isNull);
      expect(inkWellOf(tester, 'sync-diff-entry').onTap, isNull);
      expect(
          find.byWidgetPredicate((w) => w is Opacity && w.opacity == .35),
          findsNWidgets(2),
          reason: '立即同步钮 + 差异对比行置灰，其余入口不受影响');

      // 连点两入口：不产第二层 compare、不弹 S3/S4。
      await tester.tap(find.byKey(const ValueKey('btn-sync-now')),
          warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('sync-diff-entry')),
          warnIfMissed: false);
      await settle5(tester);
      expect(fake.listCount, 1, reason: '挂起期间二次 tap 绝不触发第二层 compare');
      expect(find.text('全选上传'), findsNothing); // S3 未弹
      expect(find.text('同步进行中'), findsNothing); // S4 未弹

      // compare 返回：恰好一层 S4 且能跑完（未叠层则无「已在运行」门闩错）。
      fake.listGate!.complete();
      await settle5(tester);
      expect(find.text('同步结束'), findsOneWidget);
      expect(find.textContaining('已在运行'), findsNothing);
      expect(await pollText(tester, '同步完成 · 上传 1 · 下载 0 · 失败 0'), isTrue);
      await clearToasts(tester);

      // 关 S4 → 动作结束：入口恢复可用。
      final doneBtn = find.byKey(const ValueKey('btn-cancel-sync'));
      await tester.ensureVisible(doneBtn);
      await tester.tap(doneBtn);
      await settle5(tester);
      expect(inkWellOf(tester, 'btn-sync-now').onTap, isNotNull);
      expect(inkWellOf(tester, 'sync-diff-entry').onTap, isNotNull);
      expect(fake.listCount, 1);
    });

    testWidgets('compare 异常 → finally 复位 · 入口恢复可点', (tester) async {
      seedServices(prefs);
      final gate = Completer<void>();
      fake.listGate = gate;
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);

      await tester.tap(find.byKey(const ValueKey('btn-sync-now')));
      await settle5(tester);
      expect(inkWellOf(tester, 'btn-sync-now').onTap, isNull);

      // 让 list 抛错（compare 失败路径）。
      fake.listError = StateError('PROPFIND 失败：网络中断');
      gate.complete();
      await settle5(tester);
      expect(await pollText(tester, '同步准备失败：Bad state: PROPFIND 失败：网络中断'),
          isTrue);
      await clearToasts(tester);
      expect(inkWellOf(tester, 'btn-sync-now').onTap, isNotNull,
          reason: '异常也要经 finally 复位，不许永久置灰');
    });
  });

  group('导航返回退出修复（R2 项④：go→push）', () {
    testWidgets('/sync 不再挂日志入口（2026-09-26 外移到设置）· 历史入口仍在',
        (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      expect(find.byKey(const ValueKey('svc-card')), findsOneWidget);

      // 唯一入口改成「设置 → 运行日志」（entry-log，返回语义见 sync_nav_back_test）；
      // 同步页里再挂一行会让同一功能两个归属，用户按「备份」找不到日志反而绕路。
      expect(find.byKey(const ValueKey('sync-log-entry')), findsNothing);
      expect(find.text('环形缓冲 300 · 按日落盘'), findsNothing);
      expect(find.byKey(const ValueKey('sync-history-entry')), findsOneWidget,
          reason: '同步历史仍留在本页：点行进日志窗口是它自己的语义');
    });

    testWidgets('从 /sync 进 /sync/history：系统返回回 /sync', (tester) async {
      seedServices(prefs);
      seedHistory(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);

      await openSheetVia(tester, 'sync-history-entry');
      await settle5(tester);
      expect(find.textContaining('上传 3 · 下载 2'), findsOneWidget);

      await tester.pageBack();
      await settle5(tester);
      expect(find.byKey(const ValueKey('svc-card')), findsOneWidget);
    });
  });

  group('立即同步快照生成（终审修复波 Critical-1）', () {
    testWidgets('点「立即同步」→ build 恰 1 次且先于 compare 的远端 list',
        (tester) async {
      seedServices(prefs);
      // 一条仅本地快照：compare 完成后 actionable 非空，可一路跑到 S4 结束。
      snap.inventory = [
        FileEntry(relativePath: 'sync_20260925_120000.lhbak', size: 8388608),
      ];
      final gate = Completer<void>();
      fake.listGate = gate; // 挂起 compare 的网络段，定格「build 已先发生」
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      expect(snap.buildCount, 0, reason: '进页/静止态绝不悄悄生成快照');
      expect(syncActionOrder, isEmpty);

      await tester.tap(find.byKey(const ValueKey('btn-sync-now')));
      await settle5(tester);
      expect(snap.buildCount, 1, reason: 'build 是快照的唯一生产触发点');
      expect(fake.listCount, 1);
      expect(syncActionOrder, ['build', 'list'],
          reason: '快照必须先于 compare（否则 sync/ 目录永远为空）');

      // 放行 compare → S4 上传该快照 → 结束；全程仍只 build 一次。
      gate.complete();
      await settle5(tester);
      expect(find.text('同步结束'), findsOneWidget);
      expect(snap.buildCount, 1, reason: '一轮同步只生成一份快照');
      expect(fake.putCalls, ['sync_20260925_120000.lhbak']);
      expect(await pollText(tester, '同步完成 · 上传 1 · 下载 0 · 失败 0'), isTrue);
      await clearToasts(tester);
      final doneBtn = find.byKey(const ValueKey('btn-cancel-sync'));
      await tester.ensureVisible(doneBtn);
      await tester.tap(doneBtn);
      await settle5(tester);
    });
  });

  group('S6 控流弹层（s-throttle）', () {
    testWidgets('档位回写 ServiceConfig.requestIntervalMs · 滚轮份数 · 仅Wi-Fi 存 prefs',
        (tester) async {
      seedServices(prefs);
      await useSurface(tester, const Size(800, 2400));
      await boot(tester);
      await openSheetVia(tester, 'sync-throttle-entry');

      expect(find.text('控流设置'), findsOneWidget);
      expect(find.text('429 / 503 退避'), findsOneWidget);

      // 800ms 档写回当前服务（svcW）。
      await tester.tap(find.byKey(const ValueKey('throttle-seg-800')));
      expect(await pollText(tester, '请求间隔已设为 800ms · 仅作用于该服务的同步请求排队'),
          isTrue);
      await clearToasts(tester);
      expect(loaded().services.firstWhere((c) => c.id == 'svcW').requestIntervalMs,
          800);

      // 快照份数滚轮（T6 同源 CupertinoPicker）：5 → 拖一格 = 3。
      expect(prefs.getInt('sync_keep_snapshots'), isNull);
      await tester.drag(find.byKey(const ValueKey('keep-n-wheel')), const Offset(0, 34));
      await settle5(tester);
      expect(prefs.getInt('sync_keep_snapshots'), 3);

      // 仅Wi-Fi 开关存 prefs sync_wifiOnly（T19 自动同步引擎消费）。
      expect(prefs.getBool('sync_wifiOnly'), isNull);
      await tester.tap(find.byKey(const ValueKey('wifi-switch')));
      await settle5(tester);
      expect(prefs.getBool('sync_wifiOnly'), isTrue);
    });
  });

  group('P2 历史页直开', () {
    testWidgets('时间/服务/量/结果渲染 · 空态行', (tester) async {
      seedServices(prefs);
      seedHistory(prefs, ok: false);
      await useSurface(tester, const Size(800, 2000));
      await boot(tester, initial: '/sync/history');
      expect(find.text('部分失败'), findsOneWidget);
      expect(find.textContaining('坚果云 · WebDAV'), findsOneWidget);

      // 空历史。
      prefs.remove('sync_history');
      await boot(tester, initial: '/sync/history');
      expect(find.text('暂无同步记录'), findsOneWidget);
    });
  });
}
