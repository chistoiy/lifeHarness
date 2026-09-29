import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/kits/domain/kit_imgz.dart';

/// V1.47 批3 · 图片体积缩小域层（压缩计划 + 自写基线 JPEG 编码器）。
///
/// JPEG 一律用 `dart:ui` 真解码回读校验：编错就解不开，比数标记靠得多。
/// 解码走 [WidgetTester.runAsync]（真异步通道），FakeAsync 下 codec 不落地。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List solid(int w, int h, int r, int g, int b) {
    final out = Uint8List(w * h * 3);
    for (var i = 0; i < w * h; i++) {
      out[i * 3] = r;
      out[i * 3 + 1] = g;
      out[i * 3 + 2] = b;
    }
    return out;
  }

  /// 横向渐变 + 竖向条带，让 DCT 有高频成分可压。
  Uint8List gradient(int w, int h) {
    final out = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 3;
        out[o] = (x * 255 ~/ (w - 1));
        out[o + 1] = (y * 255 ~/ (h - 1));
        out[o + 2] = ((x + y) % 7 == 0) ? 255 : 40;
      }
    }
    return out;
  }

  group('1 · 压缩计划', () {
    test('最长边等比缩放 · 不放大 · 结果至少 1px', () {
      final p = kitImgzPlan(srcW: 4000, srcH: 3000, maxEdge: 1600);
      expect((p.outW, p.outH), (1600, 1200));
      expect(p.scaled, isTrue);
      expect(p.ratio, closeTo(0.4, 1e-9));

      final same = kitImgzPlan(srcW: 800, srcH: 600, maxEdge: 1600);
      expect((same.outW, same.outH), (800, 600));
      expect(same.scaled, isFalse);

      final tiny = kitImgzPlan(srcW: 3, srcH: 1, maxEdge: 64);
      expect((tiny.outW, tiny.outH), (3, 1));
      expect(kitImgzPlan(srcW: 0, srcH: 0, maxEdge: 999).outW, 0);
      // 越界的最长边先夹到区间再用。
      expect(kitImgzPlan(srcW: 100, srcH: 100, maxEdge: 100000).outW, 100);
    });

    test('节省百分比与文案（原型 #imgzInfo 口径）', () {
      expect(kitImgzSavedPct(1000, 250), 75.0);
      expect(kitImgzSavedPct(0, 10), 0.0);
      expect(kitImgzSavedPct(1000, 1200), closeTo(-20.0, 1e-9));
      final plan = kitImgzPlan(srcW: 4000, srcH: 3000, maxEdge: 1600);
      final info = kitImgzInfo(
        plan: plan,
        srcBytes: 2560 * 1024,
        outBytes: 180 * 1024,
        fmt: kKitImgzFmtJpeg,
        watermark: true,
      );
      expect(info, contains('原图 4000×3000'));
      expect(info, contains('缩至 1600×1200'));
      expect(info, contains('体积减少'));
      expect(info, contains('JPEG 质量档已生效'));
      expect(info, contains('已加右下角水印'));
      expect(
        kitImgzShare(plan: plan, srcBytes: 1000, outBytes: 300),
        '图片压缩 4000×3000 1000B → 1600×1200 300B · −70.0%',
      );
    });

    test('批量队列只算真实字节 · 未压的标排队中', () {
      const a = KitImgzQueueItem(name: 'a.jpg', srcBytes: 2000, outBytes: 500);
      const b = KitImgzQueueItem(name: 'b.jpg', srcBytes: 1000);
      expect(kitImgzQueueText(a), '2.0KB → 500B · −75%');
      expect(kitImgzQueueText(b), '排队中…');
      final sum = kitImgzBatchSummary([a, b]);
      expect(sum, contains('批量合计 2 张 · 已压 1 张'));
      expect(sum, contains('每张都为本机真实编码'));
      expect(kitImgzBatchSummary([b]), isEmpty);
    });

    test('参数落库 round-trip · 越界与缺省回默认', () {
      final s = KitImgzState.decode(
        kitImgzEncode(edge: 1200, quality: 80, watermark: true),
      );
      expect((s.edge, s.quality, s.mark), (1200, 80, true));
      final def = KitImgzState.decode({});
      expect((def.edge, def.quality, def.mark), (1600, 60, false));
      expect(
        KitImgzState.decode({'imgzEdge': 1, 'imgzQ': 999}).edge,
        kKitImgzEdgeMin,
      );
      expect(KitImgzState.decode({'imgzQ': 999}).quality, kKitImgzQMax);
    });
  });

  group('2 · JPEG 编码器', () {
    test('质量缩放因子（libjpeg 同式）', () {
      expect(kitJpegScale(50), 100);
      expect(kitJpegScale(75), 50);
      expect(kitJpegScale(25), 200);
      expect(kitJpegScale(90), 20);
    });

    test('码流骨架：SOI/APP0/DQT×2/SOF0/DHT×4/SOS/EOI', () {
      final bytes = kitJpegEncode(
        width: 32,
        height: 16,
        rgb: solid(32, 16, 10, 200, 60),
      );
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);
      expect(bytes[bytes.length - 2], 0xFF);
      expect(bytes[bytes.length - 1], 0xD9);
      final marks = <int>[];
      for (var i = 0; i < bytes.length - 1; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] != 0x00 && bytes[i + 1] != 0xFF) {
          marks.add(bytes[i + 1]);
        }
      }
      expect(marks.first, 0xD8);
      expect(
        marks,
        containsAllInOrder([
          0xD8,
          0xE0,
          0xDB,
          0xDB,
          0xC0,
          0xC4,
          0xC4,
          0xC4,
          0xC4,
          0xDA,
          0xD9,
        ]),
      );
      // SOS 之后的熵数据里 0xFF 必须成对（0xFF00 字节填充），不允许出现裸标记。
      final sos = bytes.indexOf(0xDA, 2);
      final eoi = bytes.length - 2;
      for (var i = sos; i < eoi; i++) {
        if (bytes[i] == 0xFF) {
          expect(bytes[i + 1], 0x00, reason: '扫描段内的 0xFF 必须跟 0x00 填充');
        }
      }
    });

    testWidgets('单色小图可被 dart:ui 真解码 · 尺寸一致', (tester) async {
      await tester.runAsync(() async {
        final bytes = kitJpegEncode(
          width: 48,
          height: 32,
          rgb: solid(48, 32, 200, 30, 90),
        );
        final img = await _decode(bytes);
        expect(img.width, 48);
        expect(img.height, 32);
        final data = await img.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        expect(data, isNotNull);
        final px = data!.buffer.asUint8List();
        // 中心像素应接近原色（JPEG 有损，容差 24）。
        final o = ((16 * 48) + 24) * 4;
        expect(px[o], closeTo(200, 24));
        expect(px[o + 1], closeTo(30, 24));
        expect(px[o + 2], closeTo(90, 24));
        expect(px[o + 3], 255);
        img.dispose();
      });
    });

    testWidgets('渐变图解码后仍可还原 · 且质量越低体积越小', (tester) async {
      await tester.runAsync(() async {
        final rgb = gradient(96, 64);
        final hi = kitJpegEncode(width: 96, height: 64, rgb: rgb, quality: 90);
        final lo = kitJpegEncode(width: 96, height: 64, rgb: rgb, quality: 20);
        expect(lo.length, lessThan(hi.length));
        final img = await _decode(hi);
        expect((img.width, img.height), (96, 64));
        final data = await img.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        final px = data!.buffer.asUint8List();
        // 左上应偏暗、右下应偏亮（R 通道随 x 递增）。
        final tl = px[0], br = px[((63 * 96) + 95) * 4];
        expect(tl, lessThan(br));
        img.dispose();
      });
    });

    testWidgets('非 16 倍数的奇尺寸图（边缘补齐）也能解码', (tester) async {
      await tester.runAsync(() async {
        final bytes = kitJpegEncode(width: 17, height: 9, rgb: gradient(17, 9));
        final img = await _decode(bytes);
        expect(img.width, lessThanOrEqualTo(17));
        expect(img.height, lessThanOrEqualTo(9));
        img.dispose();
      });
    });
  });
}

Future<ui.Image> _decode(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  return frame.image;
}
