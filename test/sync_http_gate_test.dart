import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/sync/http_gate.dart';
import 'package:lifeharness/core/sync/service_config.dart';

/// Task 12：HttpGate 唯一请求出口（按服务节流 + 429/503 退避重发）。
///
/// 纪律（协议文档 §9）：单测不真连公网——MockClient + 假 sleeper（不真等），
/// 只在节流间隔断言里用真实 [DateTime.now] 时钟（等待量由假 sleeper 捕获参数）。
void main() {
  setUp(AppLog.reset);
  tearDown(AppLog.reset);

  ServiceConfig cfg({String id = 'svc1', int intervalMs = 0}) =>
      ServiceConfig(id: id, requestIntervalMs: intervalMs);

  http.Request get(String path) =>
      http.Request('GET', Uri.parse('https://dav.example.com$path'));

  test('429→200：两次尝试成功，且请求工厂被调用 2 次（重发必须 build 重建）',
      () async {
    var builds = 0;
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) {
        return http.Response('slow down', 429, headers: {'retry-after': '5'});
      }
      return http.Response('ok', 200);
    });
    final waits = <Duration>[];
    final gate = HttpGate(sleeper: (d) async {
      waits.add(d);
    });

    final res = await gate.send(
      client,
      () {
        builds++;
        return get('/f/a.txt');
      },
      config: cfg(),
      label: 'GET /f/a.txt',
    );

    expect(res.statusCode, 200);
    // 已知坑：复用同一请求对象必失败（流式体只读一遍 + 签名含日期）→ 工厂重建。
    expect(builds, 2, reason: '退避重发必须用 build() 重建请求');
    expect(waits, contains(const Duration(seconds: 5)));
    expect(
      AppLog.lines.map((l) => l.text),
      contains('⏳ GET /f/a.txt 被限流(429)，等待 5s 后重发'),
      reason: 'label 只含方法+路径，凭据永不进 label',
    );
  });

  test('Retry-After HTTP-date 形态：按 now 差值喂 sleeper（假时钟钉死时刻）',
      () async {
    final now = DateTime.utc(2026, 9, 25, 12);
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          '',
          503,
          headers: {
            'retry-after': HttpDate.format(now.add(const Duration(seconds: 10)))
          },
        );
      }
      return http.Response('ok', 200);
    });
    final waits = <Duration>[];
    final gate = HttpGate(
      sleeper: (d) async {
        waits.add(d);
      },
      clock: () => now,
    );

    final res = await gate.send(client, () => get('/f/b.txt'),
        config: cfg(), label: 'GET /f/b.txt');

    expect(res.statusCode, 200);
    expect(waits, contains(const Duration(seconds: 10)),
        reason: 'HTTP-date 形态按 Retry-After 与 now 的差值等待');
  });

  test('连 3 次 503：耗尽次数把最后一个响应交回调用方（不抛、不吞）', () async {
    var builds = 0;
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('busy $calls', 503);
    });
    final waits = <Duration>[];
    final gate = HttpGate(sleeper: (d) async {
      waits.add(d);
    });

    final res = await gate.send(client, () {
      builds++;
      return get('/f/c.txt');
    }, config: cfg(), label: 'GET /f/c.txt');

    expect(res.statusCode, 503);
    expect(calls, 3);
    expect(builds, 3, reason: '每次重发都经工厂重建');
    // 缺省退避 2s<<attempt：attempt0→2s、attempt1→4s。
    expect(waits, contains(const Duration(seconds: 2)));
    expect(waits, contains(const Duration(seconds: 4)));
    expect(await res.stream.bytesToString(), 'busy 3',
        reason: '交回的是最后一次响应本体');
  });

  test('节流：同服务 requestIntervalMs=800，第二请求被喂 >0 的间隔等待',
      () async {
    final client = MockClient((_) async => http.Response('ok', 200));
    final waits = <Duration>[];
    final gate = HttpGate(sleeper: (d) async {
      waits.add(d);
    });
    final c = cfg(intervalMs: 800);

    await gate.send(client, () => get('/a'), config: c, label: 'GET /a');
    expect(waits, isEmpty, reason: '首请求无历史，不应等待');

    await gate.send(client, () => get('/b'), config: c, label: 'GET /b');
    expect(waits, hasLength(1));
    expect(waits.first > Duration.zero, isTrue,
        reason: '间隔 ≥ requestIntervalMs：距上次完成不足 800ms 必须等');
    expect(waits.first.inMilliseconds, lessThanOrEqualTo(800));
  });

  test('跨请求串行：并发水位 == 1（全局串行队列，【调度】R3）', () async {
    var inflight = 0;
    var peak = 0;
    final client = MockClient((_) async {
      inflight++;
      if (inflight > peak) peak = inflight;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inflight--;
      return http.Response('ok', 200);
    });
    final gate = HttpGate(sleeper: (d) async {});

    final results = await Future.wait([
      gate.send(client, () => get('/s1/a'),
          config: cfg(id: 's1'), label: 'GET /s1/a'),
      gate.send(client, () => get('/s2/b'),
          config: cfg(id: 's2'), label: 'GET /s2/b'),
      gate.send(client, () => get('/s1/c'),
          config: cfg(id: 's1'), label: 'GET /s1/c'),
    ]);

    expect(results.map((r) => r.statusCode), [200, 200, 200]);
    expect(peak, 1, reason: '同一时刻只允许一个请求在飞（多服务并发非本期场景）');
  });

  group('waitForStatus 纯函数（顶层导出）', () {
    final now = DateTime.utc(2026, 9, 25, 12);

    test('非 429/503 → null（不等待）', () {
      expect(waitForStatus(200, null, 0, now), isNull);
      expect(waitForStatus(200, '5', 0, now), isNull);
      expect(waitForStatus(500, '5', 0, now), isNull);
    });

    test('Retry-After 秒数形态', () {
      expect(waitForStatus(429, '7', 0, now), const Duration(seconds: 7));
      expect(waitForStatus(503, ' 9 ', 0, now), const Duration(seconds: 9));
    });

    test('Retry-After HTTP-date 形态按 now 差值', () {
      expect(
        waitForStatus(
            503, HttpDate.format(now.add(const Duration(seconds: 13))), 0, now),
        const Duration(seconds: 13),
      );
      expect(
        waitForStatus(
            429, HttpDate.format(now.subtract(const Duration(seconds: 5))), 0, now),
        Duration.zero,
        reason: '已过期的 HTTP-date 钳到 0（立即可重发）',
      );
    });

    test('缺省 2s<<attempt，上限 30s', () {
      expect(waitForStatus(429, null, 0, now), const Duration(seconds: 2));
      expect(waitForStatus(429, null, 1, now), const Duration(seconds: 4));
      expect(waitForStatus(429, null, 2, now), const Duration(seconds: 8));
      expect(waitForStatus(429, '3600', 0, now), const Duration(seconds: 30),
          reason: '任何来源的等待都不超过 30s');
    });

    test('无法解析的 Retry-After 回落缺省退避', () {
      expect(waitForStatus(429, 'soon-ish', 1, now), const Duration(seconds: 4));
    });
  });

  test('全局单例 httpGate 存在且可注入（生产出口唯一）', () {
    expect(httpGate, isA<HttpGate>());
  });
}
