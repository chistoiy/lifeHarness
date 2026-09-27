import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/epub_doc.dart';

// V1.50 批1 · EPUB 容器解析选型验证（自研 archive+xml/html）。
// 独立文件防 isolate 污染；fixture 用 ZipEncoder 现场打包，不引外部书。

List<int> _b(String s) => utf8.encode(s);

Archive _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, content) {
    final bytes = _b(content);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return a;
}

Uint8List _zipBytes(Map<String, String> files) =>
    Uint8List.fromList(ZipEncoder().encode(_zip(files))!);

const _container =
    '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''';

String _opf2({bool coverMeta = true}) => '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书甲</dc:title>
    <dc:creator>某某</dc:creator>
    <dc:publisher>某出版社</dc:publisher>
    <dc:date>2020-01-02</dc:date>
    <dc:language>zh</dc:language>
    <dc:description>一本用于解析验证的书。</dc:description>
    ${coverMeta ? '<meta name="cover" content="cover-img"/>' : ''}
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="chap%202.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-img" href="images/cover.jpg" media-type="image/jpeg"/>
    <item id="img1" href="images/p1.png" media-type="image/png"/>
    <item id="f1" href="fonts/x.otf" media-type="application/vnd.adobe.x-opentype"/>
  </manifest>
  <spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''';

const _ncx = '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="p1" playOrder="1">
      <navLabel><text>第一部</text></navLabel>
      <content src="chapter1.xhtml"/>
      <navPoint id="p1-1" playOrder="2"><navLabel><text>第一章</text></navLabel><content src="chapter1.xhtml#s1"/></navPoint>
      <navPoint id="p1-2" playOrder="3"><navLabel><text>第二章</text></navLabel><content src="chap 2.xhtml"/></navPoint>
    </navPoint>
    <navPoint id="p2" playOrder="4">
      <navLabel><text>第二部</text></navLabel>
      <content src="chap 2.xhtml"/>
    </navPoint>
  </navMap>
  <pageList>
    <pageTarget id="1" type="front" value="1"><navLabel><text>封面</text></navLabel><content src="chapter1.xhtml"/></pageTarget>
    <pageTarget id="2" type="normal" value="2"><navLabel><text>正文页</text></navLabel><content src="chap 2.xhtml"/></pageTarget>
  </pageList>
</ncx>''';

const _ch1 = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>1</title></head>
<body>
  <h1>章一标题</h1>
  <p>第一段 正文。</p>
  <p>第二段　正文  带
换行与空白。</p>
  <blockquote>引文一段。</blockquote>
  <figure><img src="images/p1.png" alt="插图一"/><figcaption>图一说明</figcaption></figure>
  <p>第三段 正文。</p>
</body></html>''';

const _ch2 = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>2</title></head>
<body><h2>章二标题</h2><p>第二章 内容。</p></body></html>''';

Map<String, String> _epub2Files() => {
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': _opf2(),
  'OEBPS/toc.ncx': _ncx,
  'OEBPS/chapter1.xhtml': _ch1,
  'OEBPS/chap 2.xhtml': _ch2,
  'OEBPS/images/cover.jpg': 'JPEGDATA',
  'OEBPS/images/p1.png': 'PNGDATA',
  'OEBPS/fonts/x.otf': 'FONT',
};

Uint8List _epub2() => _zipBytes(_epub2Files());

String _opf3() => '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书乙</dc:title><dc:creator>乙作者</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-img" href="img/cover.png" media-type="image/png" properties="cover-image"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''';

const _nav3 = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>n</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="text/c1.xhtml">开篇</a>
        <ol><li><a href="text/c1.xhtml#x">小节一</a></li></ol>
      </li>
      <li><a href="text/c1.xhtml#y">独立章</a></li>
    </ol>
  </nav>
</body></html>''';

Uint8List _epub3() => _zipBytes({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': _opf3(),
  'OEBPS/nav.xhtml': _nav3,
  'OEBPS/text/c1.xhtml': _ch1,
  'OEBPS/img/cover.png': 'PNG',
});

const _drmEnc =
    '''<?xml version="1.0"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <EncryptedModule xmlns:enc="http://www.w3.org/2001/04/xmlenc#" Name="Adobic" enc:Algorithm="http://ns.adobe.com/digitaleditions/enc">
    <EncryptionMethod Algorithm="http://ns.adobe.com/digitaleditions/enc"/>
    <DataReference URI="OEBPS/xhtml/01.xhtml"/>
  </EncryptedModule>
</encryption>''';

const _fontObf =
    '''<?xml version="1.0"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
    <EncryptionMethod Algorithm="http://www.idpf.org/2004/embedded-fonts"/>
    <DataReference URI="../OEBPS/fonts/x.otf"/>
  </EncryptedData>
