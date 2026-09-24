import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_log.dart';

/// 三处全局错误捕获（【日志方案】§3 / R8：启动即挂，先于一切初始化）。
///
/// 从 `main.dart` 提取为独立函数，便于测试直接调用；
/// 记录一律走 [AppLog]（`reportError` 自带防递归 + 500ms 合并限频，
/// `addStack` 堆栈前 14 行压单行，R10）。
void installGlobalErrorLogging() {
  // 1) Flutter 框架内构建/布局错误。
  FlutterError.onError = (FlutterErrorDetails d) {
    AppLog.reportError('‼️ FlutterError: ${d.exception}');
    final stack = d.stack;
    if (stack != null) AppLog.addStack(stack.toString());
    FlutterError.presentError(d); // 保留默认 debug 呈现
  };

  // 2) 异步未捕获异常。
  PlatformDispatcher.instance.onError = (Object e, StackTrace st) {
    AppLog.reportError('‼️ 未捕获异常: $e');
    AppLog.addStack(st.toString());
    return true;
  };

  // 3) 出错 widget 的占位渲染（顺便记录，R12 给「详情见日志」指引）。
  ErrorWidget.builder = (FlutterErrorDetails d) {
    AppLog.reportError('‼️ WidgetError: ${d.exception}');
    return Center(
      child: Text('页面局部错误（详情见日志）：${d.exception}'),
    );
  };
}
