/// 小工具合集 · 基线 JPEG 编码器（纯 Dart · 批3）。
///
/// 为什么自己写：`dart:ui` 只能编 PNG（无损，压不动照片），仓库内没有可离线
/// 拉取的 JPEG 依赖（批3 写区不动 pubspec/lock），而「图片体积缩小」的核心承诺
/// 是**按质量档真实压出字节数**。这里实现一份最小可用的 baseline DCT 编码器：
/// - 量化表与 Huffman 表**现场生成并随流下发**（DQT/DHT），不抄任何常量表；
/// - 4:2:0 色度抽样 + 标准之字扫描 + EXTEND 规则（ISO/IEC 10912 F.13）；
/// - 避开「全 1 码字」保留位（把唯一最长码缩短一级，见 [_avoidAllOnes]）；
/// - 纯函数、零 I/O，输入是 `dart:ui` 解码后的 RGB 字节。
/// 用例用 `ui.instantiateImageCodec` 把产物真解码回读——编错就解不开。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 质量 → libjpeg 同式缩放因子（<50 走 5000/q，否则 200-2q）。
int kitJpegScale(int quality) {
  final q = quality.clamp(1, 99);
  return q < 50 ? (5000 / q).round() : (200 - q * 2);
}

/// 标准之字扫描顺序（对角线 d=0..14，偶数向右上、奇数向左下）。
final List<int> _zigzag = _buildZigzag();

List<int> _buildZigzag() {
  final out = <int>[];
  for (var d = 0; d <= 14; d++) {
    final lo = d > 7 ? d - 7 : 0;
    if (d.isEven) {
      for (var r = math.min(d, 7); r >= lo; r--) {
        out.add(r * 8 + (d - r));
      }
    } else {
      for (var c = math.min(d, 7); c >= lo; c--) {
        out.add((d - c) * 8 + c);
      }
    }
  }
  return out;
}

/// 量化表（按 (u+v) 频率位置递增，模拟感知权重；DQT 内按之字序下发）。
Uint8List _quantMatrix(int scale, {required double chromaBoost}) {
  final m = Uint8List(64);
  for (var v = 0; v < 8; v++) {
    for (var u = 0; u < 8; u++) {
      final base = (2 + (u + v) * (u + v) * 1.05) * chromaBoost;
      m[u * 8 + v] = ((base * scale + 50) / 100).round().clamp(1, 255);
    }
  }
  return Uint8List.fromList([for (final p in _zigzag) m[p]]);
}

/// 一维 DCT 核：C[u][x] = a(u)·cos((2x+1)uπ/16)。
final List<Float64List> _dctCore = _buildDctCore();

List<Float64List> _buildDctCore() {
  final c = [for (var i = 0; i < 8; i++) Float64List(8)];
  for (var u = 0; u < 8; u++) {
    // 正交归一 DCT-II：a(0)=√(1/N)=1/√8，a(u≠0)=√(2/N)=1/2（N=8）。
    // 解码端的 IDCT 用同一组系数，编码端写错这个尺度会让整幅亮度整体偏暗/溢出
    // （DC 写成 4× 真值时，纯色 200 亮度会被还原成 0）。
    final a = u == 0 ? 1 / math.sqrt(8) : math.sqrt(2 / 8);
    for (var x = 0; x < 8; x++) {
      c[u][x] = a * math.cos((2 * x + 1) * u * math.pi / 16);
    }
  }
  return c;
}

/// 8×8 前向 DCT（分离两次一维；输入已减 128）。
void _fdct8(Float64List src, Float64List dst, Float64List tmp) {
  for (var y = 0; y < 8; y++) {
    for (var u = 0; u < 8; u++) {
      var s = 0.0;
      for (var x = 0; x < 8; x++) {
        s += _dctCore[u][x] * src[y * 8 + x];
      }
      tmp[y * 8 + u] = s;
    }
  }
  for (var x = 0; x < 8; x++) {
    for (var v = 0; v < 8; v++) {
      var s = 0.0;
      for (var y = 0; y < 8; y++) {
        s += _dctCore[v][y] * tmp[y * 8 + x];
      }
      dst[v * 8 + x] = s;
    }
  }
}

