import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/nfc/data/nfc_tag_io.dart';
import 'package:lifeharness/features/nfc/domain/nfc_tag_content.dart';
import 'package:lifeharness/features/nfc/presentation/nfc_tag_tool_sheet.dart';

NfcRawRecord _uri(String uri, [int code = 0]) => NfcRawRecord(
      tnf: 1,
      type: Uint8List.fromList(const [0x55]), // RTD-URI 'U'
      payload: Uint8List.fromList([code, ...utf8.encode(uri)]),
    );

NfcRawRecord _text(String body, [String lang = 'en']) => NfcRawRecord(
      tnf: 1,
      type: Uint8List.fromList(const [0x54]), // RTD-Text 'T'
      payload: Uint8List.fromList([
        0x02, // 状态位：UTF-8 ＋ 语言码 2 字节
        ...utf8.encode(lang),
        ...utf8.encode(body),
      ]),
    );

NfcRawRecord _aar([String pkg = 'com.lifeharness.lifeharness']) => NfcRawRecord(
      tnf: 4,
      type: Uint8List.fromList(utf8.encode('android.com:pkg')),
      payload: Uint8List.fromList(utf8.encode(pkg)),
    );

void main() {
  group('NFC 卡片内容 · 解析', () {
    test('URI 记录：前缀码还原成完整网址（0x04＝https://）', () {
      final c = nfcContentOf([_uri('example.com/x', 4)]);
      expect(c.records.length, 1);
      expect(c.records[0].kind, NfcContentKind.uri);
      expect(c.records[0].typeLabel, '网址');
      expect(c.records[0].text, 'https://example.com/x');
      expect(c.records[0].editable, true);
    });

    test('URI 记录：0x00 前缀码＝完整 URI（本 App 的卡片走这支）', () {
      final c = nfcContentOf([_uri('lh://nfc/abc123DEF456')]);
      expect(c.records[0].text, 'lh://nfc/abc123DEF456');
      expect(c.isLifeHarnessCard, true);
    });

    test('文本记录：剥掉状态位与语言码，只留正文', () {
      final c = nfcContentOf([_text('今天读了一章')]);
      expect(c.records[0].kind, NfcContentKind.text);
      expect(c.records[0].typeLabel, '文本');
      expect(c.records[0].text, '今天读了一章');
    });

    test('AAR 记录：只读展示，不可修改（改掉＝卡废）', () {
      final c = nfcContentOf([_uri('lh://nfc/abc123DEF456'), _aar()]);
      expect(c.records.length, 2);
      expect(c.records[1].kind, NfcContentKind.aar);
      expect(c.records[1].typeLabel, '本 App 绑定');
      expect(c.records[1].editable, false);
      expect(c.records[1].text, 'com.lifeharness.lifeharness');
    });

    test('可编辑序号取第一条可改记录（AAR 单独存在时无）', () {
      expect(nfcContentOf([_uri('lh://nfc/x'), _aar()]).firstEditableIndex, 0);
      expect(nfcContentOf([_aar()]).firstEditableIndex, null);
    });

    test('外部类型记录：按 ASCII 只读展示', () {
      final r = NfcRawRecord(
        tnf: 4,
        type: Uint8List.fromList(utf8.encode('com.example:note')),
        payload: Uint8List.fromList(utf8.encode('hello')),
      );
      final c = nfcContentOf([r]);
      expect(c.records[0].kind, NfcContentKind.other);
      expect(c.records[0].typeLabel, '外部 · com.example:note');
      expect(c.records[0].text, 'hello');
      expect(c.records[0].editable, false);
    });
  });

  group('NFC 卡片内容 · base64 判定', () {
    test('标准 base64 → 认出并给出解码文', () {
      expect(decodeBase64Text(base64.encode(utf8.encode('Hello world'))),
          'Hello world');
    });

    test('中文 base64 也能解', () {
      expect(
          decodeBase64Text(base64.encode(utf8.encode('今天打卡完成'))), '今天打卡完成');
    });

    test('普通文本 → 不是 base64', () {
      expect(decodeBase64Text('lh://nfc/abc123DEF456'), null);
      expect(decodeBase64Text('今天读了一章'), null);
    });

    test('过短（<8）→ 不是 base64', () {
      expect(decodeBase64Text('aGk='), null);
    });

    test('长度非 4 的倍数 → 不是 base64', () {
      expect(decodeBase64Text('abcdefg'), null);
    });

    test('解码后不可打印（二进制垃圾）→ 不是 base64', () {
      final bytes =
          Uint8List.fromList(const [0x00, 0x01, 0x02, 0x03, 0x04, 0x05]);
      expect(decodeBase64Text(base64.encode(bytes)), null);
    });

    test('base64 记录展示：原文 ＋ 解码后两栏都有', () {
      final raw = base64.encode(utf8.encode('打卡成功'));
      final c = nfcContentOf([_text(raw)]);
      final r = c.records[0];
      expect(r.isBase64, true);
      expect(r.text, raw);
      expect(r.decodedText, '打卡成功');
      expect(r.editValue, '打卡成功'); // 编辑框给解码文
      expect(c.hasBase64, true);
    });
  });

  group('NFC 卡片内容 · 改与清空', () {
    test('改 URI：沿用原前缀码写回（形态不变）', () {
      final orig = _uri('example.com/a', 4);
      // 用户看到的是完整网址（前缀码已还原），改完仍是 https:// 开头 ⇒ 沿用 0x04。
      final next = nfcRecordWithText(orig, 'https://example.com/b');
      expect(next.tnf, 1);
      expect(next.type, orig.type);
      expect(next.payload[0], 4);
      expect(utf8.decode(next.payload.sublist(1)), 'example.com/b');
    });

    test('改 URI：改后不再以原前缀开头 ⇒ 退回 0x00 全量写', () {
      final orig = _uri('example.com/a', 4);
      final next = nfcRecordWithText(orig, 'lh://nfc/abc123DEF456');
      expect(next.payload[0], 0);
      expect(utf8.decode(next.payload.sublist(1)), 'lh://nfc/abc123DEF456');
    });

    test('改文本：保留状态位与语言码，只换正文', () {
      final orig = _text('旧内容');
      final next = nfcRecordWithText(orig, '新内容');
      expect(next.payload[0], 0x02);
      expect(utf8.decode(next.payload.sublist(3)), '新内容');
    });

    test('base64 卡：改解码文 → 按原样重新编码写回', () {
      final raw = base64.encode(utf8.encode('旧文本'));
      final orig = _text(raw);
      final stored = encodeBase64Text('新文本'); // 调用方先编码
      final next = nfcRecordWithText(orig, stored);
      final back = nfcContentOf([next]);
      expect(back.records[0].isBase64, true);
      expect(back.records[0].decodedText, '新文本');
      expect(back.records[0].text, base64.encode(utf8.encode('新文本')));
    });

    test('清空 ⇒ 一条 TNF=EMPTY 空记录（读侧得不出任何内容）', () {
      final empty = nfcEmptyRecords();
      expect(empty.length, 1);
      expect(empty[0].tnf, 0);
      expect(empty[0].type.isEmpty, true);
      expect(empty[0].payload.isEmpty, true);
      expect(nfcContentOf(empty).firstEditableIndex, null);
    });

    test('空消息（零记录）⇒ 视为空卡', () {
      expect(nfcContentOf(const <NfcRawRecord>[]).isEmpty, true);
    });
    test('TNF=EMPTY 记录被过滤：清空过的卡读回就是空', () {
      // 真机复现的根因：清空写的是 EMPTY 记录，它排在首位时整条消息在系统
      // 眼里是空的（Android 按首条记录取类型）⇒ 读回显示「类型 0（空）」。
      final cleared = nfcEmptyRecords();
      final c = nfcContentOf(cleared);
      expect(c.records, isEmpty);
      expect(c.isEmpty, true);
      expect(c.firstEditableIndex, null);
    });

    test('EMPTY 排在内容前面时也被滤掉，内容正常显示', () {
      // 追加在 EMPTY 后面的内容此前完全读不出来（系统只看首条）。
      final c = nfcContentOf([...nfcEmptyRecords(), _text('hello')]);
      expect(c.records.length, 1);
      expect(c.records[0].kind, NfcContentKind.text);
      expect(c.records[0].text, 'hello');
      expect(c.records[0].index, 0); // 下标按滤后序列
    });

    test('新建 RTD-URI 记录：形态与系统识别的 RTD-URI 一致', () {
      final r = nfcNewUriRecord('lh://nfc/abc123DEF456');
      expect(r.tnf, 1);
      expect(r.type, Uint8List.fromList(const [0x55]));
      expect(r.payload[0], 0); // 无前缀码
      expect(utf8.decode(r.payload.sublist(1)), 'lh://nfc/abc123DEF456');
      // 读回应是网址类型（不是文本）。
      expect(nfcContentOf([r]).records[0].kind, NfcContentKind.uri);
    });

    test('新建 RTD-Text 记录：状态位＋en 语言码＋正文', () {
      final r = nfcNewTextRecord('今天读了一章');
      expect(r.tnf, 1);
      expect(r.type, Uint8List.fromList(const [0x54]));
      expect(nfcContentOf([r]).records[0].text, '今天读了一章');
      expect(nfcContentOf([r]).records[0].kind, NfcContentKind.text);
    });

    test('清空后写入网址：读回是网址且内容正确（真机报障主链路）', () {
      // 模拟：清空卡 → 写入一个网址 → 再读。此前会得到 [EMPTY, Text] ⇒ 读成空。
      final next = [...nfcContentOf(nfcEmptyRecords()).raw, nfcNewUriRecord('https://a.com')];
      final back = nfcContentOf(next);
      expect(back.records.length, 1);
      expect(back.records[0].kind, NfcContentKind.uri);
      expect(back.records[0].text, 'https://a.com');
      expect(back.isEmpty, false);
    });
  });

  group('NFC 卡片内容工具 · 弹层', () {
    testWidgets('贴卡 → 展示原文与类型；只读记录标「只读」', (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      expect(find.text('把卡片贴到手机背面'), findsOneWidget);

      io.tap(_probeOf([_uri('lh://nfc/abc123DEF456'), _aar()]));
      await tester.pumpAndSettle();

      expect(find.text('网址'), findsOneWidget);
      expect(find.text('lh://nfc/abc123DEF456'), findsOneWidget);
      expect(find.text('本 App 绑定'), findsOneWidget);
      expect(find.text('com.lifeharness.lifeharness'), findsOneWidget);
      expect(find.text('只读'), findsOneWidget);
      expect(find.text('144 字节 · 可写 · 2 条记录'), findsOneWidget);
    });

    testWidgets('base64 卡 → 原文与解码文同时展示', (tester) async {
      final io = _FakeIo();
      final raw = base64.encode(utf8.encode('打卡成功'));
      await _pump(tester, io);
      io.tap(_probeOf([_text(raw)]));
      await tester.pumpAndSettle();

      expect(find.text(raw), findsOneWidget);
      expect(find.text('解码后'), findsOneWidget);
      expect(find.text('打卡成功'), findsOneWidget);
      expect(find.text('base64'), findsOneWidget);
    });

    testWidgets('修改内容 → 保存 → 贴卡才写；写回保留其余记录', (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      io.tap(_probeOf([_uri('lh://nfc/abc123DEF456'), _aar()]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit')));
      await tester.pumpAndSettle();
      expect(find.text('lh://nfc/abc123DEF456'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('nfc-tool-text')), 'lh://nfc/NEW00000001');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit-save')));
      await tester.pumpAndSettle();

      expect(find.text('把卡片贴回手机背面'), findsOneWidget);
      expect(io.written, isNull); // 卡没贴回来就不写

      io.tap(_probeOf([_uri('lh://nfc/abc123DEF456'), _aar()]));
      await tester.pumpAndSettle();
      expect(find.text('已写入'), findsOneWidget);

      final w = io.written!;
      expect(w.length, 2);
      expect(utf8.decode(w[1].payload), 'com.lifeharness.lifeharness');
      expect(utf8.decode(w[0].payload.sublist(1)), 'lh://nfc/NEW00000001');
    });

    testWidgets('清空卡片 → 二次确认 → 写一条 EMPTY 记录', (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      io.tap(_probeOf([_uri('lh://nfc/abc123DEF456'), _aar()]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nfc-tool-clear')));
      await tester.pumpAndSettle();
      expect(find.text('清空卡片内容'), findsOneWidget);

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('把卡片贴回手机背面'), findsOneWidget);

      io.tap(_probeOf([_uri('lh://nfc/abc123DEF456'), _aar()]));
      await tester.pumpAndSettle();
      expect(find.text('已写入'), findsOneWidget);
      expect(io.written!.length, 1);
      expect(io.written![0].tnf, 0);
      expect(io.written![0].payload.isEmpty, true);
    });

    testWidgets('空卡 → 也能写一段新内容进去', (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      io.tap(_probeOf(const <NfcRawRecord>[]));
      await tester.pumpAndSettle();
      expect(find.text('这张卡是空的'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('nfc-tool-text')), '我的第一段内容');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit-save')));
      await tester.pumpAndSettle();

      io.tap(_probeOf(const <NfcRawRecord>[]));
      await tester.pumpAndSettle();
      expect(find.text('已写入'), findsOneWidget);
      final w = io.written!;
      expect(w.length, 1);
      expect(w[0].type, Uint8List.fromList(const [0x54])); // RTD-Text
      expect(utf8.decode(w[0].payload.sublist(3)), '我的第一段内容');
    });

    testWidgets('不是 NDEF 的卡 ⇒ 提示且不进入内容态', (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      io.tap(const NfcTagProbe(isNdef: false, isWritable: false));
      await tester.pumpAndSettle();
      expect(find.text('这张卡不支持 NDEF 记录（读不出也写不了）'), findsOneWidget);
      expect(find.byKey(const ValueKey('nfc-tool-edit')), findsNothing);
    });

    testWidgets('取消写入 ⇒ 回到已读内容态', (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      io.tap(_probeOf([_text('abc')]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('nfc-tool-text')), 'xyz');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit-save')));
      await tester.pumpAndSettle();
      expect(io.written, isNull);

      await tester.tap(find.byKey(const ValueKey('nfc-tool-write-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nfc-tool-edit')), findsOneWidget);
      expect(io.written, isNull);
    });

    testWidgets('空卡写网址：存成 RTD-URI，读回是网址而不是文本（真机报障主链路）',
        (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      // 先读一张**清空过的卡**（只有一条 EMPTY 记录）。
      io.tap(_probeOf(nfcEmptyRecords()));
      await tester.pumpAndSettle();
      expect(find.text('这张卡是空的'), findsOneWidget);

      // 粘进一个网址 → 类型应自动切到「网址」。
      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('nfc-tool-text')), 'lh://nfc/abc123DEF456');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nfc-tool-kind-uri')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit-save')));
      await tester.pumpAndSettle();
      io.tap(_probeOf(nfcEmptyRecords()));
      await tester.pumpAndSettle();
      expect(find.text('已写入'), findsOneWidget);

      // 写出去的必须是 RTD-URI，且是**首条**（读回来系统才认）。
      final w = io.written!;
      expect(w.length, 1);
      expect(w[0].tnf, 1);
      expect(w[0].type, Uint8List.fromList(const [0x55]));
      expect(utf8.decode(w[0].payload.sublist(1)), 'lh://nfc/abc123DEF456');
      // 模拟再读一次：显示为网址。
      io.tap(_probeOf(w));
      await tester.pumpAndSettle();
      expect(find.text('网址'), findsOneWidget);
      expect(find.text('lh://nfc/abc123DEF456'), findsOneWidget);
    });

    testWidgets('类型可手动切换：文本改网址后按 RTD-URI 写回', (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      io.tap(_probeOf([_text('plain text')]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit')));
      await tester.pumpAndSettle();
      // 默认沿用原类型＝文本。
      expect(find.byKey(const ValueKey('nfc-tool-kind-text')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nfc-tool-kind-uri')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('nfc-tool-text')), 'https://a.com/x');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nfc-tool-edit-save')));
      await tester.pumpAndSettle();
      io.tap(_probeOf([_text('plain text')]));
      await tester.pumpAndSettle();

      final w = io.written!;
      expect(w.length, 1);
      expect(w[0].type, Uint8List.fromList(const [0x55])); // 已换成 RTD-URI
      expect(utf8.decode(w[0].payload.sublist(1)), 'https://a.com/x');
    });

    testWidgets('关层 ⇒ 停会话（不留后台 NFC 监听）', (tester) async {
      final io = _FakeIo();
      await _pump(tester, io);
      io.tap(_probeOf([_text('abc')]));
      await tester.pumpAndSettle();
      expect(io.stops, 0);
      await tester.tap(find.byKey(const ValueKey('nfc-tool-close')));
      await tester.pumpAndSettle();
      expect(io.stops, 1);
    });
  });
}

class _FakeIo implements NfcTagIo {
  void Function(NfcTagProbe)? onProbe;
  void Function(String)? onError;
  List<NfcRawRecord>? written;
  int stops = 0;
  bool enabled = true;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> startRead({
    required void Function(NfcTagProbe probe) onProbe,
    required void Function(String code) onError,
  }) async {
    this.onProbe = onProbe;
    this.onError = onError;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> writeUri(String uri) async {}

  @override
  Future<void> writeRecords(List<NfcRawRecord> records) async {
    written = records;
  }

  /// 模拟「把卡贴上来」。
  ///
  /// ⚠ **必须是同步方法**：`await Future.delayed(...)` 之后再 pump 会死锁——
  /// 假时钟只有 pump 才推进，而 pump 又排在 await 之后（2026-10-17 实测白耗 6 分钟）。
  /// 回调内部的 await（写卡）由紧随其后的 `pump` 推进。
  void tap(NfcTagProbe p) {
    onProbe!(p);
  }
}

NfcTagProbe _probeOf(List<NfcRawRecord> recs) =>
    NfcTagProbe(isNdef: true, isWritable: true, maxSize: 144, records: recs);

Future<void> _pump(WidgetTester tester, _FakeIo io) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (ctx) {
      return Scaffold(
        body: TextButton(
          onPressed: () => showNfcTagToolSheet(ctx, io: io),
          child: const Text('open'),
        ),
      );
    }),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
