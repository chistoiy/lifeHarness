import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/log_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 真机反馈轮4 批B④ 常驻回归（独立文件防 isolate 污染）：
/// 日志页点行勾选多条复制；长按单条复制不破坏；勾选态可辨、可取消。
/// 剪贴板断言走 mock 通道捕获（FakeAsync 下 await Clipboard.getData 永挂·既有坑）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    AppLog.reset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await FileLogSink.dispose();
    AppLog.reset();
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

  Future<void> pumpLog(WidgetTester t) async {
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: LogPage())));
    await settle5(t);
  }

  testWidgets('点行勾选→浮条计数→复制已选=两条一行', (t) async {
    final copied = mockClipboard(t);
    AppLog.add('第一行内容');
    AppLog.add('第二行内容');
    AppLog.add('第三行内容');
    await pumpLog(t);

    await t.tap(find.textContaining('第一行内容'));
    await t.pump();
    await t.tap(find.textContaining('第三行内容'));
    await t.pump();
    expect(find.text('已选 2 条'), findsOne);

    await t.tap(find.byKey(const ValueKey('log-sel-copy')));
    await settle5(t);
    expect(copied, hasLength(1));
    final lines = copied.single.split('\n');
    expect(lines, hasLength(2));
    expect(lines.any((l) => l.contains('第一行内容')), isTrue);
    expect(lines.any((l) => l.contains('第三行内容')), isTrue);
    await clearToasts(t);
    await drainLogTimer(t);
  });

  testWidgets('再点同一行取消勾选；「取消」清空并收起浮条', (t) async {
    AppLog.add('甲行');
    AppLog.add('乙行');
    await pumpLog(t);

    await t.tap(find.textContaining('甲行'));
    await t.pump();
    await t.tap(find.textContaining('乙行'));
    await t.pump();
    expect(find.text('已选 2 条'), findsOne);

    await t.tap(find.textContaining('乙行')); // 取消该行
    await t.pump();
    expect(find.text('已选 1 条'), findsOne);

    await t.tap(find.byKey(const ValueKey('log-sel-clear')));
    await t.pump();
    expect(find.byKey(const ValueKey('log-sel-count')), findsNothing);
    await drainLogTimer(t);
  });

  testWidgets('长按一行仍复制该行一条（旧交互不破坏）', (t) async {
    final copied = mockClipboard(t);
    AppLog.add('唯一一行');
    await pumpLog(t);
    await t.longPress(find.textContaining('唯一一行'));
    await settle5(t);
    expect(copied, hasLength(1));
    expect(copied.single.split('\n'), hasLength(1));
    expect(copied.single, contains('唯一一行'));
    await clearToasts(t);
    await drainLogTimer(t);
  });
}
