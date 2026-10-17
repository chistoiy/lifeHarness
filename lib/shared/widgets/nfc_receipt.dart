import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/notifications/notification_service.dart';
import 'ui_kit.dart' show AppToast;

/// 贴卡回执的分流判定（**纯函数**·可单测）。
///
/// 贴卡有两种到达方式，界面在场与否完全不同：
/// · **App 在前台**（用户正看着 App 贴卡）⇒ 应用内 toast 最轻、不占通知栏；
/// · **App 在后台**（透明中转界面直投·界面全程没出现）⇒ toast 挂在没人看的
///   widget 树上，用户只会听到「叮」一声、什么都没有（8166 真机实锤：打卡/阅读
///   卡贴完只震动无任何反馈）。这种情形必须走系统 **Heads-Up 横幅**。
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

/// 贴卡结果回执：前台走应用内 toast，后台走系统横幅（2026-10-17 产品令）。
///
/// [host] 可为 null（首帧前／界面已销毁），此时一律走横幅。
void nfcReceipt(BuildContext? host, String msg) {
  final usable = host != null && host.mounted;
  if (!nfcReceiptNeedsBanner(inApp: nfcInAppNow(), hostUsable: usable)) {
    AppToast.show(host!, msg);
    return;
  }
  // 不 await：回执失败绝不能影响已经落库的业务动作。
  unawaited(NotificationService.showNfcReceipt(text: msg));
}
