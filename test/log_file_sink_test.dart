import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Task 5：FileLogSink 按天滚动落盘 + 凭据脱敏。
///
/// 纪律（brief Step 1）：一律纯 `test()` + 系统临时目录注入，
/// 不碰 path_provider（那是生产侧 main.dart 的取目录方式）、不依赖 3s 周期定时器
/// （用例显式 `await FileLogSink.flush()`），tearDown 里 `FileLogSink.dispose()`
/// 取消定时器防 pending timer。
void main() {
  late String dir;

  /// 本地日期 → `YYYYMMDD`（与 sink 命名口径一致）。
  String tag(DateTime t) => '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}';

  String dayName(DateTime t) => 'lh-${tag(t)}.log';
  File fileAt(String name) => File('$dir${Platform.pathSeparator}$name');
  File dayFile(DateTime t) => fileAt(dayName(t));
  String readSafe(File f) => f.existsSync() ? f.readAsStringSync() : '';

  /// 轮询等待（用于「warn/error/关键行立即刷」这类不显式 flush 的断言）。
  Future<void> waitUntil(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue, reason: '等待超时：sink 未按预期落盘');
  }

  setUp(() {
    AppLog.reset();
    dir = Directory.systemTemp.createTempSync('lh_file_log_sink_').path;
  });

  tearDown(() async {
    await FileLogSink.dispose();
    AppLog.reset();
    try {
      Directory(dir).deleteSync(recursive: true);
    } catch (_) {
      // Windows 偶发句柄未放：临时目录残留可忽略，不让测试假红。
    }
  });

  test('init 后 write 三行 → flush → 当天文件存在且含 3 行、格式同 formatted',
      () async {
    await FileLogSink.init(dir);
    final now = DateTime.now();
    final lines = [
      LhLogLine(now, LhLevel.info, '普通信息行'),
      LhLogLine(now, LhLevel.warn, '警告行'),
      LhLogLine(now, LhLevel.error, '错误行'),
    ];
    for (final l in lines) {
      FileLogSink.write(l);
    }
    await FileLogSink.flush();

    final f = dayFile(now);
    expect(f.existsSync(), isTrue, reason: '应生成 ${f.path}');
    expect(f.readAsLinesSync(), lines.map((l) => l.formatted).toList());
  });

  test('retentionDays: 0 → init 时按文件名日期删过期文件，当天文件原样保留',
      () async {
    final now = DateTime.now();
    final old = fileAt('lh-20000101.log');
    final today = fileAt(dayName(now));
    old.writeAsStringSync('过期文件\n');
    today.writeAsStringSync('当天文件\n');
    expect(old.existsSync(), isTrue);

    await FileLogSink.init(dir, retentionDays: 0);

    expect(old.existsSync(), isFalse,
        reason: 'retentionDays 0 应删掉所有非当天（按文件名日期）文件');
    expect(today.existsSync(), isTrue);
    expect(today.readAsLinesSync(), ['当天文件']); // 保留期内的文件不被改写
  });

  test('maxBytes 小阈值 → 单文件封顶后滚出 .1 分卷，行不丢', () async {
    await FileLogSink.init(dir, maxBytes: 200);
    final now = DateTime.now();
    final texts = List.generate(5, (i) => 'line$i ' * 6); // 每行约 54 字节
    for (final t in texts) {
      FileLogSink.write(LhLogLine(now, LhLevel.info, t));
    }
    await FileLogSink.flush();

    final base = dayFile(now);
    final part1 = fileAt('${dayName(now)}.1');
    expect(base.existsSync(), isTrue);
    expect(part1.existsSync(), isTrue, reason: '超过 maxBytes 应滚出 .1 分卷');
    final baseLines = base.readAsLinesSync();
    expect(baseLines.length, lessThan(texts.length));
    final expected = texts
        .map((t) => LhLogLine(now, LhLevel.info, t).formatted)
        .toList();
    expect([...baseLines, ...part1.readAsLinesSync()], expected);
    // dayFiles 新→旧，分卷排在其日后。
    expect(await FileLogSink.dayFiles(), ['${dayName(now)}.1', dayName(now)]);
  });

  test('dayFiles 按天列出、新→旧', () async {
    await FileLogSink.init(dir, retentionDays: 14);
    final now = DateTime.now();
    final ago3 = now.subtract(const Duration(days: 3));
    FileLogSink.write(LhLogLine(now, LhLevel.info, '今天'));
    FileLogSink.write(LhLogLine(ago3, LhLevel.info, '三天前'));
    await FileLogSink.flush();
    expect(await FileLogSink.dayFiles(), [dayName(now), dayName(ago3)]);
  });

  test('单行字节数即超封顶（极端长堆栈）也要落盘，且不死循环滚分卷', () async {
    await FileLogSink.init(dir, maxBytes: 200);
    final now = DateTime.now();
    final huge = '长堆栈' * 300; // 约 4500 字节，远超 maxBytes
    FileLogSink.write(LhLogLine(now, LhLevel.error, huge));
    await FileLogSink.flush().timeout(const Duration(seconds: 5));

    final content = readSafe(dayFile(now));
    expect(content.trim().length, greaterThan(200));
    expect(content, contains('长堆栈'));
    // 只这一段文件，不会无限造 .1/.2……
    expect(await FileLogSink.dayFiles(), [dayName(now)]);
  });

  test('warn/error/关键行 write 后立即刷，不等周期定时器', () async {
    await FileLogSink.init(dir);
    final now = DateTime.now();
    FileLogSink.write(LhLogLine(now, LhLevel.warn, '立即刷的警告'));
    await waitUntil(() => readSafe(dayFile(now)).contains('立即刷的警告'));
    FileLogSink.write(LhLogLine(now, LhLevel.info, '关键路径行', key: true));
    await waitUntil(() => readSafe(dayFile(now)).contains('关键路径行'));
    expect(dayFile(now).readAsLinesSync().length, 2);
  });

  test('sanitize：Authorization 整值替换（大小写不敏感、冒号/等号、带认证方案前缀）',
      () {
    expect(
      sanitize('请求头 Authorization: Bearer abcDEF123456 已发出'),
      '请求头 Authorization: ***(已脱敏)*** 已发出',
    );
    expect(
      sanitize('authorization=Basic zzzzz'),
      'authorization=***(已脱敏)***',
    );
  });

  test('sanitize：X-Amz-Signature 与 credential= 命中且不吃掉后续参数', () {
    expect(
      sanitize('...&X-Amz-Signature=1a2b3c4d5e6f&other=1'),
      '...&X-Amz-Signature=***&other=1',
    );
    expect(
      sanitize('scope=20260925/cn-east-1/s3/aws4_request,'
          'credential=AKIA1234567SECRET/2026,'),
      'scope=20260925/cn-east-1/s3/aws4_request,credential=***/2026,',
    );
  });

  test('sanitize：口令/AK/SK 字段值只留末 4 位', () {
    expect(
      sanitize('passphrase: SuperSecretPass1234'),
      'passphrase: ***(…1234)***',
    );
    expect(
      sanitize('appPassword = hv9pRwZaxkK2'),
      'appPassword = ***(…xkK2)***',
    );
    expect(
      sanitize('secretKey: "wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY"'),
      'secretKey: "***(…EKEY)***"',
    );
    expect(
      sanitize('accessKey=AKIDEXAMPLE'),
      'accessKey=***(…MPLE)***',
    );
  });

  test('sanitize：普通中文/技术行不误伤', () {
    const plain = [
      '同步完成：上传 3 个文件、下载 0 个，耗时 12.4s',
      '未捕获异常: Bad state: Future already completed',
      '## call (package:lifeharness/core/sync/http_gate.dart:88)',
      'credential 字段缺省落回 WebDAV（向后兼容单测）',
      '同步历史已写入，Authorization 头不在此行',
    ];
    for (final s in plain) {
      expect(sanitize(s), s, reason: '普通行必须原样返回：$s');
    }
  });

  test('AppLog 全入口先过 sanitize 再入缓冲并回调 onLine → 落盘无凭据', () async {
    await FileLogSink.init(dir);
    AppLog.add('启动同步 Authorization: Bearer TOPSECRET9999');
    AppLog.addKey('关键路径 secretKey: ABCDWXYZ1234EKEY');
    AppLog.addStack('第一行 accessKey=AKIDXSECRETVALUE | 第二行 frame');
    await FileLogSink.flush();

    final content = readSafe(dayFile(DateTime.now()));
    expect(content, contains('Authorization: ***(已脱敏)***'));
    expect(content, contains('secretKey: ***(…'));
    expect(content, contains('accessKey=***(…'));
    expect(content, isNot(contains('TOPSECRET9999')));
    expect(content, isNot(contains('ABCDWXYZ1234EKEY')));
    expect(content, isNot(contains('AKIDXSECRETVALUE')));
    // 缓冲侧（内存查看页/一键复制）同样只存脱敏后的文本。
    expect(AppLog.allText(), isNot(contains('TOPSECRET9999')));
    expect(AppLog.lines.length, 3);
    expect(AppLog.lines[1].key, isTrue); // 关键行标记保留
  });

  test('readRetentionDays 白名单钳制：非 7/14/30 历史脏值回落最近档（等距取小），'
      '未配置默认 14，白名单值原样透传（评审修复轮1）', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Future<int> readWith(Object? value) async {
      SharedPreferences.setMockInitialValues(
          value == null ? {} : {FileLogSink.retentionDaysKey: value});
      return FileLogSink.readRetentionDays(
          await SharedPreferences.getInstance());
    }

    expect(await readWith(7), 7); // 白名单原样
    expect(await readWith(14), 14);
    expect(await readWith(30), 30);
    expect(await readWith(null), 14); // 未配置 → 默认档
    expect(await readWith(0), 7); // 脏值 0 → 最近档 7
    expect(await readWith(999), 30); // 脏值 999 → 最近档 30
    expect(await readWith(10), 7); // 10 距 7 更近（3 < 4）
    expect(await readWith(22), 14); // 22 等距（8/8）取小档 14
    expect(await readWith(-5), 7); // 负值同样钳到最近档
  });
}
