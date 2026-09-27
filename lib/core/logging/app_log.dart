import 'dart:async';

import 'package:flutter/foundation.dart';

import 'file_log_sink.dart';

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
  LhLogLine(this.time, this.level, this.text,
      {this.key = false, this.src = srcSystem});

  /// 未标注来源时的兜底档（日志页筛选 chips 也按它排序收尾）。
  static const String srcSystem = '系统';

  final DateTime time;
  final LhLevel level;
  final String text;

  /// 来源标签（真机反馈 2026-09-26：整屏日志混在一起，看不出是谁报的错）。
  /// 由 [AppLog] 按**调用帧的代码路径**自动归类，各模块无需传参。
  final String src;

  /// 关键路径日志标记（R13：sink 侧与 warn/error 同级「写后立即刷」，
  /// 不做全量 logcat 镜像）。
  final bool key;

  /// `MM-dd HH:mm:ss.SSS [级别] [来源] 文本`
  /// （真机反馈 2026-09-27 V1.50批3.6：只显时分秒跨启动分不清哪天，补月-日。）
  String get formatted {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    final ts =
        '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}'
        '.${three(time.millisecond)}';
    return '$ts [${level.tag}] [$src] $text';
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

  /// 落盘挂点（Task 5）：`FileLogSink.init` 赋值、`dispose` 摘除。
  /// 每条**已脱敏**的行入缓冲后回调一次；回调异常被吞掉，不影响主流程。
  static void Function(LhLogLine)? onLine;

  static Timer? _flushTimer;
  static DateTime? _lastErrorLog;
  static bool _reporting = false;

  /// 普通记录。
  static void add(String text, {LhLevel level = LhLevel.info, String? src}) {
    _push(
        LhLogLine(DateTime.now(), level, _oneLine(sanitize(text)), src: src ?? _deriveSrc()));
  }

  /// 堆栈记录：取前 14 行压单行（R10），级别 error。
  static void addStack(String stack, {String? src}) {
    final flattened = stack
        .split('\n')
        .take(_stackKeepLines)
        .join(' | ');
    _push(LhLogLine(
        DateTime.now(), LhLevel.error, _oneLine(sanitize(flattened)),
        src: src ?? _deriveSrc()));
  }

  /// 关键路径记录：进缓冲并打 key 标记（R13：warn/error 与 key 行落盘即刷）。
  static void addKey(String text, {String? src}) {
    _push(LhLogLine(DateTime.now(), LhLevel.info, _oneLine(sanitize(text)),
        key: true, src: src ?? _deriveSrc()));
  }

  /// 错误上报：防递归 + 500ms 合并限频（R9）。
  static void reportError(String text, {String? src}) {
    if (_reporting) return; // 重入直接吞掉
    final now = DateTime.now();
    if (_lastErrorLog != null &&
        now.difference(_lastErrorLog!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastErrorLog = now;
    _reporting = true;
    try {
      final line = LhLogLine(
          now, LhLevel.error, _oneLine(sanitize(text)), src: src ?? '异常');
      _push(line);
      onReport?.call(line);
    } finally {
      _reporting = false;
    }
  }

  /// 一条日志＝文件里的一行：换行压成 `⏎`、超长截断。
  /// 真机日志页出现过整段 WebDAV/S3 错误 XML 入缓冲，落盘后冷启动回填按物理行
  /// 反解，把一条炸成多条 `00:00:00.000 [I] <?xml…` 的假行——源头压平才是根治。
  static const int _maxTextChars = 600;

  static String _oneLine(String s) {
    var out = s.replaceAll(RegExp(r'\r?\n'), ' ⏎ ');
    if (out.length > _maxTextChars) {
      out = '${out.substring(0, _maxTextChars)}…(+${out.length - _maxTextChars})';
    }
    return out;
  }

  /// 代码路径 → 中文来源标签（两级目录足够定位到模块；未列出的按一级或兜底）。
  static const Map<String, String> _srcLabels = {
    'core/ai': 'AI',
    'core/sync': '同步',
    'core/backup': '备份',
    'core/database': '数据库',
    'core/media': '图片',
    'core/notifications': '通知',
    'core/settings': '设置',
    'core/theme': '设置',
    'core/host': '系统',
    'core/nav': '系统',
    'core/router': '系统',
    'core/logging': '系统',
    'features/read': '阅读',
    'features/todo': '待办',
    'features/calendar': '日程',
    'features/dashboard': '今日',
    'features/days': '日子',
    'features/goals': '目标',
    'features/habit': '习惯',
    'features/inbox': '收集箱',
    'features/items': '物品',
    'features/journal': '日记',
    'features/ledger': '记账',
    'features/care': '呵护',
    'features/settings': '设置',
    'shared': '界面',
  };

  static final RegExp _framePath = RegExp(
      r'(?:package:lifeharness/|lib[/\\])((?:core|features|shared)[^\s)]*?\.dart)');

  /// 从调用栈反推来源：跳过日志基建自己的帧，取第一个业务帧的路径。
  static String _deriveSrc() {
    for (final f in StackTrace.current.toString().split('\n')) {
      final m = _framePath.firstMatch(f);
      if (m == null) continue;
      final rel = m.group(1)!.replaceAll(r'\', '/');
      if (rel.startsWith('core/logging')) continue; // add/_deriveSrc 自身帧
      final segs = rel.split('/');
      final label = segs.length >= 2
          ? _srcLabels['${segs[0]}/${segs[1]}']
          : _srcLabels[segs.first];
      return label ?? _srcLabels[segs.first] ?? LhLogLine.srcSystem;
    }
    return LhLogLine.srcSystem;
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

  /// 冷启动回填历史行（日志页跨重启可见）：直接插到缓冲最前，
  /// **不回调 [onLine]**——这些行本来就在落盘文件里，再走一遍就是重复写盘。
  static void seed(List<LhLogLine> rows) {
    if (rows.isEmpty) return;
    lines.insertAll(0, rows);
    if (lines.length > _max) lines.removeRange(0, lines.length - _max);
    version.value++;
  }

  /// 手动清空内存缓冲（日志页「清理」动作；不动落盘挂点与定时器，
  /// version 立即自增让局部件同步收敛显示）。
  static void clearMemory() {
    lines.clear();
    version.value++;
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
    // 落盘挂钩：入缓冲后同步交给 sink（sink 内部只进队列，绝不同步写文件）。
    try {
      onLine?.call(line);
    } catch (_) {
      // 日志基建的失败不能反噬业务调用栈。
    }
    // R5 节流：300ms 内的突发合并成一次 version 通知。
    _flushTimer ??= Timer(const Duration(milliseconds: 300), () {
      _flushTimer = null;
      version.value++;
    });
  }
}
