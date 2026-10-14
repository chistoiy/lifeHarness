/// 批B（工单 悬浮胶囊增强批-20261014 §7）：app 外系统悬浮窗通道。
///
/// 原生侧 `lh/pill`：sync＝（按需起前台 Service 并）同步悬浮窗内容与可见性
/// （visible=false＝服务保活、视图收起）；stop＝停 Service；
/// canDrawOverlays/requestOverlayPermission＝「显示在其他应用上层」权限
/// 探问与跳转（Android 11+ 无弹窗式授权，走系统设置页）。
/// takePillEvent＝悬浮窗「■ 结束」一次性事件（MainActivity 入队，Dart 侧
/// 每 tick 消费；与 `lh/intents` 的 takeOpenFile 同模式）。
///
/// 全部方法按「测试/桌面缺原生」降级不抛（与 `open_intent.dart` 同口径）；
/// 目标决策走纯函数 [sysPillTarget]，零原生依赖，单测与同步器共用。
library;

import 'package:flutter/services.dart';

const MethodChannel _pillChannel = MethodChannel('lh/pill');

/// 系统悬浮窗应对准的目标（读侧优先于影音侧——单浮窗口径）。
enum SysPillTarget { none, read, media }

/// 悬浮窗可见性决策（纯函数·批B §7 口径 ①②③⑦）：
/// 功能关 / 权限缺 / **app 在前台**（含在阅读器/计时页里）→ 一律 none
/// （none 时原生收窗，服务是否保活由「会话在不在跑」另行决定，不走本函数）。
///
/// **「进阅读器隐藏」的范围（6131 热修）**：只在 app 前台时成立——app 内已有
/// 胶囊，系统悬浮窗是重复；但**退出 app 后阅读页仍在导航栈上**，若把
/// `readerOpen` 当独立条件，回桌面/切别的 app 就永不显示（6129 装机实测：
/// 在阅读计时页按 HOME 无胶囊）。悬浮窗的用武之地恰在 app 外，故这里只看
/// app 前后台，不看栈上有什么页。
SysPillTarget sysPillTarget({
  required bool sysPillOn,
  required bool canDraw,
  required bool appActive,
  required bool readRunning,
  required bool mediaRunning,
}) {
  if (!sysPillOn || !canDraw) return SysPillTarget.none;
  if (appActive) return SysPillTarget.none;
  if (readRunning) return SysPillTarget.read;
  if (mediaRunning) return SysPillTarget.media;
  return SysPillTarget.none;
}

/// 权限引导话术（2026-10-14 产品过门冻结原文·原型 sheetPillDemo 同文，
/// 设置页引导弹层与守护测试共用这一句，禁漂移）。
const kSysPillPermitText =
    '悬浮计时条需要在其他应用上层显示，以便你在桌面或别的 App 里继续看到计时。'
    '该权限只用于显示计时胶囊，不读取、不上传任何内容。';

/// 悬浮窗内容载荷（与 app 内胶囊同构：书名 · 状态词 · 秒数）。
class SysPillState {
  const SysPillState({
    required this.kind,
    required this.title,
    required this.status,
    required this.seconds,
  });

  final String kind; // 'read' | 'media'
  final String title;
  final String status; // '阅读中' / mediaTimerWord（观影中/追剧中/…）
  final int seconds;
}

/// 悬浮窗一次性事件（■结束）：type='end'；kind 回显当时展示的一侧，
/// 真正结束哪条会话由 Dart 侧按在跑会话现算（事件不带 id）。
class SysPillEvent {
  const SysPillEvent({required this.type, required this.kind});

  final String type;
  final String kind;
}

/// 「显示在其他应用上层」是否已授权（通道缺失＝未授权，走降级）。
Future<bool> sysPillCanDraw() async {
  try {
    return await _pillChannel.invokeMethod<bool>('canDrawOverlays') ?? false;
  } catch (_) {
    // catch-ok: 测试/桌面无原生＝按未授权降级（仅 app 内胶囊，功能不受影响）。
    return false;
  }
}

/// 跳系统「显示在其他应用上层」设置页（返回 true＝已成功拉起设置页；
/// 授权结果由调用方在 resumed 后经 [sysPillCanDraw] 复探）。
Future<bool> sysPillRequestPermission() async {
  try {
    await _pillChannel.invokeMethod<void>('requestOverlayPermission');
    return true;
  } catch (_) {
    // catch-ok: 无原生/无设置页可跳＝引导失败，调用方保持关闭态。
    return false;
  }
}

/// 同步悬浮窗（工单 §7 服务生命周期口径：起服务只发生在 app 前台——
/// 规避 Android 14+ 后台起 FGS 限制；退后台后只更新/收视图，服务已在跑则
/// 继续保活）。visible=false＝服务保活但视图收起（app 前台/进阅读器时），
/// 载荷照常推送（通知文案用）。
Future<void> sysPillSync(SysPillState state, bool visible) async {
  try {
    await _pillChannel.invokeMethod<void>('sync', {
      'kind': state.kind,
      'title': state.title,
      'status': state.status,
      'seconds': state.seconds,
      'visible': visible,
    });
  } catch (_) {
    // catch-ok: 原生异常不打断计时主流程（悬浮窗是附加显示，不是会话本体）。
  }
}

/// 停 Service（会话结束/功能关闭/权限被撤时；stopService 不受后台启动限制）。
Future<void> sysPillStop() async {
  try {
    await _pillChannel.invokeMethod<void>('stop');
  } catch (_) {
    // catch-ok: 同上。
  }
}

/// 一次性消费悬浮窗事件（null＝无待处理）。
Future<SysPillEvent?> takePillEvent() async {
  try {
    final Object? raw =
        await _pillChannel.invokeMethod<Map<dynamic, dynamic>>('takePillEvent');
    if (raw is! Map) return null;
    final type = (raw['type'] as String?) ?? '';
    if (type.isEmpty) return null;
    return SysPillEvent(type: type, kind: (raw['kind'] as String?) ?? 'read');
  } catch (_) {
    // catch-ok: 无原生＝无事件。
    return null;
  }
}
