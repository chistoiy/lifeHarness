/// R3-6 · 一键简繁（**仅阅读器正文显示层**）。
///
/// 需求口径（工单 R3-6 已拍板）：只转「段文本 → 上屏」这最后一公里——
/// 库存原文、书摘/摘录、检索、X-Ray 解析与词表一律不动。
///
/// 两条硬约束：
/// 1. **逐字等长**：源文本与转换结果长度必须相同，且第 i 位仍对应原文第 i 位。
///    选区、划线、链接命中、书摘都按原文偏移切片，一旦变长就全体错位。
///    因此生成期丢掉了所有变长词组（见 `tools/reader/gen_s2t.py`），运行时再兜一道
///    `assert`；非汉字（标点/数字/拉丁）原样输出。
/// 2. **单点通道**：所有上屏与测量都走 [paraBody]/[paraDisplayText]，不许各自调转换器
///    （两边分叉＝按转换后的字排页、按原文画页＝溢出/空页）。
///
/// 词表：`assets/read_s2t/s2t.json`（zhconv 1.4.3 数据，**仅生成期使用**，运行时零依赖）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 三档口径与 [ReaderCfg.s2t] 同字面量：跟随原书 / 简体 / 繁体。
const String kS2TOrig = 'orig';
const String kS2TSimp = 's';
const String kS2TTrad = 't';

/// 一套方向的表：逐字兜底 + 短语择字（最长优先）+ 短语最大长度。
class S2tTable {
  const S2tTable({required this.chars, required this.phrases, required this.maxPhrase});

  static const S2tTable empty = S2tTable(
      chars: {}, phrases: {}, maxPhrase: 0);

  final Map<String, String> chars;
  final Map<String, String> phrases;
  final int maxPhrase;

  factory S2tTable.fromJson(Map<String, dynamic> j) {
    final src = j['chars'] as String? ?? '';
    final dst = j['to'] as String? ?? '';
    final sr = src.runes.toList(), dr = dst.runes.toList();
    assert(sr.length == dr.length, 's2t 资产逐字表面长度不等');
    final c = <String, String>{};
    final n = sr.length < dr.length ? sr.length : dr.length;
    for (var i = 0; i < n; i++) {
      final t = String.fromCharCode(dr[i]);
      // 非 BMP 目标（如扩展 B 区 𣌶）在 Dart 里占 2 个码元 → 会把选区/划线/
      // 书摘的下标整体挪一位。生成期已滤（gen_s2t.py 的 u16），这里再兜一道。
      if (t.length != 1) continue;
      c[String.fromCharCode(sr[i])] = t;
    }
    final phr = <String, String>{};
    var mx = 0;
    for (final e in (j['phr'] as List? ?? const [])) {
      final s = '$e';
      final bar = s.indexOf('|');
      // 「src|tgt」两侧码元数必须相等（偏移红线），且词组至少 2 字
      // （单字条目运行时永远轮不到——匹配从 len>1 起，留着就是死重量）。
      if (bar < 2 || bar != s.length - bar - 1) continue;
      phr[s.substring(0, bar)] = s.substring(bar + 1);
      if (bar > mx) mx = bar;
    }
    return S2tTable(chars: c, phrases: phr, maxPhrase: mx);
  }

  /// 贪心最长匹配：先试短语（解决 干→幹/乾、发→發/髮 这类一简对多繁），
  /// 落单字走逐字表，表里没有的原样输出（含标点、数字、拉丁与已同形的汉字）。
  String apply(String s) {
    if (s.isEmpty || (chars.isEmpty && phrases.isEmpty)) return s;
    final out = StringBuffer();
    var i = 0;
    final n = s.length;
    while (i < n) {
      var hit = false;
      // 起始长度＝「剩余可读长度」与「表内最长词组」取小；把越界判断写进循环
      // 继续条件会让短段（整段不足最长词组长）一次都试不到词组——真机表现是
      // 「词表装了但择字全不生效」，只走逐字兜底。
      final cap = (n - i) < maxPhrase ? (n - i) : maxPhrase;
      for (var len = cap; len > 1; len--) {
        final sub = s.substring(i, i + len);
        final v = phrases[sub];
        if (v != null) {
          out.write(v);
          i += len;
          hit = true;
          break;
        }
      }
      if (hit) continue;
      final ch = s[i];
      out.write(chars[ch] ?? ch);
      i++;
    }
    final r = out.toString();
    // 偏移红线兜底：任何情况下长度都不许变（真机炸在选区/命中上比这条 assert 贵得多）。
    assert(r.length == s.length, '简繁转换改变了长度：$s → $r');
    return r;
  }
}

/// 显示层转换入口（进程内单例表 + 结果缓存）。
class S2t {
  S2t._();

  static S2tTable _s2t = S2tTable.empty;
  static S2tTable _t2s = S2tTable.empty;
  static bool _loaded = false;
  static final Map<String, String> _cache = {};

  static const String assetPath = 'assets/read_s2t/s2t.json';

  /// 表是否已就位（未就位时 [convert] 回落原文，绝不报错——阅读不能因词表失败而白屏）。
  static bool get ready => _loaded;

  /// 加载词表（首帧前由阅读器装载链 await 一次；重复调用零成本）。
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(assetPath);
      installFromJson(raw);
    } catch (e) {
      // catch-ok: 词表缺失/坏档时简繁切换退化成「跟随原书」，正文照常渲染。
      debugPrint('S2t 词表加载失败，简繁切换暂不可用: $e');
    }
  }

  /// 从 JSON 文本装表（测试注入与真机加载共用同一协议，夹具不另跑一遍握手）。
  @visibleForTesting
  static void installFromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    _s2t = S2tTable.fromJson((m['s2t'] ?? const {}) as Map<String, dynamic>);
    _t2s = S2tTable.fromJson((m['t2s'] ?? const {}) as Map<String, dynamic>);
    _loaded = true;
    _cache.clear();
  }

  /// 直接注表（纯逻辑用例免资产 IO）。
  @visibleForTesting
  static void installTables({required S2tTable toTrad, required S2tTable toSimp}) {
    _s2t = toTrad;
    _t2s = toSimp;
    _loaded = true;
    _cache.clear();
  }

  @visibleForTesting
  static void resetForTest() {
    _s2t = S2tTable.empty;
    _t2s = S2tTable.empty;
    _loaded = false;
    _cache.clear();
  }

  /// 按档位转换（只有 kS2TSimp / kS2TTrad 两个已知档动手，其余一律原文——
  /// 未知值当成简体用会让脏配置悄悄改字面）。
  static String convert(String text, String mode) {
    if (text.isEmpty || !_loaded) return text;
    final trad = mode == kS2TTrad;
    if (!trad && mode != kS2TSimp) return text;
    final key = '${trad ? 't' : 's'}\u0000$text';
    final hit = _cache[key];
    if (hit != null) return hit;
    final out = trad ? _s2t.apply(text) : _t2s.apply(text);
    // 段文本重复率高（测量与上屏来回调），缓存键含档位；超上限整体丢弃重建，
    // 不做一个会涨到天上去的 Map（阅读器整本预载时段落数以万计）。
    if (_cache.length > 4000) _cache.clear();
    _cache[key] = out;
    return out;
  }

  @visibleForTesting
  static int get cacheSize => _cache.length;
}
