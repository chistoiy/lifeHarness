import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 凭据保险箱（协议口径 R11 / D1）：真实凭据只进这里，明文 prefs 不留。
///
/// - 键约定 `sync_secret_{serviceId}`（[keyFor]，设计稿 §4.3 权威口径）。
/// - [write] 失败返回 false，调用方保留原值——绝不能把服务变成「没有凭据」。
/// - Android 侧按包默认最佳实践开 `encryptedSharedPreferences`（Keystore 支撑）。
/// - [CredentialVault.inMemory] 为测试注入版：Map 后端 + [failNextWrite] 钩子
///   （既定坑：真实加密存储没有测试平台通道实现，widget/单测一律注入内存版）。
class CredentialVault {
  /// 真实后端：flutter_secure_storage 包装。
  factory CredentialVault({
    AndroidOptions options =
        const AndroidOptions(encryptedSharedPreferences: true),
  }) =>
      CredentialVault._(FlutterSecureStorage(aOptions: options), null);

  /// 测试版：内存 Map 后端，全程零平台通道。
  factory CredentialVault.inMemory() =>
      CredentialVault._(null, <String, String>{});

  CredentialVault._(this._storage, this._mem);

  static const _keyPrefix = 'sync_secret_';

  /// 凭据键约定：`sync_secret_{serviceId}`（设计稿 §4.3）。
  static String keyFor(String serviceId) => '$_keyPrefix$serviceId';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _mem;

  /// 仅内存版测试钩子：置 true 让下一次 [write] 失败并自动复位（模拟保险箱异常）。
  bool failNextWrite = false;

  Future<String?> read(String serviceId) async {
    final mem = _mem;
    if (mem != null) return mem[keyFor(serviceId)];
    return _storage!.read(key: keyFor(serviceId));
  }

  /// 写凭据；成功 true，异常/注入失败 false（R11：失败时调用方保留原值并记日志）。
  Future<bool> write(String serviceId, String secret) async {
    if (failNextWrite) {
      failNextWrite = false;
      return false;
    }
    final mem = _mem;
    if (mem != null) {
      mem[keyFor(serviceId)] = secret;
      return true;
    }
    try {
      await _storage!.write(key: keyFor(serviceId), value: secret);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 删凭据（删服务时清孤儿键）；后端异常静默吞掉，不阻断配置侧删除。
  Future<void> delete(String serviceId) async {
    final mem = _mem;
    if (mem != null) {
      mem.remove(keyFor(serviceId));
      return;
    }
    try {
      await _storage!.delete(key: keyFor(serviceId));
    } catch (_) {
      // 删不掉密钥不算配置删除失败：凭据本就独立于明文侧。
    }
  }
}
