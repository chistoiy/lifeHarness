import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'package:lifeharness/features/read/domain/reader_cfg.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_appearance_sheet.dart';

/// 交互整改批四 · T14（阅读外观草稿丢弃找回）常驻用例。
///
/// 口径：面板带着**未保存草稿**离场＝给一条带「撤销」的提示条，点了原样重开；
/// 没改动、或改动又调回已生效值＝不打扰；走过「保存应用」＝不再给撤销。
/// 三条离场路径都要覆盖：取消按钮、点遮罩/下滑（Flutter **不给回调**那条）、
/// 保存（不该出条）。独立文件防 isolate 污染。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReaderCfg? saved;
  const base = ReaderCfg();

  Future<void> openSheet(WidgetTester t) async {
    await useSurface(t, const Size(420, 900));
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showReaderAppearance(
              c,
              current: base,
              unsupported: const [],
              onSave: (d, book, img) => saved = d,
            ),
            child: const Text('openAp'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('openAp'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// 行距分段的「松」档是否处于选中态（kApSegLh l=1.9，与默认 1.62 不同＝
  /// 一次可观测、可回退的草稿改动）。
  bool lhLooseOn(WidgetTester t) {
    final c = t.widget<Container>(find.descendant(
        of: find.byKey(const ValueKey('brApSeg-lh-l')),
        matching: find.byType(Container)));
    return (c.decoration as BoxDecoration).color != Colors.transparent;
  }

  Future<void> openSheetToLoose(WidgetTester t) async {
    await openSheet(t);
    expect(lhLooseOn(t), isFalse, reason: '前置：默认档不等于「松」');
    await t.tap(find.byKey(const ValueKey('brApSeg-lh-l')));
    await t.pump();
    expect(lhLooseOn(t), isTrue, reason: '草稿即时生效（分段选中态跟着变）');
  }

  Future<void> settleInOut(WidgetTester t, {int times = 8}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() => saved = null);

  testWidgets('改过→取消：出带「撤销」的提示条，撤销＝带着草稿重开面板', (t) async {
    await openSheetToLoose(t);
    await t.tap(find.byKey(const ValueKey('brApCancel')));
    await settleInOut(t);
    expect(find.text('外观改动已丢弃'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(saved, isNull, reason: '丢弃不该触发保存回调');
    await t.tap(find.text('撤销'));
    await settleInOut(t);
    expect(find.byKey(const ValueKey('sheetBrAppearance')), findsOneWidget);
    expect(lhLooseOn(t), isTrue, reason: '重开必须续用被丢弃的草稿');
    await clearToasts(t);
  });

  testWidgets('没改动→取消：不打扰（无提示条）', (t) async {
    await openSheet(t);
    await t.tap(find.byKey(const ValueKey('brApCancel')));
    await settleInOut(t);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('改了又调回已生效值→取消：不算丢弃（无提示条）', (t) async {
    await openSheetToLoose(t);
    await t.tap(find.byKey(const ValueKey('brApSeg-lh-m')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('brApCancel')));
    await settleInOut(t);
    expect(find.byType(SnackBar), findsNothing,
        reason: '草稿回到已生效值就没有可找回的东西');
  });

  testWidgets('点遮罩离场（框架不给回调那条路）同样给找回', (t) async {
    await openSheetToLoose(t);
    await t.tapAt(const Offset(6, 6)); // 遮罩＝hideSheet：绕过按钮，只有关闭后的结果
    await settleInOut(t, times: 10);
    expect(find.byKey(const ValueKey('sheetBrAppearance')), findsNothing);
    expect(find.text('外观改动已丢弃'), findsOneWidget);
    await t.tap(find.text('撤销'));
    await settleInOut(t);
    expect(lhLooseOn(t), isTrue);
    await clearToasts(t);
  });

  testWidgets('撤销重开后再取消：还能再找回一次（基准仍是页面已生效配置）',
      (t) async {
    await openSheetToLoose(t);
    await t.tap(find.byKey(const ValueKey('brApCancel')));
    await settleInOut(t);
    await t.tap(find.text('撤销'));
    await settleInOut(t);
    await t.tap(find.byKey(const ValueKey('brApCancel')));
    await settleInOut(t);
    expect(find.text('外观改动已丢弃'), findsOneWidget,
        reason: '重开时若拿草稿当判脏基准，第二次取消就静默丢了');
    await clearToasts(t);
  });

  testWidgets('保存应用＝草稿已落库，不再给撤销', (t) async {
    await openSheetToLoose(t);
    await t.tap(find.byKey(const ValueKey('brApSave')));
    await settleInOut(t);
    expect(saved?.lh, kApSegLh['l'], reason: '保存回调拿到的是草稿值');
    expect(find.text('外观改动已丢弃'), findsNothing);
    await clearToasts(t);
  });
}
