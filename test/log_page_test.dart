import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/log_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// V1.50 批3.6 日志页 widget 用例（原型 p-logs · V4 风格 + V5 齿轮弹层）。
///
/// 布局变化：级别/来源/关键词/字号/保留/归档全部收进 AppBar 齿轮 → 底部弹层
/// （分段 Tab 筛选 | 配置）；页面主体只剩页头信息条 + 通底 `.logline` 列表。
/// 因此过滤/配置类断言需先 [openSheet] 进弹层，再按 Tab 定位控件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  String? sinkDir;

  Future<void> seedPrefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() => AppLog.reset());

  tearDown(() async {
    await FileLogSink.dispose();
    AppLog.reset();
    if (sinkDir != null) {
      try {
        Directory(sinkDir!).deleteSync(recursive: true);
      } catch (_) {}
      sinkDir = null;
    }
  });

  List<String> mockClipboard(WidgetTester tester) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return copied;
  }

  Future<void> openLogPage(WidgetTester tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.go('/log'),
                child: const Text('goto-log'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(path: '/log', builder: (_, _) => const LogPage()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    await tester.tap(find.text('goto-log'));
    await settle5(tester);
  }

  void inject(int info, int warn, int error) {
    var i = 0, w = 0, e = 0;
    while (i < info || w < warn || e < error) {
      if (i < info) AppLog.add('信息行$i', level: LhLevel.info);
      if (w < warn) AppLog.add('警告行$w', level: LhLevel.warn);
      if (e < error) AppLog.add('错误行$e', level: LhLevel.error);
      i++;
      w++;
      e++;
    }
  }

  /// 通底日志窗内的行（每行含一个以 `MM-dd HH:mm:ss.SSS` 开头的时间戳 Text）。
  Finder logLines() => find.descendant(
        of: find.byKey(const ValueKey('log-list')),
        matching: find.textContaining(
            RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.')),
      );

  int logLineCount(WidgetTester tester) => logLines().evaluate().length;

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('log-settings-gear')));
    await settle5(tester);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    // 点弹层上方 barrier 空白（barrierDismissible 默认开）关闭底部弹层。
    await tester.tapAt(const Offset(450, 4));
    await settle5(tester);
  }

  Future<void> toConfigTab(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('seg-配置')));
    await settle5(tester);
  }

  group('p-log 窗口/过滤/复制', () {
    testWidgets('窗口=120 · 警告+/错误真过滤（弹层内） · 复制全量=缓冲300行',
        (tester) async {
      await seedPrefs();
      inject(150, 100, 100);
      expect(AppLog.lines.length, 300);

      await useSurface(tester, const Size(800, 9000));
      final copied = mockClipboard(tester);
      await openLogPage(tester);

      final win = AppLog.lines.sublist(AppLog.lines.length - AppLog.displayWindow);
      LhLogLine winFirst(LhLevel lv) => win.firstWhere((l) => l.level == lv);
      LhLogLine winLast(LhLevel lv) => win.lastWhere((l) => l.level == lv);

      // ① 通底窗口=最近 120 条（高视口全量入树）。
      expect(logLineCount(tester), 120);
      expect(find.text(win.first.text), findsOneWidget);

      // ② 级别过滤在齿轮弹层「筛选」Tab。
      final warnUpExpected = win.where((l) => l.level != LhLevel.info).length;
      final errorExpected = win.where((l) => l.level == LhLevel.error).length;
      expect(win.where((l) => l.level == LhLevel.info), isNotEmpty);

      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('seg-警告+')));
      await settle5(tester);
      await closeSheet(tester);
      expect(logLineCount(tester), warnUpExpected);
      expect(find.text(winFirst(LhLevel.info).text), findsNothing);
      expect(find.text(winLast(LhLevel.warn).text), findsOneWidget);

      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('seg-错误')));
      await settle5(tester);
      await closeSheet(tester);
      expect(logLineCount(tester), errorExpected);
      expect(find.text(winLast(LhLevel.error).text), findsOneWidget);
      expect(find.text(winFirst(LhLevel.warn).text), findsNothing);

      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('seg-全部')));
      await settle5(tester);
      await closeSheet(tester);
      expect(logLineCount(tester), 120);

      // ③ 复制永远全量（页头「复制全部」钮）。
      await tester.tap(find.byKey(const ValueKey('log-copy-all')));
      expect(await pollText(tester, '已复制 300 条全量日志 · 凭据已脱敏'), isTrue);
      await clearToasts(tester);
      expect(copied, hasLength(1));
      expect(copied.single.split('\n').length, AppLog.lines.length);
      expect(copied.single, AppLog.allText());
    });

    testWidgets('长按一行 = 复制该行（formatted 整行）', (tester) async {
      await seedPrefs();
      AppLog.add('PROPFIND /sync → 207', src: '同步');
      await useSurface(tester, const Size(800, 2400));
      final copied = mockClipboard(tester);
      await openLogPage(tester);

      await tester.longPress(find.text('PROPFIND /sync → 207'));
      await settle5(tester);
      expect(await pollText(tester, '已复制该行日志'), isTrue);
      expect(copied.single, contains('[同步]'));
      expect(copied.single, contains('PROPFIND /sync → 207'));
      await clearToasts(tester);
      await settleLogTimer(tester);
    });
  });

  group('配置弹层：字号 / 保留（横滑 HPick）', () {
    testWidgets('字号回显默认 11 · 点选 13 落 prefs 并即时应用', (tester) async {
      await seedPrefs();
      await useSurface(tester, const Size(900, 2400));
      await openLogPage(tester);
      await openSheet(tester);
      await toConfigTab(tester);

      expect(find.byKey(const ValueKey('log-font-pick')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('log-font-current'))).data,
          '11px');

      await tester.tap(find.byKey(const ValueKey('hopt-13')));
      await settle5(tester);
      expect(prefs.getInt('log.fontSize'), 13);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('log-font-current'))).data,
          '13px');
      await settleLogTimer(tester);
    });

    testWidgets('保留回显持久值 · 点选 14 天写 prefs + 同步 FileLogSink',
        (tester) async {
      await seedPrefs({'log.retentionDays': 30});
      await useSurface(tester, const Size(900, 2400));
      await openLogPage(tester);
      await openSheet(tester);
      await toConfigTab(tester);

      expect(find.byKey(const ValueKey('keep-days-wheel')), findsOneWidget);
      // FileLogSink 内存值随 seedPrefs+页面读侧钳制为 30。
      expect(FileLogSink.readRetentionDays(prefs), 30);

      await tester.tap(find.byKey(const ValueKey('hopt-14 天')));
      await settle5(tester);
      expect(prefs.getInt('log.retentionDays'), 14);
      expect(FileLogSink.retentionDays, 14);
      await settleLogTimer(tester);
    });
  });

  group('文件日志行（弹层配置区）', () {
    testWidgets('落盘后弹层显示 dayFiles 文件名', (tester) async {
      await seedPrefs();
      late List<String> files;
      await tester.runAsync(() async {
        sinkDir = Directory.systemTemp.createTempSync('lh_log_page_').path;
        await FileLogSink.init(sinkDir!);
        AppLog.add('落盘一行');
        await FileLogSink.flush();
        files = await FileLogSink.dayFiles();
      });
      expect(files, hasLength(1));

      await useSurface(tester, const Size(900, 2400));
      await openLogPage(tester);
      await openSheet(tester);
      await toConfigTab(tester);
      expect(find.text('文件日志：${files.take(3).join(' · ')}'), findsOneWidget);
    });

    testWidgets('未 init 落盘时明示未启用', (tester) async {
      await seedPrefs();
      await useSurface(tester, const Size(900, 2400));
      await openLogPage(tester);
      await openSheet(tester);
      await toConfigTab(tester);
      expect(find.text('文件日志：未启用落盘'), findsOneWidget);
    });
  });
}
