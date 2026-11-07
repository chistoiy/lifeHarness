import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart'
    show bgPrefetchOrder;

// 二期批5 · 效率三件（F5-1 邻近章预排 / F5-4 快照保存入 isolate / F5-5 真 LRU）。
// 独立文件防 isolate 污染。

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

const _lorem = '这是一段用于分页实测的中文正文，重复若干次即可稳定地撑满一页。';

EpubDoc _doc({int chapters = 3, int paras = 4}) => EpubDoc(
  format: 'EPUB3',
  title: '效率书',
  author: '甲',
  toc: const [],
  chapters: [
    for (var c = 0; c < chapters; c++)
      EpubChapter(
        href: 'c$c',
        title: '第${c + 1}章',
        paras: [
          EpubPara(kind: EpubParaKind.heading, text: '第${c + 1}章', headingLevel: 1),
          for (var i = 0; i < paras; i++) _p('$c-$i。$_lorem'),
        ],
      ),
  ],
  imageCount: 0,
  totalChars: chapters * paras * _lorem.length,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F5-1 · 邻近章优先的后台预排序', () {
    test('±3 章排在最前，其余环形扫尾，且不重不漏', () {
      final order = bgPrefetchOrder(10, 5);
      expect(order.length, 9, reason: '当前章不进队列');
      expect(order.take(6).toList(), [6, 4, 7, 3, 8, 2]);
      expect(order.toSet(), {0, 1, 2, 3, 4, 6, 7, 8, 9});

      // 口径断言：邻近 3 章必须全部排在「距离 >3」的章之前。
      final far = order.where((c) => (c - 5).abs() > 3).toList();
      expect(far, isNotEmpty);
      final firstFar = order.indexOf(far.first);
      for (final c in order.where((c) => (c - 5).abs() <= 3)) {
        expect(
          order.indexOf(c),
          lessThan(firstFar),
          reason: '第 $c 章离当前章 ≤3，必须排在远端章之前',
        );
      }
    });

    test('边界章不越界（首章/末章）', () {
      final at0 = bgPrefetchOrder(6, 0);
      expect(at0.first, 1);
      expect(at0.contains(-1), isFalse);
      expect(at0.toSet(), {1, 2, 3, 4, 5});
      final last = bgPrefetchOrder(6, 5);
      expect(last.first, 4);
      expect(last.contains(6), isFalse);
      // 单章/空书不排
      expect(bgPrefetchOrder(1, 0), isEmpty);
      expect(bgPrefetchOrder(0, 0), isEmpty);
    });
  });

  group('F5-4 · 快照保存不占主线程且字节稳定', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lh-doc-save-');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('保存跑在别的 isolate，落盘字节两次完全一致', () async {
      final doc = _doc(chapters: 3, paras: 30);
      await DocStore.save(tmp.path, 'b1', 'fp-1', doc);

      final dir = Directory('${tmp.path}/epub_snap/b1');
      final data1 = await File('${dir.path}/data.bin').readAsBytes();
      final idx1 = await File('${dir.path}/index.json').readAsString();

      expect(
        DocStore.debugLastSaveOffMain,
        isTrue,
        reason: 'jsonEncode(全书) 必须离开主 isolate，否则预载期照样卡主线程',
      );
      expect(data1, isNotEmpty);
      expect(idx1, contains('"fp":"fp-1"'));

      // 同一份快照再存一次（覆盖式）：字节必须逐字节相同（md5 口径）。
      await DocStore.save(tmp.path, 'b1', 'fp-1', doc);
      final data2 = await File('${dir.path}/data.bin').readAsBytes();
      final idx2 = await File('${dir.path}/index.json').readAsString();
      expect(data2.length, data1.length);
      expect(data2, data1, reason: 'data.bin 不许因「换 isolate」而变字节');
      expect(idx2, idx1, reason: 'index.json 同样要稳定');
    });

    test('存后能按指纹读回（章数/段数/标题不掉）', () async {
      final doc = _doc(chapters: 4, paras: 5);
      await DocStore.save(tmp.path, 'b2', 'fp-2', doc);
      final back = await DocStore.load(tmp.path, 'b2', 'fp-2');
      expect(back, isNotNull);
      expect(back!.chapters.length, 4);
      expect(back.chapters[2].title, '第3章');
      expect(back.chapters[2].paras.length, 6);
      expect(back.chapters[1].paras[1].text, '1-0。$_lorem');
      // 指纹不符＝不许读（防串书）
      expect(await DocStore.load(tmp.path, 'b2', 'fp-x'), isNull);
    });
  });

  group('F5-5 · 真 LRU 与缓存上界', () {
    test('内存书缓存：命中刷新使用序（热点书不被误逐）', () {
      final c = EpubDocCache(maxLive: 2);
      final a = _doc(chapters: 1);
      final b = _doc(chapters: 2);
      final d = _doc(chapters: 3);
      c.put('a', a);
      c.put('b', b);
      // A 再读一次＝成为最近使用；随后放入 C 应淘汰 B（最久未用），不是 A。
      expect(c.get('a'), same(a));
      c.put('c', d);
      expect(c.get('b'), isNull, reason: 'B 才是最久未用');
      expect(c.get('a'), same(a), reason: '热点书 A 不许被误逐');
      expect(c.get('c'), same(d));
    });

    test('懒章缓存有上界，超界淘汰最久未用章', () async {
      final tmp = await Directory.systemTemp.createTemp('lh-lazy-cap-');
      try {
        final doc = _doc(chapters: LazyChapterList.cacheCap + 6, paras: 2);
        await DocStore.save(tmp.path, 'b3', 'fp-3', doc);
        final back = await DocStore.load(tmp.path, 'b3', 'fp-3');
        final chs = back!.chapters;
        expect(chs, isA<LazyChapterList>());
        final lazy = chs as LazyChapterList;

        // 全量读一遍：缓存必须停在上界，不许把整本 materialize。
        for (var i = 0; i < chs.length; i++) {
          expect(chs[i].title, '第${i + 1}章');
        }
        expect(
          lazy.debugCacheSize,
          LazyChapterList.cacheCap,
          reason: '${chs.length} 章读完仍要停在上界 ${LazyChapterList.cacheCap}',
        );
        // 队首＝最久未用：前面那些章已被逐出。
        expect(lazy.debugCacheOrder.first, chs.length - LazyChapterList.cacheCap);

        // 回读老章（已逐出）把它顶成最近使用，最久未用随之顺延一位。
        expect(chs[0].title, '第1章');
        expect(lazy.debugCacheOrder.last, 0);
        expect(lazy.debugCacheOrder.first, chs.length - LazyChapterList.cacheCap + 1);
      } finally {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      }
    });
  });
}
