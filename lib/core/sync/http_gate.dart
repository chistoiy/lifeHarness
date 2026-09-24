import 'dart:async';
import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;

import '../logging/app_log.dart';
import 'service_config.dart';

/// 触发退避的状态码（R10：只认账号频控类 429/503，其余错误交调用方决策）。
const _throttledStatuses = {429, 503};

/// 退避上限：任何来源（含超大 Retry-After）都不超过 30s。
const _maxBackoff = Duration(seconds: 30);

/// 缺省退避：`2s << attempt`（attempt 从 0 起 → 2s、4s、8s…）。
Duration defaultBackoff(int attempt) => Duration(seconds: 2 << attempt);

/// 退避时长判定纯函数（顶层导出供单测，协议文档 §8 waitFor 的拆形版）：
/// 非 429/503 返回 null（不等待）；否则优先解析 `Retry-After`
/// （秒数 `5` 与 HTTP-date `Wed, 21 Oct 2015 07:28:00 GMT` 双形态），
/// 解析失败回落 [defaultBackoff]；结果钳进 [0, 30s]。
Duration? waitForStatus(
    int statusCode, String? retryAfterHeader, int attempt, DateTime now) {
  if (!_throttledStatuses.contains(statusCode)) return null;
  final wait =
      _retryAfterToDuration(retryAfterHeader, now) ?? defaultBackoff(attempt);
  if (wait < Duration.zero) return Duration.zero;
  return wait > _maxBackoff ? _maxBackoff : wait;
}

/// Retry-After 头 → 时长；无法识别返回 null（由调用方回落缺省）。
Duration? _retryAfterToDuration(String? header, DateTime now) {
  final h = header?.trim();
  if (h == null || h.isEmpty) return null;
  final secs = int.tryParse(h);
  if (secs != null) return Duration(seconds: secs < 0 ? 0 : secs);
  try {
    // HTTP-date（IMF-fixdate，如 "Fri, 25 Sep 2026 13:00:00 GMT"）：
    // Dart 的 DateTime.parse 不认该形态，走 dart:io HttpDate（返回 UTC）；
    // 与 now 求差，过期时刻钳 0，由上层统一钳制。
    return HttpDate.parse(h).difference(now.toUtc());
  } catch (_) {
    return null;
  }
}

/// 按服务 id 记录上次请求完成时刻的节流器（[HttpGate.send] 的私有内部件）。
class _Throttle {
  final Map<String, DateTime> _lastDone = {};

  /// 同服务距上次完成不足 `config.requestIntervalMs` 时，经 [sleeper] 补足差值。
  Future<void> wait(ServiceConfig config, DateTime Function() clock,
      Future<void> Function(Duration) sleeper) async {
    final last = _lastDone[config.id];
    if (last == null) return;
    final gap = Duration(milliseconds: config.requestIntervalMs) -
        clock().difference(last);
    if (gap > Duration.zero) await sleeper(gap);
  }

  /// 记录「该服务本次请求完成」节流基准时刻。
  void done(String id, DateTime at) => _lastDone[id] = at;
}

/// 唯一请求出口（【云盘】§8 / R10 语义，协议文档骨架的实例化落点）。
///
/// 做且只做两件事：
/// 1. **节流**：按服务 id 记录上次请求完成时刻，同服务两次请求间隔
///    ≥ `config.requestIntervalMs`（档位 150/300/800，读取放 [send] 内）；
/// 2. **退避**：撞 429/503 时优先听 `Retry-After`（秒数与 HTTP-date 双形态），
///    缺省 `2s<<attempt`、上限 30s，重发一律用工厂 [build] 重建请求
///    （流式体只读一遍 + SigV4 签名含日期，复用同一对象必失败——已知坑）。
///
/// 串行口径（【调度】R3）：跨服务共享一个串行队列，同一时刻只有一个请求在飞；
/// 多服务并发不是本期场景，全局串行最保守。
///
/// 测试纪律（§9）：注入假 sleeper（不真等）+ MockClient 假 client；
/// 生产 sleeper 默认 [Future.delayed]。
class HttpGate {
  HttpGate({
    Future<void> Function(Duration)? sleeper,
    DateTime Function()? clock,
  })  : _sleeper = sleeper ?? Future.delayed,
        _clock = clock ?? DateTime.now;

  final Future<void> Function(Duration) _sleeper;
  final DateTime Function() _clock;
  final _Throttle _throttle = _Throttle();

  /// 全局串行尾：所有 [send] 首尾相接排队（含节流等待与退避重发整段），
  /// 杜绝任何两请求同时在飞；队列不因单次失败而断链。
  Future<void> _tail = Future<void>.value();

  /// 发出唯一形态的请求：先排队过节流，再 [client] send [build]；
  /// 429/503 按 [waitForStatus] 退避重发（每次 build 重建），
  /// 耗尽 [maxAttempts] 次把最后一个响应原样交回调用方（不抛、不吞）。
  Future<http.StreamedResponse> send(
    http.Client client,
    http.BaseRequest Function() build, {
    required ServiceConfig config,
    required String label,
    int maxAttempts = 3,
  }) {
    final next = _tail
        .then((_) => _sendLocked(client, build, config, label, maxAttempts));
    // 链尾吞掉异常与结果：失败只回给当次调用方，后续请求照常排队。
    _tail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }

  Future<http.StreamedResponse> _sendLocked(
    http.Client client,
    http.BaseRequest Function() build,
    ServiceConfig config,
    String label,
    int maxAttempts,
  ) async {
    http.StreamedResponse? res;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await _throttle.wait(config, _clock, _sleeper);
      // 每次重建请求：流式体只读一遍 + 签名含日期。
      res = await client.send(build());
      _throttle.done(config.id, _clock());
      final wait = waitForStatus(
          res.statusCode, res.headers['retry-after'], attempt, _clock());
      // 非限流码 → 原样交回；已是最后一次尝试 → 不再空等，直接交回。
      if (wait == null || attempt == maxAttempts - 1) return res;
      // label 只含方法+路径（凭据永不进 label）；AppLog.add 入口另有 sanitize。
      AppLog.add('⏳ $label 被限流(${res.statusCode})，'
          '等待 ${wait.inSeconds}s 后重发');
      await _sleeper(wait);
    }
    return res!; // 耗尽次数：把最后的响应交回调用方
  }
}

/// 全局唯一出口实例：core/sync 之外不得自建 client（architecture_test R5 守护）。
final httpGate = HttpGate();
