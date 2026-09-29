// Legado 书源规则子集引擎 · 预研探针（独立于 lifeHarness 工程，不进其依赖链）
//
// 覆盖规则语法：
//   class.x / id.x / tag.a / CSS 选择器 + 索引 .0 .-1 [a:b]
//   @href @src @content 等属性步、text / html、text.关键词[.idx] 文本定位
//   mini xpath（//tag[@a='v']/@attr、child/following-sibling/parent、[last()]）
//   && 并联聚合、| 优先、|| 聚合、##正则##替换 净化
//   {{key}} {{page}} 模板、搜索配置 ,{'method':'POST','body':'','charset':'gbk'}
//   章内 nextContentUrl 翻页、目录 nextTocUrl 翻页、Cookie 粗粒度保持
// 明确不支持（检测到即抛 UnsupportedRule，便于按源统计覆盖率）：
//   @js: / <js> 嗅探 / evalJs / useWebView / ruleStyle 字体反混淆
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as htmlparser;
import 'package:http/http.dart' as http;
import 'package:fast_gbk/fast_gbk.dart' as gbkpkg;

import 'jsbridge.dart';

// ---------- 期4：JSON API 通道辅助 ----------
bool _looksJson(String t) {
  final s = t.trimLeft();
  return s.startsWith('{') || s.startsWith('[');
}

dynamic _jsonAt(dynamic root, String path) {
  var cur = root;
  final rel = path.replaceFirst(RegExp(r'^\$\.?'), '');
  if (rel.isEmpty) return cur;
  for (final seg in rel.split('.')) {
    if (seg.isEmpty) continue;
    final m = RegExp(r'^(\w+)\[(-?\d+)\]$').firstMatch(seg);
    if (m != null) {
      final key = m.group(1)!;
      var idx = int.parse(m.group(2)!);
      cur = cur is Map ? cur[key] : cur;
      if (cur is! List) return null;
      if (idx < 0) idx += cur.length;
      cur = idx >= 0 && idx < cur.length ? cur[idx] : null;
    } else {
      cur = cur is Map ? cur[seg] : null;
    }
    if (cur == null) return null;
  }
  return cur;
}

String _tplJson(String s, Map? item, dynamic ctx) =>
    s.replaceAllMapped(RegExp(r'\{\{\$?\.?([\w_]+)\}\}'), (m) {
      final k = m.group(1)!;
      final v = item != null && item[k] != null
          ? item[k]
          : (ctx is Map ? ctx[k] : null);
      return v == null ? '' : '$v';
    });

const kDesktopUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

String _cut(String s) => s.length > 70 ? '${s.substring(0, 70)}…' : s;

class UnsupportedRule implements Exception {
  UnsupportedRule(this.msg);
  final String msg;
  @override
  String toString() => '不支持的规则: $msg';
}

/// ---------- HTTP ----------
class FetchResult {
  FetchResult({
    required this.url,
    required this.status,
    required this.body,
    this.charsetHint,
  });

  final String url;
  final int status;
  final List<int> body;
  final String? charsetHint;

  /// 优先显式 charset，其次响应头，最后嗅探 meta。
  String text() {
    var cs = (charsetHint ?? '').toLowerCase();
    final known = cs.contains('gb') || cs.contains('utf');
    if (!known) {
      final head = String.fromCharCodes(body.take(4096));
      final m = RegExp(
        r'''charset\s*=\s*["']?([\w-]+)''',
        caseSensitive: false,
      ).firstMatch(head);
      cs = (m?.group(1) ?? 'utf-8').toLowerCase();
    }
    if (cs.contains('gbk') || cs.contains('gb2312') || cs.contains('gb18030')) {
      try {
        return gbkpkg.gbk.decode(body);
      } catch (_) {}
    }
    return utf8.decode(body, allowMalformed: true);
  }
}

class HttpCtx {
  HttpCtx({this.verbose = false});

  final bool verbose;
  final client = http.Client();
  final Map<String, String> _cookies = {}; // host → "k=v"

  Future<FetchResult> fetch(
    String url, {
    String method = 'GET',
    List<int>? bodyBytes,
    String? bodyContentType,
    Map<String, String> headers = const {},
    String? charsetHint,
    int depth = 0,
  }) async {
    final u = Uri.parse(url);
    final h = <String, String>{'User-Agent': kDesktopUA, ...headers};
    final jar = _cookieFor(u.host);
    if (jar.isNotEmpty) h['Cookie'] = jar;
    final req = http.Request(method, u)..headers.addAll(h);
    if (bodyBytes != null) {
      req.bodyBytes = bodyBytes;
      req.headers['Content-Type'] =
          bodyContentType ?? 'application/x-www-form-urlencoded';
    }
    if (verbose) stderr.writeln('  -> $method $url');
    final streamed =
        await client.send(req).timeout(const Duration(seconds: 25));
    final res = await http.Response.fromStream(streamed);
    _absorbCookies(u.host, res.headers['set-cookie']);
    final loc = res.headers['location'];
    if (res.statusCode >= 300 &&
        res.statusCode < 400 &&
        loc != null &&
        depth < 5) {
      return fetch(
        u.resolve(loc).toString(),
        method: method,
        bodyBytes: bodyBytes,
        bodyContentType: bodyContentType,
        headers: headers,
        charsetHint: charsetHint,
        depth: depth + 1,
      );
    }
    return FetchResult(
      url: res.request?.url.toString() ?? url,
      status: res.statusCode,
      body: res.bodyBytes,
      charsetHint: charsetHint ?? res.headers['content-type'],
    );
  }

  /// 粗粒度：同名 Cookie 覆盖。
  void _absorbCookies(String host, String? raw) {
    if (raw == null) return;
    for (final part in _splitSetCookie(raw)) {
      final kv = part.split(';').first.trim();
      final eq = kv.indexOf('=');
      if (eq <= 0) continue;
      final name = kv.substring(0, eq);
      _cookies.removeWhere(
        (h, v) => v.split(';').first.split('=').first == name,
      );
      if (kv.substring(eq + 1).isNotEmpty) _cookies[host] = kv;
    }
  }

