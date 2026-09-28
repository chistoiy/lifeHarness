/// AI 配置持久层（纯 Dart）：总开关、能力矩阵逐项授权、**服务商列表**与提示词覆盖。
///
/// 隐私红线（需求清单 §六）：总开关默认关；关闭时 [AiService] 一律拒发请求。
/// Key 不在此处——只进 [ai_vault.dart] 的加密保险箱（V1.53.1 起按服务商分域）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一个 AI 服务商条目（V1.53.1）：名称 + Base URL + 模型 + 协议。
///
/// 预置只是**首次种子**，不是白名单：用户可改可删可加（中转站、局域网 Ollama 等
/// 任意 OpenAI 兼容 / Anthropic 端点），改过后不再被预置覆盖。
class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.protocol = 'openai',
    this.builtin = false,
  });

  factory AiProvider.fromJson(Map<String, dynamic> j) => AiProvider(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? '未命名端点'}',
        baseUrl: '${j['baseUrl'] ?? ''}',
        model: '${j['model'] ?? ''}',
        protocol: j['protocol'] == 'anthropic' ? 'anthropic' : 'openai',
        builtin: j['builtin'] == true,
      );

  final String id;
  final String name;

  /// 完整前缀（含 `/v1` 等），请求按协议再拼 `/chat/completions` 或 `/messages`。
  final String baseUrl;
  final String model;

  /// 'openai'（Chat Completions）| 'anthropic'（Messages API）。
  final String protocol;

  /// 预置条目（UI 打标；删除后自动掉标，不影响功能）。
  final bool builtin;

  bool get isAnthropic => protocol == 'anthropic';

  /// 明文 http 端点：只建议局域网/回环，UI 侧要求二次确认（原则 2「端点自治」的边界）。
  bool get isPlainHttp => baseUrl.trim().toLowerCase().startsWith('http://');

  /// 展示用 host[:port]；解析不出来就原样给回（绝不让 UI 因脏数据崩）。
  String get host {
    final u = Uri.tryParse(baseUrl.trim());
    final h = u?.host ?? '';
    if (h.isEmpty) return baseUrl;
    final port = u!.hasPort ? ':${u.port}' : '';
    return '$h$port';
  }

  AiProvider copyWith({
    String? name,
    String? baseUrl,
    String? model,
    String? protocol,
    bool? builtin,
  }) =>
      AiProvider(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        protocol: protocol ?? this.protocol,
        builtin: builtin ?? this.builtin,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
        'protocol': protocol,
        if (builtin) 'builtin': true,
      };
}

