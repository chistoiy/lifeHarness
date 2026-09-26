import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';

/// 脱敏模式（Dart 的 RegExp 不支持行内 `(?i)`，故统一 `caseSensitive: false`）。
///
/// Authorization 值形态三类（T5 评审 I-1，HttpGate 落日志前的红线前提）：
/// ① 裸头/`=` 形态 `Authorization: Bearer xyz`（值到空白止）；
/// ② JSON 引号形态 `"Authorization": "Bearer tok"`（值到闭合引号止）；
/// ③ Map/List toString 形态 `{authorization: [Bearer tok]}`（方括号整值）。
/// 值字符类排除 `"` `,` `]` `}`，防止吃掉后续字段。
final _reAuth = RegExp(
    r'''(authorization\s*["']?\s*[:=]\s*)'''
    r'''(?:"[^"]*"|'[^']*'|\[[^\]]*\]|'''
    r'''(?:bearer|basic|token|digest)\s+\S+|[^"\s,\]}]+)''',
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

/// 归档包元信息（日志管理增强 · 归档清单展示用）。
class LhArchiveEntry {
  const LhArchiveEntry({
    required this.name,
    required this.bytes,
    required this.created,
  });

  /// 文件名 `lh-arch-YYYYMMDD-HHmmss.zip`（时间戳可从名复原，不依赖 mtime）。
  final String name;
  final int bytes;
  final DateTime created;
}

/// 归档结果（toast 复述口径：包名 + 成员数 + 包体大小）。
class LhArchiveResult {
  const LhArchiveResult(
      {required this.name, required this.files, required this.bytes});

  final String name;
  final int files;
  final int bytes;
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

  /// 最近一次落盘失败原因（仅供诊断展示；落盘失败绝不影响主流程）。
  static String? lastError;

  // ---- 保留天数持久化（Task 6 · 设计稿 §2「保留天数在日志设置页配置」）----

  /// 保留天数持久化键（SharedPreferences · 参考 settings_repository 用法）。
  static const String retentionDaysKey = 'log.retentionDays';

  /// 保留天数合法档位白名单（日志页滚轮与此同源；非白名单历史值读侧回落）。
  static const List<int> retentionOptions = [7, 14, 30];

  /// 保留天数默认值（未配置时）。
  static const int defaultRetentionDays = 14;

  /// 当前生效的保留天数（内存值；落盘清理按文件名日期比较时使用）。
  static int get retentionDays => _retentionDays;

  /// 读持久化保留天数：未配置回落 [defaultRetentionDays]；读到非白名单值
  /// （历史脏数据 0/999 等）钳制到最近档位（等距取小档），保证页面文本
  /// 与滚轮回显自洽（评审修复轮1）。
  static int readRetentionDays(SharedPreferences prefs) {
    final v = prefs.getInt(retentionDaysKey);
    if (v == null) return defaultRetentionDays;
    if (retentionOptions.contains(v)) return v;
    var best = retentionOptions.first;
    for (final o in retentionOptions) {
      if ((o - v).abs() < (best - v).abs()) best = o;
    }
    return best;
  }

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
    Directory(dirPath).createSync(recursive: true);
    _purgeExpired();
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
      flush(); // 刷盘同步且自带吞异常，此处无需 await
    }
  }

  /// 立即把待刷队列落盘（测试与「附带日志导出」前的显式调用点）。
  ///
  /// **同步刷盘**：单线程内 drain 天然串行（无需再串 `_tail` 链），
  /// 且不依赖真实事件循环——widget 测试的 FakeAsync 时钟下 dart:io 的异步
  /// future 永不返回（日志页归档/清理用例曾挂死），同步链路两种时钟都能跑完。
  static Future<void> flush() {
    _drain();
    return Future<void>.value();
  }

  /// 当前落盘目录（未 init 为 null）。Task 10 导出「附带日志」按
  /// [dayFiles] 文件名拼完整路径用；本类仍不碰平台通道。
  static String? get dirPath => _dirPath;

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

  /// 归档子目录（logs/archive/ · 主清理/过期判定只扫顶层 `lh-*.log*`，互不误伤）。
  static String _archiveDir() => p.join(_dirPath!, 'archive');

  static final RegExp _archPattern = RegExp(
      r'^lh-arch-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})(?:_\d+)?\.zip$');

  /// 归档包保留个数上限（超出裁最旧——归档是历史包袱，不能无限涨）。
  static const int maxArchives = 10;

  /// 手动归档：把当前全部落盘日志打包成 `archive/lh-arch-<ts>.zip`。
  /// 打包成功**才**删原文件（removeSource=true 默认，归档即搬家不是复制）；
  /// 空目录返回 null（页面据此 toast「暂无可归档日志」）。
  static Future<LhArchiveResult?> archive({bool removeSource = true}) async {
    final dir = _dirPath;
    if (dir == null) return null;
    await flush();
    final names = await dayFiles(); // 新→旧
    if (names.isEmpty) return null;
    final ad = Directory(_archiveDir());
    ad.createSync(recursive: true);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stem = 'lh-arch-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    // 同秒二次归档防撞：已存在则补 `_k` 序号（名内时间戳仍以前 6 组为准）。
    var archName = '$stem.zip';
    for (var k = 2; File(p.join(ad.path, archName)).existsSync(); k++) {
      archName = '${stem}_$k.zip';
    }
    final outPath = p.join(ad.path, archName);
    var bytes = 0;
    try {
      // 全同步入包（同 _drain 口径：FakeAsync 时钟下真实异步 future 不返回）。
      // InputFileStream 边读边写、逐文件释放，内存占用不随日志总量增长。
      final encoder = ZipFileEncoder()..create(outPath);
      for (final name in names.reversed) {
        // 按旧→新入包（解包阅读顺序自然）。
        final f = File(_join(name));
        if (!f.existsSync()) continue;
        final src = InputFileStream(f.path);
        try {
          final entry = ArchiveFile.stream(name, f.lengthSync(), src)
            ..lastModTime = f.lastModifiedSync().millisecondsSinceEpoch ~/ 1000
            ..mode = f.statSync().mode;
          encoder.addArchiveFile(entry);
        } finally {
          src.closeSync();
        }
      }
      encoder.closeSync();
      bytes = File(outPath).lengthSync();
    } catch (e) {
      // 打包失败不动原文件；留诊断信息，由页面 toast 归因。
      lastError = '归档失败: $e';
      try {
        File(outPath).deleteSync();
      } catch (_) {}
      rethrow;
    }
    if (removeSource) {
      for (final name in names) {
        try {
          File(_join(name)).deleteSync();
          _sizeCache.remove(name);
        } catch (e) {
          lastError = '归档后删除原文件失败 $name: $e';
        }
      }
    }
    await _pruneArchives();
    return LhArchiveResult(name: archName, files: names.length, bytes: bytes);
  }

  /// 归档包清单（新→旧）。名内时间戳复原 created，不依赖文件系统 mtime。
  static Future<List<LhArchiveEntry>> archives() async {
    final dir = _dirPath;
    if (dir == null) return const [];
    final ad = Directory(_archiveDir());
    if (!ad.existsSync()) return const [];
    final out = <LhArchiveEntry>[];
    for (final f in ad.listSync().whereType<File>()) {
      final name = p.basename(f.path);
      final m = _archPattern.firstMatch(name);
      if (m == null) continue;
      out.add(LhArchiveEntry(
          name: name,
          bytes: f.lengthSync(),
          created: DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
              int.parse(m.group(3)!), int.parse(m.group(4)!),
              int.parse(m.group(5)!), int.parse(m.group(6)!))));
    }
    out.sort((a, b) => b.created != a.created
        ? b.created.compareTo(a.created)
        : b.name.compareTo(a.name));
    return out;
  }

  /// 读归档包全文（各成员按旧→新拼接；页面「查看/复制归档」用）。
  static Future<String> archiveText(String name) async {
    final m = _archPattern.firstMatch(name);
    if (m == null || _dirPath == null) return '';
    final file = File(p.join(_archiveDir(), name));
    if (!file.existsSync()) return '';
    final input = InputFileStream(file.path);
    try {
      final zip = ZipDecoder().decodeBuffer(input, verify: true);
      // 成员=原日志文件（isFile=true；目录条目带 '/' 后缀才排除）。
      final members = zip.files.where((e) => e.isFile).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final buf = StringBuffer();
      for (final e in members) {
        buf.write(utf8.decode(e.content as List<int>,
            allowMalformed: true));
      }
      return buf.toString();
    } finally {
      input.closeSync();
    }
  }

  /// 删除归档包（页面二次确认后调用；非法名拒绝，防路径注入）。
  static Future<void> deleteArchive(String name) async {
    if (_archPattern.firstMatch(name) == null || _dirPath == null) return;
    try {
      File(p.join(_archiveDir(), name)).deleteSync();
    } catch (e) {
      lastError = '删除归档失败 $name: $e';
    }
  }

  /// 手动清理落盘日志：flush 后删除全部 `lh-*.log*` 分卷，返回删除文件数。
  /// 归档包不在此列（清理毁历史、归档保历史，两口径分离）。
  static Future<int> purgeDisk() async {
    final dir = _dirPath;
    if (dir == null) return 0;
    await flush();
    final names = await dayFiles();
    for (final name in names) {
      try {
        File(_join(name)).deleteSync();
        _sizeCache.remove(name);
      } catch (e) {
        lastError = '清理日志失败 $name: $e';
      }
    }
    return names.length;
  }

  /// 冷启动回填：把最近落盘文件的尾部 [limit] 行读回内存环形缓冲，
  /// 让日志页跨进程重启仍能看到上一次记下的报错（真机反馈③「日志里没有内容」
  /// 的第二成因——窗口只读内存，冷启动后自然是空的）。
  ///
  /// 只读每个文件**尾部 128KB**（单文件封顶 5MB，整读会在启动路径上抖一下），
  /// 按新→旧逐文件向旧补齐；行格式 `HH:mm:ss.SSS [I|W|E] 文本` 反解失败的原样
  /// 按 info 收进缓冲（宁可少判级别，不吞行）。全程同步 I/O（FakeAsync 可测）。
  static Future<int> loadRecent({int limit = 300}) async {
    final dir = _dirPath;
    if (dir == null) return 0;
    final chunks = <List<LhLogLine>>[]; // 新→旧，每块内部按时间正序
    var got = 0;
    for (final name in await dayFiles()) {
      if (got >= limit) break;
      final f = File(_join(name));
      if (!f.existsSync()) continue;
      final size = f.lengthSync();
      if (size == 0) continue;
      final take = size < _tailReadBytes ? size : _tailReadBytes;
      late List<int> bytes;
      final raf = f.openSync();
      try {
        raf.setPositionSync(size - take);
        bytes = raf.readSync(take);
      } finally {
        raf.closeSync();
      }
      final all = utf8.decode(bytes, allowMalformed: true).split('\n');
      // 从文件中部起读时首行是残行，丢弃。
      if (take < size && all.isNotEmpty) all.removeAt(0);
      final day = _dayOf(name);
      final rows = <LhLogLine>[];
      for (final raw in all) {
        final line = _parseLine(raw, day);
        if (line != null) rows.add(line);
      }
      if (rows.isEmpty) continue;
      final need = limit - got;
      chunks.add(rows.length > need ? rows.sublist(rows.length - need) : rows);
      got += chunks.last.length;
    }
    // chunks 是新→旧，拼回时间正序（旧→新）再入缓冲。
    final ordered = <LhLogLine>[];
    for (final c in chunks.reversed) {
      ordered.addAll(c);
    }
    AppLog.seed(ordered);
    return ordered.length;
  }

  static const int _tailReadBytes = 128 * 1024;

  static final RegExp _linePattern =
      RegExp(r'^(\d{2}):(\d{2}):(\d{2})\.(\d{3}) \[([IWE])\] (.*)$');

  /// 反解一行落盘文本（日期取文件名日期）；不匹配则按 info 原样收下行。
  static LhLogLine? _parseLine(String raw, DateTime day) {
    final text = raw.trimRight();
    if (text.isEmpty) return null;
    final m = _linePattern.firstMatch(text);
    if (m == null) {
      return LhLogLine(day, LhLevel.info, text);
    }
    final t = DateTime(day.year, day.month, day.day, int.parse(m.group(1)!),
        int.parse(m.group(2)!), int.parse(m.group(3)!), int.parse(m.group(4)!));
    final level = switch (m.group(5)) {
      'W' => LhLevel.warn,
      'E' => LhLevel.error,
      _ => LhLevel.info,
    };
    return LhLogLine(t, level, m.group(6)!);
  }

  static Future<void> _pruneArchives() async {
    final list = await archives();
    for (final extra in list.skip(maxArchives)) {
      try {
        File(p.join(_archiveDir(), extra.name)).deleteSync();
      } catch (_) {}
    }
  }

  /// 收起定时器并摘钩（测试结束/退出时调用，防 pending timer 与落盘泄漏）。
  static Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    if (AppLog.onLine == write) AppLog.onLine = null;
    _drain(); // 退出前把最后一段待刷行同步落盘（原 _tail 链的收尾语义）
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

  static void _purgeExpired() {
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

  static void _drain() {
    final dir = _dirPath;
    if (dir == null || _pending.isEmpty) return;
    final batch = List<LhLogLine>.of(_pending);
    _pending.clear();
    try {
      final buffer = StringBuffer();
      var bufferBytes = 0;
      var name = '';
      var size = 0;
      void closeCurrent() {
        if (buffer.isEmpty) return;
        _append(dir, name, buffer.toString());
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
          closeCurrent();
          name = _targetFor(line.time, bytes);
          size = _sizeOf(name);
        }
        buffer.write(text);
        bufferBytes += bytes;
      }
      closeCurrent();
      lastError = null;
    } catch (e) {
      // 落盘失败：丢掉本批并留诊断信息，绝不向上抛（日志不能引发二次错误）。
      lastError = '日志落盘失败: $e';
    }
  }

  static void _append(String dir, String name, String text) {
    if (text.isEmpty) return;
    File(p.join(dir, name))
        .writeAsStringSync(text, mode: FileMode.append, flush: true);
    _sizeCache[name] = _sizeOf(name) + utf8.encode(text).length;
  }
}
