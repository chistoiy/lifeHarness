import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'theme_tokens.dart';

/// 单个主题的亮/深两套解析后令牌。`forceDark` 主题只有深态，亮态回落到深态。
class ThemeBundle {
  const ThemeBundle({
    required this.id,
    required this.meta,
    required this.forceDark,
    required this.light,
    required this.dark,
  });

  final String id;
  final ThemeMeta meta;
  final bool forceDark;
  final ThemeTokens light;
  final ThemeTokens dark;

  ThemeTokens pick(bool isDark) => (forceDark || isDark) ? dark : light;
}

/// 全部主题的内存注册表（启动时一次性载入，运行时同步切换）。
class ThemeRegistry {
  ThemeRegistry(this._bundles, this.defaultId);

  final Map<String, ThemeBundle> _bundles;
  final String defaultId;

  Iterable<String> get ids => _bundles.keys;
  List<ThemeBundle> get all => _bundles.values.toList();

  ThemeBundle of(String id) => _bundles[id] ?? _bundles[defaultId]!;
  ThemeBundle get fallback => _bundles[defaultId]!;
  bool contains(String id) => _bundles.containsKey(id);
}

/// 主题加载与解析。负责读取 `assets/themes/index.json` 与各主题 json。
class ThemeRepository {
  const ThemeRepository();

  static const String _assetDir = 'assets/themes';

  /// 载入全部主题。缺失文件回落到简约默认，保证不崩。
  Future<ThemeRegistry> loadAll({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final indexRaw = await _safeString(b, '$_assetDir/index.json');
    final index = indexRaw == null
        ? const <String, dynamic>{'default': 'minimal'}
        : jsonDecode(indexRaw) as Map<String, dynamic>;
    final defaultId = index['default'] as String? ?? 'minimal';
    final ids = (index['themes'] as List?)?.cast<String>() ?? const <String>[];

    // 先解析简约亮态作为回落基准。
    final baseRaw = await _readTokens(b, 'minimal');
    final baseLight = _merge(baseRaw?['tokens'], null);

    final bundles = <String, ThemeBundle>{};
    for (final id in (ids.isEmpty ? [defaultId] : ids)) {
      final raw = await _readTokens(b, id) ?? (id == defaultId ? baseRaw : null);
      if (raw == null) continue;
      final forceDark = raw['forceDark'] == true;
      final meta = _meta(id, raw['meta']);
      final light = ThemeTokens.fromMap(
        id,
        _merge(raw['tokens'], baseLight),
        meta: meta,
      );
      final dark = ThemeTokens.fromMap(
        id,
        _merge(raw['dark'], baseLight),
        meta: meta,
      );
      bundles[id] = ThemeBundle(
        id: id,
        meta: meta,
        forceDark: forceDark,
        light: light,
        dark: dark,
      );
    }

    if (bundles.isEmpty) {
      // 极端兜底：连简约都读不到时用内置默认，避免空注册表。
      final d = ThemeTokens.fromMap('minimal', baseLight);
      bundles['minimal'] = ThemeBundle(
        id: 'minimal',
        meta: const ThemeMeta(name: '简约'),
        forceDark: false,
        light: d,
        dark: d,
      );
    }
    return ThemeRegistry(bundles, bundles.containsKey(defaultId) ? defaultId : bundles.keys.first);
  }

  Future<Map<String, dynamic>?> _readTokens(AssetBundle b, String id) async {
    final s = await _safeString(b, '$_assetDir/$id.json');
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _safeString(AssetBundle b, String key) async {
    try {
      return await b.loadString(key);
    } catch (_) {
      return null;
    }
  }

  /// 深态覆盖亮态：dark 组缺失的键回落。返回扁平令牌 map。
  Map<String, dynamic> _merge(Object? tokens, Map<String, dynamic>? fallback) {
    final out = <String, dynamic>{...?fallback};
    if (tokens is Map) {
      tokens.forEach((k, v) => out['$k'] = v);
    }
    return out;
  }

  ThemeMeta _meta(String id, Object? raw) {
    if (raw is Map) {
      return ThemeMeta(
        name: raw['name'] as String? ?? id,
        ver: raw['ver'] as String? ?? '1.0',
        author: raw['author'] as String? ?? '',
        license: raw['license'] as String? ?? '',
      );
    }
    return ThemeMeta(name: id);
  }
}
