import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/kits/domain/kit_net.dart';

/// V1.47 批3 · 网络类工具域层（Ping / 测速）。纯计算、随机源注入，零 I/O。
void main() {
  group('1 · Ping 探针', () {
    test('成功行：ms≥1 且落在基准 ±55% 内 · TTL 54~61', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 400; i++) {
        final base = kitPingBase(rnd);
        expect(base, inInclusiveRange(12, 52));
        final l = kitPingProbe(seq: i + 1, timeoutS: 2, base: base, rnd: rnd);
        expect(base, inInclusiveRange(12, 52));
        if (!l.ok) continue;
        expect(l.ms, greaterThanOrEqualTo(1));
        expect(l.ms, lessThanOrEqualTo(base * 1.6));
        expect(l.ttl, inInclusiveRange(54, 61));
        expect(l.text, contains('seq=${l.seq}'));
        expect(l.text, contains('ttl=${l.ttl}'));
        expect(l.text, contains('ms'));
      }
    });

    test('丢包率≈原型 7%（2000 次样本容差 4%~10%）', () {
      final rnd = math.Random(20260929);
      var lost = 0;
      for (var i = 0; i < 2000; i++) {
        if (!kitPingProbe(seq: i, timeoutS: 2, base: 30, rnd: rnd).ok) lost++;
      }
      expect(lost / 2000, inInclusiveRange(.04, .10));
    });

    test('超时行文案带超时秒数（原型「请求超时（>2s）」）', () {
      final rnd = math.Random(1);
      KitPingLine? lostLine;
      for (var i = 0; i < 200 && lostLine == null; i++) {
        final l = kitPingProbe(seq: i + 1, timeoutS: 3, base: 30, rnd: rnd);
        if (!l.ok) lostLine = l;
      }
      expect(lostLine, isNotNull);
      final l = lostLine!;
      expect(l.text, 'seq=${l.seq} 请求超时（>3s）');
    });

    test('模拟解析 IP：两段前缀之一 + 四节', () {
      final rnd = math.Random(5);
      final heads = <String>{};
      for (var i = 0; i < 200; i++) {
        final ip = kitPingIp(rnd);
        expect(ip.split('.').length, 4);
        heads.add(ip.substring(0, ip.indexOf('.', ip.indexOf('.') + 1)));
      }
      expect(heads, {'39.156', '110.242'});
    });

    test('首行口径：主机 / 56 字节包 / 超时秒', () {
      expect(
        kitPingHead('baidu.com', '39.156.20.7', 2),
        'PING baidu.com · 模拟解析 → 39.156.20.7 · 56 字节包 · 超时 2s',
      );
    });
  });

  group('2 · Ping 统计', () {
    const ok1 = KitPingLine(seq: 1, ok: true, ms: 20, ttl: 55, timeoutS: 2);
    const ok2 = KitPingLine(seq: 2, ok: true, ms: 40, ttl: 56, timeoutS: 2);
    const bad = KitPingLine(seq: 3, ok: false, ms: 0, ttl: 0, timeoutS: 2);

    test('收/发·min/max·平均·抖动·丢包率全部实算', () {
      var s = const KitPingStats();
      for (final l in [ok1, ok2, bad]) {
        s = kitPingApply(s, l);
      }
      expect(s.sent, 3);
      expect(s.recv, 2);
      expect(s.lost, 1);
      expect(s.minMs, 20);
      expect(s.maxMs, 40);
      expect(s.avgMs, 30);
      expect(s.jitterMs, 20); // |40-20| ÷ (2-1)
      expect(s.lossPct, 33);
      expect(s.lossWarn, isTrue); // >10%
    });

    test('四格读数顺序与占位（未发包一律「—」）', () {
      final empty = kitPingCells(const KitPingStats());
      expect(empty.map((e) => e.$1).toList(), ['—', '—', '— / —', '—']);
      expect(empty[3].$2, '丢包率');
      final s = kitPingApply(kitPingApply(const KitPingStats(), ok1), ok2);
      final cells = kitPingCells(s);
      expect(cells[0].$1, '2/2');
      expect(cells[1].$1, '30.0');
      expect(cells[2].$1, '20.0 / 40.0');
      expect(cells[3].$1, '0%');
    });

    test('分享串含收发/平均/丢包/抖动', () {
      final s = kitPingApply(const KitPingStats(), ok1);
      expect(
        kitPingShare('baidu.com', s),
        'PING baidu.com · 发 1 收 1 · 平均 20.0ms · 丢包 0% · 抖动 0.0ms',
      );
    });
  });

  group('3 · 测速', () {
    test('目标 40~200Mbps · 仪表角度按 200 满量程钉顶', () {
      final rnd = math.Random(3);
      for (var i = 0; i < 300; i++) {
        expect(kitSpeedTarget(rnd), inInclusiveRange(40, 200));
      }
      expect(kitSpeedGaugeAngle(0), 0);
      expect(kitSpeedGaugeAngle(100), closeTo(180, .001));
      expect(kitSpeedGaugeAngle(240), 360);
    });

    test('爬坡值非负且不超目标 1.2 倍', () {
      final rnd = math.Random(11);
      for (var t = 1; t <= 46; t++) {
        final p = t * kKitSpeedTickMs / kKitSpeedRampMs;
        final v = kitSpeedRampValue(progress: p, target: 100, rnd: rnd);
        expect(v, greaterThanOrEqualTo(0));
        if (p < 1) expect(v, lessThanOrEqualTo(100 * 1.18));
      }
      expect(kKitSpeedRampMs ~/ kKitSpeedTickMs, 45);
    });

    test('收尾：上传≈下载 12~22% · 延迟 8~48 · 抖动 0~20', () {
      final rnd = math.Random(13);
      for (var i = 0; i < 200; i++) {
        final r = kitSpeedFinish(
          node: '电信·杭州',
          target: 100,
          ts: 1000,
          rnd: rnd,
        );
        expect(r.up, inInclusiveRange(12, 22));
        expect(r.pingMs, inInclusiveRange(8, 48));
        expect(r.jitterMs, inInclusiveRange(0, 20));
        expect(r.node, '电信·杭州');
      }
    });

    test('历史最多 5 条 · 新结果落表头', () {
      var hist = const <KitSpeedResult>[];
      for (var i = 0; i < 7; i++) {
        hist = kitSpeedPush(
          hist,
          kitSpeedFinish(
            node: kKitSpeedNodes[i % 3],
            target: 50.0 + i,
            ts: 1000 + i,
            rnd: math.Random(i),
          ),
        );
      }
      expect(hist.length, kKitSpeedHistMax);
      expect(hist.first.down, closeTo(56, .001));
      expect(hist.first.ts, 1006);
    });

    test('对比标记：首条相对上一条 ▲/▼ · 不足两条为 null', () {
      const a = KitSpeedResult(
        node: 'x',
        down: 90,
        up: 10,
        pingMs: 20,
        jitterMs: 5,
        ts: 3,
      );
      const b = KitSpeedResult(
        node: 'x',
        down: 50,
        up: 8,
        pingMs: 20,
        jitterMs: 5,
        ts: 2,
      );
      expect(kitSpeedDelta([a, b]), '▲');
      expect(kitSpeedDelta([b, a]), '▼');
      expect(kitSpeedDelta([a]), isNull);
    });

    test('落库串 round-trip（spd 键与原型 KITS.spd 同构）', () {
      const r = KitSpeedResult(
        node: '移动·广州',
        down: 88.4,
        up: 12.3,
        pingMs: 25,
        jitterMs: 9,
        ts: 1700000000000,
      );
      final back = kitSpeedDecode(kitSpeedEncode([r]));
      expect(back.single.node, '移动·广州');
      expect(back.single.down, 88.4);
      expect(back.single.up, 12.3);
      expect(back.single.pingMs, 25);
      expect(back.single.jitterMs, 9);
      expect(back.single.ts, 1700000000000);
      expect(kitSpeedDecode({}), isEmpty);
      expect(
        kitSpeedDecode({
          'spd': [
            null,
            1,
            {'n': 'x'},
          ],
        }),
        isEmpty,
      );
    });

    test('结果说明行与分享串（原型 #spdMsg 口径）', () {
      const r = KitSpeedResult(
        node: '电信·杭州',
        down: 88.4,
        up: 12.3,
        pingMs: 25,
        jitterMs: 9,
        ts: 1,
      );
      expect(kitSpeedMsg(r), '下载 88.4 · 上传 12.3 Mbps · 延迟 25ms · 抖动 9ms');
      expect(kitSpeedShare(r), '测速 电信·杭州 · 下载 88.4Mbps / 上传 12.3 · 延迟 25ms');
    });
  });
}
