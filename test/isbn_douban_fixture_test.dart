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
}
