import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';
import 'package:lifeharness/features/read/data/isbn_enrich.dart';

/// 日志来源标签（真机反馈 2026-09-26：「增加一个来源，按模块或其他可以快速识别
/// 日志来源，或者筛选」）。
///
/// 口径：来源由**调用帧的代码路径**自动归类，各模块不传参也不注册；
/// 落盘行式随之变成 `HH:mm:ss.SSS [I] [来源] 文本`，旧文件（无来源段）回填时归「系统」。
void main() {
  setUp(AppLog.reset);
  tearDown(AppLog.reset);

  test('调用帧自动归类：features/read 里报的日志标「阅读」', () async {
    // 不发网络：注入一个「取到页面但没有书目节点」的假应答，走 isbn_enrich 的告警分支。
    await IsbnEnrich.lookup(
      '9787108009821',
      fetch: (_) async => '<html><title>找不到</title></html>',
    );
    final line = AppLog.lines.last;
    expect(line.src, '阅读');
    expect(line.text, contains('解析不出书目'));
    expect(line.formatted, contains('[阅读]'),
        reason: '渲染与复制都靠 formatted，来源必须带上');
  });

  test('测试文件/日志基建自身调用 → 归「系统」，不会误挂业务模块', () {
    AppLog.add('手工一行');
    expect(AppLog.lines.last.src, LhLogLine.srcSystem);
    expect(AppLog.lines.last.formatted, endsWith('[系统] 手工一行'));
  });

  test('显式 src 覆盖自动归类', () {
    AppLog.add('同步摘要', src: '同步');
    expect(AppLog.lines.last.src, '同步');
  });

  test('一条日志＝一行：换行压平成 ⏎、超长截断并标省略量', () {
    AppLog.add('容量读取失败：FormatException\n<?xml version="1.0"?>\n  <Error/>');
    final t = AppLog.lines.last.text;
    expect(t.contains('\n'), isFalse,
        reason: '整段 XML 入缓冲会把冷启动回填炸成多条 00:00:00.000 的假行');
    expect(t, contains('⏎'));

    AppLog.add('x' * 700);
    final long = AppLog.lines.last.text;
    expect(long.length, lessThan(700));
    expect(long, endsWith('…(+100)'));
  });

  group('落盘与回填兼容', () {
    late String dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('lh_src_').path;
      await FileLogSink.init(dir);
    });
    tearDown(() async {
      await FileLogSink.dispose();
      AppLog.reset();
      try {
        Directory(dir).deleteSync(recursive: true);
      } catch (_) {}
    });

    test('新行落盘带来源段，回填后来源不丢', () async {
      FileLogSink.write(
          LhLogLine(DateTime(2026, 9, 26, 8, 30, 4), LhLevel.warn, '429 退避',
              src: '同步'));
      await FileLogSink.flush();
      final raw = File(
              '$dir${Platform.pathSeparator}lh-20260926.log')
          .readAsLinesSync();
      // 落盘行与 `formatted` 同源：V1.50批3.6 起带 `MM-dd ` 段（跨启动分不清哪天）。
      expect(raw.single, '09-26 08:30:04.000 [W] [同步] 429 退避');

      await FileLogSink.dispose();
      AppLog.reset();
      await FileLogSink.init(dir);
      expect(await FileLogSink.loadRecent(), 1);
      expect(AppLog.lines.single.src, '同步');
      expect(AppLog.lines.single.level, LhLevel.warn);
      // 反解必须吃掉日期段：日期以文件名日期为准，文本只留正文
      // （回归点：`_linePattern` 漏了这段时整行会被当裸文本按 info 收进缓冲）。
      expect(AppLog.lines.single.text, '429 退避');
      expect(AppLog.lines.single.time, DateTime(2026, 9, 26, 8, 30, 4));
    });

    test('旧格式行（无来源段）照旧回填，归「系统」', () async {
      File('$dir${Platform.pathSeparator}lh-20260925.log')
          .writeAsStringSync('09:00:00.000 [I] 旧进程留下的一行\n');
      expect(await FileLogSink.loadRecent(), 1);
      final l = AppLog.lines.last;
      expect(l.text, '旧进程留下的一行');
      expect(l.src, LhLogLine.srcSystem);
    });
  });
}
