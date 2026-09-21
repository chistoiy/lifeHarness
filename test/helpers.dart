import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试共享防坑工具（计划书 §7.2）。新用例一律 import 本文件，不再各自造轮子。
///
/// 既有铁律不变：**全 app（LifeHarnessApp）用例必须一个文件一个**，
/// 同 isolate 多全 app 用例会互相污染挂死（pumpAndSettle 永动 / --timeout 不生效）。
///
/// 模拟器取证坐标（720×1280 · Small_Phone_API_35）：
/// 底栏 y≈1160；五 tab 中心 x = 72(今天) / 216(待办) / 360(时间) / 504(日记) / 648(我的)。
/// Flutter 文本不进 uiautomator dump，逐屏取证用 `adb exec-out screencap -p`。

/// 全 app 场景 pumpAndSettle 可能不收敛：5s 上限快速失败并暴露现场。
Future<void> settle5(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5));

/// 有界轮询等某段文案出现（默认 15×80ms=1.2s）。
/// SnackBar 断言专用：show 后禁止先 pumpAndSettle——会把 fake 时间推过其
/// 1.6s 自动消失期导致查无；应 `pollText` 命中后再继续。返回是否命中。
Future<bool> pollText(WidgetTester tester, String text,
    {int times = 15, int ms = 80}) async {
  for (var i = 0; i < times; i++) {
    if (find.text(text).evaluate().isNotEmpty) return true;
    await tester.pump(Duration(milliseconds: ms));
  }
  return find.text(text).evaluate().isNotEmpty;
}

/// 等所有 SnackBar 自动消失。fake 时间下**单次大 pump 不会触发 SnackBar 关闭
/// 定时器**（只有小步循环 pump 才会）；浮层 SnackBar 会挡住底栏命中测试，
/// 需在再点底部按钮前清场。
Future<void> clearToasts(WidgetTester tester, {int ms = 100}) async {
  for (var i = 0;
      i < 40 && find.byType(SnackBar).evaluate().isNotEmpty;
      i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
  await tester.pumpAndSettle();
}

/// 加高视口让懒构建 ListView 的深部长尾子项全部入树（模板行/保存钮等），
/// 自动 tearDown 还原。默认 800×2400。
Future<void> useSurface(WidgetTester tester,
    [Size size = const Size(800, 2400)]) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
