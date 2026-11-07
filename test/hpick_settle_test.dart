/// R3-9 · HPick 滚动收尾自激回归（真机 16:36:45 · 日志页 · Stack Overflow 855 层）。
/// 旧实现：ScrollEndNotification 回调内**无条件** animateTo → 动画收尾再发一条
/// ScrollEnd → 自激回中；判据＝fling 落定后 ①零异常 ②onChanged 次数有界
/// （旧实现会 5→3→1→0 连环改判）③offset 收敛到选中项居中位。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/shared/widgets/ui_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fling 落定：零异常 · onChanged 有界 · offset 居中收敛', (t) async {
    var changes = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: HPick(
              items: List.generate(10, (i) => 'L$i'),
              index: 5,
              itemWidth: 76,
              onChanged: (_) => changes++,
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.fling(find.byType(ListView), const Offset(-260, 0), 1800);
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull,
        reason: 'end 回调自激 animateTo＝真机栈溢出根因（R3-9）');
    expect(changes, lessThanOrEqualTo(2),
        reason: '一次 fling 只该落定一次；连环改判＝回中 runaway（旧实现 5→3→1→0）');
    final pos = t.state<ScrollableState>(find.byType(Scrollable)).position;
    // 与 `_center` 同一约定：pad=(vw-w)/2，居中位＝i*w-pad（索引反算＝(offset+pad)/w）。
    const pad = (320 - 76) / 2;
    final i = ((pos.pixels + pad) / 76).round().clamp(0, 9);
    final target = (i * 76.0 - pad).clamp(0.0, pos.maxScrollExtent);
    expect((pos.pixels - target).abs(), lessThan(1.5),
        reason: '落定必须居中：offset=${pos.pixels} target=$target');
  });
}
