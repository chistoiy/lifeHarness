import 'dart:async';

/// 事件总线（宿主能力 API 基线 v0，需求 V1.15 预埋）。
///
/// 模块间与后续插件通过事件解耦通信（联动 L1~L14 亦经此编排），
/// 插件只能 publish/subscribe 白名单事件类型，禁止直接 import 宿主 UI。
class EventBus {
  final StreamController<Object> _controller = StreamController<Object>.broadcast();

  /// 订阅某类型事件。
  Stream<T> on<T extends Object>() =>
      _controller.stream.where((e) => e is T).cast<T>();

  /// 发布事件（无订阅者时安全丢弃）。
  void publish(Object event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
