import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/isbn_enrich.dart';

/// 豆瓣防封批（2026-09-26 · calibre-douban 手法移植）单测：
/// UA 池、Cookie 持有器、熔断（拦截页/403/冷却恢复/持久化钩子）、
/// 搜索页兜底解析、suggest「书名+作者」重试链。全部走注入 fetcher，
/// 不碰真实网络（禁真实异步 I/O 口径）。
void main() {
  setUp(() {
    DoubanGuard.reset();
    DoubanGuard.restore(null);
    DoubanCookie.set(null);
    DoubanGuard.persist = null;
  });

  group('UA 池', () {
    test('全部是桌面系（混入移动 UA 会被 m 站分流、microdata 必空）', () {
      expect(doubanUserAgents.length, greaterThanOrEqualTo(3));
      for (final ua in doubanUserAgents) {
        expect(ua, isNot(contains('Android')));
        expect(ua, isNot(contains('iPhone')));
        expect(ua, isNot(contains('Mobile')));
      }
      expect(doubanUserAgent, doubanUserAgents[0]);
      expect(doubanUserAgents, contains(pickDoubanUserAgent()));
    });
  });

  group('Cookie 持有器', () {
    test('空串/纯空格＝未配置；有效值去首尾空白', () {
      DoubanCookie.set('   ');
      expect(DoubanCookie.value, isNull);
      DoubanCookie.set(' ck=1; ll="118351" ');
      expect(DoubanCookie.value, 'ck=1; ll="118351"');
      DoubanCookie.set(null);
      expect(DoubanCookie.value, isNull);
    });
  });

  group('熔断（DoubanGuard）', () {
    test('拦截页文案触发 blocked，冷却期内后续查询一发都不发', () async {
      var calls = 0;
      final first = await IsbnEnrich.lookupDetailed(
        '9787108009821',
        fetch: (u) async {
          calls++;
          return '<html><head><title>禁止访问</title></head></html>';
        },
      );
      expect(first.miss, IsbnMiss.blocked);
      expect(calls, 1);
      final second = await IsbnEnrich.lookupDetailed(
        '9787108009821',
        fetch: (u) async {
          calls++;
          return null;
        },
      );
      expect(second.miss, IsbnMiss.blocked);
      expect(calls, 1, reason: '冷却中不得再发任何豆瓣请求');
    });

    test('默认 fetcher 报 403（noteHttpStatusBlocked）也判 blocked', () async {
      final out = await IsbnEnrich.lookupDetailed(
        '9787108009821',
        fetch: (u) async {
          DoubanGuard.noteHttpStatusBlocked();
          return null;
        },
      );
      expect(out.miss, IsbnMiss.blocked);
    });

    test('trip 走 persist 钩子；restore 过去值自动放行', () async {
      int? saved;
      DoubanGuard.persist = (ms) => saved = ms;
      final before = DateTime.now().millisecondsSinceEpoch;
      await IsbnEnrich.lookupDetailed(
        '9787108009821',
        fetch: (u) async => '<title>禁止访问</title>',
      );
      expect(saved, isNotNull);
      expect(saved!, greaterThan(before));
      expect(
        saved!,
        lessThanOrEqualTo(
            before + DoubanGuard.defaultBlockMinutes * 60000 + 5000),
      );
      // 模拟重启：restore 一个已过期的到期点 → 直接放行。
      DoubanGuard.restore(before - 1);
      expect(DoubanGuard.active(), isFalse);
      var calls = 0;
      final out = await IsbnEnrich.lookupDetailed(
        '9787108009821',
        fetch: (u) async {
          calls++;
          return null;
        },
      );
      expect(calls, 1);
      expect(out.miss, IsbnMiss.network);
    });
  });

  group('搜索页兜底', () {
    test('真页 fixture：提取去重 subject_id 且封顶 limit 个', () {
      final html = File('test/fixtures/douban_search.html').readAsStringSync();
      final ids = IsbnEnrich.parseSearchSubjectIds(html);
      expect(ids, contains('2567698'));
      expect(ids.toSet().length, ids.length, reason: '不得重复');
      expect(IsbnEnrich.parseSearchSubjectIds(html, limit: 3).length, 3);
    });

    test('suggest 全空 → 书名+作者重试 → 搜索页 → 详情页命中', () async {
      final desktop = File('test/fixtures/douban_isbn_desktop.html')
          .readAsStringSync();
      final asked = <String>[];
      final out = await IsbnEnrich.lookupDetailed(
        '9780000000000',
        title: '万历十五年',
        author: '黄仁宇',
        fetch: (u) async {
          final s = u.toString();
          if (s.contains('subject_suggest')) {
            asked.add(Uri.parse(s).queryParameters['q'] ?? '');
            return '[]'; // 本机实测：部分出口 IP 恒空。
          }
          if (s.contains('subject_search')) {
            asked.add('SEARCH');
            return '<a href="https://book.douban.com/subject/1041482/">x</a>';
          }
          if (s.contains('subject/1041482')) {
            asked.add('DETAIL');
            return desktop;
          }
          // /isbn/ 页取到了但没这条书目（未收录形态）。
          asked.add('MISS');
          return '<html><head><title>豆瓣</title></head></html>';
        },
      );
      expect(asked, ['MISS', '万历十五年', '万历十五年 黄仁宇', 'SEARCH', 'DETAIL']);
      expect(out.hit, isTrue);
      expect(out.viaSuggest, isTrue);
    });
  });
}
