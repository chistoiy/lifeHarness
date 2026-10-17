import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_log.dart';

/// 保真批F2 · ISBN 命中 → 豆瓣书目补全。
/// 网络层全部走可注入 fetcher：默认真实 HttpClient；widget 测试注入假实现
/// （禁真实异步 I/O · 见记忆 feedback-widget-test-no-real-async-io）。
///
/// 真机反馈（2026-09-26）「填了 ISBN 也拉不到资源」的两条根因，均已钉在
/// test/fixtures/douban_isbn_*.html（真页抓取）上：
/// ① UA 写 Android/iPhone 时豆瓣**服务端改写跳 m.douban.com 移动版**，移动版
///    页面没有 `property="v:itemreviewed"` 等 microdata → 解析必为空，表现就是
///    「离线或未命中」。这里固定发**桌面 UA**（只有桌面版带 microdata）。
/// ② 桌面页里作者/出版社的 `<a>` 前后夹着换行与缩进，旧正则用 `[^\n]{0,40}?`
///    跨不过换行 → 字段静默丢失。现按 `href="…/author/…"`、`href="…/press/…"`
///    直取，并对空白容错。
/// 失败成因（网络层 / HTTP 码 / 取到页但解析不出）一律进 [AppLog]：日志页可查，
/// 不再把三种成因混成同一句「离线或未命中」。

typedef IsbnPageFetcher = Future<String?> Function(Uri uri);
typedef IsbnBytesFetcher = Future<List<int>?> Function(Uri uri);

/// 桌面 UA 池：豆瓣按 UA 分流移动/桌面版，只有桌面版页面带 v: microdata。
/// 2026-09-26 参照 calibre-douban 的随机 UA 手法，本机实测 5 款桌面 UA
/// （Win/Mac × Chrome/Edge/Firefox/Safari）都能拿到带 microdata 的整页；
/// 每次请求随机取一款，避免单一固定指纹被高频标记。
/// 注意：**不得混入移动端 UA**（m 站无 microdata，解析必空，是真机第一轮翻车点）。
const List<String> doubanUserAgents = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) '
      'Gecko/20100101 Firefox/128.0',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.4 Safari/605.1.15',
];

/// 兼容旧引用（测试与日志锚点）：池内第一款。
final String doubanUserAgent = doubanUserAgents[0];

String pickDoubanUserAgent([math.Random? rng]) =>
    doubanUserAgents[(rng ?? math.Random()).nextInt(doubanUserAgents.length)];

/// 豆瓣登录 Cookie（calibre-douban 同款防封手法 · 2026-09-26 用户拍板：
/// 信任用户自填＋明示风险；不做代理通道）。**只存本机设置表**：
/// 不进日志（AppLog 一律不落 Cookie 值），值由启动/设置保存处 [set] 注入，
/// 空/纯空格＝未配置（匿名抓取）。
class DoubanCookie {
  DoubanCookie._();
  static String? _value;
  static String? get value => _value;
  static void set(String? raw) {
    final v = raw?.trim() ?? '';
    _value = v.isEmpty ? null : v;
  }
}

/// 风控熔断（识别到豆瓣拦截后，冷却期内不再发起任何豆瓣请求）。
/// 触发来源：①HTTP 403/429（默认 fetcher 内）；②拦截页文案（lookup 侧，
/// 注入假 fetcher 的测试也走这条）。冷却落内存；跨重启持久化由设置键
/// read.dbBlockUntil 承担（启动时 [restore]）。
class DoubanGuard {
  DoubanGuard._();
  static const int defaultBlockMinutes = 20;

  static int? _blockUntilMs;
  static bool _lastFetchBlocked = false;

  /// 冷却落盘钩子（main.dart 启动时注入：写 SharedPreferences
  /// read.dbBlockUntil；测试可注入假实现或留空）。
  static void Function(int untilMs)? persist;

  /// 默认 fetcher 记一次「本连接被 403/429」；lookupDetailed 开头清零。
  static bool get lastFetchBlocked => _lastFetchBlocked;
  static void clearLastFetchBlocked() => _lastFetchBlocked = false;
  static void noteHttpStatusBlocked() => _lastFetchBlocked = true;
  static int? get blockUntilMs => _blockUntilMs;

