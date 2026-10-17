import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/notifications/notification_service.dart';
import '../../features/nfc/data/nfc_tag_io.dart' show nfcShowBanner;
import 'ui_kit.dart' show AppToast;

/// 贴卡回执的分流判定（**纯函数**·可单测）。
///
/// 贴卡有两种到达方式，界面在场与否完全不同：
/// · **App 在前台**（用户正看着 App 贴卡）⇒ 应用内 toast 最轻、不占通知栏；
/// · **App 在后台**（透明中转界面直投·界面全程没出现）⇒ toast 挂在没人看的
///   widget 树上，用户只会听到「叮」一声、什么都没有（8166 真机实锤：打卡/阅读
///   卡贴完只震动无任何反馈）。这种情形必须走**系统层可见**的回执。
///
/// 所以：只有在「App 在前台 **且** host 可用」时才允许用应用内 toast。
bool nfcReceiptNeedsBanner({required bool inApp, required bool hostUsable}) =>
    !(inApp && hostUsable);

/// App 此刻是否「用户看得见」（resumed／inactive）。
///
/// inactive 也算——下拉通知栏、弹系统权限框时 App 仍可见，toast 看得见。
/// 拿不到生命周期状态（单测）按前台处理。
bool nfcInAppNow() {
  final life = WidgetsBinding.instance.lifecycleState;
  return life == null ||
      life == AppLifecycleState.resumed ||
      life == AppLifecycleState.inactive;
}

/// 贴卡结果回执：前台 toast／后台**自绘悬浮横幅**（2026-10-17 产品令）。
///
/// [host] 可为 null（首帧前／界面已销毁），此时一律走横幅。
void nfcReceipt(BuildContext? host, String msg) {
  final usable = host != null && host.mounted;
  if (!nfcReceiptNeedsBanner(inApp: nfcInAppNow(), hostUsable: usable)) {
    AppToast.show(host!, msg);
    return;
  }
  // 不 await：回执失败绝不能影响已经落库的业务动作。
  unawaited(nfcBannerOrNotify(msg));
}

/// 延后 [after] 再发回执（**只在 App 不在前台时发**）。
///
/// 用于「本就有前台 toast」的分支（打卡成功）：前台再弹一条横幅会重复打扰，
/// 故前台直接返回，后台才落到横幅/通知。
Future<void> nfcReceiptLater(
  String msg, {
  Duration after = const Duration(milliseconds: 700),
}) async {
  if (nfcInAppNow()) return;
  if (after > Duration.zero) await Future<void>.delayed(after);
  await nfcBannerOrNotify(msg);
}

/// 后台回执的唯一落地口：**先自绘横幅，弹不出来才退回系统通知**。
///
/// 为什么不信系统 Heads-Up：真机（HyperOS）上 high 渠道的通知只进通知栏不上浮
/// （`dumpsys` 里 importance=4 已核），ROM 层静默且系统无强制手段。自绘悬浮窗与
/// 悬浮胶囊同一套机制，真机可证可用。横幅弹成功时另发一条**静默记录**进通知栏
/// （importance=low），这样「看得见」与「查得到」两件事都成立且不重复打扰。
Future<void> nfcBannerOrNotify(String msg) async {
  if (msg.trim().isEmpty) return;
  if (await nfcShowBanner(msg)) {
    await NotificationService.showNfcRecord(text: msg);
    return;
  }
  await NotificationService.showNfcReceipt(text: msg);
}
