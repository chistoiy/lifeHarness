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