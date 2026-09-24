import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';

/// 脱敏模式（Dart 的 RegExp 不支持行内 `(?i)`，故统一 `caseSensitive: false`）。
final _reAuth = RegExp(
    r'(authorization\s*[:=]\s*)(?:(?:bearer|basic|token|digest)\s+)?\S+',
    caseSensitive: false);
final _reAmzSignature =
    RegExp(r'(x-amz-signature[=:])([^&;\s]+)', caseSensitive: false);
final _reCredential = RegExp(r'(credential=)([^,;\s/]+)', caseSensitive: false);
final _reSecretField = RegExp(
    r'(passphrase|appPassword|secretKey|accessKey)("?\s*[:=]\s*"?)([^\s",;]+)',
    caseSensitive: false);

/// 凭据脱敏（设计稿 §2 红线 / Global Constraints 的代码化落点）：
/// `Authorization` 头、SigV4 signature、`credential=` Scope、口令/AK/SK 字段值
/// 一律先脱敏才允许进任何日志（内存缓冲、文件日志、错误上报同源）。
///
/// 幂等：已打码段（以 `***` 起头）不再二次处理，故 AppLog 入口与 sink
/// 落盘各过一次不会吃掉后续文本。
String sanitize(String text) {
  var out = text;
  // 1) Authorization 头：含可选认证方案前缀（Bearer/Basic/Token/Digest）一并打码。
  out = out.replaceAllMapped(_reAuth, (m) => '${m.group(1)}***(已脱敏)***');
  // 2) SigV4 预签名：X-Amz-Signature（查询串以 & 分隔，不吃掉后续参数）。
  out = out.replaceAllMapped(_reAmzSignature, (m) => '${m.group(1)}***');
  // 3) SigV4 Credential Scope：credential=AKID.../date/region/service/…
  //    只打码密钥段（`/` 后的公开 Scope 保留，便于比对是哪把钥匙）。
  out = out.replaceAllMapped(
      _reCredential,
      (m) => m.group(2)!.startsWith('***') ? m[0]! : '${m.group(1)}***');
  // 4) 口令与密钥字段值：保留末 4 位用于人工比对，其余打码成 `***(…尾4位)***`。
  out = out.replaceAllMapped(_reSecretField, (m) {
    final v = m.group(3)!;
    if (v.startsWith('***')) return m[0]!;
    final tail = v.length > 4 ? '(…${v.substring(v.length - 4)})' : '';
    return '${m.group(1)}${m.group(2)}***$tail***';
  });
  return out;
}

/// 按天滚动文件日志（设计稿 §2「落盘」段）。
///
/// 口径：
/// - 写应用文档目录 `logs/` 下（目录由调用方注入，生产侧走 path_provider，
///   测试侧走系统临时目录——本类不碰平台通道）；
/// - 文件名 `lh-YYYYMMDD.log`（**本地日期**），单文件封顶 [maxBytes]（默认 5MB）
///   后追加 `.1`、`.2` 分卷；
/// - 保留天数 [retentionDays]（默认 14）在 `init` 时按**文件名日期**比较清理，
///   不 stat 文件时间（用户改系统时间/拷贝文件都不影响判定）；
/// - info/warn/error 三级全落；异步批量刷：内部待刷队列 + 3s 周期定时器，
///   warn/error/关键路径行（R13）与满 500 行立即刷，绝不在 UI 线程同步写文件；
/// - 落盘文本先过 [sanitize]（与 AppLog 入口同一函数，双保险）。
class FileLogSink {
  FileLogSink._();

  /// 单文件封顶字节数默认值（5MB）。
  static const int defaultMaxBytes = 5 * 1024 * 1024;

  /// 待刷队列上限：满则立即刷，避免内存堆积（R：环形队列语义，超阈值即落盘）。
  static const int _flushThresholdLines = 500;

  /// 批量刷周期。
  static const Duration _flushInterval = Duration(seconds: 3);

  static String? _dirPath;
  static int _retentionDays = 14;
  static int _maxBytes = defaultMaxBytes;