/// 幅值 → JPEG 类别（0 表示零，1..10 表示位数）。
int _category(int v) {
  var t = v.abs();
  var n = 0;
  while (t > 0) {
    t = t >> 1;
    n++;
  }
  return n;
}

/// F.13 EXTEND 的编码侧对偶：负数发送补码位型。
int _extendBits(int v, int n) => v < 0 ? v + ((1 << n) - 1) : v;

// ============================ Huffman 表 ============================

/// 现场生成的 Huffman 表（DHT 下发 bits/vals + 编码用规范码）。
class _Huff {
  _Huff({
    required this.bits,
    required this.symbols,
    required this.code,
    required this.len,
  });

  /// bits[i] = 长度为 i+1 的码字个数。
  final Uint8List bits;

  /// 按（码长, 符号值）升序的符号表（DHT 下发顺序）。
  final List<int> symbols;
  final Map<int, int> code;
  final Map<int, int> len;
}

/// 由符号频次构造 Huffman 表；分布畸形导致码过长时回落等长码。
_Huff _buildHuff(Map<int, int> freq) {
  final symbols = (freq.keys.toList()..sort()).where((s) => s <= 0xFF).toList();
  while (symbols.length < 2) {
    final next = symbols.isEmpty ? 0 : symbols.last + 1;
    if (symbols.contains(next)) break;
    symbols.add(next);
  }
  final weights = [for (final s in symbols) freq[s] ?? 1];
  var lens = _huffmanLengths(weights);
  if (lens == null || lens.any((l) => l > 15)) {
    final fixed = math.max(1, (math.log(symbols.length) / math.ln2).ceil());
    lens = [for (var i = 0; i < symbols.length; i++) fixed];
  }
  _avoidAllOnes(lens);
  return _canonical(symbols, lens);
}

/// 两队列贪心求码长（叶队列 + 内部队列，合并权值天然有序）。
List<int>? _huffmanLengths(List<int> weights) {
  final n = weights.length;
  if (n == 0) return null;
  if (n == 1) return [1];
  final leaves = [for (var i = 0; i < n; i++) i]
    ..sort((a, b) => weights[a].compareTo(weights[b]));
  final w = <int>[...weights]; // 内部节点权值追加在 n 之后
  final parent = List<int>.filled(2 * n - 1, -1);
  final inner = <int>[];
  var p1 = 0, p2 = 0, next = n;

  int? takeMin() {
    final a = p1 < leaves.length ? leaves[p1] : null;
    final b = p2 < inner.length ? inner[p2] : null;
    if (a != null && (b == null || w[a] <= w[b])) {
      p1++;
      return a;
    }
    if (b != null) {
      p2++;
      return b;
    }
    return null;
  }

  var alive = n;
  while (alive > 1) {
    final a = takeMin();
    final b = takeMin();
    if (a == null || b == null) return null;
    final id = next++;
    w.add(w[a] + w[b]);
    parent[a] = id;
    parent[b] = id;
    inner.add(id);
    alive--;
  }
  final out = List<int>.filled(n, 1);
  for (var i = 0; i < n; i++) {
    // 深度 = 到根节点的边数（叶自身不算，根节点那次合并也只算一条边）。
    var d = 0, p = parent[i];
    while (p != -1) {
      d++;
      p = parent[p];
    }
    out[i] = d;
  }
  return out;
}

/// JPEG 禁止「全 1」码字（解码端用它当填充/保留标记）：码表**完备**（Kraft=1）时，
/// 规范码的最后一个码字必然是全 1，所以把该符号加长一级，让码表留出一个空洞。
void _avoidAllOnes(List<int> lens) {
  int kraft() => lens.fold(0, (a, l) => a + (1 << (16 - l)));
  var guard = 0;
  while (kraft() == 0x10000 && guard++ < 16) {
    var lastLongest = 0;
    for (var i = 1; i < lens.length; i++) {
      if (lens[i] >= lens[lastLongest]) lastLongest = i;
    }
    if (lens[lastLongest] >= 16) return;
    lens[lastLongest] = lens[lastLongest] + 1;
  }
}

