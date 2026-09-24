import 'dart:async';

import 'package:flutter/foundation.dart';

/// 日志级别（【日志方案】R3：info/warn/error 三档）。
enum LhLevel {
  info('I'),
  warn('W'),
  error('E');

  const LhLevel(this.tag);

  /// 单字母标记，用于 `formatted` 渲染。
  final String tag;
}

/// 一条内存日志。
class LhLogLine {
  LhLogLine(this.time, this.level, this.text, {this.key = false});

  final DateTime time;
  final LhLevel level;
  final String text;

  /// 关键路径日志标记（R13：本期只进缓冲，logcat 转发留待接 NativeLog）。
  final bool key;

  /// `HH:mm:ss.SSS [级别] 文本`
  String get formatted {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    final ts = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}'
        '.${three(time.millisecond)}';
    return '$ts [${level.tag}] $text';
  }
}

/// App 内存日志核心：环形缓冲 300 条 + 300ms 节流版本信号 +
/// 错误上报防递归/500ms 限频 + 堆栈前 14 行压单行。
///
/// 全局静态单例（与【日志方案】§3 骨架一致），业务层与 UI 直接引用；
/// UI 只订阅 [version]，渲染走 [windowText]，复制走 [allText]。
class AppLog {
  AppLog._();

  static final List<LhLogLine> lines = [];
  static final ValueNotifier<int> version = ValueNotifier(0);

  /// 环形缓冲上限（R2）。
  static const int _max = 300;

  /// UI 渲染窗口条数（R6：复制永远全量，渲染只给窗口）。
  static const int displayWindow = 120;

  /// 堆栈压缩保留行数（R10）。
  static const int _stackKeepLines = 14;

  /// 测试钩子：每次错误上报落一条后回调，用于注入重入/断言逻辑。
  static void Function(LhLogLine)? onReport;

  static Timer? _flushTimer;
  static DateTime? _lastErrorLog;
  static bool _reporting = false;

  /// 普通记录。
  static void add(String text, {LhLevel level = LhLevel.info}) {
    _push(LhLogLine(DateTime.now(), level, text));
  }

  /// 堆栈记录：取前 14 行压单行（R10），级别 error。
  static void addStack(String stack) {
    final flattened = stack
        .split('\n')
        .take(_stackKeepLines)
        .join(' | ');
    _push(LhLogLine(DateTime.now(), LhLevel.error, flattened));
  }

  /// 关键路径记录：本期只进缓冲并打 key 标记。
  /// // R13 接 NativeLog 的挂点（Android EventChannel 在 Task 5 一并接
  /// file sink 时再评估，不做全量 logcat 镜像）。
  static void addKey(String text) {
    _push(LhLogLine(DateTime.now(), LhLevel.info, text, key: true));
  }

  /// 错误上报：防递归 + 500ms 合并限频（R9）。
  static void reportError(String text) {
    if (_reporting) return; // 重入直接吞掉
    final now = DateTime.now();
    if (_lastErrorLog != null &&
        now.difference(_lastErrorLog!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastErrorLog = now;
    _reporting = true;
    try {
      final line = LhLogLine(now, LhLevel.error, text);
      _push(line);
      onReport?.call(line);
    } finally {
      _reporting = false;
    }
  }

  /// 全量文本（复制永远全量，R11）。
  static String allText() =>
      lines.map((l) => l.formatted).join('\n');

  /// 渲染窗口文本：取最近 [width] 条，再截到 [displayWindow]。
  static String windowText(int width) {
    final w = width > displayWindow ? displayWindow : width;
    final start = lines.length > w ? lines.length - w : 0;
    return lines.sublist(start).map((l) => l.formatted).join('\n');
  }

  /// 重置全部状态（测试 setUp 用；生产侧进程重启即天然清空）。
  static void reset() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _lastErrorLog = null;
    _reporting = false;
    lines.clear();
    version.value = 0;
  }

  static void _push(LhLogLine line) {
    lines.add(line);
    if (lines.length > _max) lines.removeRange(0, lines.length - _max);
    // R5 节流：300ms 内的突发合并成一次 version 通知。
    _flushTimer ??= Timer(const Duration(milliseconds: 300), () {
      _flushTimer = null;
      version.value++;
    });
  }
}
