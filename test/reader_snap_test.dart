import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';

// 批5 · 排版快照（DocStore）回归：round-trip / 指纹失效 / 懒读章 / 回收。
// 纯 IO 单测（非 widget 测试），真文件读写不受 FakeAsync 限制。

EpubDoc _doc({String title = '快照书'}) => EpubDoc(
  format: 'EPUB3',
  title: title,
  author: '甲',
  publisher: '乙社',
  pubDate: '2020',
  language: 'zh',
  description: '简介',
  coverBytes: Uint8List.fromList([1, 2, 3, 4]),
  coverName: 'cov.jpg',
  toc: const [
    EpubTocItem(label: '上部', href: 'a.xhtml', level: 1),
    EpubTocItem(label: '一章', href: 'a.xhtml', level: 2),
  ],
  chapters: [
    EpubChapter(href: 'a.xhtml', title: '一章', paras: [
      const EpubPara(
        kind: EpubParaKind.heading,
        text: '第一章',
        headingLevel: 1,
      ),
      const EpubPara(
        kind: EpubParaKind.text,
        text: '看外链',
        links: [
          EpubLink(start: 1, end: 3, href: 'https://x.cn', external: true),
          EpubLink(start: 0, end: 1, href: 'b.xhtml', external: false),
        ],
      ),
      const EpubPara(kind: EpubParaKind.image, imgSrc: 'i.png', alt: '图'),
      const EpubPara(kind: EpubParaKind.quote, text: '引文'),
    ]),
    EpubChapter(href: 'b.xhtml', title: '二章', paras: [
      const EpubPara(kind: EpubParaKind.text, text: '唯一段。'),
    ]),
  ],
  imageCount: 9,
  totalChars: 123,
  fontCount: 2,
  bookmarkCount: 1,
);

void main() {
  late Directory tmp;
  late String src;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lh_snap');
    src = '${tmp.path}/book.epub';
    File(src).writeAsBytesSync(List.filled(1000, 7));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String fp() => DocStore.fingerprint(src);

  test('round-trip：元数据/目录/段落（含链接与图）全字段一致', () async {
    final doc = _doc();
    await DocStore.save(tmp.path, 's1', fp(), doc);
    // 不传 srcPath＝不重挂懒归档（本用例只验文本/元数据，不测图片按需解码）。
    final back = await DocStore.load(tmp.path, 's1', fp());
    expect(back, isNotNull);
    expect(back!.title, '快照书');
    expect(back.author, '甲');
    expect(back.publisher, '乙社');
    expect(back.pubDate, '2020');
    expect(back.language, 'zh');
    expect(back.description, '简介');
    expect(back.coverName, 'cov.jpg');
    expect(back.coverBytes, [1, 2, 3, 4]);
    expect(back.imageCount, 9);
    expect(back.totalChars, 123);
    expect(back.fontCount, 2);
    expect(back.bookmarkCount, 1);
    expect(back.toc.length, 2);
    expect(back.toc[1].label, '一章');
    expect(back.toc[1].level, 2);
    expect(back.chapters.length, 2);
    final p0 = back.chapters[0].paras;
    expect(p0[0].kind, EpubParaKind.heading);
    expect(p0[0].headingLevel, 1);
    expect(p0[1].links.length, 2);
    expect(p0[1].links[0].external, isTrue);
    expect(p0[1].links[1].href, 'b.xhtml');
    expect(p0[2].kind, EpubParaKind.image);
    expect(p0[2].imgSrc, 'i.png');
    expect(p0[3].kind, EpubParaKind.quote);
    expect(back.chapters[1].paras.single.text, '唯一段。');
    expect(back.chapters[1].charCount, 4);
    back.lazy?.dispose();
  });

  test('指纹不符/源缺失/坏索引＝null（调用方回落解析）', () async {
    final doc = _doc();
    await DocStore.save(tmp.path, 's2', fp(), doc);
    expect(await DocStore.load(tmp.path, 's2', '999|0', srcPath: src), isNull);
    // 源文件被删 → 指纹空 → 直接 null（不读盘）。
    File(src).deleteSync();
    expect(DocStore.fingerprint(src), '');
    expect(await DocStore.load(tmp.path, 's2', '', srcPath: src), isNull);
    // 索引损坏 → null 不抛。
    File(src).writeAsBytesSync(List.filled(1000, 7));
    File(DocStore.dirFor(tmp.path, 's2') + '/index.json')
        .writeAsStringSync('{坏档');
    expect(
      await DocStore.load(tmp.path, 's2', fp(), srcPath: src),
      isNull,
    );
  });

  test('懒读章：length 不触盘；越界/坏区间回落空段而不抛', () async {
    await DocStore.save(tmp.path, 's3', fp(), _doc());
    final back = await DocStore.load(tmp.path, 's3', fp());
    expect(back!.chapters.length, 2); // 只读索引，不 materialize
    // 篡改 data.bin 长度 → 章内读失败应回落空段（渲染不崩）。
    File(DocStore.dirFor(tmp.path, 's3') + '/data.bin')
        .writeAsBytesSync([1, 2]);
    expect(back.chapters[1].paras, isEmpty);
    expect(back.chapters[1].href, 'b.xhtml');
    back.lazy?.dispose();
  });

  test('sizeOf/remove：清理后目录不存在、体积归零', () async {
    await DocStore.save(tmp.path, 's4', fp(), _doc());
    expect(await DocStore.sizeOf(tmp.path, 's4'), greaterThan(0));
    await DocStore.remove(tmp.path, 's4');
    expect(await DocStore.sizeOf(tmp.path, 's4'), 0);
    expect(await DocStore.load(tmp.path, 's4', fp(), srcPath: src), isNull);
  });

  test('真实大书（素材在才跑）：快照载入远快于整本解析且内容一致', () async {
    final agatha = File(
      '${Platform.environment['USERPROFILE']}'
      '\\Downloads\\阿加莎·克里斯蒂侦探小说大全集（全85册） (阿加莎·_ '
      '(z-library.sk, 1lib.sk, z-lib.sk).epub',
    );
    if (!agatha.existsSync()) return;
    final t0 = DateTime.now();
    final doc = await EpubDoc.openFileDetached(agatha.path);
    final parseMs = DateTime.now().difference(t0).inMilliseconds;
    final probe = doc.chapters[1200];
    final probeText = probe.paras.map((p) => p.text).join();
    doc.lazy?.dispose(); // 快照写入不再需要句柄

    final t1 = DateTime.now();
    await DocStore.save(tmp.path, 'ag', DocStore.fingerprint(agatha.path), doc);
    final saveMs = DateTime.now().difference(t1).inMilliseconds;

    final t2 = DateTime.now();
    final back = await DocStore.load(
      tmp.path,
      'ag',
      DocStore.fingerprint(agatha.path),
      srcPath: agatha.path,
    );
    final loadMs = DateTime.now().difference(t2).inMilliseconds;
    expect(back, isNotNull);
    expect(back!.chapters.length, doc.chapters.length);
    final p = back.chapters[1200];
    expect(p.href, probe.href);
    expect(p.paras.map((x) => x.text).join(), probeText);
    expect(loadMs, lessThan(parseMs), reason: '快照=$loadMs 解析=$parseMs');
    if (kDebugMode) {
      debugPrint('snap 真实大书：parse=${parseMs}ms save=${saveMs}ms load=${loadMs}ms');
    }
    back.lazy?.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
