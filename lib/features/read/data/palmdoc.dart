/// PalmDOC / MOBI 二进制容器解析（纯 Dart、零新依赖）。
///
/// 分层：
/// - [PdbFile]：78 字节 PDB 头 + 记录偏移表 → 逐条记录字节；
/// - [MobiHeader]：record 0 的 PalmDOC 头 + MOBI 头 + EXTH 元数据；
/// - [palmdocDecompress]：PalmDOC LZ77（compression=2）解压。
///
/// 只做「读」：HUFF/CDIC（17480）与 DRM 加密在 [MobiHeader] 层保留原始标记，
/// 由 [parseMobiDraft] 显式拒绝并给文案，不在这里假装解压成功。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'ebook_exception.dart';

/// PDB 容器（MOBI / PalmDOC 的物理外壳）。
class PdbFile {
  PdbFile._(this._bytes, this.name, this.type, this.creator, this._offsets);

  final List<int> _bytes;
  final String name;
  final String type;
  final String creator;
  final List<int> _offsets;

  int get recordCount => _offsets.length;

  /// 解析 PDB 头与记录表；结构不完整一律抛 [EbookFormatException]。
  static PdbFile parse(List<int> bytes) {
    if (bytes.length < 78) {
      throw const EbookFormatException('文件过短，不是有效的 MOBI/PDB 容器');
    }
    final n = _u16(bytes, 76);
    if (n <= 0 || 78 + n * 8 > bytes.length) {
      throw const EbookFormatException('PDB 记录表损坏（记录数越界）');
    }
    final offsets = <int>[];
    for (var i = 0; i < n; i++) {
      final off = _u32(bytes, 78 + i * 8);
      if (off < 0 || off >= bytes.length) {
        throw EbookFormatException('PDB 第 $i 条记录偏移越界（文件损坏）');
      }
      offsets.add(off);
    }
    final name = String.fromCharCodes(bytes.sublist(0, 32))
        .replaceAll('\u0000', '')
        .trim();
    final type = _ascii(bytes, 60, 64);
    final creator = _ascii(bytes, 64, 68);
    return PdbFile._(bytes, name, type, creator, offsets);
  }

  /// 第 [i] 条记录的字节（按相邻偏移切分；末条到文件尾）。
  List<int> record(int i) {
    if (i < 0 || i >= _offsets.length) return const [];
    final start = _offsets[i];
    final end = i + 1 < _offsets.length ? _offsets[i + 1] : _bytes.length;
    if (end <= start) return const [];
    return _bytes.sublist(start, end > _bytes.length ? _bytes.length : end);
  }
}

/// record 0 的 PalmDOC 头 + MOBI 头 + EXTH。
class MobiHeader {
  MobiHeader._({
    required this.compression,
    required this.textLength,
    required this.textRecordCount,
    required this.recordSize,
    required this.encryptionType,
    required this.mobiType,
    required this.textEncoding,
    required this.firstImageIndex,
    required this.fullName,
    required this.exth,
  });

  final int compression;
  final int textLength;
  final int textRecordCount;
  final int recordSize;

  /// 0＝未加密；非 0＝DRM（本应用拒绝）。
  final int encryptionType;

  final int mobiType;
  final int textEncoding;
  final int firstImageIndex;
  final String? fullName;

  /// EXTH 记录：type → 原始数据（同一 type 取首条）。
  final Map<int, List<int>> exth;

  bool get hasDrm => encryptionType != 0;

  /// EXTH 文本字段（UTF-8 容错解码）。
  String? exthString(int type) {
    final raw = exth[type];
    if (raw == null || raw.isEmpty) return null;
    final s = utf8.decode(raw, allowMalformed: true).trim();
    return s.isEmpty ? null : s;
  }

