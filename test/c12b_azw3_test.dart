import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/azw3_import.dart';
import 'package:lifeharness/features/read/data/ebook_exception.dart';
import 'package:lifeharness/features/read/data/ebook_html.dart';
import 'package:lifeharness/features/read/data/text_import.dart';

/// C12b · AZW3（KF8）导入守护：容器/OPF/spine/实体/章节切分/显式拒绝。
/// 全部用内存构造的最小样本，不依赖任何大文件。
void main() {
  test('① AZW3 正档：OPF 元数据 + spine 两章 + 实体反转义 / 负档空与非 ZIP', () {
    final zip = _zip({
      'mimetype': utf8.encode('application/vnd.amazon.ebook'),
      'META-INF/container.xml': utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<container><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/>'
        '</rootfiles></container>',
      ),
      'OEBPS/content.opf': utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>相机 &amp; 保养</dc:title><dc:creator>张三</dc:creator>'
        '</metadata><manifest>'
        '<item id="c0" href="Text/c0.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c1" href="Text/c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '</manifest><spine><itemref idref="c0"/><itemref idref="c1"/></spine>'
        '</package>',
      ),
      'OEBPS/Text/c0.xhtml': utf8.encode(
        '<html><head><title>x</title></head><body>'
        '<h1>第一章 镜头</h1>'
        '<p>镜头清灰 &amp; 换干燥剂&nbsp;OK</p></body></html>',
      ),
      'OEBPS/Text/c1.xhtml': utf8.encode(
        '<h1>第二章 机身</h1><p>机身检查&#12290;</p>',
      ),
    });

    final d = parseAzw3Draft(zip, fileName: '相机.azw3');
    expect(d.format, 'AZW3');
    expect(d.title, '相机 & 保养', reason: '正档：OPF 标题实体反转义');
    expect(d.author, '张三', reason: '正档：dc:creator');
    expect(d.chapters, hasLength(2), reason: '正档：spine 两章，nav 已跳过');
    expect(d.chapters.first.title, '第一章 镜头');
    expect(d.chapters.first.text.contains('镜头清灰 & 换干燥剂 OK'), isTrue,
        reason: '正档：正文实体与 nbsp 已处理');
    expect(d.chapters.last.text.contains('机身检查。'), isTrue,
        reason: '正档：数字实体还原');
    expect(d.isEmpty, isFalse);

    expect(
      () => parseAzw3Draft(const <int>[]),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('空'),
      )),
      reason: '负档：空文件显式拒绝',
    );
    expect(
      () => parseAzw3Draft(const [1, 2, 3, 4, 5]),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('ZIP'),
      )),
      reason: '负档：非 ZIP 不猜、不假装成功',
    );
  });

  test('② AZW3 负档：DRM 声明拒绝 / 缺 OPF 拒绝；正档无 container 也能按 *.opf 探测', () {
    final drm = _zip({
      'mimetype': utf8.encode('application/vnd.amazon.ebook'),
      'META-INF/encryption.xml': utf8.encode('<encryption/>'),
      'OEBPS/content.opf': utf8.encode('<package/>'),
    });
    expect(
      () => parseAzw3Draft(drm),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('DRM'),
      )),
      reason: '负档：加密声明必须显式拒绝',
    );

    final noOpf = _zip({
      'mimetype': utf8.encode('application/vnd.amazon.ebook'),
    });
    expect(
      () => parseAzw3Draft(noOpf),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('OPF'),
      )),
      reason: '负档：缺内容清单不静默降级',
    );

    final rootOpf = _zip({
      'mimetype': utf8.encode('application/vnd.amazon.ebook'),
      'content.opf': utf8.encode(
        '<package><metadata><title>根目录书</title></metadata>'
        '<manifest><item id="c0" href="c0.xhtml" '
        'media-type="application/xhtml+xml"/></manifest>'
        '<spine><itemref idref="c0"/></spine></package>',
      ),
      'c0.xhtml': utf8.encode('<h1>唯一章</h1><p>正文</p>'),
    });
    final d = parseAzw3Draft(rootOpf);
    expect(d.title, '根目录书', reason: '正档：无 container.xml 时探测 *.opf');
    expect(d.chapters.single.title, '唯一章');
    expect(d.chapters.single.text, '正文');
  });

  test('③ HTML 实体与章节切分：正档命名/数字实体与分页符 / 负档未知实体原样', () {
    expect(
      htmlUnescape('A&nbsp;B&amp;C&hellip;&#x4E2D;&#12290;'),
      'A\u00A0B&C\u2026中。',
      reason: '正档：命名实体 + 数字实体',
    );
    expect(htmlUnescape('&xxe;'), '&xxe;',
        reason: '负档：未知实体不展开（防 XXE）');

    const html = '<div>开头段</div><mbp:pagebreak/>'
        '<h1>第一章 镜头</h1><p>镜头正文</p>'
        '<mbp:pagebreak/><h1>第二章 机身</h1><p>机身正文</p>';
    final chapters = splitHtmlIntoChapters(html);
    expect(chapters, hasLength(3), reason: '正档：分页符与标题都切章');
    expect(chapters.first.title, '开头段', reason: '正档：无标题时取首行');
    expect(chapters[1].title, '第一章 镜头');
    expect(chapters[2].text, '机身正文');

    expect(splitHtmlIntoChapters('<div></div>'), isEmpty,
        reason: '负档：空内容不臆造章节');
    expect(htmlFragmentText('<p>句子。</p>'), '句子。');
  });

  test('④ 格式登记：正档 AZW3/MOBI 可识别且标实验性 / 负档 PDF 不在实验性', () {
    expect(binaryBookFormatOf('book.AZW3'), 'AZW3');
    expect(binaryBookFormatOf('book.mobi'), 'MOBI');
    expect(binaryBookFormatOf('book.txt'), isNull,
        reason: '负档：文本格式不走二进制入口');
    expect(binaryBookFormatOf('book.epub'), isNull,
        reason: '负档：EPUB 走既有导入链');

    final unsupported = kUnsupportedReadFormats
        .where((f) => !f.experimental)
        .map((f) => f.ext)
        .toSet();
    expect(unsupported, {'pdf', 'drm', 'chm', 'djvu'},
        reason: '正档：真不支持清单只剩 PDF/DRM/CHM/DjVu');
    expect(
      kUnsupportedReadFormats
          .firstWhere((f) => f.ext == 'azw3')
          .experimental,
      isTrue,
      reason: '正档：AZW3 标实验性支持',
    );
    expect(isExperimentalReadFile('book.mobi'), isTrue);
    expect(isExperimentalReadFile('book.pdf'), isFalse,
        reason: '负档：PDF 不在实验性清单');
  });
}

List<int> _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, bytes) {
    final f = ArchiveFile(name, bytes.length, bytes);
    f.compress = name != 'mimetype';
    archive.addFile(f);
  });
  return ZipEncoder().encode(archive)!;
}
