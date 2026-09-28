import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../providers.dart';
import 'ai_call_store.dart';
import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_prompt_pack.dart';
import 'ai_service.dart';
import 'ai_vault.dart';

/// 默认提示词资产（打包进 APK 的事实源；用户覆盖不写回这里）。
const kAiPromptAssetPath = 'assets/ai_prompts/prompts.json';

@visibleForTesting
AiPromptPack decodePromptPack(String source) => AiPromptPack.decode(source);

/// 内置提示词包（main 启动时加载并 overrideWithValue；测试注入固定 JSON 串）。
final aiPromptPackProvider = Provider<AiPromptPack>(
  (ref) => throw UnimplementedError('需在 main 中 overrideWithValue（测试注入）'),
);

/// 启动期加载默认提示词包（损坏时回退空表：仅影响 AI 功能，不拖垮启动）。
Future<AiPromptPack> loadAiPromptPack() async {
  try {
    return AiPromptPack.decode(await rootBundle.loadString(kAiPromptAssetPath));
  } catch (e) {
    debugPrint('AI 提示词包加载失败：$e');
    return const AiPromptPack(
        version: 0, defaultBaseUrl: '', defaultModel: '', tasks: []);
  }
}

final aiConfigRepoProvider = Provider<AiConfigRepository>(
    (ref) => AiConfigRepository(ref.watch(sharedPreferencesProvider)));

/// AI Key 保险箱：main 装配真实版；测试注入 [AiKeyVault.inMemory]。
final aiKeyVaultProvider = Provider<AiKeyVault>(
  (ref) => throw UnimplementedError('需在 main 中 overrideWithValue（测试注入 fake）'),
);

final aiClientProvider = Provider<AiClient>((ref) {
  final client = AiClient();
  ref.onDispose(client.close);
  return client;
});

/// AI 使用记录（V1.53 · 表 ai_calls）。
/// 未开库环境（如只 pump 单页的 widget 测试）返回 null＝不落记录，绝不因此崩。
final aiCallStoreProvider = Provider<AiCallStore?>((ref) {
  if (!AppDatabase.instance.isInitialized) return null;
  return AiCallStore(AppDatabase.instance.db);
});

/// 能力编排服务（同步可用：包已在 main 预载 override）。
final aiServiceProvider = Provider<AiService>((ref) => AiService(
      configRepo: ref.watch(aiConfigRepoProvider),
      keyVault: ref.watch(aiKeyVaultProvider),
      client: ref.watch(aiClientProvider),
      pack: ref.watch(aiPromptPackProvider),
      calls: ref.watch(aiCallStoreProvider),
    ));

/// AI 配置响应式快照：所有写操作经本 Notifier（写盘 + 重建 state）。
class AiConfigNotifier extends Notifier<AiConfig> {
  @override
  AiConfig build() => ref.watch(aiConfigRepoProvider).load();

  AiConfigRepository get _repo => ref.read(aiConfigRepoProvider);

  Future<void> setMaster(bool on) async {
    await _repo.setMaster(on);
    ref.invalidateSelf();
  }

  Future<void> setEndpoint(String baseUrl, String model,
      {String? protocol}) async {
    await _repo.setEndpoint(baseUrl: baseUrl, model: model, protocol: protocol);
    ref.invalidateSelf();
  }

  /// 增/改一条服务商（V1.53.1：预置只是种子，用户可改可删可加）。
  Future<void> saveProvider(AiProvider p) async {
    await _repo.saveProvider(p);
    ref.invalidateSelf();
  }

  /// 切换当前服务商（id 不在列表内返回 false，state 不动）。
  Future<bool> useProvider(String id) async {
    final ok = await _repo.useProvider(id);
    if (ok) ref.invalidateSelf();
    return ok;
  }

  /// 删服务商，并连带清除它在加密区的 Key；当前激活项拒删。
  Future<bool> deleteProvider(String id) async {
    final ok = await _repo.deleteProvider(id);
    if (!ok) return false;
    await ref.read(aiKeyVaultProvider).clear(providerId: id);
    ref.invalidateSelf();
    return true;
  }

  Future<void> setCap(String taskId, bool on) async {
    await _repo.setCap(taskId, on);
    ref.invalidateSelf();
  }

  /// 覆盖提示词模板段（null=该段保持默认）。
  Future<void> setPromptOverride(String taskId, String? system, String? user) async {
    await _repo.setPromptOverride(taskId, system, user);
    ref.invalidateSelf();
  }

  Future<void> clearPromptOverride(String taskId) async {
    await _repo.clearPromptOverride(taskId);
    ref.invalidateSelf();
  }

  /// V1.53 使用记录设置：是否留存正文（关掉后新调用只记用量）。
  Future<void> setRecordBody(bool on) async {
    await _repo.setRecordBody(on);
    ref.invalidateSelf();
  }

  /// V1.53 使用记录保留天数（0=不限）；改完即刻按新值裁剪超期记录。
  Future<void> setCallKeepDays(int days) async {
    await _repo.setCallKeepDays(days);
    ref.read(aiCallStoreProvider)?.prune(days);
    ref.invalidateSelf();
  }

  Future<void> setVerifyResult({
    required bool ok,
    required int at,
    int? latencyMs,
    String? reason,
  }) async {
    await _repo.setVerifyResult(ok: ok, at: at, latencyMs: latencyMs, reason: reason);
    ref.invalidateSelf();
  }
}

final aiConfigProvider =
    NotifierProvider<AiConfigNotifier, AiConfig>(AiConfigNotifier.new);

@visibleForTesting
String encodeSample(Map<String, String> m) => jsonEncode(m);