  /// Set-Cookie 可能多条且值内含逗号（Expires）：引号感知切分。
  List<String> _splitSetCookie(String raw) {
    final out = <String>[];
    var cur = '';
    var inQuote = false;
    for (final ch in raw.split('')) {
      if (ch == '"') inQuote = !inQuote;
      if (ch == ',' && !inQuote) {
        out.add(cur);
        cur = '';
        continue;
      }
      cur += ch;
    }
    out.add(cur);
    return out.map((e) => e.trim()).where((e) => e.contains('=')).toList();
  }

  String _cookieFor(String host) {
    final parts = <String>[];
    _cookies.forEach((h, v) {
      if (host == h || host.endsWith('.$h') || h.endsWith('.$host')) {
        parts.add(v);
      }
    });
    return parts.join('; ');
  }
}

/// ---------- 值节点（元素 or 文本） ----------
abstract class Val {
  String text();
  String? attr(String name);
}

class ElVal implements Val {
  ElVal(this.el);

  final Element el;

  @override
  String text() => el.text.trim();

  @override
  String? attr(String name) {
    for (final e in el.attributes.entries) {
      if (e.key.toString() == name) return e.value.toString();
    }
    for (final e in el.attributes.entries) {
      if (e.key.toString().toLowerCase() == name.toLowerCase()) {
        return e.value.toString();
      }
    }
    return null;
  }

  @override
  String toString() => 'El(${el.localName})';
}

class StrVal implements Val {
  StrVal(this.v);

  final String v;

  @override
  String text() => v.trim();

  @override
  String? attr(String _) => null;

  @override
  String toString() => 'Str(${_cut(v)})';
}

/// ---------- 规则求值器 ----------
class Analyzer {
  Analyzer(this.base);

  /// bookSourceUrl，作为相对链接基准
  final String base;

  List<String> eval(String rule, Document doc) =>
      evalNodes(rule, doc).map((v) => v.text()).toList();

  List<String> evalIn(String rule, List<Val> scope, Document doc) =>
      _evalVals(rule, scope, doc).map((v) => v.text()).toList();

  List<Val> evalNodes(String rule, Document doc) =>
      _evalVals(rule, [ElVal(doc.documentElement!)], doc);

  List<Val> _evalVals(String rule, List<Val> seeds, Document doc) {
    if (rule.trim().isEmpty) return const [];
    _assertSupported(rule);
    final out = <Val>[];
    for (final agg in _splitTop(rule, '||')) {
      out.addAll(_evalOrChain(agg, seeds, doc));
    }
    return out;
  }