  static final List<LhLogLine> _pending = [];
  static Timer? _timer;

  /// 文件名 → 已写字节数缓存：避免每行都 stat（单进程独占目录，可信）。
  static final Map<String, int> _sizeCache = {};

  /// 刷盘串行尾：所有 flush 串成一条链，杜绝并发 append 交错。
  static Future<void> _tail = Future<void>.value();

  /// 最近一次落盘失败原因（仅供诊断展示；落盘失败绝不影响主流程）。
  static String? lastError;

  // ---- 保留天数持久化（Task 6 · 设计稿 §2「保留天数在日志设置页配置」）----

  /// 保留天数持久化键（SharedPreferences · 参考 settings_repository 用法）。
  static const String retentionDaysKey = 'log.retentionDays';

  /// 保留天数默认值（未配置时）。
  static const int defaultRetentionDays = 14;

  /// 当前生效的保留天数（内存值；落盘清理按文件名日期比较时使用）。
  static int get retentionDays => _retentionDays;

  /// 读持久化保留天数（未配置回落 [defaultRetentionDays]）。
  static int readRetentionDays(SharedPreferences prefs) =>
      prefs.getInt(retentionDaysKey) ?? defaultRetentionDays;

  /// 写持久化保留天数并同步内存值（日志页滚轮改档即时生效，
  /// 下次启动由 main 经 [readRetentionDays] 传入 [init]）。
  static Future<void> saveRetentionDays(
      SharedPreferences prefs, int days) async {
    final d = days < 0 ? 0 : days;
    _retentionDays = d;
    await prefs.setInt(retentionDaysKey, d);
  }

  /// 打开落盘：建目录 → 清过期 → 挂 [AppLog.onLine] → 起周期定时器。
  static Future<void> init(
    String dirPath, {
    int retentionDays = 14,
    int maxBytes = defaultMaxBytes,
  }) async {
    _dirPath = dirPath;
    _retentionDays = retentionDays < 0 ? 0 : retentionDays;
    _maxBytes = maxBytes <= 0 ? defaultMaxBytes : maxBytes;
    _pending.clear();
    _sizeCache.clear();
    lastError = null;
    await Directory(dirPath).create(recursive: true);
    await _purgeExpired();
    AppLog.onLine = write;
    _timer ??= Timer.periodic(_flushInterval, (_) {
      // 定时器里不 await：flush 自身串行且吞异常。
      flush();
    });
  }

  /// 入待刷队列（不同步写盘）。warn/error/关键行与满阈值即刻刷。
  static void write(LhLogLine line) {
    if (_dirPath == null) return; // 未 init：静默丢弃（日志基建不得抛错给业务）
    final text = sanitize(line.text);
    final safe = text == line.text
        ? line
        : LhLogLine(line.time, line.level, text, key: line.key);
    _pending.add(safe);
    if (safe.level != LhLevel.info ||
        safe.key ||
        _pending.length >= _flushThresholdLines) {
      flush(); // 串行链自带吞异常，此处无需 await
    }
  }

  /// 立即把待刷队列落盘（测试与「附带日志导出」前的显式调用点）。
  static Future<void> flush() {
    final next = _tail.then((_) => _drain());
    _tail = next.catchError((_) {}); // 链上不留未处理异常
    return next;
  }