</encryption>''';

void main() {
  group('批1-EP · EPUB2 解析（ncx 目录 / 元数据 / 段落 / 统计）', () {
    final doc = EpubDoc.parse(_epub2());

    test('格式与元数据', () {
      expect(doc.format, 'EPUB2');
      expect(doc.title, '测试书甲');
      expect(doc.author, '某某');
      expect(doc.publisher, '某出版社');
      expect(doc.pubDate, '2020-01-02');
      expect(doc.description, '一本用于解析验证的书。');
    });

    test('ncx 两级目录 · 锚点剥离 · 相对路径归一（含 %20 文件名）', () {
      expect(doc.toc.map((t) => (t.label, t.href, t.level)).toList(), [
        ('第一部', 'OEBPS/chapter1.xhtml', 1),
        ('第一章', 'OEBPS/chapter1.xhtml', 2),
        ('第二章', 'OEBPS/chap 2.xhtml', 2),
        ('第二部', 'OEBPS/chap 2.xhtml', 1),
      ]);
    });

    test('spine 章节顺序与标题命中目录首项', () {
      // 章标题＝目录中首个 href 命中项（c1→第一部，c2→第二章）。
      expect(doc.chapters.map((c) => c.title).toList(), ['第一部', '第二章']);
      expect(doc.chapters.first.href, 'OEBPS/chapter1.xhtml');
    });

    test('段落抽取：h1/p/引文/figure 图注 · 空白归一', () {
      final p0 = doc.chapters[0].paras;
      expect(p0[0].kind, EpubParaKind.heading);
      expect(p0[0].headingLevel, 1);
      expect(p0[1].text, '第一段 正文。');
      // 全角空格 U+3000 按 HTML5 解析规约归一为普通空格（与浏览器渲染一致）。
      expect(p0[2].text, '第二段 正文 带 换行与空白。');
      expect(p0[3].kind, EpubParaKind.quote);
      expect(p0[4].kind, EpubParaKind.image);
      expect(p0[4].imgSrc, 'OEBPS/images/p1.png');
      expect(p0[4].alt, '图一说明');
      expect(p0[5].kind, EpubParaKind.text);
    });

    test('封面 / 图片 / 字体 / 书签 / 字数统计', () {
      expect(doc.coverName, 'OEBPS/images/cover.jpg');
      expect(doc.coverBytes, isNotNull);
      expect(doc.imageCount, 2);
      expect(doc.fontCount, 1);
      expect(doc.bookmarkCount, 2);
      expect(doc.totalChars, greaterThan(30));
    });
  });

  test('批1-EP · EPUB3 nav 嵌套目录 + cover-image 属性', () {
    final doc = EpubDoc.parse(_epub3());
    expect(doc.format, 'EPUB3');
    expect(doc.title, '测试书乙');
    expect(doc.toc.map((t) => (t.label, t.level)).toList(), [
      ('开篇', 1),
      ('小节一', 2),
      ('独立章', 1),
    ]);
    expect(doc.coverName, 'OEBPS/img/cover.png');
  });

  test('批1-EP · DRM 加密声明拒开', () {
    final files = {..._epub2Files(), 'META-INF/encryption.xml': _drmEnc};
    expect(
      () => EpubDoc.parse(_zipBytes(files)),
      throwsA(
        isA<EpubFormatException>().having(
          (e) => e.reason,
          'reason',
          contains('DRM'),
        ),
      ),
    );
  });

  test('批1-EP · 字体混淆白名单不误判 DRM', () {
    final files = {..._epub2Files(), 'META-INF/encryption.xml': _fontObf};
    final doc = EpubDoc.parse(_zipBytes(files));
    expect(doc.title, '测试书甲');
  });

  test('批1-EP · 坏包 / 非 epub / 无正文三类拒绝', () {
    expect(
      () => EpubDoc.parse([1, 2, 3]),
      throwsA(isA<EpubFormatException>()),
    );
    expect(
      () =>
          EpubDoc.parse(_zipBytes({..._epub2Files(), 'mimetype': 'text/plain'})),
      throwsA(isA<EpubFormatException>().having(
          (e) => e.reason, 'm', contains('mimetype'))),
    );
    expect(
      () => EpubDoc.parse(_zipBytes({
        'mimetype': 'application/epub+zip',
        'OEBPS/content.opf': _opf2(),
      })),
      throwsA(isA<EpubFormatException>()
          .having((e) => e.reason, 'r', contains('container'))),
    );
    expect(
      () => EpubDoc.parse(_zipBytes({
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': _container,
        'OEBPS/content.opf': _opf2(),
      })),
      throwsA(isA<EpubFormatException>()
          .having((e) => e.reason, 'r2', contains('文本文档'))),
    );
  });

  test('批1-EP · 无目录回落：toc 空 + 章节标题取文件名', () {
    final files = {
      for (final e in _epub2Files().entries)
        if (e.key != 'OEBPS/toc.ncx') e.key: e.value,
    };
    final doc = EpubDoc.parse(_zipBytes(files));
    expect(doc.toc, isEmpty);
    expect(doc.chapters.map((c) => c.title).toList(), ['chapter1', 'chap 2']);
  });

  test('批1-EP · CFI 前缀常量（epub/2/{章序+2}/{段} 的段一）', () {
    expect(EpubDoc.cfiPrefix, 'epub/2');
  });
}