  /// 应用启动时用设置表 read.dbBlockUntil 的值恢复冷却态。
  static void restore(int? untilMs) => _blockUntilMs = untilMs;

  static void reset() {
    _blockUntilMs = null;
    _lastFetchBlocked = false;
  }

  /// 冷却是否仍生效；过期顺手清除（下一次真正放行）。
  static bool active({int? nowMs}) {
    final until = _blockUntilMs;
    if (until == null) return false;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (now < until) return true;
    _blockUntilMs = null;
    return false;
  }

  /// 触发/续期冷却（取更晚的到期点），并留一条日志（不含任何凭据）。
  static void trip({int minutes = defaultBlockMinutes}) {
    _lastFetchBlocked = true;
    final cand = DateTime.now().millisecondsSinceEpoch + minutes * 60000;
    final first = _blockUntilMs == null;
    if (first || cand > _blockUntilMs!) {
      _blockUntilMs = cand;
      persist?.call(cand);
    }
    AppLog.add(
      (first
              ? '豆瓣访问受限，熔断 $minutes 分钟内不再发起豆瓣请求'
              : '豆瓣仍受限，熔断延长至 $minutes 分钟后（滚动）') +
          // V1.46 过期提醒：带着 Cookie 仍被风控，多半是登录态失效而非纯频控。
          (DoubanCookie.value != null
              ? ' · 登录态可能已失效，可在阅读设置重新登录豆瓣'
              : ''),
      level: LhLevel.warn,
    );
  }
}

/// 豆瓣拦截页特征（calibre-douban is_prohibited 同款文案 + 站内风控提示语）。
bool doubanBlockedPage(String body) =>
    body.contains('<title>禁止访问</title>') ||
    body.contains('有异常请求') ||
    body.contains('你的访问出了点小问题');

/// 真机第二轮反馈（2026-09-26）：桌面页有 13 万字符，移动网络常在收 body
/// 中途被掐断（`HttpException: Connection closed while receiving data`）→
/// 一次失败就判「拉不到」不合理。默认 fetcher 内部对**传输层**失败重试 3 次
/// （350/700ms 退避），状态码类失败不重试；再不行由 [IsbnEnrich.lookupDetailed]
/// 走联想/搜索页兜底。
const int _textAttempts = 3;

void _doubanHeaders(HttpClientRequest req, {String? referer}) {
  req.headers.set(HttpHeaders.userAgentHeader, pickDoubanUserAgent());
  req.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
  final ck = DoubanCookie.value;
  if (ck != null) req.headers.set(HttpHeaders.cookieHeader, ck);
  if (referer != null) req.headers.set(HttpHeaders.refererHeader, referer);
}

/// 列表缩略图直连 img*.doubanio.com 的请求头：真机实证（2026-09-27）无
/// UA/Referer 的裸请求会被防盗链拦下（表单里 saveCover 走带 Referer 的
/// 字节通道就能取到）——Image.network 用这份头即可在列表阶段直接显图。
Map<String, String> doubanImageHeaders() => {
  HttpHeaders.userAgentHeader: pickDoubanUserAgent(),
  'Referer': 'https://book.douban.com/',
};

Future<String?> _httpGetText(Uri uri) async {
  String? lastErr;
  for (var i = 1; i <= _textAttempts; i++) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(uri);
      _doubanHeaders(req);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        // 状态码类失败重试无意义：直接记一条并交给上层判「未收录」。
        // 403/429 不是「没这本书」而是被风控 → 记熔断信号给 lookupDetailed。
        if (res.statusCode == 403 || res.statusCode == 429) {
          DoubanGuard.noteHttpStatusBlocked();
        }
        AppLog.add('豆瓣请求 HTTP ${res.statusCode} ← $uri', level: LhLevel.warn);
        return null;
      }
      final body = await utf8.decoder
          .bind(res)
          .join()
          .timeout(const Duration(seconds: 12));
      if (body.trim().isNotEmpty) return body;
      lastErr = '空响应体';
    } catch (e) {
      lastErr = '$e';
    } finally {
      client.close(force: true);
    }
    if (i < _textAttempts) {
      await Future<void>.delayed(Duration(milliseconds: 350 * i));
    }
  }
  AppLog.add(
      '豆瓣响应读取失败（第 $_textAttempts 次仍断连）：$lastErr ← $uri',
      level: LhLevel.error);
  return null;
}

