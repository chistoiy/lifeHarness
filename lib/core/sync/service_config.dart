import 'dart:convert';

import 'package:lifeharness/core/logging/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credential_vault.dart';

/// 云存储协议种类（协议文档 §3 的 `StoreProvider`，加 Kind 后缀避开 Flutter
/// Widget 层的 Provider 命名；分发口径见 R2/R3）。
enum StoreProviderKind { webdav, s3 }

/// 一条云盘服务配置（协议文档 §3 ServiceConfig + cloudDirName 映射）。
///
/// 本任务唯一口径（brief）：一条记录即一个「服务 + 目录」映射。
/// **无 authCode 字段**——凭据只走 [CredentialVault]（D1/R11）。旧明文数据里
/// 残留的 `authCode` 键：读取时容忍并忽略（R4 兼容），保存时一律剔除（D1 取舍，
/// 见 task-11 报告）。
class ServiceConfig {
  ServiceConfig({
    required this.id,
    this.provider = StoreProviderKind.webdav,
    this.apiUrl = '',
    this.account = '',
    this.region = '',
    this.bucket = '',
    this.cloudDirName = '',
    this.requestIntervalMs = defaultRequestIntervalMs,
    this.verifyContent = false,
  });

  /// 控流默认档（§4.2 档位 150/300/800，默认 300）。
  static const defaultRequestIntervalMs = 300;

  String id;

  /// 决定协议分发与表单字段（R2/R3）。
  StoreProviderKind provider;

  /// WebDAV 根 / S3 endpoint（含 scheme）。
  String apiUrl;

  /// WebDAV 账户邮箱 / S3 Access Key（R3 同名复用，标签随协议切换）。
  String account;

  /// 仅 S3；缤纷云目前只有 cn-east-1。
  String region;

  /// 仅 S3，同时是 virtual-hosted 的域名前缀。
  String bucket;

  /// 云端目录名（跨服务允许同名，判重见 [endpointKey]）。
  String cloudDirName;

  /// 请求最小间隔（毫秒），按服务配（R10）。
  int requestIntervalMs;

  /// R8 第③档严格 MD5 校验开关，默认关。
  bool verifyContent;

  bool get isS3 => provider == StoreProviderKind.s3;

  /// 「同服务 id 下 cloudDirName 唯一」钉死后的判重端点键（见 task-11 报告）：
  /// provider + apiUrl（去尾斜杠归一）+ bucket；跨 provider 天然不同键可同名。
  String get endpointKey =>
      '${provider.name}|${apiUrl.replaceAll(RegExp(r'/+$'), '')}|$bucket';

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider.name,
        'apiUrl': apiUrl,
        'account': account,
        'region': region,
        'bucket': bucket,
        'cloudDirName': cloudDirName,
        'requestIntervalMs': requestIntervalMs,
        'verifyContent': verifyContent,
        // 刻意不写 authCode（D1：保存时剔除明文占位残留）。
      };

  /// R4：缺 provider/region/bucket/节奏字段一律落 WebDAV 默认，旧数据原样可读；
  /// 残留的 authCode 键容忍读取（忽略不入内存模型）。
  factory ServiceConfig.fromJson(Map<String, dynamic> m) => ServiceConfig(
        id: m['id'] as String? ?? '',
        provider: m['provider'] == StoreProviderKind.s3.name
            ? StoreProviderKind.s3
            : StoreProviderKind.webdav,
        apiUrl: m['apiUrl'] as String? ?? '',
        account: m['account'] as String? ?? '',
        region: m['region'] as String? ?? '',
        bucket: m['bucket'] as String? ?? '',
        cloudDirName: m['cloudDirName'] as String? ?? '',
        requestIntervalMs: _intervalOf(m['requestIntervalMs']),
        verifyContent: m['verifyContent'] == true,
      );

  static int _intervalOf(Object? v) => switch (v) {
        final num n when n.toInt() > 0 => n.toInt(),
        final String s when int.tryParse(s) != null && int.parse(s) > 0 =>
          int.parse(s),
        _ => defaultRequestIntervalMs,
      };
}

/// [SyncConfigStore.load] 的返回：服务列表 + 当前激活 id。
class SyncConfigSnapshot {
  const SyncConfigSnapshot({required this.services, this.activeId});

  final List<ServiceConfig> services;
  final String? activeId;
}

