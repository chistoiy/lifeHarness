import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/shared/widgets/confirm_dialog.dart';

/// LH-S31 破坏确认的触觉锚（2026-10-11 手感批 · 工单 §1/§⚙）。
/// 独立文件：纯 shared 层最小 pump，不碰 app 根（全 app pump 拆分铁律）。
/// 判法＝mock `SystemChannels.platform` 收 `HapticFeedback.vibrate` 的 pattern 参数，
/// 断言「按 destructive＝一次 MediumImpact」「按取消＝零震」。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<String> captureHaptics() {
    final patterns = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') patterns.add('${call.arguments}');
      return null;
    });
    return patterns;
  }

  Future<void> openConfirm(WidgetTester t, void Function(bool?) done) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
              onPressed: () async => done(await lhConfirm(ctx, '删除这条记录？')),
              child: const Text('go'),
            )),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget);
  }

  testWidgets('按 destructive 确认钮＝一记 MediumImpact 且结果为真', (t) async {
    final patterns = captureHaptics();
    bool? result;
    await openConfirm(t, (v) => result = v);
    await t.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await t.pumpAndSettle();
    expect(result, isTrue);
    expect(patterns, ['HapticFeedbackType.mediumImpact'],
        reason: '不可逆动作落定必须有触觉（手感批四锚之一；参数名取当前框架枚举序列化实读值）');
  });

  testWidgets('按取消＝零震且结果为假', (t) async {
    final patterns = captureHaptics();
    bool? result;
    await openConfirm(t, (v) => result = v);
    await t.tap(find.byKey(const ValueKey('d-confirm-cancel')));
    await t.pumpAndSettle();
    expect(result, isFalse);
    expect(patterns, isEmpty, reason: '取消不是不可逆动作，不许震（防触觉滥用）');
  });
}
