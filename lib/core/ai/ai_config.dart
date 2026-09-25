/// AI 配置持久层（纯 Dart）：总开关、能力矩阵逐项授权、端点与提示词覆盖。
///
/// 隐私红线（需求清单 §6）：总开关默认关；关闭时 [AiService] 一律拒发请求。
/// Key 不在此处——只进 [ai_vault.dart] 的加密保险箱。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 内存快照（不可变）；写回一律经 [AiConfigRepository]。
class AiConfig {
  const AiConfig({
    this.master = false,
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.model = 'deepseek-flash',
    this.protocol = 'openai',
    this.caps = const {},
    this.promptOverrides = const {},
    this.verifyAtMs,
    this.verifyOk = false,
    this.verifyLatencyMs,
    this.verifyReason,
  });

  /// AI 总开关（默认关：未开启时全应用零 AI 请求）。
  final bool master;
  final String baseUrl;
  final String model;

  /// 端点协议：'openai'（Chat Completions）| 'anthropic'（Messages API）。
  final String protocol;

  /// 能力矩阵逐项授权：taskId → 是否授权（缺省=未授权）。
  final Map<String, bool> caps;

  /// 提示词用户覆盖：taskId → (system|user) 模板串。
  final Map<String, Map<String, String>> promptOverrides;

  /// 最近一次连通性验证结果（设置页「验证状态」行展示）。
  final int? verifyAtMs;
  final bool verifyOk;
  final int? verifyLatencyMs;
  final String? verifyReason;

  bool capEnabled(String taskId) => master && (caps[taskId] ?? false);

  /// 端点参数是否配齐（不含总开关：门控由 [capEnabled] + Key 共同决定）。
  bool get readyForRequest =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;
}

class AiConfigRepository {
  const AiConfigRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kMaster = 'ai.master';
  static const _kBaseUrl = 'ai.base_url';
  static const _kModel = 'ai.model';
  static const _kProtocol = 'ai.protocol';
  static const _kCaps = 'ai.caps';
  static const _kPromptPrefix = 'ai.prompt.'; // + taskId
  static const _kVerify = 'ai.verify'; // {atMs,ok,ms,reason}

  AiConfig load() {
    final caps = _decodeBoolMap(_prefs.getString(_kCaps));
    final overrides = <String, Map<String, String>>{};
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_kPromptPrefix)) continue;
      final taskId = key.substring(_kPromptPrefix.length);
      final raw = _prefs.getString(key);
      if (raw == null) continue;
      try {
        final m = jsonDecode(raw);
        if (m is Map) {
          overrides[taskId] = m.map((k, v) => MapEntry('$k', '$v'));
        }
      } catch (_) {
        // 覆盖值损坏：按未覆盖处理，不阻断配置加载。
      }
    }
    final v = _decodeMap(_prefs.getString(_kVerify));
    return AiConfig(
      master: _prefs.getBool(_kMaster) ?? false,
      baseUrl: _prefs.getString(_kBaseUrl) ?? const AiConfig().baseUrl,
      model: _prefs.getString(_kModel) ?? const AiConfig().model,
      protocol: _prefs.getString(_kProtocol) ?? const AiConfig().protocol,
      caps: caps,
      promptOverrides: overrides,
      verifyAtMs: (v['atMs'] as num?)?.toInt(),
      verifyOk: v['ok'] == true,
      verifyLatencyMs: (v['ms'] as num?)?.toInt(),
      verifyReason: v['reason'] as String?,
    );
  }

  Future<void> setMaster(bool on) => _prefs.setBool(_kMaster, on);

  Future<void> setEndpoint({
    required String baseUrl,
    required String model,
    String? protocol,
  }) =>
      Future.wait([
        _prefs.setString(_kBaseUrl, baseUrl.trim()),
        _prefs.setString(_kModel, model.trim()),
        if (protocol != null) _prefs.setString(_kProtocol, protocol),
      ]).then((_) {});

  Future<void> setCap(String taskId, bool on) async {
    final caps = {...load().caps, taskId: on};
    await _prefs.setString(_kCaps, jsonEncode(caps));
  }

  /// 覆盖某能力点的模板（system/user 任一段传 null 表示保持现值/默认）。
  Future<void> setPromptOverride(
      String taskId, String? system, String? user) async {
    final key = '$_kPromptPrefix$taskId';
    final cur = _decodeStringMap(_prefs.getString(key));
    final next = {...cur, 'system': ?system, 'user': ?user};
    await _prefs.setString(key, jsonEncode(next));
  }

  Future<void> clearPromptOverride(String taskId) =>
      _prefs.remove('$_kPromptPrefix$taskId');

  Future<void> setVerifyResult({
    required bool ok,
    required int at,
    int? latencyMs,
    String? reason,
  }) =>
      _prefs.setString(
          _kVerify,
          jsonEncode({
            'atMs': at,
            'ok': ok,
            'ms': ?latencyMs,
            'reason': ?reason,
          }));

  Map<String, bool> _decodeBoolMap(String? raw) {
    final m = _decodeMap(raw);
    return m.map((k, v) => MapEntry(k, v == true));
  }

  Map<String, String> _decodeStringMap(String? raw) {
    final m = _decodeMap(raw);
    return m.map((k, v) => MapEntry(k, '$v'));
  }

  Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final j = jsonDecode(raw);
      return j is Map ? j.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }
}
