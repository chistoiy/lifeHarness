import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/data/isbn_enrich.dart';

/// 真机反馈（2026-09-26）「填了 ISBN 后豆瓣拉不到资源」的回归钉。
/// 两份 fixture 都是**真页抓取**（同一 ISBN 9787108009821）：
/// · douban_isbn_desktop.html ＝ 桌面 UA 拿到的页面（带 v: microdata）→ 必须解析成功；
/// · douban_isbn_mobile.html  ＝ 手机 UA 被服务端改写后的 m.douban 页（无 microdata）
///   → 解析为空，正是旧实现「离线或未命中」的成因，故 UA 已固定为桌面版。
void main() {
  final desktop = File(
    'test/fixtures/douban_isbn_desktop.html',
  ).readAsStringSync();
  final mobile = File('test/fixtures/douban_isbn_mobile.html').readAsStringSync();

  test('桌面页真样本：全字段解析（书名/作者/出版社/出版年/页数/评分/封面）', () {
    final m = IsbnEnrich.parse(desktop);
    expect(m, isNotNull, reason: '真页解析失败＝豆瓣改版或正则不容换行');
    expect(m!.title, '万历十五年');
    expect(m.author, '黄仁宇', reason: '桌面页作者链接在 </span> 内且夹换行缩进');
    expect(m.publisher, '生活·读书·新知三联书店');
    expect(m.pubDate, '1997-05');
    expect(m.pages, 320);
    expect(m.rating, 9.0, reason: 'rating_num 节点里是「 9.0 」带空格');
    expect(m.coverUrl, startsWith('https://img'));
  });

  test('移动页真样本：无 microdata → 解析为空（旧 bug 的成因，UA 已改桌面）', () {
    expect(IsbnEnrich.parse(mobile), isNull);
    // 桌面 UA 常量不得回退成 Android/iPhone：一退就又被导到移动版页面。
    expect(doubanUserAgent, contains('Windows NT'));
  });

  test('lookup：页面取到但解析不出 → 返回 null 且落日志（与离线可区分）', () async {
    final meta = await IsbnEnrich.lookup(
      '9787108009821',
      fetch: (_) async => mobile,
    );
    expect(meta, isNull);
  });

  // 真机第二轮：豆瓣 `/isbn/` 只认它登记过的条码，且 13 万字符的桌面页在移动
  // 网络下常在收 body 时被掐断（日志：Connection closed while receiving data）。
  // 两条路都断时按**书名**走联想接口反查 subject_id 再抓详情页。
  test('书名兜底：ISBN 整页断连 → 联想接口拿 id → 详情页字段齐全', () async {
    const suggestJson =
        '[{"title":"万历十五年","url":"https://book.douban.com/subject/1041482/",'
        '"pic":"https://img9.doubanio.com/view/subject/s/public/s1800355.jpg",'
        '"author_name":"[美] 黄仁宇","year":"1997","type":"b","id":"1041482"},'
        '{"title":"万历十五年（修订版）","id":"26418524","author_name":"黄仁宇",'
        '"year":"2015","type":"b","pic":""}]';
    final urls = <String>[];
    final out = await IsbnEnrich.lookupDetailed(
      '9787108009821',
      title: '万历十五年',
      fetch: (uri) async {
        final u = uri.toString();
        urls.add(u);
        if (u.contains('/isbn/')) return null; // 断连/未登记
        if (u.contains('subject_suggest')) return suggestJson;
        if (u.contains('/subject/1041482/')) return desktop;
        return null;
      },
    );
    expect(out.hit, isTrue);
    expect(out.viaSuggest, isTrue, reason: '要说清是按书名匹配，不是 ISBN 命中');
    expect(out.meta!.title, '万历十五年');
    expect(out.meta!.publisher, '生活·读书·新知三联书店');
    expect(urls, containsAll(<String>[
      'https://book.douban.com/isbn/9787108009821/',
      IsbnEnrich.suggestUrl('万历十五年').toString(),
      'https://book.douban.com/subject/1041482/',
    ]));
  });

  test('书名兜底：详情页也抓不到 → 吃联想简版字段（书名/作者/年份/封面）', () async {
    const suggestJson =
        '[{"title":"万历十五年","author_name":"[美] 黄仁宇","year":"1997",'
        '"id":"1041482","pic":"https://img9.doubanio.com/x/s1800355.jpg"}]';
    final out = await IsbnEnrich.lookupDetailed(
      '9787108009821',
      title: '万历十五年',
      fetch: (uri) async => uri.toString().contains('subject_suggest')
          ? suggestJson
          : null,
    );
    expect(out.hit, isTrue);
    final m = out.meta!;
    expect(m.title, '万历十五年');
    expect(m.author, '黄仁宇', reason: '去掉「[美] 」国别前缀（作者库口径）');
    expect(m.pubDate, '1997');
    expect(m.coverUrl, endsWith('s1800355.jpg'));
    expect(m.pages, isNull, reason: '简版没有页数：留空，不编造');
  });

  test('书名兜底：联想也没有 → 维持原未命中档（网络不通/未收录不混档）', () async {
    final out = await IsbnEnrich.lookupDetailed(
      '9787108009821',
      title: '一本没有的书',
      fetch: (uri) async => uri.toString().contains('subject_suggest') ? '[]' : null,
    );
    expect(out.hit, isFalse);
    expect(out.miss, IsbnMiss.network);
    final unparse = await IsbnEnrich.lookupDetailed(
      '9787108009821',
      title: '一本没有的书',
      fetch: (uri) async => uri.toString().contains('subject_suggest') ? '[]' : mobile,
    );
    expect(unparse.miss, IsbnMiss.unparseable);
  });
}
