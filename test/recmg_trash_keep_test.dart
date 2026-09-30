import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/recmg_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// V1.57 E 批 · 「记录管理 · 通用 · 回收站自动清理」由占位改真选择器。
/// 档位是垃圾箱屏与待办页入口行文案的**唯一来源**，故这里同时钉：
/// 选后落盘（重启还在）+ 即时回显 + 「不清理」档独立文案。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget app() => ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: RecmgSettingsPage()),
      );

  /// 通用行在列表尾部：懒构建，先拖到出现再确保可见（同 widget_test 记录管理用例手法）。
  Future<void> open(WidgetTester tester, [Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(app());
    await settle5(tester);
    final row = find.byKey(const ValueKey('trash-days'));
    for (var i = 0; i < 12 && row.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(row);
    await settle5(tester);
    expect(row, findsOneWidget, reason: '未滚到「回收站自动清理」行');
  }

  testWidgets('默认档＝30 天（未落盘时读默认，不显示空值）', (tester) async {
    await open(tester);
    expect(find.text('回收站自动清理'), findsOneWidget);
    expect(find.text('30 天'), findsOneWidget);
    expect(prefs.getInt('lh.trash_keep_days'), isNull);
    await clearToasts(tester);
  });

  testWidgets('点行→半屏四档 → 选 7 天：回显＋提示条＋真实落盘', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('trash-days')));
    await settle5(tester);

    // 档位表：30/7/90 天 · 不清理（原型 #recTrashOpt 同源）
    for (final lab in ['7 天', '90 天', '不清理']) {
      expect(find.text(lab), findsOneWidget, reason: '缺档：$lab');
    }
    await tester.tap(find.text('7 天'));
    await settle5(tester);

    expect(find.textContaining('回收站内容保留 7 天后自动彻底删除'), findsOneWidget);
    expect(find.text('7 天'), findsOneWidget, reason: '行尾即时回显');
    expect(prefs.getInt('lh.trash_keep_days'), 7,
        reason: '必须落盘（只改 Provider 态＝重启回 30 天，属假承诺）');
    await clearToasts(tester);
  });

  testWidgets('「不清理」档：行尾显「不清理」＋文案改口＋落盘 0', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('trash-days')));
    await settle5(tester);
    await tester.tap(find.text('不清理'));
    await settle5(tester);

    expect(find.textContaining('回收站不再自动清理'), findsOneWidget);
    expect(find.text('不清理'), findsOneWidget);
    expect(prefs.getInt('lh.trash_keep_days'), 0);
    await clearToasts(tester);
  });

  testWidgets('已落盘档位冷重载后仍在（读盘而非默认值吞掉）', (tester) async {
    await open(tester, {'lh.trash_keep_days': 90});
    expect(find.text('90 天'), findsOneWidget);
    await clearToasts(tester);
  });
}
