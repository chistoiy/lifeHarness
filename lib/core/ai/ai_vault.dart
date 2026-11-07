import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_log.dart';

/// AI API Key 保险箱：真实 Key 只进系统级加密区（Keystore），
/// 不入 prefs 明文、不进备份导出、不随 WebDAV/S3 同步（需求清单 §6 原则 2）。
///
/// V1.53.1 起**按服务商分域**：每条端点一把 Key，槽位 `ai_key:<providerId>`；
/// 旧的全局槽 `ai_api_key` 只读回落（升级后原 Key 继续可用，用户为某条端点
/// 单独填过 Key 即以该槽为准）。
/// 仿 sync 的 CredentialVault：`inMemory()` 为测试注入版（真实加密存储
/// 无测试平台通道实现，widget/单测一律注入内存版——既定坑）。
class AiKeyVault {
  factory AiKeyVault({
    AndroidOptions options =
        const AndroidOptions(encryptedSharedPreferences: true),
  }) =>
      AiKeyVault._(FlutterSecureStorage(aOptions: options), null);

  factory AiKeyVault.inMemory({String? apiKey}) => AiKeyVault._(
      null, {if (apiKey != null && apiKey.isNotEmpty) _legacyKey: apiKey});

  AiKeyVault._(this._storage, this._mem);

  static const _legacyKey = 'ai_api_key';

  /// 某服务商的 Key 槽位名。
  static String slot(String providerId) => 'ai_key:$providerId';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _mem;

  /// 读 Key。给 [providerId] 时：先取该服务商槽位，空则回落旧全局槽。
  Future<String?> read([String? providerId]) async {
    if (providerId != null) {
      final own = await _read(slot(providerId));
      if (own != null && own.isNotEmpty) return own;
    }
    return _read(_legacyKey);
  }

  /// 该服务商是否**自己**存过 Key（UI 行上「Key 已单独保存 / 沿用旧全局 Key」区分）。
  Future<bool> hasOwnKey(String providerId) async {
    final own = await readOwn(providerId);
    return own != null && own.isNotEmpty;
  }

  /// 只读该服务商自己的槽位（不回落旧全局）：表单里「已存 Key（末 4 位）」的口径。
  Future<String?> readOwn(String providerId) => _read(slot(providerId));

  /// 写 Key；异常返回 false（调用方保留原值并提示，绝不清空既有 Key）。
  Future<bool> write(String key, {String? providerId}) async {
    final slotKey = providerId == null ? _legacyKey : slot(providerId);
    final mem = _mem;
    if (mem != null) {
      mem[slotKey] = key;
      return true;
    }
    try {
      await _storage!.write(key: slotKey, value: key);
      return true;
    } catch (e) {
      // 只记槽位名，绝不记 Key 本体。
      AppLog.add('AI Key 写入失败（槽 $slotKey）：$e', level: LhLevel.error);
      return false;
    }
  }

  /// 清除 Key：不给 [providerId] 时清旧全局槽，给则只清该服务商槽位。
  Future<void> clear({String? providerId}) async {
    final slotKey = providerId == null ? _legacyKey : slot(providerId);
    final mem = _mem;
    if (mem != null) {
      mem.remove(slotKey);
      return;
    }
    try {
      await _storage!.delete(key: slotKey);
    } catch (e) {
      // 删不掉不阻断 UI 流程。
      AppLog.add('AI Key 删除失败（槽 $slotKey）：$e', level: LhLevel.error);
    }
  }

  Future<String?> _read(String key) async {
    final mem = _mem;
    if (mem != null) return mem[key];
    try {
      return await _storage!.read(key: key);
    } catch (e) {
      // 读不到＝表现为「未配置 Key」，没有这行日志根本查不出是保险箱炸了。
      AppLog.add('AI Key 读取失败（槽 $key）：$e', level: LhLevel.error);
      return null;
    }
  }
}
