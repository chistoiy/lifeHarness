import 'dart:io';

import 'package:flutter/cupertino.dart';
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

/// Task 6：日志查看页 widget 用例（原型 index-sync.html · p-log）。
///
/// 纪律：①打开 `/log` 走本地极简 GoRouter（context.go 同款语义，不拉全 app）；
/// ②剪贴板经 MockClipboard（`flutter/platform` channel 桩）断言全量行数；
/// ③FileLogSink 一律临时目录 init + tearDown dispose，页面不碰 path_provider；
/// ④注入 350 条用 AppLog.add 三级交错循环（保证窗口尾部三级混合，
///   「警告+」档为真过滤断言——评审修复轮1）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  String? sinkDir;

  Future<void> seedPrefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() {
    AppLog.reset();
  });

  tearDown(() async {
    await FileLogSink.dispose();
    AppLog.reset();
    if (sinkDir != null) {
      try {
        Directory(sinkDir!).deleteSync(recursive: true);
      } catch (_) {
        // Windows 偶发句柄未放：临时目录残留可忽略，不让测试假红。
      }
      sinkDir = null;
    }
  });

  /// MockClipboard：记录每次 `Clipboard.setData` 的文本，返回记录表。
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

  /// 经本地路由表 `context.go('/log')` 打开日志页（守护跳转语义）。
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

  /// 按级别**交错**注入（每轮 info→warn→error 各一条），总量 info+warn+error。
  /// 交错保证环形缓冲尾部窗口内三级混合，「警告+」档才能真正验证 info 被过滤
  /// （评审修复轮1：顺序注入下窗口内无 info，过滤断言形同虚设）。
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

  /// 窗口列表内的日志行（每行以 `HH:mm:ss.SSS` 时间戳开头）。
  Finder logLines() => find.descendant(
        of: find.byKey(const ValueKey('log-list')),
        matching: find.textContaining(RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.')),
      );

  int logLineCount(WidgetTester tester) => logLines().evaluate().length;

  Text currentKeepDays(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('keep-days-current')));

  group('p-log 窗口/过滤/复制', () {
    testWidgets('交错注入350条 → 窗口=120 三级混合 · 警告+/错误真过滤 · 复制全量=缓冲300行',
        (tester) async {
      await seedPrefs();
      inject(150, 100, 100);
      // 交错注入 350 条，环形缓冲 300 丢最旧 50 条；尾部窗口（最近 120 条）
      // 内 info/warn/error 三级混合，过滤档才有非平凡断言价值。
      expect(AppLog.lines.length, 300);

      await useSurface(tester, const Size(800, 3600));
      final copied = mockClipboard(tester);
      await openLogPage(tester);

      // 渲染窗口口径的当前视图（页面同源：环形缓冲尾部 displayWindow 条）。
      final win = AppLog.lines
          .sublist(AppLog.lines.length - AppLog.displayWindow);
      LhLogLine winFirst(LhLevel lv) => win.firstWhere((l) => l.level == lv);
      LhLogLine winLast(LhLevel lv) => win.lastWhere((l) => l.level == lv);

      // ① 渲染窗口=最近 120 条，高视口下全量入树；窗口边界精确。
      final total = logLineCount(tester);
      expect(total, lessThanOrEqualTo(AppLog.displayWindow));
      expect(total, 120);
      expect(find.text(AppLog.lines[180].formatted), findsOneWidget); // 窗内首行
      expect(find.text(AppLog.lines[179].formatted), findsNothing); // 窗口外

      // ② 级别过滤（评审修复轮1）：窗口内确有 info 行，「警告+」条数必须
      // 等于窗口内 warn+error 实际条数（<120 的确定值），且树内查无 info 行。
      final warnUpExpected =
          win.where((l) => l.level != LhLevel.info).length;
      expect(win.where((l) => l.level == LhLevel.info), isNotEmpty,
          reason: '窗口内必须有 info 行，否则警告+ 档断言退化为恒真');
      expect(warnUpExpected, lessThan(120));
      await tester.tap(find.text('警告+'));
      await settle5(tester);
      expect(logLineCount(tester), warnUpExpected);
      expect(find.text(winFirst(LhLevel.info).formatted), findsNothing);
      expect(find.text(winLast(LhLevel.info).formatted), findsNothing);
      expect(find.text(winFirst(LhLevel.warn).formatted), findsOneWidget);
      expect(find.text(winLast(LhLevel.error).formatted), findsOneWidget);
      // 错误档：只剩 error，warn 也不出现。
      final errorExpected =
          win.where((l) => l.level == LhLevel.error).length;
      await tester.tap(find.text('错误'));
      await settle5(tester);
      expect(logLineCount(tester), errorExpected);
      expect(find.text(winLast(LhLevel.error).formatted), findsOneWidget);
      expect(find.text(winFirst(LhLevel.warn).formatted), findsNothing);
      expect(find.text(winFirst(LhLevel.info).formatted), findsNothing);
      await tester.tap(find.text('全部'));
      await settle5(tester);
      expect(logLineCount(tester), 120);

      // ③ 复制永远全量：钮面计数=缓冲条数，剪贴板行数=AppLog.lines.length。
      expect(find.text('复制全部（300）'), findsOneWidget);
      await tester.tap(find.text('复制全部（300）'));
      expect(await pollText(tester, '已复制 300 条全量日志 · 凭据已脱敏'), isTrue);
      await clearToasts(tester);
      expect(copied, hasLength(1));
      expect(copied.single.split('\n').length, AppLog.lines.length);
      expect(copied.single, AppLog.allText());
    });
  });

  group('保留天数滚轮', () {
    testWidgets('当前值回显 · 滑档即写 SharedPreferences 并同步内存值',
        (tester) async {
      await seedPrefs({'log.retentionDays': 30});
      await useSurface(tester, const Size(800, 3600));
      await openLogPage(tester);

      // ④ 滚轮出现且回显持久化值 30（7/14/30 三档）。
      expect(find.byKey(const ValueKey('keep-days-wheel')), findsOneWidget);
      expect(find.byType(CupertinoPicker), findsOneWidget);
      expect(currentKeepDays(tester).data, '30 天');

      // 下滑一档 30→14：回显更新 + prefs 落键 + FileLogSink 内存值同步。
      await tester.drag(
          find.byKey(const ValueKey('keep-days-wheel')), const Offset(0, 34));
      await settle5(tester);
      expect(currentKeepDays(tester).data, '14 天');
      expect(prefs.getInt('log.retentionDays'), 14);
      expect(FileLogSink.retentionDays, 14);
    });

    testWidgets('未配置时默认 14 天回显', (tester) async {
      await seedPrefs();
      await useSurface(tester, const Size(800, 3600));
      await openLogPage(tester);
      expect(currentKeepDays(tester).data, '14 天');
    });
  });

  group('底部文件日志行', () {
    testWidgets('临时目录 init+落盘后 显示 dayFiles 文件名（最近3天）',
        (tester) async {
      await seedPrefs();
      late List<String> files;
      // 真实文件 I/O 只能在 runAsync 事件循环里跑（FakeAsync 下 await 挂死）。
      await tester.runAsync(() async {
        sinkDir = Directory.systemTemp.createTempSync('lh_log_page_').path;
        await FileLogSink.init(sinkDir!);
        AppLog.add('落盘一行');
        await FileLogSink.flush();
        files = await FileLogSink.dayFiles();
      });
      expect(files, hasLength(1));

      await useSurface(tester, const Size(800, 3600));
      await openLogPage(tester);
      expect(find.text('文件日志：${files.take(3).join(' · ')}'), findsOneWidget);
    });

    testWidgets('未 init 落盘时明示未启用', (tester) async {
      await seedPrefs();
      await useSurface(tester, const Size(800, 3600));
      await openLogPage(tester);
      expect(find.text('文件日志：未启用落盘'), findsOneWidget);
    });
  });
}
