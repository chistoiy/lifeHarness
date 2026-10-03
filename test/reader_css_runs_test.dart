import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_css.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';

// 批三实现批·刀2：原书样式**进段落模型**与快照/分页表版本双升。
//   抽取面＝`_extractParas` 接文档自带 CSS（`<link>`＋`<style>`＋内联 style），
//            段级语义进 EpubPara.style、段内区间进 EpubPara.runs；
//   落盘面＝DocStore.snapVersion 3→4（载荷改「样式字典＋段落表」）、PagStore.tableVersion 3→4；
//   不静默＝包里的竖排/图片装饰线等记进 EpubDoc.unsupported。
// 独立文件防 isolate 污染；fixture 用 ZipEncoder 现场打包（结构照《資治通鑑》卷一首篇）。

const _css = '''
body { writing-mode: vertical-rl; line-height: 150%; text-align: left; }
.origin { font-size: 1rem; font-weight: normal; text-indent: 2em; }
.comment { color: navy; text-indent: 2em; -webkit-margin-start: 2em; }
.note { color: DarkGreen; font-size: 0.75rem; -webkit-margin-start: 0.5em; }
.name { border-left: 0.12em solid; }
.book-title { background-image: url(../Images/line.gif); background-repeat: repeat-y; padding-left: 0.15em; }
''';

const _container = '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''';

const _opf = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>資治通鑑 特殊標點版（樣本）</dc:title><dc:creator>司馬光</dc:creator>
  </metadata>
  <manifest>
    <item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="s1" href="Styles/style0001.css" media-type="text/css"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''';

/// 卷一首篇骨架：正文段带注·专名线·内联 style·书名线，另有一段整块蓝的史评。
const _xhtml = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>卷一</title><link rel="stylesheet" type="text/css" href="../Styles/style0001.css"/></head>
<body>
<p class="origin"><span class="name">司馬光</span>編集</p>
<p class="origin">臣聞天子之職莫大於禮<span class="note">胡三省註</span>，非<span style="color:#c00000">礼</span>不能以正之。</p>
<p class="comment">臣光曰：是故天子之職莫大於禮。</p>
<p class="origin">據<span class="book-title">資治通鑑</span>卷一。</p>
</body>
</html>''';