/// 端点归一化：忽略末尾斜杠与首尾空格（比对与落盘统一口径）。
String aiNormBase(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

/// 预置种子（无 `ai.providers` 落盘数据时派生）。
const kAiProviderSeeds = <AiProvider>[
  AiProvider(id: 'deepseek', name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-flash', builtin: true),
  AiProvider(id: 'openai', name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', builtin: true),
  AiProvider(id: 'anthropic', name: 'Anthropic claude',
      baseUrl: 'https://api.anthropic.com/v1', model: 'claude-3-5-haiku-latest',
      protocol: 'anthropic', builtin: true),
  AiProvider(id: 'kimi', name: 'Moonshot Kimi',
      baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8s', builtin: true),
  AiProvider(id: 'qwen', name: '通义千问',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-turbo',
      builtin: true),
  AiProvider(id: 'glm', name: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash', builtin: true),
  AiProvider(id: 'ollama', name: 'Ollama（本地）',
      baseUrl: 'http://127.0.0.1:11434/v1', model: 'qwen2.5:7b', builtin: true),
];

/// 旧版本单值端点匹配不到预置时合成的条目 id（升级兼容用）。
const kAiCustomProviderId = 'custom';

/// 内存快照（不可变）；写回一律经 [AiConfigRepository]。
class AiConfig {
  const AiConfig({
    this.master = false,
    this.providers = kAiProviderSeeds,
    this.activeProviderId = 'deepseek',
    this.caps = const {},
    this.promptOverrides = const {},
    this.verifyAtMs,
    this.verifyOk = false,
    this.verifyLatencyMs,
    this.verifyReason,
  });

  /// AI 总开关（默认关：未开启时全应用零 AI 请求）。
  final bool master;

  /// 服务商列表（含预置与用户自增）。
  final List<AiProvider> providers;

  /// 当前激活服务商 id。
  final String activeProviderId;

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

  /// 激活服务商（列表空/找不到时回落第一条，保证永不为 null）。
  AiProvider get active {
    for (final p in providers) {
      if (p.id == activeProviderId) return p;
    }
    return providers.isEmpty ? kAiProviderSeeds.first : providers.first;
  }

  /// 端点三要素＝激活条目（业务侧与 [AiService] 只读这三个字段，与 V1.53.1 前同源）。
  String get baseUrl => active.baseUrl;
  String get model => active.model;
  String get protocol => active.protocol;

  /// 端点参数是否配齐（不含总开关：门控由 [capEnabled] + Key 共同决定）。
  bool get readyForRequest =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 生成新 id（用户自增条目）。
  static String newId(String baseUrl) {
    final host = Uri.tryParse(baseUrl.trim())?.host ?? '';
    final base = host.isEmpty
        ? 'prov'
        : host.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    return '$base-${DateTime.now().millisecondsSinceEpoch % 100000}';
  }
}

class AiConfigRepository {
  const AiConfigRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kMaster = 'ai.master';
  static const _kProviders = 'ai.providers';
  static const _kActiveProv = 'ai.activeProvider';
  static const _kCaps = 'ai.caps';
  static const _kPromptPrefix = 'ai.prompt.'; // + taskId
  static const _kVerify = 'ai.verify'; // {atMs,ok,ms,reason}
  // 旧版单值键（只读迁移来源，V1.53.1 起不再写入）
  static const _kBaseUrl = 'ai.base_url';
  static const _kModel = 'ai.model';
  static const _kProtocol = 'ai.protocol';

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
    final stored = _decodeProviders(_prefs.getString(_kProviders));
    final v = _decodeMap(_prefs.getString(_kVerify));
    if (stored.isNotEmpty) {
      return AiConfig(
        master: _prefs.getBool(_kMaster) ?? false,
        providers: stored,
        activeProviderId: _prefs.getString(_kActiveProv) ?? stored.first.id,
        caps: caps,
        promptOverrides: overrides,
        verifyAtMs: (v['atMs'] as num?)?.toInt(),
        verifyOk: v['ok'] == true,
        verifyLatencyMs: (v['ms'] as num?)?.toInt(),
        verifyReason: v['reason'] as String?,
      );
    }
    // 未落过 providers：按旧单值键派生，保证升级后用户原端点不被预置顶掉。
    final legacyUrl = aiNormBase(_prefs.getString(_kBaseUrl) ?? '');
    final legacyModel = (_prefs.getString(_kModel) ?? '').trim();
    final legacyProto = _prefs.getString(_kProtocol) ?? 'openai';
    final ps = [...kAiProviderSeeds];
    var active = 'deepseek';
    if (legacyUrl.isNotEmpty) {
      final hit = ps.where((p) => aiNormBase(p.baseUrl) == legacyUrl).firstOrNull;
      if (hit != null) {
        active = hit.id;
        // 旧版可单独改模型名/协议：迁移时一并保住，否则升级即丢用户配置。
        if (legacyModel.isNotEmpty && legacyModel != hit.model.trim()) {
          ps[ps.indexOf(hit)] = hit.copyWith(
              model: legacyModel,
              protocol: legacyProto == 'anthropic' ? 'anthropic' : null);
        }
      } else {
        ps.add(AiProvider(
            id: kAiCustomProviderId,
            name: '自定义端点',
            baseUrl: legacyUrl,
            model: legacyModel,
            protocol: legacyProto));
        active = kAiCustomProviderId;
      }
    } else if (_prefs.getString(_kActiveProv) != null) {
      active = _prefs.getString(_kActiveProv)!;
    }
    return AiConfig(
      master: _prefs.getBool(_kMaster) ?? false,
      providers: ps,
      activeProviderId: active,
      caps: caps,
      promptOverrides: overrides,
      verifyAtMs: (v['atMs'] as num?)?.toInt(),
      verifyOk: v['ok'] == true,
      verifyLatencyMs: (v['ms'] as num?)?.toInt(),
      verifyReason: v['reason'] as String?,
    );
  }

  Future<void> setMaster(bool on) => _prefs.setBool(_kMaster, on);

  /// 增/改一条服务商（按 id 覆盖；整表落盘即完成 providers 迁移）。
  Future<void> saveProvider(AiProvider p) async {
    final cur = load();
    final list = [...cur.providers];
    final i = list.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      list[i] = p;
    } else {
      list.add(p);
    }
    await _prefs.setString(
        _kProviders, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  /// 切换激活服务商（id 必须存在于列表）。
  Future<bool> useProvider(String id) async {
    final cur = load();
    if (!cur.providers.any((p) => p.id == id)) return false;
    await _prefs.setString(_kActiveProv, id);
    return true;
  }

  /// 删除服务商；**激活项拒删**（防把唯一可用配置删没）。连带清 Key 由调用方走 vault。
  Future<bool> deleteProvider(String id) async {
    final cur = load();
    if (cur.activeProviderId == id) return false;
    final list = cur.providers.where((p) => p.id != id).toList();
    if (list.length == cur.providers.length) return false; // 不存在
    await _prefs.setString(
        _kProviders, jsonEncode(list.map((e) => e.toJson()).toList()));
    return true;
  }

  /// 旧签名兼容：改「当前服务商」的端点三要素（AI 增强页与既有测试仍用它）。
  Future<void> setEndpoint({
    required String baseUrl,
    required String model,
    String? protocol,
  }) =>
      saveProvider(load().active.copyWith(
        baseUrl: baseUrl.trim(),
        model: model.trim(),
        protocol: protocol,
      ));

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

  List<AiProvider> _decodeProviders(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      final out = j
          .whereType<Map>()
          .map((e) => AiProvider.fromJson(e.cast<String, dynamic>()))
          .where((p) => p.baseUrl.trim().isNotEmpty)
          .toList();
      return out;
    } catch (_) {
      // 脏数据：回落到预置种子，AI 功能仍可用，不阻断启动。
      return const [];
    }
  }

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