Future<List<int>?> _httpGetBytes(Uri uri) async {
  // 封面图床（doubanio）偶发校验来源，带 Referer 更稳。
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(uri);
    _doubanHeaders(req, referer: 'https://book.douban.com/');
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      AppLog.add('封面请求 HTTP ${res.statusCode} ← $uri', level: LhLevel.warn);
      return null;
    }
    return await res
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
        .timeout(const Duration(seconds: 12));
  } catch (e) {
    AppLog.add('封面读取失败：$e ← $uri', level: LhLevel.error);
    return null;
  } finally {
    client.close(force: true);
  }
}

final isbnPageFetcherProvider = Provider<IsbnPageFetcher>(
  (ref) => _httpGetText,
);
final isbnBytesFetcherProvider = Provider<IsbnBytesFetcher>(
  (ref) => _httpGetBytes,
);

class IsbnBookMeta {
  const IsbnBookMeta({
    required this.title,
    this.author,
    this.publisher,
    this.pubDate,
    this.pages,
    this.rating,
    this.coverUrl,
    // V1.44 先搜后加：详情页能给的字段全量入 meta，表单照填（缓存表仍只
    // 存上面的最小字段集——用户口径「本地只存当前使用的字段」不变）。
    this.translator,
    this.series,
    this.binding,
    this.price,
    this.wordCount,
    this.isbn,
    this.intro,
    this.authorNote,
  });
  final String title;
  final String? author;
  final String? publisher;
  final String? pubDate;
  final int? pages;
  final double? rating;
  final String? coverUrl;
  final String? translator;
  final String? series;
  final String? binding;

  /// 定价原样（豆瓣形态「18.00元」）；表单落「购入价格」时取数字部分。
  final String? price;
  final int? wordCount;
  final String? isbn;
  final String? intro;
  final String? authorNote;

  /// 「18.00元」→ 18.0（无数字返回 null）。
  double? get priceValue => double.tryParse(
    RegExp(r'[\d.]+').firstMatch(price ?? '')?.group(0) ?? '',
  );
}

/// 搜索结果列表行（V1.44 先搜后加 · 原型 bsrMock 的字段形态）。
/// suggest 路只有 书名/作者/年份/封面；搜索页 window.__DATA__ 路多给
/// 出版社/定价/评分（abstract 拆「作者 / 出版社 / 年-月 / 定价」）。
class DoubanSearchRow {
  const DoubanSearchRow({
    required this.subjectId,
    required this.title,
    this.author,
    this.publisher,
    this.pubDate,
    this.price,
    this.rating,
    this.coverUrl,
  });
  final String subjectId;
  final String title;
  final String? author;
  final String? publisher;
  final String? pubDate;
  final String? price;

  /// 豆瓣 10 分制评分（列表右侧只读展示，不换算本地 5 星）。
  final double? rating;
  final String? coverUrl;
}

/// 未命中的成因（真机反馈：过去全被写成「离线或未命中」，无从下手）。
/// blocked＝识别到豆瓣风控（403/429 或拦截页文案），已进熔断冷却。
enum IsbnMiss { none, tooShort, network, unparseable, blocked }

/// [IsbnEnrich.lookupDetailed] 的结果：命中给元信息，未命中给归类。
class IsbnOutcome {
  const IsbnOutcome(this.meta, this.miss, {this.viaSuggest = false});
  final IsbnBookMeta? meta;
  final IsbnMiss miss;

  /// true＝ISBN 那条路没走通，靠**书名**在豆瓣联想接口反查到条目后补全的
  /// （UI 要说清「按书名匹配」，别让用户以为是 ISBN 命中的）。
  final bool viaSuggest;
  bool get hit => meta != null;
}

class IsbnEnrich {
  IsbnEnrich._();

