import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';

import 'helpers.dart';

/// LHWheel 共享数字滚轮（LH-K39）常驻用例。
/// 纯 shared 层组件，不碰 app 根/路由，自建最小 wrap（helpers 无封装助手）。
Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    );

void main() {
  testWidgets('选中项中心与导引线中心偏差 = 0', (tester) async {
    int? got;
    await tester.pumpWidget(wrap(LHWheel(
        labels: ['—', '1 杯', '2 杯', '3 杯'], initialIndex: 2,
        onSelect: (i) => got = i, keyPrefix: 'w')));
    await settle5(tester);
    expect(got, isNull); // 首帧自动回调不外泄（未选中即未上报）
    final sel = tester.getCenter(find.byKey(const ValueKey('witem2')));
    final guide = tester.getCenter(find.byKey(const ValueKey('wheel-guide-line')));
    expect((sel.dy - guide.dy).abs(), lessThan(0.5));
  });

  testWidgets('容器高度改 160 后仍居中（回归既定坑：改高后导引线偏）', (tester) async {
    int? got;
    await tester.pumpWidget(wrap(LHWheel(
        labels: ['—', '1 杯', '2 杯', '3 杯'], initialIndex: 2,
        onSelect: (i) => got = i, keyPrefix: 'w', height: 160)));
    await settle5(tester);
    expect(got, isNull);
    final sel = tester.getCenter(find.byKey(const ValueKey('witem2')));
    final guide = tester.getCenter(find.byKey(const ValueKey('wheel-guide-line')));
    expect((sel.dy - guide.dy).abs(), lessThan(0.5));
    // 等价式双保险：中心即容器几何中心 160/2=80（相对 wheel 顶），
    // wheel 顶 = (600 视口高 - 160)/2 = 220。
    expect(sel.dy, closeTo(220 + 80, 0.5));
  });

  testWidgets('首项「—」＝未记录语义，读回 null 而非 0', (tester) async {
    final labels = ['—', '1 杯', '2 杯', '3 杯'];
    int? got;
    await tester.pumpWidget(wrap(LHWheel(
        labels: ['—', '1 杯', '2 杯', '3 杯'], initialIndex: 2,
        onSelect: (i) => got = i, keyPrefix: 'w')));
    await settle5(tester);
    // 从「2 杯」滚回首项「—」：两次 itemExtent(34) 的下拖恰好落在 index 0。
    await tester.drag(find.byType(CupertinoPicker), const Offset(0, 68));
    await settle5(tester);
    expect(got, 0);
    expect(labels[got!], '—');
    // 调用侧映射口径：index 0 ＝ 空语义，不是数值 0。
    final int? cups = got == 0 ? null : got;
    expect(cups, isNull);
  });

  test('置首标签纯函数：hour/minute/cups 读数格式', () {
    expect(hourLabel(8), '8 时');
    expect(minuteLabel(5), '5 分');
    expect(cupsLabel(2), '2 杯');
  });
}
