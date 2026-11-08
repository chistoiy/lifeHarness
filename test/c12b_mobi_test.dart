import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/ebook_exception.dart';
import 'package:lifeharness/features/read/data/mobi_import.dart';
import 'package:lifeharness/features/read/data/palmdoc.dart';

/// C12b · MOBI（PalmDOC）导入守护：PDB/MOBI 头/EXTH、LZ77 解压、HTML 章节、
/// DRM/HUFF-CDIC/截断的显式拒绝。样本全部为内存合成的最小字节序列。
void main() {
  test('① PalmDOC LZ77：正档字面段+回溯 / 负档截断与距离越界', () {
    // 0x03 + "ABC" + 回溯（距离 3、长度 3）→ "ABCABC"
    final out = palmdocDecompress(const [0x03, 0x41, 0x42, 0x43, 0x80, 0x18]);
    expect(out, const [0x41, 0x42, 0x43, 0x41, 0x42, 0x43],
        reason: '正档：重叠回溯复制正确');

    expect(
      () => palmdocDecompress(const [0x03, 0x41]),
      throwsA(isA<EbookFormatException>()),
      reason: '负档：字面段不完整必须抛错',
    );
    expect(
      () => palmdocDecompress(const [0x80, 0x00]),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('越界'),
      )),
      reason: '负档：回溯距离 0 不得静默产出乱码',
    );
  });

  test('② MOBI 头/EXTH：正档标题作者编码 / 负档过短与非 MOBI', () {
    final html = utf8.encode('<h1>第一章</h1><p>正文</p>');
    final bytes = _buildMobi(text: html, title: '相机保养', author: '张三');

    final pdb = PdbFile.parse(bytes);
    expect(pdb.type, 'BOOK', reason: '正档：PDB 类型');
    expect(pdb.creator, 'MOBI');
    expect(pdb.recordCount, 2);

    final h = MobiHeader.parse(pdb.record(0));
    expect(h.compression, 1, reason: '正档：未压缩');
    expect(h.textEncoding, 65001);
    expect(h.textLength, html.length);
    expect(h.exthString(503), '相机保养', reason: '正档：EXTH 503 标题');
    expect(h.exthString(100), '张三', reason: '正档：EXTH 100 作者');
    expect(h.hasDrm, isFalse);

    expect(
      () => PdbFile.parse(const [1, 2, 3]),
      throwsA(isA<EbookFormatException>()),
      reason: '负档：过短文件不崩、显式拒绝',
    );
    expect(
      () => MobiHeader.parse(List<int>.filled(300, 0)),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('MOBI'),
      )),
      reason: '负档：缺 MOBI 标识',
    );
  });

  test('③ parseMobiDraft 正档：LZ77 + HTML 实体 + 分页章节 / 负档 DRM 拒绝', () {
    final html = utf8.encode(
      '<html><head><title>x</title></head><body>'
      '<h1>第一章 镜头</h1><p>镜头清灰 &amp; 换干燥剂&nbsp;OK</p>'
      '<mbp:pagebreak/><h1>第二章 机身</h1><p>机身检查&#12290;</p>'
      '</body></html>',
    );
    final bytes = _buildMobi(
      text: _literalCompress(html),
      compression: 2,
      textLength: html.length,
    );

    final d = parseMobiDraft(bytes, fileName: '相机.mobi');
    expect(d.format, 'MOBI');
    expect(d.title, '相机保养', reason: '正档：EXTH 标题优先');
    expect(d.author, '张三');
    expect(d.encoding, 'utf-8');
    expect(d.chapters, hasLength(2), reason: '正档：mbp:pagebreak 切章');
    expect(d.chapters.first.title, '第一章 镜头');
    expect(d.chapters.first.text.contains('镜头清灰 & 换干燥剂 OK'), isTrue,
        reason: '正档：实体与 nbsp 处理');
    expect(d.chapters.last.text.contains('机身检查。'), isTrue);
    expect(d.isEmpty, isFalse);
    expect(d.warnings, isEmpty);

    final drm = _buildMobi(
      text: utf8.encode('<p>正文</p>'),
      encryption: 2,
    );
    expect(
      () => parseMobiDraft(drm),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('DRM'),
      )),
      reason: '负档：加密书必须明确拒绝，不假装解析',
    );
  });

  test('④ 负档：HUFF/CDIC 与截断正文记录均给明确原因，不崩', () {
    final huff = _buildMobi(
      text: utf8.encode('<p>正文</p>'),
      compression: 17480,
    );
    expect(
      () => parseMobiDraft(huff),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('HUFF'),
      )),
      reason: '负档：零依赖不可解的压缩方式显式拒绝',
    );

    // 声称 3 字节字面段，实际只给 1 字节 → LZ77 截断。
    final broken = _buildMobi(
      text: const [0x03, 0x41],
      compression: 2,
      textLength: 3,
    );
    expect(
      () => parseMobiDraft(broken),
      throwsA(isA<EbookFormatException>().having(
        (e) => e.reason,
        'reason',
        contains('截断'),
      )),
      reason: '负档：坏记录不静默降级',
    );

    expect(
      () => parseMobiDraft(const <int>[]),
      throwsA(isA<EbookFormatException>()),
      reason: '负档：空文件',
    );
  });
}