  /// 单 '|' 链：取首个非空分支
  List<Val> _evalOrChain(String chain, List<Val> seeds, Document doc) {
    for (final alt in _splitTop(chain, '|')) {
      final out = _evalAndChain(alt.trim(), seeds, doc);
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// '&&'：各段结果顺序拼接
  List<Val> _evalAndChain(String expr, List<Val> seeds, Document doc) {
    final parts = _splitTop(expr, '&&');
    if (parts.length > 1) {
      final out = <Val>[];
      for (final p in parts) {
        out.addAll(_evalSeq(p.trim(), seeds, doc));
      }
      return out;
    }
    return _evalSeq(expr, seeds, doc);
  }

  /// '@' 段链求值 + 尾部 ## 净化
  List<Val> _evalSeq(String expr, List<Val> seeds, Document doc) {
    final segs = _splitSegments(expr);
    if (segs.isEmpty) return const [];
    var cur = seeds;
    String? cleaner;
    for (final raw in segs) {
      var seg = raw;
      final hash = _findTop(seg, '##');
      if (hash >= 0) {
        cleaner = seg.substring(hash + 2);
        seg = seg.substring(0, hash);
      }
      if (seg.isEmpty) continue;
      final next = <Val>[];
      for (final node in cur) {
        next.addAll(_applySeg(node, seg, doc));
      }
      cur = next;
      if (cur.isEmpty) return const [];
    }
    if (cleaner == null) return cur;
    final texts = _cleanReplace([for (final v in cur) v.text()], cleaner);
    return [for (final t in texts) StrVal(t)];
  }

  void _assertSupported(String rule) {
    final low = rule.toLowerCase();
    if (low.contains('@js:') ||
        low.contains('<js>') ||
        low.contains('@evaljs') ||
        low.contains('usewebview')) {
      throw UnsupportedRule(_cut(rule));
    }
  }

  /// 顶层分隔符拆分（跳过引号与 [] () {} 内部）
  List<String> _splitTop(String s, String sep) {
    final out = <String>[];
    var cur = '';
    var q = '';
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (q.isNotEmpty) {
        cur += ch;
        if (ch == q) q = '';
        continue;
      }
      if (ch == "'" || ch == '"') {
        q = ch;
        cur += ch;
        continue;
      }
      if (ch == '[' || ch == '{' || ch == '(') depth++;
      if (ch == ']' || ch == '}' || ch == ')') depth--;
      if (depth == 0 && s.substring(i).startsWith(sep)) {
        out.add(cur);
        cur = '';
        i += sep.length - 1;
        continue;
      }
      cur += ch;
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  int _findTop(String s, String sub) {
    var q = '';
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (q.isNotEmpty) {
        if (ch == q) q = '';
        continue;
      }
      if (ch == "'" || ch == '"') {
        q = ch;
        continue;
      }
      if (ch == '[' || ch == '(' || ch == '{') depth++;
      if (ch == ']' || ch == ')' || ch == '}') depth--;
      if (depth == 0 && s.substring(i).startsWith(sub)) return i;
    }
    return -1;
  }

  /// '@' 分段：引号内不分；`/@attr`、`[@pred]` 属 xpath，不分
  List<String> _splitSegments(String chain) {
    final out = <String>[];
    var cur = '';
    var q = '';
    for (var i = 0; i < chain.length; i++) {
      final ch = chain[i];
      if (q.isNotEmpty) {
        cur += ch;
        if (ch == q) q = '';
        continue;
      }
      if (ch == "'" || ch == '"') {
        q = ch;
        cur += ch;
        continue;
      }
      if (ch == '@' &&
          cur.isNotEmpty &&
          i > 0 &&
          chain[i - 1] != '/' &&
          chain[i - 1] != '[') {
        out.add(cur);
        cur = '';
        continue;
      }
      cur += ch;
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  static final _attrRe =
      RegExp(r'^(href|src|content|alt|title|data-[\w-]+|onclick|id|class)$');

  List<Val> _applySeg(Val node, String seg, Document doc) {
    if (seg == 'text') {
      return [if (node is ElVal) StrVal(node.text()) else node];
    }
    if (seg == 'html') {
      return [if (node is ElVal) StrVal(node.el.innerHtml.trim()) else node];
    }
    if (seg.startsWith('text.')) return _textLocate(node, seg.substring(5));
    if (_attrRe.hasMatch(seg)) {
      final v = node.attr(seg);
      if (v == null || v.isEmpty) return const [];
      // 仅链接类属性做绝对化
      final link = seg == 'href' || seg == 'src';
      return [StrVal(link ? _abs(v) : v)];
    }
    if (seg.startsWith('//')) return _xpath(node, seg, doc);
    return _selector(node, seg, doc);
  }

  /// text.关键词[.idx]：当前子树里“直接文本含关键词”的最内层元素
  List<Val> _textLocate(Val node, String spec) {
    final parts = spec.split('.');
    final kw = parts[0];
    final idx = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (kw.isEmpty) return const [];
    final hits = <Val>[];
    void walk(Element e) {
      final direct = e.nodes
          .whereType<Text>()
          .map((t) => t.data.trim())
          .join(' ');
      if (direct.contains(kw)) {
        hits.add(ElVal(e));
        return;
      }
      for (final c in e.children) {
        walk(c);
      }
    }

    if (node is ElVal) {
      walk(node.el);
    } else if (node.text().contains(kw)) {
      hits.add(node);
    }
    if (idx == null) return hits;
    final i = idx < 0 ? hits.length + idx : idx;
    return (i >= 0 && i < hits.length) ? [hits[i]] : const [];
  }

  String _abs(String raw) {
    final r = raw.trim();
    if (r.startsWith('http') ||
        r.startsWith('javascript') ||
        r.startsWith('mailto')) {
      return r;
    }
    try {
      return Uri.parse(base).resolve(r).toString();
    } catch (_) {
      return r;
    }
  }

  List<Val> _selector(Val node, String seg, Document doc) {
    var body = seg;
    var idx = '';
    final mBr = RegExp(r'(\[[^\[\]]*\])$').firstMatch(body);
    if (mBr != null &&
        !RegExp(r'\[[^\[\]]*[*^$|~]?=').hasMatch(mBr.group(1)!)) {
      idx = mBr.group(1)!;
      body = body.substring(0, mBr.start);
    } else {
      final mTail = RegExp(r'^(.+?)\.(-?\d+)$').firstMatch(body);
      if (mTail != null && mTail.group(1)!.isNotEmpty) {
        idx = '.${mTail.group(2)}';
        body = mTail.group(1)!;
      }
    }
    if (body.isEmpty) return const [];
    final roots = _elsOf(node);
    if (roots.isEmpty) return const [];
    List<Element> found;
    if (body.startsWith('class.')) {
      found = _q(roots, '.${body.substring(6)}');
    } else if (body.startsWith('id.')) {
      found = _q(roots, '#${body.substring(3)}');
    } else if (body.startsWith('tag.')) {
      found = _q(roots, body.substring(4));
    } else {
      found = _q(roots, body);
    }
    final (left, picked) = _parseIdx([for (final e in found) ElVal(e)], idx);
    if (left.isNotEmpty) {
      final (_, fin) = _parseIdx(picked, left);
      return fin;
    }
    return picked;
  }

  List<Element> _q(List<Element> roots, String css) =>
      roots.expand((r) => r.querySelectorAll(css)).toList();

  List<Element> _elsOf(Val node) => node is ElVal ? [node.el] : const [];

  /// 返回（未消费的索引串，结果）。支持 `[a:b]`、`[n]`、`.n`
  (String, List<Val>) _parseIdx(List<Val> l, String idxSpec) {
    if (idxSpec.isEmpty) return ('', l);
    final mRange = RegExp(r'^\[(-?\d*):(-?\d*)\]$').firstMatch(idxSpec);
    if (mRange != null) {
      var a = int.tryParse(mRange.group(1) ?? '') ?? 0;
      var b = int.tryParse(mRange.group(2) ?? '') ?? l.length;
      if (a < 0) a += l.length;
      if (b < 0) b += l.length;
      a = a.clamp(0, l.length);
      b = b.clamp(a, l.length);
      return ('', l.sublist(a, b));
    }
    final mOne = RegExp(r'^\[(-?\d+)\]$').firstMatch(idxSpec);
    final mDot = RegExp(r'^\.(-?\d+)$').firstMatch(idxSpec);
    final num = mOne?.group(1) ?? mDot?.group(1);
    if (num != null) {
      var i = int.parse(num);
      if (i < 0) i += l.length;
      return ('', (i >= 0 && i < l.length) ? [l[i]] : const <Val>[]);
    }
    return (idxSpec, l);
  }

  /// ---------- mini xpath ----------
  List<Val> _xpath(Val node, String expr, Document doc) {
    final roots = _elsOf(node);
    if (roots.isEmpty) return const [];
    var e = expr.trim();
    String? finalAttr;
    final mAttr = RegExp(r'/@([\w:-]+)$').firstMatch(e);
    if (mAttr != null) {
      finalAttr = mAttr.group(1);
      e = e.substring(0, mAttr.start);
    }
    final mRoot =
        RegExp(r'^//([\w*]+)(?:\[([^\]]*)\])?(?:/(.+))?$').firstMatch(e);
    if (mRoot == null) throw UnsupportedRule('xpath: ${_cut(expr)}');
    var els = _q(roots, mRoot.group(1)!);
    final rootPred = mRoot.group(2);
    if (rootPred != null && rootPred.isNotEmpty) {
      els = els.where((el) => _matchPred(el, rootPred)).toList();
    }
    final rest = mRoot.group(3);
    if (rest != null && rest.isNotEmpty) {
      for (final step in _xpathSteps(rest)) {
        final next = <Element>[];
        for (final el in els) {
          next.addAll(_xpathStepEls(el, step));
        }
        els = next;
        if (els.isEmpty) return const [];
      }
    }
    if (finalAttr != null) {
      final fa = finalAttr;
      final link = fa == 'href' || fa == 'src';
      return [
        for (final el in els)
          if (ElVal(el).attr(fa) != null)
            StrVal(link ? _abs(ElVal(el).attr(fa)!) : ElVal(el).attr(fa)!),
      ];
    }
    return [for (final el in els) ElVal(el)];
  }

  bool _matchPred(Element el, String pred) {
    final p = pred.trim();
    final m = RegExp(
      r'''@([\w:-]+)\s*=\s*'([^']*)'|@([\w:-]+)\s*=\s*"([^"]*)"''',
    ).firstMatch(p);
    if (m != null) {
      final key = m.group(1) ?? m.group(3)!;
      final want = m.group(2) ?? m.group(4)!;
      return ElVal(el).attr(key) == want;
    }
    final mOr = RegExp(
      r'''@\s*([\w:-]+)\s*=\s*'([^']*)'|(?:or|AND|AND)@([\w:-]+)\s*=\s*'([^']*)' ''',
    ).firstMatch(p);
    if (mOr != null) return true; // 由下面的多谓词拆分处理
    final mHas = RegExp(r'@([\w:-]+)').firstMatch(p);
    if (mHas != null) return ElVal(el).attr(mHas.group(1)!) != null;
    return true;
  }

  List<String> _xpathSteps(String tail) {
    final out = <String>[];
    var cur = '';
    var depth = 0;
    for (final ch in tail.split('')) {
      if (ch == '[') depth++;
      if (ch == ']') depth--;
      if (ch == '/' && depth == 0) {
        if (cur.isNotEmpty) out.add(cur);
        cur = '';
      } else {
        cur += ch;
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  List<Element> _xpathStepEls(Element el, String step) {
    var s = step;
    var axis = 'child';
    final mAx = RegExp(r'^([\w-]+)::').firstMatch(s);
    if (mAx != null) {
      axis = mAx.group(1)!;
      s = s.substring(mAx.end);
    }
    var last = false;
    final mLast = RegExp(r'\[last\(\)\]').firstMatch(s);
    if (mLast != null) {
      last = true;
      s = s.replaceFirst(mLast.group(0)!, '');
    }
    String? pred;
    final mPred = RegExp(r'\[([^\]]*)\]').firstMatch(s);
    if (mPred != null) {
      pred = mPred.group(1);
      s = s.replaceFirst(mPred.group(0)!, '');
    }
    final tag = s.isEmpty ? '*' : s;
    Iterable<Element> pool;
    if (axis == 'following-sibling') {
      final l = <Element>[];
      var n = el.nextElementSibling;
      while (n != null) {
        l.add(n);
        n = n.nextElementSibling;
      }
      pool = l;
    } else if (axis == 'parent') {
      pool = el.parent == null ? const <Element>[] : [el.parent!];
    } else {
      pool = el.children.where((c) => tag == '*' || c.localName == tag);
    }
    if (axis == 'following-sibling' && tag != '*') {
      pool = pool.where((c) => c.localName == tag);
    }
    var list = pool.where((c) => pred == null || _matchPred(c, pred!)).toList();
    if (last && list.isNotEmpty) list = [list.last];
    return list;
  }
}

/// 净化正则：`正则##替换`（支持 $1 组引用）
List<String> _cleanReplace(List<String> items, String spec) {
  final dd = spec.split('##');
  final pat = dd[0];
  final rep = dd.length > 1 ? dd[1] : '';
  RegExp re;
  try {
    re = RegExp(pat, multiLine: true);
  } catch (_) {
    return items;
  }
  return [
    for (final s in items)
      s.replaceAllMapped(re, (m) {
        var r = rep;
        for (var i = m.groupCount; i >= 1; i--) {
          r = r.replaceAll('\$$i', m.group(i) ?? '');
        }
        return r;
      }),
  ];
}

/// ---------- 书源模型 ----------
class BookSource {
  BookSource(this.j);

  final Map<String, dynamic> j;

  String get name => (j['bookSourceName'] as String?) ?? '?';
  String get url =>
      ((j['bookSourceUrl'] as String?) ?? '').replaceAll(RegExp(r'/+$'), '');
  String? get group => j['bookSourceGroup'] as String?;
  bool get enabledDefault => j['enabled'] != false;
  String get searchUrl => (j['searchUrl'] as String?) ?? '';
  Map<String, dynamic> get ruleSearch => _m(j['ruleSearch']);
  Map<String, dynamic> get ruleBookInfo => _m(j['ruleBookInfo']);
  Map<String, dynamic> get ruleToc => _m(j['ruleToc']);
  Map<String, dynamic> get ruleContent => _m(j['ruleContent']);

  static Map<String, dynamic> _m(dynamic v) => v is Map
      ? {for (final e in v.entries) e.key.toString(): e.value}
      : <String, dynamic>{};

  bool usesJs() {
    final s = jsonEncode(j);
    return s.contains('@js:') ||
        s.contains('<js>') ||
        s.contains('useWebView') ||
        s.contains('evalJs');
  }

  Map<String, String> headerMap() {
    final h = j['header'];
    if (h is Map) {
      return {
        for (final e in h.entries) e.key.toString(): e.value.toString(),
      };
    }
    if (h is String) {
      try {
        final m = jsonDecode(h.replaceAll("'", '"'));
        if (m is Map) {
          return {
            for (final e in m.entries) e.key.toString(): e.value.toString(),
          };
        }
      } catch (_) {}
    }
    return const {};
  }
}

/// ---------- 数据模型 ----------
class SearchBook {
  SearchBook(this.name, this.bookUrl);

  final String name;
  final String bookUrl;
  String author = '';
  String cover = '';
  String intro = '';
  String lastChapter = '';
  String kind = '';
  String wordCount = '';
}

class BookInfo {
  String name = '';
  String author = '';
  String cover = '';
  String intro = '';
  String lastChapter = '';
  String kind = '';
  String wordCount = '';
  String tocUrl = '';
}

class TocChapter {
  TocChapter(this.title, this.url);

  final String title;
  final String url;
}

class ChapterText {
  ChapterText({
    required this.title,
    required this.paras,
    required this.rawLen,
    required this.finalLen,
    required this.pages,
  });

  final String title;
  final List<String> paras;
  final int rawLen;
  final int finalLen;
  final int pages;
}

/// ---------- 四段流程 ----------
class SourceEngine {
  SourceEngine(this.src, this.http, {this.maxTocPages = 12});

  final BookSource src;
  final HttpCtx http;
  final int maxTocPages;

  Analyzer get az => Analyzer(src.url);

  String _r(Map<String, dynamic> rules, String k) =>
      (rules[k] ?? '').toString();

  // ---------- 期4：JSON 规则求值（$.path / {{$.field}} / ##净化 / @js:） ----------
  final JsBridge _js = JsBridge();
  String get jsEngine => _js.engine;

  String _evalJsonRule(String rule, Map? item, dynamic ctx) {
    if (rule.trim().isEmpty) return '';
    final parts = rule.split('@js:');
    var v = _jsonField(parts[0], item, ctx);
    if (parts.length > 1) {
      final js = parts.sublist(1).join('@js:');
      try {
        v = _js.run(js, v, baseUrl: src.url);
      } catch (e) {
        stderr.writeln('  [js] $e');
      }
    }
    return v.trim();
  }

  String _jsonField(String r, Map? item, dynamic ctx) {
    String? clean;
    final h = r.indexOf('##');
    if (h > 0) {
      clean = r.substring(h + 2);
      r = r.substring(0, h);
    }
    String v;
    if (r.startsWith(r'$.')) {
      var node = _jsonAt(ctx, r);
      if (node == null && item != null) {
        node = _jsonAt(item, r);
      }
      v = node == null ? '' : '$node';
    } else {
      v = _tplJson(r, item, ctx);
    }
    if (clean != null) v = _cleanReplace([v], clean).first;
    return v;
  }

  String _absFrom(String pageUrl, String raw) {
    final t = raw.trim();
    if (t.isEmpty || t.startsWith('http')) return t;
    try {
      return Uri.parse(pageUrl).resolve(t).toString();
    } catch (_) {
      return '${src.url}$t';
    }
  }

  (String, Map<String, dynamic>) _parseSearch(String key, int page) {
    var raw = src.searchUrl;
    Map<String, dynamic> cfg = {};
    final ci = raw.indexOf(',{');
    if (ci > 0) {
      try {
        cfg = _lenientJson(raw.substring(ci + 1));
      } catch (_) {}
      raw = raw.substring(0, ci);
    }
    if (raw.contains(',')) raw = raw.split(',').first;
    final gbk = (cfg['charset'] ?? '').toString().toLowerCase().contains('gb');
    final kw = gbk ? _gbkPct(key) : Uri.encodeComponent(key);
    raw = raw.replaceAll('{{key}}', kw).replaceAll('{{page}}', '$page');
    return (raw.startsWith('http') ? raw : '${src.url}$raw', cfg);
  }

  Map<String, dynamic> _lenientJson(String s) {
    final t = s.trim();
    try {
      return jsonDecode(t) as Map<String, dynamic>;
    } catch (_) {
      return jsonDecode(t.replaceAll("'", '"')) as Map<String, dynamic>;
    }
  }

  String _gbkPct(String s) => gbkpkg.gbk
      .encode(s)
      .map((b) => '%${(b is int ? b : 0).toRadixString(16).toUpperCase().padLeft(2, '0')}')
      .join();

  /// ① 搜索
  Future<List<SearchBook>> search(String key, {int page = 1}) async {
    final (url, cfg) = _parseSearch(key, page);
    final method = (cfg['method'] ?? 'GET').toString().toUpperCase();
    List<int>? body;
    String? ct;
    String? charset;
    if (method == 'POST') {
      final gbk =
          (cfg['charset'] ?? '').toString().toLowerCase().contains('gb');
      var b = (cfg['body'] ?? '').toString();
      b = b.replaceAll(
        '{{key}}',
        gbk ? _gbkPct(key) : Uri.encodeComponent(key),
      );
      body = gbk ? gbkpkg.gbk.encode(b) : utf8.encode(b);
      ct = 'application/x-www-form-urlencoded';
      if (gbk) charset = 'gbk';
    }
    final res = await http.fetch(
      url,
      method: method,
      bodyBytes: body,
      bodyContentType: ct,
      charsetHint: charset ?? (cfg['charset'] as String?),
      headers: src.headerMap(),
    );
    final txt = res.text();
    if (_looksJson(txt)) return _searchJson(jsonDecode(txt));
    return parseSearchResults(htmlparser.parse(txt), key);
  }

  List<SearchBook> _searchJson(dynamic root) {
    final list = _jsonAt(root, _r(src.ruleSearch, 'bookList'));
    if (list is! List) return const [];
    final out = <SearchBook>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      String rf(String k) => _evalJsonRule(_r(src.ruleSearch, k), item, root);
      final nm = rf('name');
      var bu = rf('bookUrl');
      if (nm.isEmpty || bu.isEmpty) continue;
      bu = _absFrom(src.url, bu);
      out.add(SearchBook(nm, bu)
        ..author = rf('author')
        ..cover = _absFrom(src.url, rf('coverUrl'))
        ..intro = rf('intro')
        ..kind = rf('kind')
        ..lastChapter = rf('lastChapter')
        ..wordCount = rf('wordCount'));
    }
    return out;
  }

  List<SearchBook> parseSearchResults(Document doc, String key) {
    final listRule = _r(src.ruleSearch, 'bookList');
    if (listRule.isEmpty) return const [];
    final items = az.evalNodes(listRule, doc);
    final out = <SearchBook>[];
    for (final it in items) {
      String rf(String k) {
        final r = _r(src.ruleSearch, k);
        if (r.isEmpty) return '';
        try {
          return az.evalIn(r, [it], doc).join('\n').trim();
        } on UnsupportedRule {
          return '';
        } catch (_) {
          return '';
        }
      }

      final nm = rf('name');
      final bu = rf('bookUrl');
      if (nm.isEmpty || bu.isEmpty) continue;
      out.add(
        SearchBook(nm, bu)
          ..author = rf('author')
          ..cover = rf('coverUrl')
          ..intro = rf('intro')
          ..kind = rf('kind')
          ..lastChapter = rf('lastChapter')
          ..wordCount = rf('wordCount'),
      );
    }
    return out;
  }

  /// ② 详情元数据
  Future<BookInfo> bookInfo(String bookUrl) async {
    final res = await http.fetch(bookUrl, headers: src.headerMap());
    final txt = res.text();
    if (_looksJson(txt)) return _bookInfoJson(jsonDecode(txt));
    final doc = htmlparser.parse(txt);
    final info = BookInfo();
    String rf(String k) {
      final r = _r(src.ruleBookInfo, k);
      if (r.isEmpty) return '';
      try {
        if (r.contains('{{')) {
          final filled = r.replaceAllMapped(
            RegExp(r'\{\{@@(.+?)\}\}'),
            (m) {
              try {
                return az.eval(m.group(1)!, doc).join('\n');
              } catch (_) {
                return '';
              }
            },
          );
          return (htmlparser.parseFragment(filled).text ?? '').trim();
        }
        return az.eval(r, doc).join('\n').trim();
      } on UnsupportedRule {
        return '[JS未支持]';
      } catch (_) {
        return '';
      }
    }

    info.name = rf('name');
    info.author = rf('author');
    info.cover = rf('coverUrl');
    info.intro = rf('intro');
    info.kind = rf('kind');
    info.lastChapter = rf('lastChapter');
    info.wordCount = rf('wordCount');
    info.tocUrl = rf('tocUrl');
    if (info.name.isEmpty) {
      info.name =
          doc.querySelector('h1')?.text.trim() ??
          doc.querySelector('title')?.text.trim() ??
          '';
    }
    if (info.tocUrl.isEmpty) info.tocUrl = bookUrl;
    info.cover = info.cover.split('\n').first.trim();
    return info;
  }

  BookInfo _bookInfoJson(dynamic root) {
    final info = BookInfo();
    dynamic ctx = root;
    final init = _r(src.ruleBookInfo, 'init');
    if (init.isNotEmpty) ctx = _jsonAt(root, init) ?? root;
    final item = ctx is Map ? Map<String, dynamic>.from(ctx) : null;
    String rf(String k) => _evalJsonRule(_r(src.ruleBookInfo, k), item, ctx);
    info.name = rf('name');
    info.author = rf('author');
    info.cover = _absFrom(src.url, rf('coverUrl'));
    info.intro = rf('intro');
    info.kind = rf('kind');
    info.lastChapter = rf('lastChapter');
    info.wordCount = rf('wordCount');
    final toc = rf('tocUrl');
    info.tocUrl = toc.isEmpty ? '' : _absFrom(src.url, toc);
    if (info.name.isEmpty) info.name = '?';
    return info;
  }

  /// ③ 目录（含目录翻页）
  Future<List<TocChapter>> toc(String url) async {
    final listRule = _r(src.ruleToc, 'chapterList');
    final nameRule = _r(src.ruleToc, 'chapterName');
    final urlRule = _r(src.ruleToc, 'chapterUrl');
    final nextRule = _r(src.ruleToc, 'nextTocUrl');
    final chapters = <TocChapter>[];
    final seen = <String>{};
    final visited = <String>{};
    var pageUrl = url;
    for (var i = 0;
        i < maxTocPages && pageUrl.isNotEmpty && visited.add(pageUrl);
        i++) {
      final res = await http.fetch(pageUrl, headers: src.headerMap());
      final rtxt = res.text();
      if (_looksJson(rtxt)) {
        final root = jsonDecode(rtxt);
        final list = _jsonAt(root, listRule);
        if (list is List) {
          for (final raw in list) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            final t = _evalJsonRule(nameRule, item, root);
            final u = _absFrom(pageUrl, _evalJsonRule(urlRule, item, root));
            if (u.isEmpty || !seen.add(u)) continue;
            chapters.add(TocChapter(t.isEmpty ? u.split('/').last : t, u));
          }
        }
        break; // API 源一次返回全目录
      }
      final doc = htmlparser.parse(rtxt);
      for (final it in az.evalNodes(listRule, doc)) {
        String pick(String r, bool isUrl) {
          if (r.isEmpty || r == 'text') {
            return isUrl ? (it.attr('href') ?? '') : it.text();
          }
          try {
            final v = az.evalIn(r, [it], doc).join(' ').trim();
            return isUrl ? Uri.parse(pageUrl).resolve(v).toString() : v;
          } catch (_) {
            return '';
          }
        }

        final u = pick(urlRule, true);
        final t = pick(nameRule, false);
        if (u.isEmpty || u.startsWith('javascript')) continue;
        if (seen.add(u)) {
          chapters.add(TocChapter(t.isEmpty ? u.split('/').last : t, u));
        }
      }
      if (nextRule.isEmpty) break;
      String next = '';
      try {
        for (final c in az.eval(nextRule, doc)) {
          if (c.startsWith('http') && !visited.contains(c)) {
            next = c;
            break;
          }
        }
      } catch (_) {
        break;
      }
      if (next.isEmpty) break;
      pageUrl = next;
    }
    return _orderedToc(chapters);
  }

  /// 期2：目录排序。Legado 口径 = chapterList 规则首字符 '-' 显式反转；
  /// 无标记时按「第X章」数字自动判向（真站 biqumo 实测返回倒序）。
  List<TocChapter> _orderedToc(List<TocChapter> chs) {
    if (chs.length < 3) return chs;
    if (_r(src.ruleToc, 'chapterList').startsWith('-')) {
      return chs.reversed.toList();
    }
    int? num(String t) {
      final m = RegExp(r'第\s*([零〇一二三四五六七八九十百千两0-9]+)\s*[章回节篇]').firstMatch(t);
      return m == null ? null : _cnNum(m.group(1)!);
    }
    final a = num(chs.first.title), b = num(chs.last.title);
    if (a == null || b == null || a <= b) return chs;
    stderr.writeln('  [自动转正] 目录倒序（首$a>末$b）已反转');
    return chs.reversed.toList();
  }

  static int _cnNum(String s) {
    if (int.tryParse(s) != null) return int.parse(s);
    const d = {
      '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    };
    const u = {'十': 10, '百': 100, '千': 1000};
    var total = 0, cur = 0;
    for (final ch in s.split('')) {
      if (d.containsKey(ch)) {
        cur = d[ch]!;
      } else if (u.containsKey(ch)) {
        total += (cur == 0 ? 1 : cur) * u[ch]!;
        cur = 0;
      }
    }
    return total + cur;
  }

  /// ④ 正文（章内翻页 + 净化 + 用户过滤正则）
  Future<ChapterText> chapter(String url,
      {int maxPages = 30, String extraFilter = ''}) async {
    final contentRule = _r(src.ruleContent, 'content');
    final nextRule = _r(src.ruleContent, 'nextContentUrl');
    final replaceRule = _r(src.ruleContent, 'replaceRegex');
    final titleRule = _r(src.ruleContent, 'title');
    _assertContentSupported(contentRule);
    final pieces = <String>[];
    final visited = <String>{};
    var title = '';
    var pageUrl = url;
    var pages = 0;
    for (var i = 0;
        i < maxPages && pageUrl.isNotEmpty && visited.add(pageUrl);
        i++) {
      final res = await http.fetch(pageUrl, headers: src.headerMap());
      final rtxt2 = res.text();
      if (_looksJson(rtxt2)) {
        final root = jsonDecode(rtxt2);
        final body = _evalJsonRule(contentRule, null, root);
        final t2 = titleRule.isNotEmpty
            ? _evalJsonRule(titleRule, null, root)
            : (root is Map && root['data'] is Map
                ? '${root['data']['chapter_name'] ?? ''}'
                : '');
        var text = body.replaceAll(RegExp(r'<[^>]+>'), '');
        final rl = text.replaceAll(RegExp(r'\s'), '').length;
        text = _defaultClean(text);
        if (replaceRule.isNotEmpty) text = _applyReplaces(text, replaceRule);
        final paras = [
          for (final p in text.split(RegExp(r'\n+')))
            if (p.trim().isNotEmpty) p.trim(),
        ];
        return ChapterText(
          title: t2.trim(),
          paras: paras,
          rawLen: rl,
          finalLen: text.replaceAll(RegExp(r'\s'), '').length,
          pages: 1,
        );
      }
      final doc = htmlparser.parse(rtxt2);
      pages++;
      if (title.isEmpty && titleRule.isNotEmpty) {
        try {
          title = az.eval(titleRule, doc).join(' ').trim();
        } catch (_) {}
      }
      List<String> got;
      got = az.eval(contentRule, doc).where((s) => s.trim().isNotEmpty).toList();
      got = _decodeWriteln(got);
      pieces.addAll(got);
      if (nextRule.isEmpty) break;
      String next = '';
      try {
        for (final c in az.eval(nextRule, doc)) {
          final m = RegExp(
            r'''realUrl\s*=\s*['"]([^'"]+)['"]''',
          ).firstMatch(c);
          if (m != null) {
            next = Uri.parse(pageUrl).resolve(m.group(1)!).toString();
            break;
          }
          if (c.startsWith('http') && c != pageUrl && !visited.contains(c)) {
            next = c;
            break;
          }
        }
      } catch (_) {
        break;
      }
      if (next.isEmpty) break;
      pageUrl = next;
    }
    var text = pieces.join('\n');
    if (text.contains('<')) {
      text = text.replaceAll(
        RegExp(r'</p>|<br\s*/?>', caseSensitive: false),
        '\n',
      );
    }
    text = htmlparser.parseFragment(text).text ?? text;
    final rawLen = text.replaceAll(RegExp(r'\s'), '').length;
    text = _defaultClean(text);
    if (replaceRule.isNotEmpty) text = _applyReplaces(text, replaceRule);
    if (extraFilter.isNotEmpty) text = _applyReplaces(text, extraFilter);
    final paras = [
      for (final p in text.split(RegExp(r'\n+')))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    return ChapterText(
      title: title,
      paras: paras,
      rawLen: rawLen,
      finalLen: text.replaceAll(RegExp(r'\s'), '').length,
      pages: pages,
    );
  }

  void _assertContentSupported(String r) {
    final low = r.toLowerCase();
    if (low.contains('<js>') ||
        low.contains('@js:') ||
        low.contains('evaljs')) {
      throw UnsupportedRule('正文需JS: ${_cut(r)}');
    }
  }

  /// 轻量混淆解码：document.writeln(fn('BASE64')) 形态（真站 biqumo 实测）。
  /// Legado 里这类站用 @js 处理；此处作为定向兜底能力。
  List<String> _decodeWriteln(List<String> raw) {
    final joined = raw.join('\n');
    if (!joined.contains('document.writeln')) return raw;
    final out = <String>[];
    for (final m in RegExp(
      r'''[\w.$]+\(\s*['"]([A-Za-z0-9+/=]{40,})['"]\s*\)''',
    ).allMatches(joined)) {
      try {
        out.add(utf8.decode(base64Decode(m.group(1)!)));
      } catch (_) {}
    }
    return out.isEmpty ? raw : out;
  }

  String _defaultClean(String t) => t
      .replaceAll(RegExp(r'\s*[（(]本章完[）)]\s*'), '')
      .replaceAll(RegExp(r'请收藏本站[^\n]*'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  /// 过滤配置：每行 `正则##替换`
  String _applyReplaces(String t, String spec) {
    var out = t;
    for (final line in spec.split(RegExp(r'[\n;]'))) {
      if (line.trim().isEmpty || !line.contains('##')) continue;
      try {
        out = _cleanReplace([out], line).first;
      } catch (_) {}
    }
    return out;
  }

  // ---------- 补验A：发现页 discoverUrl + ruleExplore ----------
  /// Legado 格式：`标题::url&&标题::url`（url 内可含 {{page}}/{{key}}）
  List<(String, String)> discoverTabs() {
    final raw = (src.j['discoverUrl'] ?? '').toString();
    if (raw.isEmpty) return const [];
    return [
      for (final e in raw.split('&&'))
        if (e.contains('::'))
          (e.split('::').first.trim(), e.split('::').skip(1).join('::').trim())
        else
          ('默认', e.trim()),
    ];
  }

  /// 执行一个发现页条目 → 书籍列表（ruleExplore 缺省回落 ruleSearch）
  Future<List<SearchBook>> explore(String urlTpl, {int page = 1, String key = ''}) async {
    var u = urlTpl.replaceAll('{{page}}', '$page').replaceAll('{{key}}', Uri.encodeComponent(key));
    if (!u.startsWith('http')) u = '${src.url}$u';
    final res = await http.fetch(u, headers: src.headerMap());
    final txt = res.text();
    final rules = src.j['ruleExplore'] is Map && (src.j['ruleExplore'] as Map).isNotEmpty
        ? Map<String, dynamic>.from(src.j['ruleExplore'] as Map)
        : src.ruleSearch;
    if (_looksJson(txt)) {
      final root = jsonDecode(txt);
      final list = _jsonAt(root, (rules['bookList'] ?? '').toString());
      if (list is! List) return const [];
      final out = <SearchBook>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        String rf(String k) => _evalJsonRule((rules[k] ?? '').toString(), item, root);
        final nm = rf('name');
        final bu = _absFrom(src.url, rf('bookUrl'));
        if (nm.isEmpty || bu.isEmpty) continue;
        out.add(SearchBook(nm, bu)
          ..author = rf('author')
          ..cover = _absFrom(src.url, rf('coverUrl'))
          ..lastChapter = rf('lastChapter'));
      }
      return out;
    }
    final doc = htmlparser.parse(txt);
    return _evalListRules(rules, doc);
  }

  List<SearchBook> _evalListRules(Map<String, dynamic> rules, Document doc) {
    final listRule = (rules['bookList'] ?? '').toString();
    if (listRule.isEmpty) return const [];
    final items = az.evalNodes(listRule, doc);
    final out = <SearchBook>[];
    for (final it in items) {
      String rf(String k) {
        final r = (rules[k] ?? '').toString();
        if (r.isEmpty) return '';
        try {
          return az.evalIn(r, [it], doc).join('\n').trim();
        } catch (_) {
          return '';
        }
      }
      final nm = rf('name');
      final bu = rf('bookUrl');
      if (nm.isEmpty || bu.isEmpty) continue;
      out.add(SearchBook(nm, bu)
        ..author = rf('author')
        ..cover = rf('coverUrl')
        ..intro = rf('intro')
        ..kind = rf('kind')
        ..lastChapter = rf('lastChapter')
        ..wordCount = rf('wordCount'));
    }
    return out;
  }

  // ---------- 补验D：字体反混淆（数据层） ----------
  /// Legado 机制：站点自定义字体把 PUA 码点(0xE000~0xF8FF)重定向为正常字符，
  /// 框架解析 TTF cmap 得 码点→字符 映射(fontMap)，正文按表回写。
  /// 本函数=回写管道（cmap 解析为立项件，见补验记录）。
  static String applyFontMap(String text, Map<String, String> fontMap) {
    final sb = StringBuffer();
    for (final ru in text.runes) {
      if (ru >= 0xE000 && ru <= 0xF8FF) {
        final rep = fontMap['${ru.toRadixString(16).toUpperCase()}'];
        sb.write(rep != null && rep.isNotEmpty ? rep : String.fromCharCode(ru));
      } else {
        sb.writeCharCode(ru);
      }
    }
    return sb.toString();
  }
}
