import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/kits/domain/kit_b64.dart';

/// V1.47 批3d · Base64 域层（真实 UTF-8 + Base64 通道 · 原型口径逐条对齐）。
void main() {
  group('1 · tab 与文案', () {
    test('四 tab 顺序与标签同原型', () {
      expect(kKitB64Tabs, ['enc', 'dec', 'xenc', 'xdec']);
      expect(kitB64TabLabel('enc'), '图片 → Base64');
      expect(kitB64TabLabel('dec'), 'Base64 → 图片');
      expect(kitB64TabLabel('xenc'), '文本 → Base64');
      expect(kitB64TabLabel('xdec'), 'Base64 → 文本');
    });

    test('计数行按 UTF-8 字节与裸串长度实算', () {
      expect(kitB64Meta(text: ''), '0 字 · UTF-8 0 B · Base64 0 字符');
      final m = kitB64Meta(text: 'LifeHarness');
      expect(m, '11 字 · UTF-8 11 B · Base64 16 字符');
      // 中文 3 字节/字：6 字 → 18 B → 24 字符。
      expect(kitB64Meta(text: '数据在自己手里'), '7 字 · UTF-8 21 B · Base64 28 字符');
    });

    test('产出说明行与串头预览', () {
      expect(
        kitB64OutLenText(srcBytes: 123, b64Len: 164),
        '原文件 123B · Base64 164 字符 ≈ 0.2 KB（约 +33%）',
      );
      final long = 'A' * 200;
      expect(kitB64Peek(long), '${'A' * 180} …');
      expect(kitB64Peek('ABC'), 'ABC');
    });
  });

  group('2 · 编解码与校验', () {
    test('文本往返（中文含多字节）', () {
      const src = 'LifeHarness · 数据在自己手里 🛠';
      final enc = kitB64EncodeText(src);
      expect(kitB64DecodeText(enc), src);
      // 与 dart:convert 标准实现同值（不是自定义表）。
      expect(enc, base64Encode(utf8.encode(src)));
    });

    test('空串与非法串给原型同款错误文案', () {
      expect(kitB64Validate(''), '先粘贴 Base64 字符串');
      expect(
        kitB64Validate('ab!c'),
        '含非法 Base64 字符 · 仅允许 A-Z a-z 0-9 + / =',
      );
      expect(kitB64Validate('ABCD'), null);
      expect(kitB64Validate('ABC'), '长度不是 4 的倍数 · 串可能被截断');
    });

    test('解码失败返回 null 不抛（屏侧按文案报错）', () {
      expect(kitB64DecodeText('####'), null);
      // 合法字符但 UTF-8 断尾：长度是 4 倍数，字节可解，文本不可解。
      expect(kitB64DecodeText('4QID'), null);
      expect(kitB64DecodeBytes('4QID'), isNotNull);
    });

    test('data URI 拆分/补前缀/回拼', () {
      const uri = kKitB64SampleDataUri;
      final s = kitB64Split(uri);
      expect(s.hasUri, isTrue);
      expect(s.mime, 'image/png');
      expect(s.raw.length % 4, 0);
      expect(kitB64Split('  ${s.raw}\n').hasUri, isFalse);
      expect(kitB64AddPrefix(s.raw), 'data:image/png;base64,${s.raw}');
      expect(kitB64AddPrefix(uri), uri);
      expect(kitB64DataUri(s.raw), uri);
      // 示例串是真实 PNG 字节（可解出图片流）。
      final bytes = kitB64DecodeBytes(s.raw)!;
      expect(bytes.length, 123);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('空白与引号不算非法（先清洗再校验）', () {
      final raw = kitB64Split('data:image/png;base64,\n"QUJD"').raw;
      expect(raw, 'QUJD');
      expect(kitB64Validate(raw), null);
      expect(kitB64DecodeText(raw), 'ABC');
    });
  });

  group('3 · 留痕与落库', () {
    final now = DateTime(2026, 9, 30, 10);
    KitB64Recent rec(int i) => KitB64Recent(
      name: 'p$i.jpg',
      size: 1000 + i,
      len: 1400 + i,
      ts: now.subtract(Duration(minutes: i)).millisecondsSinceEpoch,
    );
    KitB64Log log(int i) => KitB64Log(t: '编码 p$i', ok: i.isEven, ts: now.millisecondsSinceEpoch);

    test('头部插入并按 8/6 截断', () {
      var list = <KitB64Recent>[];
      for (var i = 0; i < 12; i++) {
        list = kitB64Push(list, rec(i), kKitB64RecentMax);
      }
      expect(list.length, kKitB64RecentMax);
      expect(list.first.name, 'p11.jpg');
      var hist = <KitB64Log>[];
      for (var i = 0; i < 9; i++) {
        hist = kitB64Push(hist, log(i), kKitB64HistMax);
      }
      expect(hist.length, kKitB64HistMax);
      expect(hist.first.mark(), '✔');
      expect(hist.last.mark(), '✖');
    });

    test('recent 行文案带体积与相对时间 · 空文件另标', () {
      expect(rec(0).text(now), contains('p0.jpg · 1000B → 1.4KB · 刚刚'));
      final empty = KitB64Recent(
        name: 'x.bin',
        size: 0,
        len: 0,
        ts: now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
      expect(empty.text(now), 'x.bin · 0B → 0B · 空文件 · 5 分钟前');
    });

    test('落库 round-trip · 脏结构回落空表', () {
      final d = kitB64Encode(recent: [rec(1)], hist: [log(2)]);
      final s = KitB64State.decode(d);
      expect(s.recent.single.name, 'p1.jpg');
      expect(s.hist.single.t, '编码 p2');
      expect(KitB64State.decode({}).recent, isEmpty);
      expect(KitB64State.decode({'b64Recent': 'x', 'b64Hist': [1]}).recent, isEmpty);
      expect(KitB64State.decode({'b64Hist': [null]}).hist, isEmpty);
    });
  });
}