/// 规范码：同长度按符号值升序编号，长度跳档时左移补位。
_Huff _canonical(List<int> symbols, List<int> lens) {
  final idx = [for (var i = 0; i < symbols.length; i++) i]
    ..sort((a, b) {
      final c = lens[a].compareTo(lens[b]);
      return c != 0 ? c : symbols[a].compareTo(symbols[b]);
    });
  final bits = Uint8List(16);
  final code = <int, int>{};
  final len = <int, int>{};
  final ordered = <int>[];
  var cur = 0, prev = lens[idx.first];
  for (final i in idx) {
    final l = lens[i];
    if (l > prev) {
      // 跳档：下一个长度的起始码 = 上一个已分配码 (cur-1) 加一后左移补位。
      // cur 已在分配后自增，这里不能再 +1，否则码值与 DHT 下发的码表不一致，
      // 解码端会读成非法码（现场生成表时最容易踩的一步）。
      cur = cur << (l - prev);
      prev = l;
    }
    code[symbols[i]] = cur;
    len[symbols[i]] = l;
    bits[l - 1]++;
    ordered.add(symbols[i]);
    cur++;
  }
  return _Huff(bits: bits, symbols: ordered, code: code, len: len);
}

// ============================ 位写入 ============================

class _BitSink {
  _BitSink(this.out);

  final BytesBuilder out;
  int _buf = 0;
  int _cnt = 0;

  void emit(int bits, int len) {
    if (len <= 0) return;
    _buf = (_buf << len) | (bits & ((1 << len) - 1));
    _cnt += len;
    while (_cnt >= 8) {
      _cnt -= 8;
      final b = (_buf >> _cnt) & 0xFF;
      _buf &= (1 << _cnt) - 1;
      out.addByte(b);
      if (b == 0xFF) out.addByte(0x00); // 字节填充
    }
  }

  void flush() {
    if (_cnt > 0) emit((1 << _cnt) - 1, _cnt);
  }
}

// ============================ 编码入口 ============================

