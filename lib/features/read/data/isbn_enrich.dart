import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 保真批F2 · ISBN 命中 → 豆瓣书目补全。
/// 网络层全部走可注入 fetcher：默认真实 HttpClient；widget 测试注入假实现
/// （禁真实异步 I/O · 见记忆 feedback-widget-test-no-real-async-io）。

typedef IsbnPageFetcher = Future<String?> Function(Uri uri);
typedef IsbnBytesFetcher = Future<List<int>?> Function(Uri uri);

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

Future<String?> _httpGetText(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent =
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36';
  try {
    final res = await (await client.getUrl(uri)).close()
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return await utf8.decoder
        .bind(res)
        .join()
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<List<int>?> _httpGetBytes(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent =
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36';
  try {
    final res = await (await client.getUrl(uri)).close()
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return await res
        .fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        )
        .timeout(const Duration(seconds: 10));
  } catch (_) {
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

class IsbnEnrich {
  IsbnEnrich._();

  /// 10/13 位纯数字＝ISBN（走 /isbn/ 自动重定向）；其余按豆瓣 subject_id。
  static Uri urlFor(String code) =>
      RegExp(r'^(\d{10}|\d{13})$').hasMatch(code)
          ? Uri.parse('https://book.douban.com/isbn/$code/')
          : Uri.parse('https://book.douban.com/subject/$code/');

  static final _titleRe = RegExp(r'property="v:itemreviewed">([^<]+)<');
  static final _authorMicro = RegExp(r'property="v:author"[^>]*>([^<]+)<');
  static final _authorLink = RegExp(
    r'作者[^\n]{0,40}?</span>[^\n]{0,80}?<a[^>]*>([^<]+)</a>',
  );
  static final _pubLink = RegExp(
    r'出版社[^\n]{0,40}?</span>[^\n]{0,80}?<a[^>]*>([^<]+)</a>',
  );
  static final _pubText = RegExp(
    r'出版社[^\n]{0,40}?</span>([^<]+?)<',
  );
  static final _pubDate = RegExp(
    r'出版年[^\n]{0,40}?</span>[^\d]*(\d{4})[-/.年](\d{1,2})?',
  );
  static final _pages = RegExp(r'页数[^\n]{0,40}?</span>[^\d]*(\d+)');
  static final _rating = RegExp(r'rating_num[^>]*>([\d.]+)<');
  static final _cover = RegExp(r'id="mainpic"[\s\S]{0,400}?src="([^"]+)');

  /// 豆瓣书目页 → 结构化元信息；非书目页（无标题节点）返回 null。
  static IsbnBookMeta? parse(String html) {
    final title = _titleRe.firstMatch(html)?.group(1)?.trim();
    if (title == null || title.isEmpty) return null;
    final rawAuthor =
        _authorMicro.firstMatch(html)?.group(1)?.trim() ??
        _authorLink.firstMatch(html)?.group(1)?.trim();
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

  static Future<IsbnBookMeta?> lookup(
    String code, {
    required IsbnPageFetcher fetch,
  }) async {
    final c = code.trim();
    if (c.length < 8) return null;
    try {
      final html = await fetch(urlFor(c));
      return html == null ? null : parse(html);
    } catch (_) {
      return null;
    }
  }

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
          dirOverride ??
          (await getApplicationDocumentsDirectory()).path;
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
