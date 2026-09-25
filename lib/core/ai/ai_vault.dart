import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AI API Key 保险箱：真实 Key 只进系统级加密区（Keystore），
/// 不入 prefs 明文、不进备份导出、不随 WebDAV/S3 同步（需求清单 §6 原则 2）。
/// 仿 sync 的 CredentialVault：`inMemory()` 为测试注入版（真实加密存储
/// 无测试平台通道实现，widget/单测一律注入内存版——既定坑）。
class AiKeyVault {
  factory AiKeyVault({
    AndroidOptions options =
        const AndroidOptions(encryptedSharedPreferences: true),
  }) =>
      AiKeyVault._(FlutterSecureStorage(aOptions: options), null);

  factory AiKeyVault.inMemory({String? apiKey}) => AiKeyVault._(
      null, {if (apiKey != null && apiKey.isNotEmpty) _key: apiKey});

  AiKeyVault._(this._storage, this._mem);

  static const _key = 'ai_api_key';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _mem;

  Future<String?> read() async {
    final mem = _mem;
    if (mem != null) return mem[_key];
    try {
      return await _storage!.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  /// 写 Key；异常返回 false（调用方保留原值并提示，绝不清空既有 Key）。
  Future<bool> write(String key) async {
    final mem = _mem;
    if (mem != null) {
      mem[_key] = key;
      return true;
    }
    try {
      await _storage!.write(key: _key, value: key);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    final mem = _mem;
    if (mem != null) {
      mem.remove(_key);
      return;
    }
    try {
      await _storage!.delete(key: _key);
    } catch (_) {
      // 删不掉不阻断 UI 流程。
    }
  }
}
