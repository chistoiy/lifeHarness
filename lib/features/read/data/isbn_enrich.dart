import 'dart:convert';
import 'dart:io';

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

/// 桌面 UA：豆瓣按 UA 分流移动/桌面版，只有桌面版页面带 v: microdata。
const String doubanUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

Future<HttpClientResponse?> _doubanOpen(
  Uri uri, {
  void Function(HttpClientRequest req)? decorate,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, doubanUserAgent);
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
    decorate?.call(req);
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      AppLog.add('豆瓣请求 HTTP ${res.statusCode} ← $uri', level: LhLevel.warn);
      return null;
    }
    return res;
  } catch (e) {
    // 与「未命中」区分：到这里都是网络层失败（离线/DNS/TLS/超时/重定向超限）。
    AppLog.add('豆瓣请求失败（网络层）：$e ← $uri', level: LhLevel.error);
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String?> _httpGetText(Uri uri) async {
  final res = await _doubanOpen(uri);
  if (res == null) return null;
  try {
    return await utf8.decoder
        .bind(res)
        .join()
        .timeout(const Duration(seconds: 12));
  } catch (e) {
    AppLog.add('豆瓣响应读取失败：$e ← $uri', level: LhLevel.error);
    return null;
  }
}

Future<List<int>?> _httpGetBytes(Uri uri) async {
  // 封面图床（doubanio）偶发校验来源，带 Referer 更稳。
  final res = await _doubanOpen(
    uri,
    decorate: (req) => req.headers.set(
      HttpHeaders.refererHeader,
      'https://book.douban.com/',
    ),
  );
  if (res == null) return null;
  try {
    return await res
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
        .timeout(const Duration(seconds: 12));
  } catch (e) {
    AppLog.add('封面读取失败：$e ← $uri', level: LhLevel.error);
    return null;
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
  });
  final String title;
  final String? author;
  final String? publisher;
  final String? pubDate;
  final int? pages;
  final double? rating;
  final String? coverUrl;
}

/// 未命中的三种成因（真机反馈：过去全被写成「离线或未命中」，无从下手）。
enum IsbnMiss { none, tooShort, network, unparseable }

/// [IsbnEnrich.lookupDetailed] 的结果：命中给元信息，未命中给归类。
class IsbnOutcome {
  const IsbnOutcome(this.meta, this.miss);
  final IsbnBookMeta? meta;
  final IsbnMiss miss;
  bool get hit => meta != null;
}

class IsbnEnrich {
  IsbnEnrich._();

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
    );
  }

  /// 带成因归类的查询：UI 用它把「网络不通 / 豆瓣未收录」分开显示。
  static Future<IsbnOutcome> lookupDetailed(
    String code, {
    required IsbnPageFetcher fetch,
  }) async {
    final c = code.trim();
    if (c.length < 8) return const IsbnOutcome(null, IsbnMiss.tooShort);
    try {
      final url = urlFor(c);
      final html = await fetch(url);
      if (html == null) return const IsbnOutcome(null, IsbnMiss.network);
      final meta = parse(html);
      if (meta == null) {
        // 取到页面却没有书目节点：多半是该码未收录/跳到了聚合页，与「离线」不是一回事。
        AppLog.add('豆瓣页面已取但解析不出书目（$c）：$url', level: LhLevel.warn);
        return const IsbnOutcome(null, IsbnMiss.unparseable);
      }
      return IsbnOutcome(meta, IsbnMiss.none);
    } catch (e) {
      AppLog.add('豆瓣书目查询异常（$c）：$e', level: LhLevel.error);
      return const IsbnOutcome(null, IsbnMiss.network);
    }
  }

  static Future<IsbnBookMeta?> lookup(
    String code, {
    required IsbnPageFetcher fetch,
  }) async => (await lookupDetailed(code, fetch: fetch)).meta;

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
