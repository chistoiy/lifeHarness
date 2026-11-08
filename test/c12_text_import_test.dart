import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:enough_convert/gbk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/text_import.dart';

/// C12 多格式解析守护（只做纯 Dart 能做的）：TXT 编码降级、FB2 XML 转义安全、
/// 最小 EPUB 产物可开；不支持格式清单显式登记（C13：不静默降级、不假装支持）。
void main() {
  test('① 字节解码：正档 UTF-8(BOM)/GBK / 负档双失败降级不崩且有提示', () {
    final utf8Bom = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('第一章 镜头\n正文')];
    final r1 = decodeBookBytes(utf8Bom);
    expect(r1.encoding, 'utf-8-bom', reason: '正档：BOM 识别');
    expect(r1.text.startsWith('第一章'), isTrue, reason: '正档：BOM 已剥');
    expect(r1.warning, isNull, reason: '正档：无损解码无提示');

    final gbkBytes = gbk.encode('相机保养\n第一章 镜头\n镜头清灰');
    final r2 = decodeBookBytes(gbkBytes);
    expect(r2.encoding, 'gbk', reason: '正档：UTF-8 失败后 GBK 兜底');
    expect(r2.text.contains('相机保养'), isTrue, reason: '正档：中文正确');
    expect(r2.warning, isNull, reason: '正档：GBK 无损');

    // 0x81 0x20 不是合法 GBK 双字节，也不是合法 UTF-8：走容错降级。
    final bad = <int>[0x81, 0x20, 0xFF, 0xFE, 0x81];
    final r3 = decodeBookBytes(bad);
    expect(r3.encoding, 'unknown', reason: '负档：双失败标记 unknown');
    expect(r3.warning, isNotNull, reason: '负档：必须给明确提示，不许静默');
    expect(r3.warning!.contains('UTF-8'), isTrue, reason: '负档：提示点名编码');
    expect(() => decodeBookBytes(bad), returnsNormally,
        reason: '负档：不抛异常');

    final empty = decodeBookBytes(const <int>[]);
    expect(empty.text, isEmpty);
    expect(empty.warning, isNotNull, reason: '负档：空文件也要说明');
  });

  test('② TXT 章节：正档按章拆分/头部元信息 / 负档句子行不误判为章节', () {
    const raw = '书名：相机保养\n'
        '作者：张三\n'
        '\n'
        '第一章 镜头\n'
        '镜头清灰。\n'
        '换干燥剂。\n'
        '\n'
        '第二章 机身\n'
        '机身检查。\n';
    final d = parseTxtDraft(raw);
    expect(d.title, '相机保养', reason: '正档：书名行');
    expect(d.author, '张三', reason: '正档：作者行');
    expect(d.chapters, hasLength(2), reason: '正档：两章');
    expect(d.chapters.first.title, '第一章 镜头');
    expect(d.chapters.first.text.contains('镜头清灰'), isTrue);
    expect(d.charCount, greaterThan(0));
    expect(d.isEmpty, isFalse);
    expect(d.warnings, isEmpty);

    final noHead = parseTxtDraft('只有一段普通文字，没有章节标记。');
    expect(noHead.chapters, hasLength(1), reason: '负档：无章节时单章兜底');
    expect(noHead.chapters.single.title, '正文');

    final sentence = parseTxtDraft(
      '第一章讲的是相机保养的方法。\n后面还有正文。',
    );
    expect(sentence.chapters, hasLength(1),
        reason: '负档：带句号的句子行不当章节标题');
    expect(sentence.chapters.single.title, '正文');

    final empty = parseTxtDraft('   \n  ');
    expect(empty.chapters, isEmpty, reason: '负档：空文本不臆造章节');
    expect(empty.warnings, isNotEmpty, reason: '负档：空文本必须提示');
  });

  test('③ FB2：正档元信息+嵌套 section / 负档坏 XML 不抛且提示', () {
    const fb2 = '<?xml version="1.0" encoding="utf-8"?>\n'
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">\n'
        '  <description><title-info>\n'
        '    <book-title>相机 &amp; 保养 &lt;指南&gt;</book-title>\n'
        '    <author><first-name>张</first-name><last-name>三</last-name></author>\n'
        '  </title-info></description>\n'
        '  <body>\n'
        '    <section><title><p>第一章 镜头</p></title>\n'
        '      <p>镜头清灰 &amp; 换干燥剂</p>\n'
        '      <section><title><p>1.1 小节</p></title><p>嵌套正文</p></section>\n'
        '    </section>\n'
        '    <section><title><p>第二章 机身</p></title><p>机身正文</p></section>\n'
        '  </body>\n'
        '</FictionBook>\n';

    final d = parseFb2Draft(fb2);
    expect(d.title, '相机 & 保养 <指南>', reason: '正档：实体反转义');
    expect(d.author, '张三', reason: '正档：中文姓名不加空格');
    expect(d.chapters.length, greaterThanOrEqualTo(3),
        reason: '正档：含嵌套小节');
    expect(d.chapters.first.title, '第一章 镜头');
    expect(d.chapters.first.text.contains('镜头清灰 & 换干燥剂'), isTrue,
        reason: '正档：正文实体反转义');
    expect(d.chapters.any((c) => c.title == '1.1 小节'), isTrue,
        reason: '正档：嵌套 section 独立成章');
    expect(d.format, 'FB2');

    final broken = parseFb2Draft(
      '<FictionBook><body><p>只有段落 &amp; 没有闭合',
      fileName: '残卷.fb2',
    );
    expect(broken.chapters, hasLength(1),
        reason: '负档：坏 XML 走段落兜底，不抛');
    expect(broken.chapters.single.text.contains('只有段落 & 没有闭合'), isTrue);
    expect(broken.warnings, isNotEmpty, reason: '负档：兜底必须留提示');
    expect(broken.title, '残卷', reason: '负档：无书名时回落文件名');

    final junk = parseFb2Draft('<html><body></body></html>');
    expect(junk.isEmpty, isTrue, reason: '负档：无正文不冒充成功');
    expect(junk.warnings, isNotEmpty);
  });

  test('④ XML 转义：正档五类字符 / 负档未知实体不展开（防 XXE）', () {
    expect(xmlEscape('<script>alert("x")</script> & '),
        '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; ',
        reason: '正档：标签与引号全转义');
    expect(xmlEscape('相机保养'), '相机保养', reason: '负档：中文不被动');

    expect(xmlUnescape('A &amp; B &lt;x&gt; &quot;y&quot; &apos;z&apos;'),
        'A & B <x> "y" \'z\'',
        reason: '正档：五类实体还原');
    expect(xmlUnescape('&#65;&#x4E2D;'), 'A中', reason: '正档：数字实体');
    expect(xmlUnescape('&xxe;'), '&xxe;',
        reason: '负档：未知实体原样保留，不展开');
  });

  test('⑤ 最小 EPUB：正档可解包且章节可读 / 负档用户文本不变成标签', () {
    const draft = TextBookDraft(
      title: '相机 & 保养',
      author: '张三',
      chapters: [
        TextChapter(title: '第一章 镜头', text: '镜头清灰。\n<script>alert(1)</script>'),
        TextChapter(title: '第二章 机身', text: '机身检查。'),
      ],
    );
    final bytes = buildEpubBytes(
      draft,
      bookId: 'b1',
      modified: DateTime.utc(2026, 11, 9),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    String textOf(String name) => utf8.decode(
          archive.files.firstWhere((f) => f.name == name).content as List<int>,
        );

    expect(archive.files.first.name, 'mimetype',
        reason: '正档：mimetype 必须是首条');
    expect(textOf('mimetype'), 'application/epub+zip');
    expect(textOf('META-INF/container.xml'), contains('OEBPS/content.opf'));
    final opf = textOf('OEBPS/content.opf');
    expect(opf, contains('相机 &amp; 保养'), reason: '正档：书名已转义');
    expect(opf, contains('dc:creator'), reason: '正档：作者元信息');
    expect(opf, contains('itemref idref="c1"'), reason: '正档：spine 两章');

    final c0 = textOf('OEBPS/c0.xhtml');
    expect(c0, contains('镜头清灰'), reason: '正档：正文落盘');
    expect(c0, contains('&lt;script&gt;'), reason: '正档：用户文本被转义');
    expect(c0, isNot(contains('<script>')),
        reason: '负档：正文里不许出现可执行标签');
    expect(textOf('OEBPS/nav.xhtml'), contains('第二章 机身'),
        reason: '正档：nav 目录含章题');
    expect(textOf('OEBPS/nav.xhtml'), isNot(contains('<script>')),
        reason: '负档：目录同样不许带裸标签');
  });

  test('⑥ 不支持格式清单：正档 MOBI/AZW3/PDF/DRM 在列 / 负档不冒充可解析', () {
    final exts = kUnsupportedReadFormats.map((f) => f.ext).toSet();
    expect(exts.containsAll(['mobi', 'azw3', 'pdf', 'drm']), isTrue,
        reason: '正档：四类显式登记');
    expect(
      kUnsupportedReadFormats.every((f) => f.reason.trim().isNotEmpty),
      isTrue,
      reason: '正档：每条都有原因',
    );
    expect(isUnsupportedReadFile('book.mobi'), isTrue, reason: '正档：后缀命中');
    expect(isUnsupportedReadFile('书.pdf'), isTrue);
    expect(isUnsupportedReadFile('book.epub'), isFalse,
        reason: '负档：EPUB 不在不支持清单');
    expect(plainBookFormatOf('book.txt'), 'TXT', reason: '正档：TXT 识别');
    expect(plainBookFormatOf('book.fb2'), 'FB2', reason: '正档：FB2 识别');
    expect(plainBookFormatOf('book.mobi'), isNull,
        reason: '负档：不支持格式不返回可解析标记');
  });
}
