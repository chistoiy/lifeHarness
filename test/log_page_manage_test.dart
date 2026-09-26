import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/log_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// 日志管理增强包 UI（归档钮/清理钮/二次确认/归档行查看/复制/删除）。
///
/// 引擎（[FileLogSink]）已改**同步文件 I/O**，fake 时钟下整条链一 pump 即落地，
/// 因此这里不需要 runAsync 交错；仅临时目录创建仍在真实区做一次（无害）。
/// 种子行经 [AppLog.add] 进环（页面窗口列表读内存缓冲，不读盘），
/// sink 由 AppLog 挂点转发落盘——测的就是生产链路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? sinkDir;

  setUp(() {
    AppLog.reset();
    SharedPreferences.setMockInitialValues({});
  });

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

  /// 临时目录 + init sink + 种 lines 行（内存缓冲与落盘同时有内容）。
  /// 调用方必须放在 runAsync 内。
  Future<void> seedDisk(WidgetTester tester, int lines) async {
    final dir =
        Directory.systemTemp.createTempSync('lh_log_page_manage_').path;
    sinkDir = dir;
    await FileLogSink.init(dir);
    for (var i = 0; i < lines; i++) {
      AppLog.add('落盘行$i', level: LhLevel.error);
    }
    await FileLogSink.flush();
  }

  Future<void> openPage(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    await useSurface(tester, const Size(800, 2200));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LogPage())));
    await settle5(tester);
  }

  /// 点动作钮 → 确认弹层落位（纯 UI）。
  Future<void> openConfirm(WidgetTester tester, Key btn) async {
    await tester.tap(find.byKey(btn));
    await settle5(tester);
  }

  /// 点「确定」→ 整条链跑完（引擎已同步刷盘：fake 时钟直接 settle 即可，
  /// 无需 runAsync 交错——这正是 sink 改同步 I/O 的目的）。
  Future<void> confirmAndDrain(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('log-confirm-ok')));
    await settle5(tester);
  }

  testWidgets('归档/清理钮存在；无档时归档区不显', (tester) async {
    await tester.runAsync(() => seedDisk(tester, 2));
    await openPage(tester);
    expect(find.byKey(const ValueKey('log-archive-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-clear-btn')), findsOneWidget);
    expect(find.text('归档包'), findsNothing);
    expect(find.textContaining('落盘行0'), findsWidgets);
  });

  testWidgets('确认弹层可取消（取消=不清理，落盘与缓冲仍在）', (tester) async {
    await tester.runAsync(() => seedDisk(tester, 3));
    await openPage(tester);
    await openConfirm(tester, const ValueKey('log-clear-btn'));
    expect(find.text('确认清理'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settle5(tester);
    expect(find.text('确认清理'), findsNothing);
    expect(find.textContaining('落盘行0'), findsWidgets);
    final days = await tester.runAsync(FileLogSink.dayFiles);
    expect(days, isNotEmpty, reason: '取消不应清理');
  });

  testWidgets('归档流：确定→打包删原→归档行出现', (tester) async {
    await tester.runAsync(() => seedDisk(tester, 2));
    await openPage(tester);

    await openConfirm(tester, const ValueKey('log-archive-btn'));
    expect(find.text('确认归档'), findsOneWidget);
    await confirmAndDrain(tester);

    expect(find.text('归档包'), findsOneWidget);
    final list = await tester.runAsync(FileLogSink.archives);
    expect(list, hasLength(1));
    expect(find.byKey(ValueKey('log-arch-view-${list!.single.name}')),
        findsOneWidget);
    final days = await tester.runAsync(FileLogSink.dayFiles);
    expect(days, isEmpty, reason: '归档即搬家：原落盘文件删除');
    expect(find.textContaining('已归档'), findsWidgets);
  });

  testWidgets('清理流：确定→落盘删净+缓冲清空 toast', (tester) async {
    await tester.runAsync(() => seedDisk(tester, 3));
    await openPage(tester);
    expect(find.textContaining('落盘行0'), findsWidgets);

    await openConfirm(tester, const ValueKey('log-clear-btn'));
    await confirmAndDrain(tester);

    expect(find.textContaining('已清理'), findsWidgets);
    expect(find.textContaining('落盘行'), findsNothing);
    final days = await tester.runAsync(FileLogSink.dayFiles);
    expect(days, isEmpty);
  });

  testWidgets('预生成归档包：页面归档行渲染 + 解包内容可读可复制', (tester) async {
    await tester.runAsync(() async {
      await seedDisk(tester, 2);
      await FileLogSink.archive();
    });
    final list = await tester.runAsync(FileLogSink.archives);
    final name = list!.single.name;

    await openPage(tester);
    expect(find.text('归档包'), findsOneWidget);
    expect(find.byKey(ValueKey('log-arch-view-$name')), findsOneWidget);

    // 解包读全文属真实 I/O，在 runAsync 内核引擎可用性。
    final content = await tester.runAsync(() => FileLogSink.archiveText(name));
    expect(content, contains('落盘行0'));
    expect(content, contains('落盘行1'));
  });

  testWidgets('归档查看弹层：打开可读 + 复制钮入剪贴板', (tester) async {
    final copied = mockClipboard(tester);
    await tester.runAsync(() async {
      await seedDisk(tester, 2);
      await FileLogSink.archive();
    });
    final name = (await tester.runAsync(FileLogSink.archives))!.single.name;
    await openPage(tester);

    await tester.tap(find.byKey(ValueKey('log-arch-view-$name')));
    await settle5(tester);
    // 归档为空则说明解包链路断了；弹层标题即包名。
    expect(find.text('（归档为空）'), findsNothing);
    expect(find.textContaining('关闭'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('log-arch-copy-$name')));
    await settle5(tester);
    expect(copied.single, contains('落盘行1'));
  });

  testWidgets('删除归档流：二次确认后行消失', (tester) async {
    await tester.runAsync(() async {
      await seedDisk(tester, 1);
      await FileLogSink.archive();
    });
    final name = (await tester.runAsync(FileLogSink.archives))!.single.name;
    await openPage(tester);
    expect(find.byKey(ValueKey('log-arch-del-$name')), findsOneWidget);

    await openConfirm(tester, ValueKey('log-arch-del-$name'));
    expect(find.text('删除归档'), findsOneWidget);
    await confirmAndDrain(tester);

    expect(find.text('归档包'), findsNothing);
    final after = await tester.runAsync(FileLogSink.archives);
    expect(after, isEmpty);
  });
}

/// 剪贴板桩：记录每次 setData 文本（同 log_page_test 口径）。
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
