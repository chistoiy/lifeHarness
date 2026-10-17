import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';

/// 日志跨重启可见（真机反馈③「日志里没有内容」第二成因）：
/// 日志页窗口读的是内存环形缓冲，冷启动后自然是空的——`loadRecent` 把上次
/// 进程落盘的尾部行回填进缓冲，且**绝不重复写盘**（seed 不回调 sink 挂点）。
///
/// 纪律同 log_manage_test：纯 test() + 临时目录同步创建 + 显式 flush；
/// 引擎全同步 I/O，无需 runAsync。
void main() {
  late String dir;
  late DateTime t0;

  setUp(() {
    AppLog.reset();
    dir = Directory.systemTemp.createTempSync('lh_log_seed_').path;
    t0 = DateTime.now();
  });

  tearDown(() async {
    await FileLogSink.dispose();
    AppLog.reset();
    try {
      Directory(dir).deleteSync(recursive: true);
    } catch (_) {
      // Windows 句柄偶发未放：残留可忽略。
    }
  });

  Future<List<String>> diskLines() async {
    final names = await FileLogSink.dayFiles();
    return File('$dir${Platform.pathSeparator}${names.first}')
        .readAsLinesSync();
  }

  group('loadRecent 冷启动回填', () {
    test('未 init：返回 0 且不炸', () async {
      expect(await FileLogSink.loadRecent(), 0);
    });

    test('三级别行回填：文本/级别复原，日期按文件名', () async {
      await FileLogSink.init(dir);
      FileLogSink.write(LhLogLine(t0, LhLevel.info, '普通一行'));
      FileLogSink.write(LhLogLine(t0, LhLevel.warn, '警告一行'));
      FileLogSink.write(LhLogLine(t0, LhLevel.error, '错误一行'));
      await FileLogSink.flush();
      await FileLogSink.dispose();
      AppLog.reset();

      await FileLogSink.init(dir);
      expect(AppLog.lines, isEmpty, reason: 'init 本身不动内存缓冲');
      final n = await FileLogSink.loadRecent();
      expect(n, 3);
      expect(AppLog.lines.map((l) => l.text),
          ['普通一行', '警告一行', '错误一行']);
      expect(AppLog.lines.map((l) => l.level),
          [LhLevel.info, LhLevel.warn, LhLevel.error]);
      final d = DateTime(t0.year, t0.month, t0.day);
      for (final l in AppLog.lines) {
        expect(DateTime(l.time.year, l.time.month, l.time.day), d);
      }
    });

    test('回填不再写盘：flush 后文件行数不变', () async {
      await FileLogSink.init(dir);
      for (var i = 0; i < 5; i++) {
        FileLogSink.write(LhLogLine(t0, LhLevel.error, '行$i'));
      }
      await FileLogSink.flush();
      final before = await diskLines();
      await FileLogSink.dispose();
      AppLog.reset();

      await FileLogSink.init(dir);
      await FileLogSink.loadRecent();
      await FileLogSink.flush();
      expect(await diskLines(), hasLength(before.length),
          reason: 'seed 若回调 sink 挂点就会把历史行重复落盘');
    });

    test('超上限取尾部且保持时间正序', () async {
      await FileLogSink.init(dir);
      for (var i = 0; i < 500; i++) {
        FileLogSink.write(LhLogLine(t0, LhLevel.info, 'padded行$i'));
      }
      await FileLogSink.flush();
      await FileLogSink.dispose();
      AppLog.reset();

      await FileLogSink.init(dir);
      final n = await FileLogSink.loadRecent(limit: 300);
      expect(n, 300);
      expect(AppLog.lines.first.text, 'padded行200');
      expect(AppLog.lines.last.text, 'padded行499');
    });

    test('非本格式行不吞：按 info 原样收进缓冲', () async {
      await FileLogSink.init(dir);
      FileLogSink.write(LhLogLine(t0, LhLevel.error, '规整行'));
      await FileLogSink.flush();
      final names = await FileLogSink.dayFiles();
      File('$dir${Platform.pathSeparator}${names.first}')
          .writeAsStringSync('裸的一行没有前缀\n', mode: FileMode.append);
      await FileLogSink.dispose();
      AppLog.reset();

      await FileLogSink.init(dir);
      await FileLogSink.loadRecent();
      expect(AppLog.lines.map((l) => l.text), ['规整行', '裸的一行没有前缀']);
      expect(AppLog.lines.last.level, LhLevel.info);
    });

    test('回填行排在本次新记录之前（时间轴不倒置）', () async {
      await FileLogSink.init(dir);
      FileLogSink.write(LhLogLine(t0, LhLevel.error, '上次进程的错'));
      await FileLogSink.flush();
      await FileLogSink.dispose();
      AppLog.reset();

      await FileLogSink.init(dir);
      await FileLogSink.loadRecent();
      AppLog.add('本次进程的新行', level: LhLevel.warn);
      expect(AppLog.lines.first.text, '上次进程的错');
      expect(AppLog.lines.last.text, '本次进程的新行');
      expect(AppLog.lines.last.level, LhLevel.warn);
    });
  });
}