  /// 落盘文件名列表（含 `.1/.2` 分卷），**新→旧**。未 init 返回空。
  static Future<List<String>> dayFiles() async {
    final dir = _dirPath;
    if (dir == null) return const [];
    final names = <String>[];
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final name = p.basename(f.path);
      if (_namePattern.hasMatch(name)) names.add(name);
    }
    names.sort(_newerFirst);
    return names;
  }

  /// 收起定时器并摘钩（测试结束/退出时调用，防 pending timer 与落盘泄漏）。
  static Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    if (AppLog.onLine == write) AppLog.onLine = null;
    await _tail;
    _pending.clear();
    _sizeCache.clear();
    _dirPath = null;
  }

  // ---- 内部实现 ----

  static final RegExp _namePattern =
      RegExp(r'^lh-(\d{4})(\d{2})(\d{2})\.log(?:\.(\d+))?$');

  /// `lh-YYYYMMDD.log`（本地日期，非 UTC）。
  static String _dayTag(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}';

  static String _baseName(DateTime t) => 'lh-${_dayTag(t)}.log';

  static int _dayKeyOf(String name) {
    final m = _namePattern.firstMatch(name);
    if (m == null) return 0;
    return int.parse('${m.group(1)}${m.group(2)}${m.group(3)}');
  }

  static int _partOf(String name) =>
      int.parse(_namePattern.firstMatch(name)?.group(4) ?? '0');

  /// 新→旧：先比日期，同日再比分卷号（分卷是当天的后写段，排前）。
  static int _newerFirst(String a, String b) {
    final d = _dayKeyOf(b).compareTo(_dayKeyOf(a));
    if (d != 0) return d;
    return _partOf(b).compareTo(_partOf(a));
  }

  static String _join(String name) => p.join(_dirPath!, p.basename(name));

  static Future<void> _purgeExpired() async {
    final dir = _dirPath;
    if (dir == null) return;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final cutoff = todayStart.subtract(Duration(days: _retentionDays));
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final name = p.basename(f.path);
      if (!_namePattern.hasMatch(name)) continue; // 非本 sink 的文件不碰
      if (_dayOf(name).isBefore(cutoff)) {
        try {
          f.deleteSync();
          _sizeCache.remove(name);
        } catch (e) {
          lastError = '删除过期日志失败 $name: $e';
        }
      }
    }
  }

  static DateTime _dayOf(String name) {
    final m = _namePattern.firstMatch(name)!;
    return DateTime(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// 找到该行的目标分卷：当日基础文件（含已有 `.N`）加上待写入字节仍超
  /// [maxBytes] 就向后滚一段，保证单文件封顶 5MB（默认）。
  /// 极端长行（单行即超封顶，如压单行的堆栈）落进空段即止，绝不死循环。
  static String _targetFor(DateTime time, int incomingBytes) {
    final base = _baseName(time);
    var name = base;
    var part = 0;
    while (_sizeOf(name) > 0 && _sizeOf(name) + incomingBytes > _maxBytes) {
      part++;
      name = '$base.$part';
    }
    return name;
  }

  static int _sizeOf(String name) => _sizeCache.putIfAbsent(name, () {
        final f = File(_join(name));
        return f.existsSync() ? f.lengthSync() : 0;
      });

  static Future<void> _drain() async {
    final dir = _dirPath;
    if (dir == null || _pending.isEmpty) return;
    final batch = List<LhLogLine>.of(_pending);
    _pending.clear();
    try {
      final buffer = StringBuffer();
      var bufferBytes = 0;
      var name = '';
      var size = 0;
      Future<void> closeCurrent() async {
        if (buffer.isEmpty) return;
        await _append(dir, name, buffer.toString());
        buffer.clear();
        bufferBytes = 0;
      }

      for (final line in batch) {
        final text = '${line.formatted}\n';
        final bytes = utf8.encode(text).length;
        // 换日 或 当前分卷装不下这批缓冲 → 落现有缓冲并重选目标文件。
        if (name.isEmpty ||
            _dayKeyOf(name) != _dayKeyOf(_baseName(line.time)) ||
            size + bufferBytes + bytes > _maxBytes) {
          await closeCurrent();
          name = _targetFor(line.time, bytes);
          size = _sizeOf(name);
        }
        buffer.write(text);
        bufferBytes += bytes;
      }
      await closeCurrent();
      lastError = null;
    } catch (e) {
      // 落盘失败：丢掉本批并留诊断信息，绝不向上抛（日志不能引发二次错误）。
      lastError = '日志落盘失败: $e';
    }
  }

  static Future<void> _append(String dir, String name, String text) async {
    if (text.isEmpty) return;
    final f = File(p.join(dir, name));
    await f.writeAsString(text, mode: FileMode.append, flush: true);
    _sizeCache[name] = _sizeOf(name) + utf8.encode(text).length;
  }
}
