import 'package:flutter/services.dart';

import 'desktop_actions.dart';

/// 桌面模块 · `lh://` 启动路由的 Dart 消费端（L3）。
///
/// 规格＝docs/handoff/桌面模块-冻结版开发方案-20261013.md §4.3。
///
/// 通道 `lh/launch`（**新通道**；既有 `lh/intents` 一字不改），方法 `takeLaunchRoute`。
/// 原生侧持有队列（冷启动意图**先入队不丢弃**·B15），本侧**单次消费**：读到即清空，
/// 防重放。
const MethodChannel _launchChannel = MethodChannel('lh/launch');

/// 消费点是否已就绪（**首帧完成后**才置 true）。
///
/// B15 红线：首帧前读队列＝永久丢失意图，判不合格。这里用可注入闸门，
/// 既保生产口径（B15），也让 `desktop_launch_queue_test` 能钉住「未就绪不消费」。
bool _launchReady = false;

/// 允许测试重置闸门与桩（生产不调用）。
void debugResetLaunchGate({bool ready = false}) => _launchReady = ready;

/// 标记消费点已就绪（首帧完成后由 `app.dart` 调）。
void markLaunchRouteReady() => _launchReady = true;

/// 门禁是否已开（测试与真机排障用）。
bool get launchRouteGateOpen => _launchReady;

/// 取一条待投递的启动路由；无则 null。
///
/// **B15**：门禁未开时**返回 null 且不清空队列**（原生侧仍持有），
/// 首帧就绪后再取一次即得目标路由；二次调用返回 null（防重放）。
Future<LaunchRoute?> takeLaunchRoute() async {
  if (!_launchReady) return null;
  final raw = await _launchChannel.invokeMapMethod<String, dynamic>(
    'takeLaunchRoute',
  );
  if (raw == null) return null;
  final action = raw['action'] as String?;
  if (action == null || action.isEmpty) return null;
  final args = <String, String>{};
  final rawArgs = raw['args'];
  if (rawArgs is Map) {
    rawArgs.forEach((k, v) {
      if (k is String && v is String) args[k] = v;
    });
  }
  return LaunchRoute(
    action: action,
    args: args,
    fromBackground: raw['fromBackground'] == true,
  );
}

/// 把界面让回原处（Android `moveTaskToBack(true)`）。
///
/// 批3（2026-10-17 产品令）：贴卡触发「不需要看界面」的动作（打卡/计时）时，
/// 系统已因 AAR 把本 App 拉到前台——执行完调这里退回用户原来的界面，
/// 结果由横幅通知呈现，用户不会被莫名其妙带到 App 里。
///
/// 失败静默：非 Android／通道缺失时什么都不做（不影响已完成的业务动作）。
Future<void> moveTaskToBack() async {
  try {
    await _launchChannel.invokeMethod<void>('moveTaskToBack');
  } catch (_) {
    // catch-ok: 让不让得回去是体验问题，不是业务问题——动作已执行完，不该报错打断。
  }
}