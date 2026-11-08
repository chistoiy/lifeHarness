import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/export/multi_format.dart';

/// C08 多格式导出纯序列化层守护：SVG 产物可开、中文不缺字、XML 转义；
/// PDF 只到域层（中文保留、分页、可序列化），明确不产 .pdf 字节。
void main() {
  test('① SVG 可开且中文不缺字：正档中文原样 / 负档无外链资源', () {
    final svg = serializeMindmapSvg(
      title: '保养导图',
      nodes: const <SvgNode>[
        SvgNode(id: 'r', text: '相机保养'),
        SvgNode(id: 'c1', text: '镜头清灰', parentId: 'r'),
        SvgNode(id: 'c2', text: '换干燥剂', parentId: 'r'),
      ],
    );
    expect(svg, startsWith('<?xml version="1.0" encoding="UTF-8"?>'),
        reason: '正档：合法 XML 声明');
    expect(svg, contains('<svg'), reason: '正档：SVG 根元素');
    expect(svg, contains(kSvgXmlns), reason: '正档：标准命名空间');
    expect(svg, contains('viewBox='), reason: '正档：可缩放画布');
    expect(svg, contains('xml:lang="zh-CN"'), reason: '正档：中文语言标记');
    expect(svg, contains('相机保养'), reason: '正档：中文原样保留，不缺字');
    expect(svg, contains('镜头清灰'), reason: '正档：子节点中文');
    expect(svg, contains('<line'), reason: '正档：父子连线');
    expect(svg, contains('<text'), reason: '正档：文本节点');
    expect(svg, isNot(contains('<image')), reason: '负档：无外链图片');
    expect(svg, isNot(contains('xlink:href')), reason: '负档：无外部引用');
    expect(svg, isNot(contains('<script')), reason: '负档：无脚本');
    expect(svg.trim(), endsWith('</svg>'), reason: '正档：闭合完整');
  });

  test('② svgEscape：正档转义特殊字符 / 负档中文不变', () {
    expect(svgEscape('A & B <x> "y" \'z\''),
        equals('A &amp; B &lt;x&gt; &quot;y&quot; &apos;z&apos;'),
        reason: '正档：五类字符全转义');
    expect(svgEscape('相机保养'), equals('相机保养'),
        reason: '负档：中文不被动');
    final svg = serializeMindmapSvg(
      title: 'A & B',
      nodes: const <SvgNode>[SvgNode(id: 'x', text: '<tag> & "q"')],
    );
    expect(svg, contains('&lt;tag&gt;'), reason: '正档：< 被转义');
    expect(svg, contains('&amp;'), reason: '正档：& 被转义');
    expect(svg, isNot(contains('<tag>')), reason: '负档：裸 < 不许留在 SVG');
  });

  test('③ PDF 域层：中文保留、标题块、分页、JSON 可解析', () {
    final lines = <String>['一月摘要 · 中文', for (var i = 0; i < 40; i++) '第 $i 行'];
    final m = buildNotePdfModel(
        title: '日记 2026', lines: lines, linesPerPage: 10);
    expect(m.title, '日记 2026', reason: '正档：标题中文保留');
    expect(m.pages.length, greaterThan(1), reason: '正档：按行分页');
    expect(m.pages.first.blocks.first.heading, isTrue,
        reason: '正档：首页首块＝标题');
    expect(m.pages.first.blocks.first.text, '日记 2026');
    final decoded =
        jsonDecode(serializePdfDocModel(m)) as Map<String, dynamic>;
    expect(decoded['title'], '日记 2026', reason: '正档：序列化保留中文');
    expect((decoded['pages'] as List).isNotEmpty, isTrue);

    final empty = buildNotePdfModel(title: '空稿', lines: const <String>[]);
    expect(empty.pages, hasLength(1),
        reason: '负档：空正文仍产标题页，不凭空造内容');
    expect(empty.pages.first.blocks, hasLength(1));
    expect(serializePdfDocModel(empty), isNot(startsWith('%PDF')),
        reason: '负档：域层不冒充 .pdf 字节（UI 出口待接线）');
  });
}
