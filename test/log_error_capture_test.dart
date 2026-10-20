import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/error_capture.dart';

void main() {
  // 先保存 old 引用，tearDown 还原三处原值（brief 纪律）。
  late FlutterExceptionHandler? oldFlutterError;
  late ErrorCallback? oldPlatformError;
  late ErrorWidgetBuilder oldErrorWidget;

  // flutter_test 在 testWidgets 体结束时自检 ErrorWidget.builder 是否被换走
  // （_verifyErrorWidgetBuilderUnset），故三处还原必须在用例体内、断言前完成；
  // tearDown 里的再还原只是兜底幂等。
  void restoreGlobals() {
    FlutterError.onError = oldFlutterError;
    PlatformDispatcher.instance.onError = oldPlatformError;
    ErrorWidget.builder = oldErrorWidget;
  }

  setUp(() {
    // AppLog.reset() 清 _lastErrorLog，规避 500ms 限频跨用例合并（R9）。
    AppLog.reset();
    oldFlutterError = FlutterError.onError;
    oldPlatformError = PlatformDispatcher.instance.onError;
    oldErrorWidget = ErrorWidget.builder;
  });

  tearDown(() {
    restoreGlobals();
    AppLog.reset();
  });

  // AppLog._push 有 300ms version 节流定时器，fake-async 不留 pending 定时器，
  // 故各用例结束前 pump(400ms) 推进时钟放行。

  testWidgets('FlutterError 构建错误进日志', (tester) async {
    installGlobalErrorLogging();
    final err = FlutterErrorDetails(exception: StateError('x'), library: 'test');
    FlutterError.reportError(err);
    restoreGlobals();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      AppLog.lines.any(
          (l) => l.text.contains('FlutterError') && l.text.contains('x')),
      isTrue,
    );
  });

  testWidgets('ErrorWidget.builder 占位错误进日志且给指引文案', (tester) async {
    installGlobalErrorLogging();
    final details =
        FlutterErrorDetails(exception: StateError('w'), library: 'test');
    final placeholder = ErrorWidget.builder(details);
    restoreGlobals();
    expect(AppLog.lines.any((l) => l.text.contains('WidgetError')), isTrue);
    // 占位 Widget 文案「页面局部错误（详情见日志）」（R12，无教学句）。
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: placeholder),
    );
    expect(find.textContaining('页面局部错误（详情见日志）'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('PlatformDispatcher.onError 返回 true 且记未捕获异常',
      (tester) async {
    installGlobalErrorLogging();
    final handler = PlatformDispatcher.instance.onError!;
    final handled = handler(StateError('a'), StackTrace.current);
    restoreGlobals();
    expect(handled, isTrue);
    expect(
      AppLog.lines.any((l) => l.text.contains('未捕获异常') && l.text.contains('a')),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 400));
  });
}
