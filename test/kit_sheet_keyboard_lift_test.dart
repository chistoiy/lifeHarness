import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/care/presentation/care_kit.dart';
import 'package:lifeharness/features/days/presentation/days_kit.dart';
import 'package:lifeharness/features/goals/presentation/goals_kit.dart';
import 'package:lifeharness/features/items/presentation/items_kit.dart';

import 'helpers.dart';

// T1（交互整改批一）·四模块统一弹层容器键盘抬升常驻回归。
// Flutter 3.38 起 showModalBottomSheet 不再随软键盘自动抬升，
// showCareSheet/showGoalsSheet/showItemsSheet/showDaysSheet 四容器必须自行并入
// viewInsets.bottom；判据＝键盘升起后输入框与保存钮的矩形下沿不越过键盘顶线。
// 正例参照 ledger_kit.showLSheet 与 todo_add_sheet。

/// 弹层内容：输入框 + 保存钮（真页表单的最小同构）。
class _T1Form extends StatelessWidget {
  const _T1Form();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          TextField(
            key: ValueKey('t1-input'),
            decoration: InputDecoration(hintText: '名称'),
          ),
          SizedBox(height: 8),
          SizedBox(
            key: ValueKey('t1-save'),
            height: 40,
            child: ColoredBox(
              color: Colors.indigo,
              child: Center(child: Text('保存', style: TextStyle(color: Colors.white))),
            ),
          ),
        ],
      );
}

/// 宿主页：点「open」即弹对应容器。
Future<void> _hostAndOpen(WidgetTester tester, Future<void> Function(BuildContext) open) async {
  await useSurface(tester, const Size(360, 560));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (c) => Align(
          alignment: Alignment.topCenter,
          child: ElevatedButton(
            onPressed: () => open(c),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// 键盘升起（viewInsets 为物理像素，按 dpr 折成逻辑）后断言两钮不被键盘线盖住。
void _expectAboveKeyboard(WidgetTester tester, double kbBottomLogical) {
  for (final key in const ['t1-input', 't1-save']) {
    final r = tester.getRect(find.byKey(ValueKey(key)));
    expect(
      r.bottom,
      lessThanOrEqualTo(kbBottomLogical + 0.5),
      reason: '$key 应被键盘抬升托在键盘顶线之上',
    );
    expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
  }
}

void main() {
  const insets = FakeViewPadding(bottom: 360);

  testWidgets('showCareSheet：键盘升起后输入框与保存钮全程在键盘上方', (tester) async {
    await _hostAndOpen(
        tester, (c) async => showCareSheet<void>(c, builder: (_) => const _T1Form()));
    tester.view.viewInsets = insets;
    await tester.pumpAndSettle();
    _expectAboveKeyboard(tester, 560 - insets.bottom / tester.view.devicePixelRatio);
    tester.view.viewInsets = FakeViewPadding.zero;
    await settleLogTimer(tester);
  });

  testWidgets('showGoalsSheet：键盘升起后输入框与保存钮全程在键盘上方', (tester) async {
    await _hostAndOpen(tester,
        (c) async => showGoalsSheet<void>(c, title: '目标', builder: (_) => const _T1Form()));
    tester.view.viewInsets = insets;
    await tester.pumpAndSettle();
    _expectAboveKeyboard(tester, 560 - insets.bottom / tester.view.devicePixelRatio);
    tester.view.viewInsets = FakeViewPadding.zero;
    await settleLogTimer(tester);
  });

  testWidgets('showItemsSheet：键盘升起后输入框与保存钮全程在键盘上方', (tester) async {
    await _hostAndOpen(tester,
        (c) async => showItemsSheet<void>(c, title: '物品', builder: (_) => const _T1Form()));
    tester.view.viewInsets = insets;
    await tester.pumpAndSettle();
    _expectAboveKeyboard(tester, 560 - insets.bottom / tester.view.devicePixelRatio);
    tester.view.viewInsets = FakeViewPadding.zero;
    await settleLogTimer(tester);
  });

  testWidgets('showDaysSheet：键盘升起后输入框与保存钮全程在键盘上方', (tester) async {
    await _hostAndOpen(tester,
        (c) async => showDaysSheet<void>(c, title: '日子', builder: (_) => const _T1Form()));
    tester.view.viewInsets = insets;
    await tester.pumpAndSettle();
    _expectAboveKeyboard(tester, 560 - insets.bottom / tester.view.devicePixelRatio);
    tester.view.viewInsets = FakeViewPadding.zero;
    await settleLogTimer(tester);
  });
}
