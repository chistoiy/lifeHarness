import 'package:flutter/services.dart';

import 'desktop_actions.dart';

/// 桌面快捷方式桥（长按菜单 = `setDynamicShortcuts`；铺到桌面 = `requestPinShortcut`）。
///
/// 通道 `lh/desktop`（批 1 新增；既有通道一字不改）。
///
/// **C15 红线**：原生侧构造的 Intent 一律
/// `ACTION_VIEW + setData(Uri.parse(lh://…)) + setClass + flags`——
/// **只 setAction 不 setData 会误匹配既有 content/file 打开方式 filter**。
/// URI 一律取动作表 Scheme 列原值（禁手写字面量）。
const MethodChannel _desktopChannel = MethodChannel('lh/desktop');

/// 动态快捷方式是否可用（设备不支持时返回 false，调用方据此禁用「铺到桌面」）。
bool _pinSupported = false;

/// 置位 pin 支持态（原生侧在 `syncShortcuts` 回包里带回）。
void debugSetPinSupported(bool v) => _pinSupported = v;
bool get pinShortcutSupported => _pinSupported;

/// 重建动态快捷方式（长按菜单）。
///
/// [actionIds] 最多 [kMenuMax] 枚；空列表＝清空长按菜单。
/// 返回实际写入的枚数（原生侧去重/截断后的真值），调用方可据此提示。
Future<int> syncShortcuts(List<String> actionIds) async {
  final valid = actionIds
      .where(desktopActionById.containsKey)
      .toSet()
      .take(kMenuMax)
      .toList();
  final n = await _desktopChannel.invokeMethod<int>(
    'syncShortcuts',
    <String, dynamic>{
      'actions': valid,
      'schemes': <String>[
        for (final id in valid) desktopActionOf(id)!.scheme,
      ],
    },
  );
  return n ?? 0;
}

/// 请求「铺到桌面」（固定快捷方式，不限量）。
///
/// 不支持时抛 [UnsupportedError]，调用方须禁用按钮并给提示（B2）。
Future<bool> requestPinShortcut(String actionId) async {
  final a = desktopActionOf(actionId);
  if (a == null) throw ArgumentError('未知动作 id：$actionId');
  final ok = await _desktopChannel.invokeMethod<bool>(
    'requestPinShortcut',
    <String, dynamic>{'action': actionId, 'scheme': a.scheme},
  );
  return ok ?? false;
}

/// 把**指定某一枚**小组件请求固定到桌面（2026-10-15 产品改口）。
///
/// 为什么要改：原先走 `addWidget` —— 先弹一个 App 自己拼的 `AlertDialog`（4 项列表）
/// 让用户选，再走系统确认。那个框是纯系统默认外观、与 App 卡片体系完全不搭，而且
/// 「列表勾选」与「添加到桌面」两个语义挤在一起，用户看不懂勾选框到底是什么意思。
/// 现在设置页**每张卡自带**「添加到桌面」按钮，点哪枚就是哪枚，App 侧不再有中间选择框。
///
/// [widgetId] ∈ `overview` / `quick` / `todo` / `ledger`，与原生 `pinWidgetById`
/// 的 when 分支逐字一致（守护测试交叉核对）。
///
/// 之后仍会弹**系统**的「是否添加到主屏幕」确认框 —— 那是小米桌面画的，不在本进程内，
/// 任何 App 放小组件都必须过这一步，没有 API 能换皮（不是我们的弹窗）。
///
/// 无桥环境（测试/异常设备）静默降级——桌面侧本就是系统 UI。
Future<void> pinDesktopWidget(String widgetId) async {
  try {
    await _desktopChannel.invokeMethod<bool>(
      'pinWidget',
      <String, dynamic>{'widget': widgetId},
    );
  } catch (_) {
    // catch-ok: 无原生桥时静默降级，不打断设置页。
  }
}
/// 把「是否添加这枚」的总开关同步给原生（2026-10-15 8148 装机实锤修「死开关」）。
///
/// 前两个开关（2×2 概览 / 4×1 快捷记录）的语义是**是否添加这枚**（产品定案），
/// 所以关掉必须**真从桌面消失** —— 这不是重发快照能办的，须原生调
/// `AppWidgetManager.deleteAppWidgetId`。原生侧同时也是渲染的兜底闸：关着的枚
/// 即使实例没被删，也只渲染「已停用」空态、不显示旧读数。
///
/// 无桥环境静默降级（桌面侧本就是系统 UI）。
Future<void> applyDesktopWidgetFlags() async {
  try {
    await _desktopChannel.invokeMethod<bool>('applyWidgetFlags');
  } catch (_) {
    // catch-ok: 无原生桥时静默降级，不打断设置页。
  }
}
