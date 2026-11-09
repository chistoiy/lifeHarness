import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/launch_route.dart';

/// 冷启动不丢弃守护（冻结档 B15/B16 · `test/desktop_launch_queue_test.dart`）。
///
/// **B15 红线**：原生侧把意图**先入队**；Dart 侧**首帧完成后**才消费。
/// 首帧前读队列＝永久丢失意图 ⇒ 判不合格。
/// **B16**：一次意图只产生一次路由（单次消费，二次调用拿不到，防重放）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  /// 模拟原生侧队列：只有被 takeLaunchRoute 取走才清空（这就是「不丢弃」的本体）。
  Map<String, dynamic>? queue = <String, dynamic>{
    'action': 'ledger',
    'args': <String, dynamic>{},
  };

  setUp(() {
    calls.clear();
    queue = <String, dynamic>{
      'action': 'ledger',
      'args': <String, dynamic>{'amount': '38.5'},
    };
    debugResetLaunchGate();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lh/launch'), (call) async {
      calls.add(call);
      if (call.method != 'takeLaunchRoute') return null;
      final q = queue;
      queue = null; // 单次消费：读到即清空
      return q;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lh/launch'), null);
    debugResetLaunchGate();
  });

  test('首帧未就绪：不消费也不清空（队列仍在原生侧）', () async {
    expect(launchRouteGateOpen, isFalse);
    final r = await takeLaunchRoute();
    expect(r, isNull, reason: '首帧前不该拿到路由');
    expect(calls, isEmpty, reason: 'B15：门禁未开时连通道都不该打');
  });

  test('就绪后单次消费得目标路由', () async {
    markLaunchRouteReady();
    final r = await takeLaunchRoute();
    expect(r, isNotNull);
    expect(r!.action, 'ledger');
    expect(r.args['amount'], '38.5');
    expect(r.route, '/ledger/add');
    expect(calls.where((c) => c.method == 'takeLaunchRoute').length, 1);
  });

  test('二次消费返回 null（防重放 · B16）', () async {
    markLaunchRouteReady();
    expect((await takeLaunchRoute())!.action, 'ledger');
    expect(await takeLaunchRoute(), isNull);
  });

  test('「未就绪时先探一次、就绪后再探」不丢意图（B15 完整时序）', () async {
    // ① 首帧前探：拿不到，但**没把原生队列读空**
    expect(await takeLaunchRoute(), isNull);
    expect(queue, isNotNull, reason: 'B15：门禁未开不该清空原生队列');

    // ② 首帧完成 → 开闸 → 一次拿到
    markLaunchRouteReady();
    final r = await takeLaunchRoute();
    expect(r!.action, 'ledger', reason: 'B15：首帧后就绪必须拿到原意图');
  });

  test('action 为空/缺失时返回 null 且不炸', () async {
    markLaunchRouteReady();
    queue = <String, dynamic>{'args': <String, dynamic>{}};
    expect(await takeLaunchRoute(), isNull);

    queue = <String, dynamic>{'action': '', 'args': <String, dynamic>{}};
    expect(await takeLaunchRoute(), isNull);
  });

  test('非 Map 的带参被安全忽略（禁脏数据炸消费端）', () async {
    markLaunchRouteReady();
    queue = <String, dynamic>{'action': 'inbox', 'args': 'oops'};
    final r = await takeLaunchRoute();
    expect(r!.action, 'inbox');
    expect(r.args, isEmpty);
  });

  test('nfc 透传路由带 isNfc 标记（本模块不解释业务）', () async {
    markLaunchRouteReady();
    queue = <String, dynamic>{'action': 'nfc:aB3xY9zQ1m2K', 'args': <String, dynamic>{}};
    final r = await takeLaunchRoute();
    expect(r!.isNfc, isTrue);
  });
}