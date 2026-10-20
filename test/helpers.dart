import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/ai/ai_review.dart' show aiRootNavKey;

/// 测试共享防坑工具（计划书 §7.2）。新用例一律 import 本文件，不再各自造轮子。
///
/// 既有铁律不变：**全 app（LifeHarnessApp）用例必须一个文件一个**，
/// 同 isolate 多全 app 用例会互相污染挂死（pumpAndSettle 永动 / --timeout 不生效）。
///
/// 模拟器取证坐标（720×1280 · Small_Phone_API_35）：
/// 底栏 y≈1160；五 tab 中心 x = 72(今天) / 216(待办) / 360(时间) / 504(日记) / 648(我的)。
/// Flutter 文本不进 uiautomator dump，逐屏取证用 `adb exec-out screencap -p`。

/// 全 app 场景 pumpAndSettle 可能不收敛：5s 上限快速失败并暴露现场。
/// 收尾顺带排空 AppLog 的节流 Timer（L3/L4 起，页面读写会落日志，FakeAsync 下
/// 不显式推进就判「A Timer is still pending」）。要「只推帧不推时间」的场合
/// 直接用手写 `pumpAndSettle` 或 [settleFrames]。
Future<void> settle5(WidgetTester tester) async {
  await settleFrames(tester);
  await drainLogTimer(tester);
}

/// 只推帧、不动节流定时器（极少数对时间推进敏感的用例用）。
Future<void> settleFrames(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5));

/// 排空 AppLog 的 300ms 节流 Timer。
/// 任何一次 `AppLog.add/addKey`（含 L3 起 Provider 读取失败留痕）都会起一个
/// 300ms 定时器；FakeAsync 下 `pumpAndSettle` 只看帧、不看定时器，收尾就会判
/// 「A Timer is still pending」。页面 pump 之后补一次本调用（400ms > 节流窗口）
/// 即可让定时器自然到期。
Future<void> drainLogTimer(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));

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

/// 等所有 SnackBar / 阅读模块浮层提示条自动消失。fake 时间下**单次大 pump 不会
/// 触发提示关闭定时器**（只有小步循环 pump 才会）；浮层会挡住底栏命中测试，
/// 需在再点底部按钮前清场。
///
/// 认两种载体：SnackBar（页面级 messenger）与 `readToast` 的根 Overlay 提示条
/// （F2-13 起改直挂，锚点键 `read-toast`）——后者是 `Timer` 摘除，
/// `pumpAndSettle` 推不掉，必须靠本函数的循环 pump 走完驻留窗口。
Future<void> clearToasts(WidgetTester tester, {int ms = 100}) async {
  bool anyToast() =>
      find.byType(SnackBar).evaluate().isNotEmpty ||
      find.byKey(const ValueKey('read-toast')).evaluate().isNotEmpty;
  for (var i = 0; i < 40 && anyToast(); i++) {
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

/// 注入 app 根 Navigator key：AI 通道（审阅/进度/结果弹层）走
/// `aiRootNavKey.value?.currentState`，测试用本地 GoRouter 时必须把自己的
/// 根栈 key 交出去，否则弹层退回落回调用页所属栈（分支页测不到根栈语义）。
/// addTearDown 自动置 null，不跨用例串味。
void useAiRootNav(WidgetTester tester, GlobalKey<NavigatorState> key) {
  aiRootNavKey.value = key;
  addTearDown(() => aiRootNavKey.value = null);
}

/// 用例收尾放掉 [AppLog] 的 300ms version 节流 Timer：日志基建每次入缓冲都会
/// 排一个一次性定时器，测试若在 300ms 假时间前结束，绑定层不变量检查直接报
/// 「A Timer is still pending」。凡断言过日志/让被测代码写过日志的用例末尾都要来一发。
Future<void> settleLogTimer(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));
