import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';
import '../providers.dart';
import 'cloud_clean_service.dart';
import 'credential_vault.dart';
import 'remote_store.dart';
import 'service_config.dart';
import 'snapshot_service.dart';
import 'sync_orchestrator.dart';

/// V1.41 Task 18 · 同步装配根（Riverpod provider 全家福）。
///
/// 口径（R2 组合根白名单）：本文件在 core 侧**不得 import features**——
/// careExcluded 这类要触达 feature 仓库的接线一律放 main.dart 组合根
/// （先例：backupServiceProvider 在 main overrideWithValue）。全部 provider
/// 可 override 供 widget 测试注入 fake（store/orchestrator/vault 三层全假）。

/// 凭据保险箱（协议口径 R11）：生产 = flutter_secure_storage 真实后端；
/// widget/单测一律 override 为 [CredentialVault.inMemory]（既定坑：真实
/// 平台通道在测试环境不可用）。
final credentialVaultProvider = Provider<CredentialVault>(
  (ref) => CredentialVault(),
);

/// 服务配置明文侧存储（prefs 单键 `sync_services`，凭据只走 vault）。
final syncConfigStoreProvider = Provider<SyncConfigStore>(
  (ref) => SyncConfigStore(
    ref.watch(sharedPreferencesProvider),
    vault: ref.watch(credentialVaultProvider),
  ),
);

/// 协议分发唯一位点（R2）：UI/编排一律经此工厂拿 store，测试注入假实现；
/// vault 统一从 [credentialVaultProvider] 接进（缺省真实后端）。
final remoteStoreFactoryProvider = Provider<RemoteStoreFactory>((ref) {
  final vault = ref.watch(credentialVaultProvider);
  return (c) => RemoteStore.forConfig(c, vault: vault);
});

/// 同步快照生成器：docsDir/careExcluded（红线 7 需触达 CareRepository）在
/// main.dart 组合根 overrideWithValue 装配（架构守护 R2：core 不得 import
/// features，照 backupServiceProvider 先例）。
final snapshotServiceProvider = Provider<SnapshotService>(
  (ref) => throw UnimplementedError('需在 main 中 overrideWithValue（测试注入 fake）'),
);

/// R5d：云端孤儿附件清理服务（store 由调用方按当前服务传入，本 provider
/// 只装配 prefs + scanner）。
final cloudCleanServiceProvider = Provider<CloudCleanService>(
  (ref) => CloudCleanService(
    prefs: ref.watch(sharedPreferencesProvider),
    scanner: ref.watch(mediaScannerProvider),
  ),
);

/// 「我的」页状态行数据源：当前激活云服务配置（未配置＝null）。
/// 与 [readActiveService] 同一判据，但**不抛错**——主页只读状态，绝不因未配置弹条。
/// 注意：这只表示「本机存了可用端点」，不代表连得上（连通性＝同步页「测试连接」的口径），
/// 因此 UI 文案用「已配置」而非「已连接」。
final activeSyncServiceProvider = Provider<ServiceConfig?>((ref) {
  final snap = ref.watch(syncConfigStoreProvider).load();
  final id = snap.activeId;
  return id == null ? null : snap.services.where((c) => c.id == id).firstOrNull;
});

/// 读取当前激活服务；无激活项抛 [StateError]（编排层与 UI 共用同一判空口径）。
ServiceConfig readActiveService(SyncConfigStore store) {
  final snap = store.load();
  final id = snap.activeId;
  final cfg = id == null ? null : snap.services.where((c) => c.id == id).firstOrNull;
  if (cfg == null) {
    throw StateError('尚未配置激活云服务：请到「服务配置」添加并切换');
  }
  return cfg;
}

/// 云同步编排器（S3/S4 数据源）：storeFactory 走 [remoteStoreFactoryProvider]
/// （vault 已注入），activeConfig 读 [syncConfigStoreProvider] 激活项。
final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  final orchestrator = SyncOrchestrator(
    snapshotService: ref.watch(snapshotServiceProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    activeConfig: () => readActiveService(ref.watch(syncConfigStoreProvider)),
    storeFactory: ref.watch(remoteStoreFactoryProvider),
  );
  ref.onDispose(orchestrator.dispose);
  return orchestrator;
});

/// 当前激活服务容量（P1 容量三态数据源）：失败/未配置一律 null——UI 据此
/// 隐藏容量行，绝不弹错打断主页（明细走 AppLog）。
final syncQuotaProvider = FutureProvider<CloudQuota?>((ref) async {
  ServiceConfig cfg;
  try {
    cfg = readActiveService(ref.watch(syncConfigStoreProvider));
  } on StateError {
    return null;
  }
  final store = ref.watch(remoteStoreFactoryProvider)(cfg);
  ref.onDispose(store.close);
  try {
    return await store.quota(cfg);
  } catch (e) {
    AppLog.add('容量读取失败（${cfg.id}）：$e', level: LhLevel.warn);
    return null;
  }
});