Uint8List _zipBytes(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

EpubDoc _parseSample() => EpubDoc.parse(
  _zipBytes({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _container,
    'OEBPS/content.opf': _opf,
    'OEBPS/Styles/style0001.css': _css,
    'OEBPS/text/c1.xhtml': _xhtml,
  }),
);

String _hex(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

void main() {
  late EpubDoc doc;
  late List<EpubPara> paras;

  setUpAll(() {
    doc = _parseSample();
    paras = doc.chapters.single.paras;
  });

  group('抽取面：段级样式与 span 区间', () {
    test('正文段＝原书声明了 text-indent → ownIndent 命中（auto 档不再叠加我们的缩进）', () {
      final p = paras.firstWhere((x) => x.text.startsWith('臣聞天子'));
      expect(p.style?.indentEm, 2.0);
      expect(p.ownIndent, isTrue);
      expect(p.style?.lineRatio, 1.5, reason: 'body{line-height:150%} 沿链级联下来');
      expect(p.style?.align, 'left');
    });

    test('注＝绿 + 0.75 倍小字，区间与折叠后的 text 严格对齐', () {
      final p = paras.firstWhere((x) => x.text.startsWith('臣聞天子'));
      final r = p.runs.firstWhere((x) => p.text.substring(x.start, x.end) == '胡三省註');
      expect(_hex(r.style.color!), '006400');
      expect(r.style.fontRatio, 0.75);
      // 偏移对齐是这条批次的命门：链接/划线/书摘全按同一坐标系切片。
      expect(p.text.substring(r.start, r.end), '胡三省註');
    });

    test('专名线走 border 通道；书名线（图片平铺）近似成下划线', () {
      final named = paras.firstWhere((x) => x.text.startsWith('司馬光'));
      final r = named.runs.single;
      expect(named.text.substring(r.start, r.end), '司馬光');
      expect(r.style.borderLeft?.isLine, isTrue);
      expect(r.style.borderLeft?.widthEm, closeTo(0.12, .0001));
      expect(r.style.borderLeft?.color, isNull, reason: '未声明边色＝跟字色');
      final bt = paras.firstWhere((x) => x.text.startsWith('據'));
      final btr = bt.runs.single;
      expect(bt.text.substring(btr.start, btr.end), '資治通鑑');
      expect(btr.style.underline, isTrue);
    });

    test('内联 style 也进 runs（全书只有 3 处的末位通道，不能只吃 class）', () {
      final p = paras.firstWhere((x) => x.text.startsWith('臣聞天子'));
      final r = p.runs.firstWhere((x) => p.text.substring(x.start, x.end) == '礼');
      expect(_hex(r.style.color!), 'C00000');
    });

    test('与段级样式同值的区间不重复记一刀（`.origin` 里的普通文字）', () {
      final p = paras.firstWhere((x) => x.text.startsWith('臣聞天子'));
      expect(
        p.runs.map((r) => p.text.substring(r.start, r.end)),
        isNot(contains('臣聞天子之職莫大於禮')),
        reason: '整段本体＝段级样式，进 runs 是白拆一刀（预研 §5.3 性能口径）',
      );
    });

    test('史评段＝整段蓝落在段级样式上，段内没有多余 run', () {
      final p = paras.firstWhere((x) => x.text.startsWith('臣光曰'));
      expect(_hex(p.style!.color!), '000080');
      expect(p.runs, isEmpty);
    });

    test('文本折叠与旧 norm 口径一致（源码换行与首尾空白不算进正文）', () {
      for (final p in paras) {
        expect(p.text, isNot(contains('\n')));
        expect(p.text, isNot(startsWith(' ')));
        expect(p.text, isNot(endsWith(' ')));
      }
    });
  });

  group('不静默降级：按书收集不支持声明', () {
    test('竖排＝结构性丢弃；图片装饰线与行内留白＝近似降级', () {
      final keys = doc.unsupported.map((u) => u.key).toSet();
      expect(keys, contains('writing-mode'));
      expect(keys, contains('padding'));
      expect(
        doc.unsupported.firstWhere((u) => u.key == 'writing-mode').kind,
        EpubUnsupportedKind.cssStructural,
      );
      expect(
        doc.unsupported.firstWhere((u) => u.key == 'padding').kind,
        EpubUnsupportedKind.cssFlattened,
      );
      expect(
        doc.unsupported.firstWhere((u) => u.key == 'writing-mode').describe(),
        contains('竖排直排'),
      );
    });
  });

  group('落盘面：快照 round-trip 与版本双升', () {
    test('snapVersion 与 tableVersion 都已升（runs 改上屏排版＝两张表都要失效重算）', () {
      expect(DocStore.snapVersion, 4);
      expect(PagStore.tableVersion, 4);
    });

    test('存盘再读回：段级样式、区间、不支持声明逐字段一致', () async {
      final dir = Directory.systemTemp.createTempSync('lh_snap_runs');
      try {
        const bookId = 'b1';
        const fp = '123|456';
        await DocStore.save(dir.path, bookId, fp, doc);
        final back = await DocStore.load(dir.path, bookId, fp);
        expect(back, isNotNull);
        expect(back!.unsupported.length, doc.unsupported.length);
        expect(
          back.unsupported.map((u) => u.key).toSet(),
          doc.unsupported.map((u) => u.key).toSet(),
        );
        final bp = back.chapters.single.paras;
        final ap = doc.chapters.single.paras;
        expect(bp.map((p) => p.text), ap.map((p) => p.text));
        for (var i = 0; i < bp.length; i++) {
          expect(bp[i].style, ap[i].style, reason: '第 $i 段段级样式');
          expect(bp[i].runs.length, ap[i].runs.length, reason: '第 $i 段区间数');
          for (var k = 0; k < ap[i].runs.length; k++) {
            expect(
              bp[i].text.substring(bp[i].runs[k].start, bp[i].runs[k].end),
              ap[i].text.substring(ap[i].runs[k].start, ap[i].runs[k].end),
              reason: '第 $i 段第 $k 个区间的文字（偏移对齐）',
            );
            expect(bp[i].runs[k].style, ap[i].runs[k].style);
          }
        }
        // 指纹不符＝整份失效（旧快照不许命中新模型）。
        expect(await DocStore.load(dir.path, bookId, '9|9'), isNull);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('老载荷缺 runs/样式字段＝防御读成「无原书样式」，不炸', () async {
      final dir = Directory.systemTemp.createTempSync('lh_snap_legacy');
      try {
        final d = DocStore.dirFor(dir.path, 'b2');
        Directory(d).createSync(recursive: true);
        // 手写 v4 索引 + 只到第 8 位（ownIndent）的段落行、且没有样式字典：
        // 模拟截断/坏数据——缺位必须回落成「无原书样式」而不是抛。
        final payload = utf8.encode(
          jsonEncode([
            [0, '正文', 0, '', '', [], 0, 0],
          ]),
        );
        File('$d/data.bin').writeAsBytesSync(payload);
        File('$d/index.json').writeAsStringSync(
          jsonEncode({
            'v': DocStore.snapVersion,
            'fp': 'f',
            'format': 'EPUB3',
            'title': 'T',
            'author': 'A',
            'toc': <Object>[],
            'spine': [
              {
                'href': 'a.xhtml',
                'title': '章',
                'n': 1,
                'chars': 2,
                'off': 0,
                'len': payload.length,
              },
            ],
          }),
        );
        final back = await DocStore.load(dir.path, 'b2', 'f');
        expect(back, isNotNull);
        final p = back!.chapters[0].paras;
        expect(p.length, 1);
        expect(p.single.text, '正文');
        expect(p.single.style, isNull);
        expect(p.single.runs, isEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