// ==================== 内存合成最小 MOBI ====================

List<int> _buildMobi({
  required List<int> text,
  int compression = 1,
  int encryption = 0,
  String title = '相机保养',
  String author = '张三',
  int? textLength,
}) {
  final rec0 = <int>[];
  rec0.addAll(_u16(compression));
  rec0.addAll(_u16(0));
  rec0.addAll(_u32(textLength ?? text.length));
  rec0.addAll(_u16(1)); // text record count
  rec0.addAll(_u16(4096));
  rec0.addAll(_u16(encryption));
  rec0.addAll(_u16(0));

  // MOBI header（从 record0 偏移 16 起）
  rec0.addAll(utf8.encode('MOBI'));
  rec0.addAll(_u32(0xE8)); // header length
  rec0.addAll(_u32(2)); // mobi type
  rec0.addAll(_u32(65001)); // UTF-8
  rec0.addAll(_u32(1)); // unique id
  rec0.addAll(_u32(6)); // file version
  while (rec0.length < 16 + 0x44) {
    rec0.add(0);
  }
  rec0.addAll(_u32(0)); // full name offset（稍后回填）
  rec0.addAll(_u32(0)); // full name length
  while (rec0.length < 16 + 0x70) {
    rec0.add(0);
  }
  rec0.addAll(_u32(0x40)); // EXTH flags
  while (rec0.length < 16 + 0xE8) {
    rec0.add(0);
  }

  final exthRecords = <List<int>>[
    _exthRecord(503, utf8.encode(title)),
    _exthRecord(100, utf8.encode(author)),
  ];
  final exthLen = 12 + exthRecords.fold<int>(0, (a, b) => a + b.length);
  rec0.addAll(utf8.encode('EXTH'));
  rec0.addAll(_u32(exthLen));
  rec0.addAll(_u32(exthRecords.length));
  for (final r in exthRecords) {
    rec0.addAll(r);
  }

  final nameBytes = utf8.encode(title);
  final nameOffset = rec0.length;
  rec0.addAll(nameBytes);
  _putU32(rec0, 84, nameOffset);
  _putU32(rec0, 88, nameBytes.length);

  return _pdb(<List<int>>[rec0, text]);
}

List<int> _pdb(List<List<int>> records) {
  final header = List<int>.filled(78, 0);
  final name = utf8.encode('synthetic');
  for (var i = 0; i < name.length && i < 32; i++) {
    header[i] = name[i];
  }
  header[60] = 0x42; // B
  header[61] = 0x4F; // O
  header[62] = 0x4F; // O
  header[63] = 0x4B; // K
  header[64] = 0x4D; // M
  header[65] = 0x4F; // O
  header[66] = 0x42; // B
  header[67] = 0x49; // I
  header[76] = records.length & 0xFF;
  header[77] = (records.length >> 8) & 0xFF;

  final infoLen = records.length * 8;
  final dataStart = 78 + infoLen + 2;
  final offsets = <int>[];
  var p = dataStart;
  for (final r in records) {
    offsets.add(p);
    p += r.length;
  }

  final out = <int>[...header];
  for (final off in offsets) {
    out.addAll(_u32(off));
    out.add(0);
    out.addAll(const [0, 0, 0]);
  }
  out.addAll(const [0, 0]);
  for (final r in records) {
    out.addAll(r);
  }
  return out;
}

List<int> _exthRecord(int type, List<int> data) => <int>[
      ..._u32(type),
      ..._u32(8 + data.length),
      ...data,
    ];

/// 每 8 字节加一个字面段头（0x01~0x08），构造合法的 LZ77 输入。
List<int> _literalCompress(List<int> src) {
  final out = <int>[];
  for (var i = 0; i < src.length; i += 8) {
    final n = (src.length - i) > 8 ? 8 : src.length - i;
    out.add(n);
    out.addAll(src.sublist(i, i + n));
  }
  return out;
}

List<int> _u16(int v) => <int>[v & 0xFF, (v >> 8) & 0xFF];

List<int> _u32(int v) => <int>[
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ];

void _putU32(List<int> b, int o, int v) {
  b[o] = v & 0xFF;
  b[o + 1] = (v >> 8) & 0xFF;
  b[o + 2] = (v >> 16) & 0xFF;
  b[o + 3] = (v >> 24) & 0xFF;
}