/// prefs 单键 `sync_services` 的 JSON 存储：`{services:[...], activeId}`。
///
/// 不变式（§4.3 / brief）：
/// - id 全局唯一；同 [ServiceConfig.endpointKey] 端点下 cloudDirName 唯一
///   （跨 provider / 跨端点可同名）。冲突抛 [StateError]，不落盘。
/// - activeId 指向被删服务时回落第一条（列表空则 null）。
/// - 凭据只进 [CredentialVault]：[saveService] 先写保险箱，写失败返回 false
///   且配置原样保留（R11），成功才清明文侧语义（本实现明文侧从未存凭据）。
class SyncConfigStore {
  SyncConfigStore(this._prefs, {required CredentialVault vault})
      : _vault = vault;

  static const servicesKey = 'sync_services';

  final SharedPreferences _prefs;
  final CredentialVault _vault;

  /// 容错读取：坏 JSON / 缺字段按 R4 落默认；activeId 悬空回落第一条。
  SyncConfigSnapshot load() {
    final raw = _prefs.getString(servicesKey);
    if (raw == null || raw.isEmpty) {
      return const SyncConfigSnapshot(services: []);
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const SyncConfigSnapshot(services: []);
      final list = (data['services'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ServiceConfig.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      var activeId = data['activeId'] as String?;
      if (activeId != null && !list.any((c) => c.id == activeId)) {
        activeId = list.isEmpty ? null : list.first.id;
      }
      return SyncConfigSnapshot(services: list, activeId: activeId);
    } catch (_) {
      return const SyncConfigSnapshot(services: []);
    }
  }

  /// 校验并整表落盘（序列化即剔除任何 authCode 残留，D1）。冲突抛 [StateError]。
  Future<void> save(SyncConfigSnapshot snap) async {
    _validate(snap.services);
    await _prefs.setString(
      servicesKey,
      jsonEncode({
        'services': snap.services.map((c) => c.toJson()).toList(),
        'activeId': snap.activeId,
      }),
    );
  }

  /// 新增或按 id 原地更新一条服务。
  ///
  /// [secret] 非空时先写保险箱（R11）：写失败返回 false，vault 与明文侧全部
  /// 保留原值并记日志；判重冲突抛 [StateError]（校验先于任何写入，不留孤儿键）。
  /// 列表原本无激活项时，新服务自动成为激活。
  Future<bool> saveService(ServiceConfig cfg, {String? secret}) async {
    final snap = load();
    final services = List<ServiceConfig>.of(snap.services);
    final at = services.indexWhere((c) => c.id == cfg.id);
    if (at >= 0) {
      services[at] = cfg;
    } else {
      services.add(cfg);
    }
    _validate(services); // 先验证再写凭据，冲突不污染 vault
    if (secret != null && secret.isNotEmpty) {
      final ok = await _vault.write(cfg.id, secret);
      if (!ok) {
        AppLog.add('保险箱写入失败，服务 ${cfg.id} 保留原凭据与原配置（R11）',
            level: LhLevel.warn);
        return false;
      }
    }
    final activeId = snap.activeId ?? cfg.id;
    await save(SyncConfigSnapshot(services: services, activeId: activeId));
    return true;
  }

  /// 删除服务：同步清 `service_secret_{id}` 孤儿键（D1）；activeId 指向被删
  /// 服务时回落第一条（列表空则 null）。
  Future<void> removeService(String id) async {
    final snap = load();
    final services = snap.services.where((c) => c.id != id).toList();
    await _vault.delete(id);
    final activeId =
        snap.activeId == id ? (services.isEmpty ? null : services.first.id) : snap.activeId;
    await save(SyncConfigSnapshot(services: services, activeId: activeId));
  }

  /// 切换当前激活服务（§4.3 单一「当前激活」）。id 不存在抛 [StateError]。
  Future<void> setActive(String id) async {
    final snap = load();
    if (!snap.services.any((c) => c.id == id)) {
      throw StateError('激活失败：服务 $id 不存在');
    }
    await save(SyncConfigSnapshot(services: snap.services, activeId: id));
  }

  static void _validate(List<ServiceConfig> services) {
    final ids = <String>{};
    final dirs = <String>{};
    for (final c in services) {
      if (!ids.add(c.id)) {
        throw StateError('服务 id 重复：${c.id}');
      }
      final key = '${c.endpointKey}|${c.cloudDirName}';
      if (!dirs.add(key)) {
        throw StateError('同端点下云端目录重复：${c.cloudDirName}（${c.endpointKey}）');
      }
    }
  }
}