  /// 解析 record 0；缺 MOBI 标识或长度不足抛 [EbookFormatException]。
  static MobiHeader parse(List<int> rec0) {
    if (rec0.length < 24) {
      throw const EbookFormatException('MOBI 头不完整（record 0 过短）');
    }
    final compression = _u16(rec0, 0);
    final textLength = _u32(rec0, 4);
    final textRecordCount = _u16(rec0, 8);
    final recordSize = _u16(rec0, 10);
    final encryptionType = _u16(rec0, 12);

    if (_ascii(rec0, 16, 20) != 'MOBI') {
      throw const EbookFormatException('缺 MOBI 标识，不是 MOBI 电子书');
    }
    if (rec0.length < 16 + 0x74) {
      throw const EbookFormatException('MOBI 头长度不足（文件可能被截断）');
    }

    final mobiType = _u32(rec0, 24);
    final textEncoding = _u32(rec0, 28);
    final headerLength = _u32(rec0, 20);
    final firstImageIndex = _u32(rec0, 108);
    final exthFlags = _u32(rec0, 128);

    final nameOff = _u32(rec0, 84);
    final nameLen = _u32(rec0, 88);
    String? fullName;
    if (nameOff > 0 &&
        nameLen > 0 &&
        nameOff + nameLen <= rec0.length &&
        nameOff >= 16) {
      fullName = utf8
          .decode(rec0.sublist(nameOff, nameOff + nameLen), allowMalformed: true)
          .trim();
      if (fullName.isEmpty) fullName = null;
    }

    final exth = <int, List<int>>{};
    if ((exthFlags & 0x40) != 0) {
      final start = 16 + headerLength;
      if (start >= 0 &&
          start + 12 <= rec0.length &&
          _ascii(rec0, start, start + 4) == 'EXTH') {
        final total = _u32(rec0, start + 4);
        final count = _u32(rec0, start + 8);
        final end = (start + total).clamp(start + 12, rec0.length);
        var p = start + 12;
        for (var i = 0; i < count && p + 8 <= end; i++) {
          final type = _u32(rec0, p);
          final len = _u32(rec0, p + 4);
          if (len < 8 || p + len > end) break;
          exth.putIfAbsent(type, () => rec0.sublist(p + 8, p + len));
          p += len;
        }
      }
    }

    return MobiHeader._(
      compression: compression,
      textLength: textLength,
      textRecordCount: textRecordCount,
      recordSize: recordSize,
      encryptionType: encryptionType,
      mobiType: mobiType,
      textEncoding: textEncoding,
      firstImageIndex: firstImageIndex,
      fullName: fullName,
      exth: exth,
    );
  }
}

/// PalmDOC LZ77 解压（MOBI compression=2）。
///
/// 编码规则：0x01~0x08＝随后 N 字节原文；0x09~0x7F＝单字节；
/// 0x80~0xBF＝两字节回溯（距离 11 位 + 长度 3 位）；0xC0~0xFF＝空格 + 字节。
List<int> palmdocDecompress(List<int> input) {
  final out = <int>[];
  var i = 0;
  while (i < input.length) {
    final c = input[i++] & 0xFF;
    if (c >= 1 && c <= 8) {
      if (i + c > input.length) {
        throw const EbookFormatException('PalmDOC 文本记录被截断（原文段不完整）');
      }
      for (var k = 0; k < c; k++) {
        out.add(input[i++] & 0xFF);
      }
    } else if (c <= 0x7F) {
      out.add(c);
    } else if (c >= 0xC0) {
      out.add(0x20);
      out.add(c ^ 0x80);
    } else {
      if (i >= input.length) {
        throw const EbookFormatException('PalmDOC 文本记录被截断（回溯对不完整）');
      }
      final pair = (c << 8) | (input[i++] & 0xFF);
      final distance = (pair >> 3) & 0x7FF;
      final length = (pair & 0x07) + 3;
      if (distance == 0 || distance > out.length) {
        throw const EbookFormatException('PalmDOC 回溯距离越界（文件损坏）');
      }
      final start = out.length - distance;
      for (var k = 0; k < length; k++) {
        out.add(out[start + k]);
      }
    }
  }
  return Uint8List.fromList(out);
}

String _ascii(List<int> b, int start, int end) {
  if (start < 0 || end > b.length || start >= end) return '';
  return String.fromCharCodes(b.sublist(start, end));
}

int _u16(List<int> b, int o) {
  if (o + 2 > b.length) return 0;
  return (b[o] & 0xFF) | ((b[o + 1] & 0xFF) << 8);
}

int _u32(List<int> b, int o) {
  if (o + 4 > b.length) return 0;
  return (b[o] & 0xFF) |
      ((b[o + 1] & 0xFF) << 8) |
      ((b[o + 2] & 0xFF) << 16) |
      ((b[o + 3] & 0xFF) << 24);
}