/// 把 RGB 字节（3 字节/像素，行优先）编成基线 JPEG。
///
/// [quality] 1~99（界面滑杆给 20~90）。返回的是**真实编码字节**，体积由量化表
/// 与熵编码共同决定，不做任何估算；[width]/[height] 为 0 时抛 [ArgumentError]。
Uint8List kitJpegEncode({
  required int width,
  required int height,
  required Uint8List rgb,
  int quality = 75,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError.value('$width×$height', '尺寸', '必须大于 0');
  }
  assert(rgb.length >= width * height * 3);
  final scale = kitJpegScale(quality);
  final qtY = _quantMatrix(scale, chromaBoost: 1.0);
  final qtC = _quantMatrix(scale, chromaBoost: 1.6);

  // 1) RGB → YCbCr + 4:2:0 抽样（2×2 均值），边缘复制补齐到 16 的倍数。
  final mcuW = (width + 15) ~/ 16;
  final mcuH = (height + 15) ~/ 16;
  final pw = mcuW * 16, ph = mcuH * 16;
  final cw = mcuW * 8, ch = mcuH * 8;
  final y = Uint8List(pw * ph);
  final cb = Uint8List(cw * ch);
  final cr = Uint8List(cw * ch);
  for (var j = 0; j < ph; j++) {
    final sy = math.min(j, height - 1);
    for (var i = 0; i < pw; i++) {
      final sx = math.min(i, width - 1);
      final o = (sy * width + sx) * 3;
      final r = rgb[o], g = rgb[o + 1], b = rgb[o + 2];
      y[j * pw + i] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
  }
  for (var j = 0; j < ch; j++) {
    for (var i = 0; i < cw; i++) {
      var sb = 0, sr = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final px = math.min(i * 2 + dx, width - 1);
          final py = math.min(j * 2 + dy, height - 1);
          final o = (py * width + px) * 3;
          final r = rgb[o], g = rgb[o + 1], b = rgb[o + 2];
          sb += (-0.168736 * r - 0.331264 * g + 0.5 * b + 128).round();
          sr += (0.5 * r - 0.418688 * g - 0.081312 * b + 128).round();
        }
      }
      cb[j * cw + i] = (sb / 4).round().clamp(0, 255);
      cr[j * cw + i] = (sr / 4).round().clamp(0, 255);
    }
  }

  // 2) 分块 DCT + 量化，同时统计符号频次（Huffman 表现场生成的依据）。
  final yBlocks = <Int16List>[];
  final cBlocks = <int, List<Int16List>>{2: [], 3: []};
  final fDc = <int, int>{0: 1}, fAc = <int, int>{0: 1};
  final fCdc = <int, int>{0: 1}, fCac = <int, int>{0: 1};
  final src = Float64List(64);
  final dst = Float64List(64);
  final tmp = Float64List(64);
  final zig = Float64List(64);

  Int16List quantize(
    Uint8List plane,
    int planeW,
    int ox,
    int oy,
    Uint8List qt,
  ) {
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        src[r * 8 + c] = plane[(oy + r) * planeW + ox + c] - 128.0;
      }
    }
    _fdct8(src, dst, tmp);
    for (var k = 0; k < 64; k++) {
      zig[k] = dst[_zigzag[k]];
    }
    final q = Int16List(64);
    for (var k = 0; k < 64; k++) {
      q[k] = (zig[k] / qt[k]).round();
    }
    return q;
  }

  /// DC 频次必须按**差值**统计 —— 编码器写出的也是 `q[0]-prev`，两遍必须用同
  /// 一条差分链（含顺序），否则差值落在表外的符号，现场生成的 Huffman 表就缺码。
  void tally(Int16List q, Map<int, int> fdc, Map<int, int> fac, List<int> prev) {
    final d = q[0] - prev[0];
    prev[0] = q[0];
    final c = _category(d);
    fdc[c] = (fdc[c] ?? 0) + 1;
    var run = 0;
    for (var k = 1; k < 64; k++) {
      if (q[k] == 0) {
        run++;
        continue;
      }
      while (run > 15) {
        fac[0xF0] = (fac[0xF0] ?? 0) + 1;
        run -= 16;
      }
      final s = _category(q[k]);
      fac[(run << 4) | s] = (fac[(run << 4) | s] ?? 0) + 1;
      run = 0;
    }
    if (run > 0) fac[0] = (fac[0] ?? 0) + 1;
  }

  // 频次遍的差分链必须与编码遍逐条对应：Cb 与 Cr 在编码端各有一条独立 prev，
  // 合用一条会让 Cr 的差值口径变成「相对上一块 Cb」。
  final prevTY = <int>[0], prevTB = <int>[0], prevTR = <int>[0];
  for (var my = 0; my < mcuH; my++) {
    for (var mx = 0; mx < mcuW; mx++) {
      for (var by = 0; by < 2; by++) {
        for (var bx = 0; bx < 2; bx++) {
          final q = quantize(y, pw, mx * 16 + bx * 8, my * 16 + by * 8, qtY);
          yBlocks.add(q);
          tally(q, fDc, fAc, prevTY);
        }
      }
      final qb = quantize(cb, cw, mx * 8, my * 8, qtC);
      cBlocks[2]!.add(qb);
      tally(qb, fCdc, fCac, prevTB);
      final qr = quantize(cr, cw, mx * 8, my * 8, qtC);
      cBlocks[3]!.add(qr);
      tally(qr, fCdc, fCac, prevTR);
    }
  }

  final hYdc = _buildHuff(fDc), hYac = _buildHuff(fAc);
  final hCdc = _buildHuff(fCdc), hCac = _buildHuff(fCac);

  // 3) 组装比特流。
  final out = BytesBuilder(copy: false);
  void marker(int m, [List<int>? body]) {
    out
      ..addByte(0xFF)
      ..addByte(m);
    if (body != null) out.add(body);
  }

  void u16(List<int> b, int at, int v) {
    b[at] = (v >> 8) & 0xFF;
    b[at + 1] = v & 0xFF;
  }

  marker(0xD8); // SOI
  final app0 = <int>[
    0x00, 0x10, // 段长
    0x4A, 0x46, 0x49, 0x46, 0x00, // 'JFIF\0'
    0x01, 0x01, 0x01, // 版本 1.1 · 单位=dots per pixel
    0x00, 0x01, 0x00, 0x01, // 密度 1×1（不宣称物理 DPI）
    0x00, 0x00, // 无缩略图
  ];
  marker(0xE0, app0);
  for (final e in [(0, qtY), (1, qtC)]) {
    final body = <int>[0x00, 0x43, e.$1, ...e.$2];
    marker(0xDB, body);
  }
  final sof = <int>[
    0x00,
    0x11,
    8,
    0,
    0,
    0,
    0,
    3,
    1,
    0x22,
    0,
    2,
    0x11,
    1,
    3,
    0x11,
    1,
  ];
  u16(sof, 3, height);
  u16(sof, 5, width);
  marker(0xC0, sof);
  void dht(int tcTh, _Huff h) {
    final body = <int>[0, 0, tcTh, ...h.bits, ...h.symbols];
    u16(body, 0, 1 + 16 + h.symbols.length + 2);
    marker(0xC4, body);
  }

  dht(0x00, hYdc);
  dht(0x10, hYac);
  dht(0x01, hCdc);
  dht(0x11, hCac);
  marker(0xDA, <int>[
    0x00, 0x0C, // 段长
    0x03, // 3 分量
    0x01, 0x00, // Y：DC 表 0 · AC 表 0
    0x02, 0x11, // Cb：DC 表 1 · AC 表 1
    0x03, 0x11, // Cr：同上
    0x00, 0x3F, 0x00, // Ss=0 · Se=63 · Ah/Al=0
  ]);

  final bits = _BitSink(out);
  void encode(Int16List q, _Huff dc, _Huff ac, List<int> prev) {
    final d = q[0] - prev[0];
    prev[0] = q[0];
    final s = _category(d);
    final hc = dc.code[s];
    final hl = dc.len[s];
    if (hc == null || hl == null) {
      // 两遍共用同一条差分链，理论上不缺码；真缺时按「本块无亮度变化」落 DC0
      // 并跳过该块，保证流仍可解（宁可掉一块细节也不在用户机上抛异常）。
      bits.emit(dc.code[0]!, dc.len[0]!);
      return;
    }
    bits.emit(hc, hl);
    if (s > 0) bits.emit(_extendBits(d, s), s);
    var run = 0;
    for (var k = 1; k < 64; k++) {
      if (q[k] == 0) {
        run++;
        continue;
      }
      while (run > 15) {
        bits.emit(ac.code[0xF0] ?? ac.code[0]!, ac.len[0xF0] ?? ac.len[0]!);
        run -= 16;
      }
      final sz = _category(q[k]);
      final sym = (run << 4) | sz;
      final hc = ac.code[sym];
      final hl = ac.len[sym];
      if (hc == null || hl == null) {
        bits.emit(ac.code[0]!, ac.len[0]!); // 兜底 EOB，保证流可解
        return;
      }
      bits.emit(hc, hl);
      bits.emit(_extendBits(q[k], sz), sz);
      run = 0;
    }
    if (run > 0) bits.emit(ac.code[0]!, ac.len[0]!);
  }

  final prevY = <int>[0], prevB = <int>[0], prevR = <int>[0];
  for (var mcu = 0; mcu < mcuW * mcuH; mcu++) {
    for (var k = 0; k < 4; k++) {
      encode(yBlocks[mcu * 4 + k], hYdc, hYac, prevY);
    }
    encode(cBlocks[2]![mcu], hCdc, hCac, prevB);
    encode(cBlocks[3]![mcu], hCdc, hCac, prevR);
  }
  bits.flush();
  marker(0xD9); // EOI
  return out.takeBytes();
}