  /// douban_meta 缓存行 → 元信息（列名与 v23 DDL 对齐 · 供表单回填）。
  static IsbnBookMeta metaFromRow(Map<String, Object?> r) => IsbnBookMeta(
    title: '${r['title'] ?? ''}',
    author: r['author'] as String?,
    publisher: r['publisher'] as String?,
    pubDate: r['pub_date'] as String?,
    pages: r['pages'] as int?,
    rating: (r['rating'] as num?)?.toDouble(),
    coverUrl: r['cover_url'] as String?,
  );

  /// 10/13 位纯数字＝ISBN（走 /isbn/ 自动重定向）；其余按豆瓣 subject_id。
  static Uri urlFor(String code) =>
      RegExp(r'^(\d{10}|\d{13})$').hasMatch(code)
          ? Uri.parse('https://book.douban.com/isbn/$code/')
          : Uri.parse('https://book.douban.com/subject/$code/');

  static final _titleRe = RegExp(r'property="v:itemreviewed">([^<]+)<');
  // 作者/出版社：桌面页里标签与链接之间夹着换行缩进，且作者链接在 </span> 之内，
  // 用「详情链接 href 形态」直取最稳；无链接页（少数条目）再退到纯文本。
  static final _authorMicro = RegExp(r'property="v:author"[^>]*>([^<]+)<');
  static final _authorLink = RegExp(
    r'/author/[^"]*"[^>]*>\s*([^<]+?)\s*</a>',
  );
  static final _authorText = RegExp(
    r'作者[\s\S]{0,16}?</span>[:：]?\s*([^<\n]+?)\s*<',
  );
  static final _pubLink = RegExp(
    r'/press/[^"]*"[^>]*>\s*([^<]+?)\s*</a>',
  );
  static final _pubText = RegExp(
    r'出版社[\s\S]{0,16}?</span>[:：]?\s*(?:&nbsp;)?\s*([^<\n]+?)\s*<',
  );
  static final _pubDate = RegExp(
    r'出版年[\s\S]{0,16}?</span>[^\d]*(\d{4})[-/.年](\d{1,2})?',
  );
  static final _pages = RegExp(r'页数[\s\S]{0,16}?</span>[^\d]*(\d+)');
  static final _rating = RegExp(r'rating_num[^>]*>\s*([\d.]+)\s*<');
  static final _cover = RegExp(r'id="mainpic"[\s\S]{0,400}?src="([^"]+)');
  // V1.44 详情页扩展字段：真实形态 `<span class="pl">装帧:</span> 平装<br>`
  // （冒号在 span 内；丛书值带 &nbsp; 后接 <a>；测试钉 douban_isbn_desktop.html）。
  static String? _plText(String html, String label) {
    final m = RegExp(
      'class="pl">[^<]*$label[^<]*</span>[:：]?\\s*(?:&nbsp;)?\\s*([^<]+?)\\s*<',
    ).firstMatch(html);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty || v == '-') ? null : v;
  }

  static final _seriesLink = RegExp(
    r'class="pl">[^<]*丛书[^<]*</span>(?:&nbsp;)?\s*<a[^>]*>\s*([^<]+?)\s*</a>',
  );
  static final _isbnVal = RegExp(
    r'class="pl">[^<]*ISBN[^<]*</span>[:：]?\s*(\d{10,13})',
  );
  static final _wordCount = RegExp(
    r'class="pl">[^<]*字数[^<]*</span>[:：]?\s*(?:&nbsp;)?\s*([\d,]+)',
  );
  static final _ogDesc = RegExp(
    r'property="og:description"\s+content="([^"]*)"',
  );
  static final _authorInfo = RegExp(
    r'id="author_info"[\s\S]{0,60}?>([\s\S]{1,2000}?)</div>',
  );

  /// 豆瓣书目页 → 结构化元信息；非书目页（无标题节点）返回 null。
  static IsbnBookMeta? parse(String html) {
    final title = _titleRe.firstMatch(html)?.group(1)?.trim();
    if (title == null || title.isEmpty) return null;
    final rawAuthor =
        _authorMicro.firstMatch(html)?.group(1)?.trim() ??
        _authorLink.firstMatch(html)?.group(1)?.trim() ??
        _authorText.firstMatch(html)?.group(1)?.trim();
    final publisher =
        _pubLink.firstMatch(html)?.group(1)?.trim() ??
        _pubText.firstMatch(html)?.group(1)?.replaceAll(RegExp(r'[:：\s]'), '');
    final pd = _pubDate.firstMatch(html);
    final pubDate =
        pd == null
            ? null
            : pd.group(2) == null
            ? pd.group(1)
            : '${pd.group(1)}-${(int.parse(pd.group(2)!) < 10 ? '0' : '')}${pd.group(2)}';
    return IsbnBookMeta(
      title: title,
      // 去掉「[日] 」「[美] 」等国别前缀（作者库口径）。
      author: rawAuthor?.replaceFirst(RegExp(r'^\[[^\]]{1,8}\]\s*'), '').trim(),
      publisher: (publisher?.isEmpty ?? true) ? null : publisher,
      pubDate: pubDate,
      pages: int.tryParse(_pages.firstMatch(html)?.group(1) ?? ''),
      rating: double.tryParse(_rating.firstMatch(html)?.group(1) ?? ''),
      coverUrl: _cover.firstMatch(html)?.group(1),
      // V1.44 照填字段（无则 null，表单留空由用户补）。
      translator: _plText(html, '译者'),
      series: _seriesLink.firstMatch(html)?.group(1)?.trim(),
      binding: _plText(html, '装帧'),
      price: _plText(html, '定价'),
      wordCount: int.tryParse(
        (_wordCount.firstMatch(html)?.group(1) ?? '').replaceAll(',', ''),
      ),
      isbn: _isbnVal.firstMatch(html)?.group(1),
      intro: _ogDesc.firstMatch(html)?.group(1)?.trim(),
      authorNote: _plainFromHtml(_authorInfo.firstMatch(html)?.group(1)),
    );
  }

  /// 简介类 HTML 片段 → 纯文本（去标签、压空白；空返 null）。
  static String? _plainFromHtml(String? frag) {
    if (frag == null) return null;
    final t = frag
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.isEmpty ? null : (t.length > 800 ? '${t.substring(0, 800)}…' : t);
  }

  /// 带成因归类的查询：UI 用它把「网络不通 / 豆瓣未收录 / 访问受限」分开显示。
  ///
  /// [title] 非空时启用**书名兜底**：豆瓣 `/isbn/` 只认它登记过的条码，且桌面
  /// 整页在移动网络下偶发断连；这两条路都走不通时，用书名打联想接口
  /// （`/j/subject_suggest`，约 1KB JSON）反查 subject_id 再抓详情页，
  /// 连详情页也抓不到时就吃联想结果里的简版字段（书名/作者/年份/封面）。
  /// [author] 非空时联想空结果会再用「书名+作者」重试一次（calibre-douban 的
  /// 检索词加作者手法，同名书少抓一次整页）；仍空则退**搜索页兜底**
  /// （2026-09-26 本机实测 suggest 对部分出口 IP 恒返回 []，
  /// 而 search.douban.com 正常出真链接）。
  /// 熔断（[DoubanGuard]）生效时**不发任何请求**，直接返回 blocked。
  static Future<IsbnOutcome> lookupDetailed(
    String code, {
    required IsbnPageFetcher fetch,
    String? title,
    String? author,
  }) async {
    final c = code.trim();
    if (c.length < 8) return const IsbnOutcome(null, IsbnMiss.tooShort);
    if (DoubanGuard.active()) return const IsbnOutcome(null, IsbnMiss.blocked);
    DoubanGuard.clearLastFetchBlocked();
    // 真机取证（2026-09-27）：每次查询落一条「带没带登录态」——只记状态，
    // Cookie 值永不进日志（AppLog.sanitize 亦会脱敏，双保险）。
    AppLog.add(
      DoubanCookie.value != null
          ? '豆瓣书目查询（$c）· 带登录态 Cookie'
          : '豆瓣书目查询（$c）· 匿名（未配置 Cookie）',
    );
    var miss = IsbnMiss.network;
    try {
      final url = urlFor(c);
      final html = await fetch(url);
      if (html != null) {
        if (doubanBlockedPage(html)) {
          DoubanGuard.trip();
          AppLog.add('豆瓣详情页命中拦截页（$c）', level: LhLevel.warn);
          return const IsbnOutcome(null, IsbnMiss.blocked);
        }
        final meta = parse(html);
        if (meta != null) return IsbnOutcome(meta, IsbnMiss.none);
        // 取到页面却没有书目节点：多半是该码未收录/跳到了聚合页，与「离线」不是一回事。
        AppLog.add('豆瓣页面已取但解析不出书目（$c）：$url', level: LhLevel.warn);
        miss = IsbnMiss.unparseable;
      } else if (DoubanGuard.lastFetchBlocked) {
        // 默认 fetcher 遇到过 403/429：这是被风控，不是「没这本书」。
        DoubanGuard.trip();
        return const IsbnOutcome(null, IsbnMiss.blocked);
      }
    } catch (e) {
      AppLog.add('豆瓣书目查询异常（$c）：$e', level: LhLevel.error);
    }
    final t = title?.trim() ?? '';
    if (t.isEmpty) return IsbnOutcome(null, _settle(miss));
    final light = await _byTitle(t, fetch: fetch, author: author);
    if (light == null) return IsbnOutcome(null, _settle(miss));
    AppLog.add('ISBN 未命中（$c）· 已按书名《$t》在豆瓣匹配补全', level: LhLevel.warn);
    return IsbnOutcome(light, IsbnMiss.none, viaSuggest: true);
  }

  /// 兜底链走完后收尾：期间若识别到风控（trip 过），一律升级为 blocked。
  static IsbnMiss _settle(IsbnMiss miss) =>
      DoubanGuard.active() ? IsbnMiss.blocked : miss;

  /// 联想接口 URL（q 为书名，豆瓣不支持按 ISBN 查）。
  static Uri suggestUrl(String q) => Uri.parse(
    'https://book.douban.com/j/subject_suggest?q=${Uri.encodeComponent(q)}',
  );

  /// 旧版图书搜索页（suggest 恒空时的第二入口 · 2026-09-26 本机实测可用）。
  static Uri searchUrl(String q) => Uri.parse(
    'https://search.douban.com/book/subject_search?search_text='
    '${Uri.encodeComponent(q)}',
  );

  static final _searchSubject = RegExp(r'book\.douban\.com/subject/(\d+)/');

  /// 从搜索页 HTML 提取 subject_id（去重保序，最多 [limit] 个）。
  static List<String> parseSearchSubjectIds(String html, {int limit = 5}) {
    final seen = <String>{};
    for (final m in _searchSubject.allMatches(html)) {
      seen.add(m.group(1)!);
      if (seen.length >= limit) break;
    }
    return seen.toList();
  }

  /// 搜索页内嵌 `window.__DATA__ = {…"items":[…]…}` → 列表行。
  /// 真页 fixture 钉格式：items[].abstract＝「作者 / 出版社 / 年-月 / 定价」，
  /// rating.value 为豆瓣 10 分制，url 带 subject_id。
  static List<DoubanSearchRow> parseSearchRows(String html, {int limit = 20}) {
    final at = html.indexOf('window.__DATA__');
    if (at < 0) return const [];
    final brace = html.indexOf('{', at);
    if (brace < 0) return const [];
    final blob = _balancedBraces(html, brace);
    if (blob == null) return const [];
    try {
      final decoded = jsonDecode(blob);
      if (decoded is! Map) return const [];
      final items = decoded['items'];
      if (items is! List) return const [];
      final rows = <DoubanSearchRow>[];
      for (final e in items) {
        if (e is! Map) continue;
        final id = '${e['id'] ?? ''}';
        final title = '${e['title'] ?? ''}'.trim();
        if (id.isEmpty || title.isEmpty) continue;
        // abstract 拆四段（缺段容忍）：作者 / 出版社 / 年-月 / 定价。
        final seg =
            '${e['abstract'] ?? ''}'
                .split(RegExp(r'\s*/\s*'))
                .map((s) => s.trim())
                .toList();
        final rating = e['rating'];
        rows.add(
          DoubanSearchRow(
            subjectId: id,
            title: title,
            author: seg.isNotEmpty
                ? seg[0].replaceAll(RegExp(r'^\[[^\]]{1,8}\]\s*'), '').trim()
                : null,
            publisher: seg.length > 1 && seg[1].isNotEmpty ? seg[1] : null,
            pubDate: seg.length > 2 && seg[2].isNotEmpty ? seg[2] : null,
            price: seg.length > 3 && seg[3].isNotEmpty ? seg[3] : null,
            rating: rating is Map
                ? (rating['value'] as num?)?.toDouble()
                : null,
            coverUrl: '${e['cover_url'] ?? ''}'.trim().isEmpty
                ? null
                : '${e['cover_url']}'.trim(),
          ),
        );
        if (rows.length >= limit) break;
      }
      return rows;
    } catch (_) {
      return const [];
    }
  }

  /// 从 [start] 处的 `{` 起做括号配对（跳过字符串字面量与转义），返回完整 JSON。
  static String? _balancedBraces(String s, int start) {
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < s.length; i++) {
      final ch = s[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (ch == r'\') {
          esc = true;
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }

  /// V1.44 先搜后加 · 列表级搜索：suggest 先行（约 1KB JSON），空则退
  /// 搜索页 `window.__DATA__`（本机出口 IP suggest 恒空即走这条路）。
  /// 熔断生效期零请求直接空列表（UI 显「豆瓣访问受限 · 稍后再试」）。
  static Future<List<DoubanSearchRow>> searchList(
    String q, {
    required IsbnPageFetcher fetch,
  }) async {
    final k = q.trim();
    if (k.length < 2 || DoubanGuard.active()) return const [];
    try {
      final rows = await _suggestRows(k, fetch);
      if (DoubanGuard.active()) return const [];
      if (rows.isNotEmpty) {
        return rows
            .map((r) {
              final id = '${r['id'] ?? ''}'.trim();
              final title = '${r['title'] ?? ''}'.trim();
              if (id.isEmpty || title.isEmpty) return null;
              final author = '${r['author_name'] ?? ''}'
                  .replaceFirst(RegExp(r'^\[[^\]]{1,8}\]\s*'), '')
                  .trim();
              final year = '${r['year'] ?? ''}'.trim();
              final pic = '${r['pic'] ?? ''}'.trim();
              return DoubanSearchRow(
                subjectId: id,
                title: title,
                author: author.isEmpty ? null : author,
                pubDate: RegExp(r'^\d{4}(-\d{1,2})?$').hasMatch(year)
                    ? year
                    : null,
                coverUrl: pic.isEmpty ? null : pic,
              );
            })
            .whereType<DoubanSearchRow>()
            .toList();
      }
    } catch (e) {
      AppLog.add('豆瓣联想列表异常（《$k》）：$e', level: LhLevel.error);
    }
    if (DoubanGuard.active()) return const [];
    try {
      final html = await fetch(searchUrl(k));
      if (html == null) return const [];
      // 先解析再判拦截：真数据页偶尔夹风控文案（搜索页带 __DATA__ 就不该
      // 被误判封禁——2026-09-27 真机「出列表却触发熔断」的成因），解析为空才认拦截。
      final rows = parseSearchRows(html);
      if (rows.isEmpty && doubanBlockedPage(html)) {
        DoubanGuard.trip();
        return const [];
      }
      if (rows.isNotEmpty) {
        AppLog.add('豆瓣联想无结果 · 搜索页出 ${rows.length} 条（《$k》）');
      }
      return rows;
    } catch (e) {
      AppLog.add('豆瓣搜索页列表异常（《$k》）：$e', level: LhLevel.error);
      return const [];
    }
  }

  /// 点搜索结果 → 按 subject_id 抓详情页全字段（表单预填用）。
  static Future<IsbnBookMeta?> detailById(
    String subjectId, {
    required IsbnPageFetcher fetch,
  }) => _detailById(subjectId, fetch);

  /// 书名 → 豆瓣条目：先拿 subject_id 抓详情页（字段全），抓不到退简版字段。
  static Future<IsbnBookMeta?> _byTitle(
    String title, {
    required IsbnPageFetcher fetch,
    String? author,
  }) async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await _suggestRows(title, fetch);
      if (rows.isEmpty && (author?.trim().isNotEmpty ?? false)) {
        rows = await _suggestRows('$title ${author!.trim()}', fetch);
      }
      if (DoubanGuard.active()) return null;
    } catch (e) {
      AppLog.add('豆瓣联想接口异常（《$title》）：$e', level: LhLevel.error);
      return null;
    }
    if (rows.isEmpty) {
      final id = await _bySearchPage(title, fetch);
      if (id == null) return null;
      return _detailById(id, fetch);
    }
    // 同名书很多：书名完全一致的优先，其次取第一条（豆瓣按热度排）。
    Map<String, dynamic> pick = rows.first;
    for (final r in rows) {
      if ('${r['title']}'.trim() == title) {
        pick = r;
        break;
      }
    }
    final id = '${pick['id'] ?? ''}'.trim();
    if (id.length >= 6) {
      final meta = await _detailById(id, fetch);
      if (meta != null) return meta;
    }
    final authorName = '${pick['author_name'] ?? ''}'
        .replaceFirst(RegExp(r'^\[[^\]]{1,8}\]\s*'), '')
        .trim();
    final year = '${pick['year'] ?? ''}'.trim();
    final pic = '${pick['pic'] ?? ''}'.trim();
    final t = '${pick['title'] ?? ''}'.trim();
    if (t.isEmpty) return null;
    return IsbnBookMeta(
      title: t,
      author: authorName.isEmpty ? null : authorName,
      pubDate: RegExp(r'^\d{4}$').hasMatch(year) ? year : null,
      coverUrl: pic.isEmpty ? null : pic,
    );
  }

  static Future<List<Map<String, dynamic>>> _suggestRows(
    String q,
    IsbnPageFetcher fetch,
  ) async {
    final raw = await fetch(suggestUrl(q));
    if (raw == null) return const [];
    if (doubanBlockedPage(raw)) {
      DoubanGuard.trip();
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  /// 搜索页兜底：suggest 全空时按书名搜，取第一条 subject_id。
  static Future<String?> _bySearchPage(
    String q,
    IsbnPageFetcher fetch,
  ) async {
    try {
      final html = await fetch(searchUrl(q));
      if (html == null) return null;
      if (doubanBlockedPage(html)) {
        DoubanGuard.trip();
        return null;
      }
      final ids = parseSearchSubjectIds(html);
      if (ids.isEmpty) return null;
      AppLog.add('联想接口空结果 · 已改走豆瓣搜索页找《$q》', level: LhLevel.warn);
      return ids.first;
    } catch (e) {
      AppLog.add('豆瓣搜索页异常（《$q》）：$e', level: LhLevel.error);
      return null;
    }
  }

  static Future<IsbnBookMeta?> _detailById(
    String id,
    IsbnPageFetcher fetch,
  ) async {
    try {
      final html = await fetch(urlFor(id));
      if (html == null) return null;
      if (doubanBlockedPage(html)) {
        DoubanGuard.trip();
        return null;
      }
      return parse(html);
    } catch (e) {
      AppLog.add('豆瓣详情页异常（subject/$id）：$e', level: LhLevel.error);
      return null;
    }
  }

  static Future<IsbnBookMeta?> lookup(
    String code, {
    required IsbnPageFetcher fetch,
    String? title,
    String? author,
  }) async => (await lookupDetailed(
    code,
    fetch: fetch,
    title: title,
    author: author,
  )).meta;

  /// 封面落本地（应用私有目录 · BsCover/coverPath 直接读文件）。
  static Future<String?> saveCover(
    IsbnBookMeta meta,
    String code, {
    required IsbnBytesFetcher fetchBytes,
    String? dirOverride,
  }) async {
    final u = meta.coverUrl;
    if (u == null || u.isEmpty) return null;
    try {
      final bytes = await fetchBytes(Uri.parse(u));
      if (bytes == null || bytes.isEmpty) return null;
      final base =
          dirOverride ?? (await getApplicationDocumentsDirectory()).path;
      final dir = Directory('$base/book_covers');
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = File('${dir.path}/isbn_${code.trim()}.jpg');
      await f.writeAsBytes(bytes);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}
