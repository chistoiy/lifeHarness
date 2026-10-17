import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

// T4（交互整改批一）·撤销提示条排他常驻回归。
// 口径：① 带「撤销」的条走 AppToast.showUndo，一律显式 persist:false（框架默认
//   persist = action != null，不点按钮就永挂——真机反馈②同款），到期自动退场；
// ② 撤销存续期内普通 AppToast.show 不顶掉它，普通提示挂起排队（只留最新一条），
//   窗口结束自动补挂；③ 点撤销即关窗并回调；④ 新撤销条接管后旧条退场不误关窗。

Widget _harness({
  required void Function(BuildContext) onUndo,
  void Function(BuildContext)? onNormal,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => Column(
            children: [
              TextButton(
                onPressed: () => onUndo(c),
                child: const Text('fire-undo'),
              ),
              if (onNormal != null)
                TextButton(
                  onPressed: () => onNormal(c),
                  child: const Text('fire-normal'),
                ),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets('撤销条到期自动退场（不永挂）', (tester) async {
    await tester.pumpWidget(_harness(
      onUndo: (c) => AppToast.showUndo(c, '已删除这条记录', ms: 400, onUndo: () {}),
    ));
    await tester.tap(find.text('fire-undo'));
    await tester.pump();
    expect(find.text('已删除这条记录'), findsOneWidget);
    await clearToasts(tester);
    expect(find.text('已删除这条记录'), findsNothing,
        reason: 'persist:false 生效：到期即退场，不点撤销也不会永挂');
  });

  testWidgets('撤销存续期内普通提示不顶掉它，窗口结束后补挂', (tester) async {
    await tester.pumpWidget(_harness(
      onUndo: (c) => AppToast.showUndo(c, '撤销条', ms: 1200, onUndo: () {}),
      onNormal: (c) => AppToast.show(c, '普通提示', ms: 400),
    ));
    await tester.tap(find.text('fire-undo'));
    await tester.pump();
    expect(find.text('撤销条'), findsOneWidget);
    await tester.tap(find.text('fire-normal'));
    await tester.pump();
    expect(find.text('撤销条'), findsOneWidget, reason: '排他：普通提示不得顶掉撤销条');
    expect(find.text('普通提示'), findsNothing);
    // 撤销窗口到期退场后，挂起的普通提示自动补挂。
    expect(await pollText(tester, '普通提示', times: 40, ms: 100), isTrue,
        reason: '窗口结束后补挂排他期间收到的普通提示');
    await clearToasts(tester);
  });

  testWidgets('点撤销：关窗＋回调，其后普通提示即时可见', (tester) async {
    var undone = 0;
    late BuildContext savedCtx;
    await tester.pumpWidget(_harness(
      onUndo: (c) {
        savedCtx = c;
        AppToast.showUndo(c, '撤销条', ms: 4000, onUndo: () => undone++);
      },
    ));
    await tester.tap(find.text('fire-undo'));
    await tester.pump();
    await tester.pumpAndSettle(); // 等入场动画落定，撤销钮进可点区
    await tester.tap(find.text('撤销'));
    await clearToasts(tester);
    expect(undone, 1);
    // 窗口已关：普通提示不再被挂起。
    AppToast.show(savedCtx, '普通提示', ms: 400);
    await tester.pump();
    expect(find.text('普通提示'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('新撤销条接管：旧条退场不误关窗，末条退场后窗口必关', (tester) async {
    await tester.pumpWidget(_harness(
      onUndo: (c) {
        AppToast.showUndo(c, '撤销条A', ms: 4000, onUndo: () {});
        AppToast.showUndo(c, '撤销条B', ms: 500, onUndo: () {});
      },
      onNormal: (c) => AppToast.show(c, '普通提示', ms: 400),
    ));
    await tester.tap(find.text('fire-undo'));
    await tester.pump();
    expect(find.text('撤销条A'), findsNothing);
    expect(find.text('撤销条B'), findsOneWidget);
    // A 的退场回调不得把 B 的窗口误关：窗口期内普通提示仍挂起。
    await tester.tap(find.text('fire-normal'));
    await tester.pump();
    expect(find.text('普通提示'), findsNothing);
    // B 到期后窗口关闭并补挂普通提示。
    expect(await pollText(tester, '普通提示', times: 30, ms: 100), isTrue);
    await clearToasts(tester);
  });

  test('守护：全 lib 仅 AppToast 原语允许手挂 SnackBarAction', () {
    // 带 action 的裸 SnackBar 即永挂隐患（框架默认 persist = action != null）。
    // 撤销条一律经 AppToast.showUndo / showUndoWith 收口。
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('shared${Platform.pathSeparator}widgets${Platform.pathSeparator}ui_kit.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('SnackBarAction(')) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: '撤销条必须走 AppToast.showUndo（ui_kit.dart 是唯一手挂点）：$offenders');
  });
}
