import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/desktop_shortcuts.dart';
import '../../core/providers.dart';

/// 桌面模块批1 · 首启初始化动态快捷方式（长按菜单）挂载点（仿 ledger_mounts 惯例。
/// app.dart watch，R1 守护下 app 只经 shared/linkage 编排 core 能力）。
///
/// **为什么必须在启动期做，而不能只在设置页里做**（冻结档 C2 行、B1 行、F1-2 行
/// 三处同口径＝「App 首启以默认 4 枚初始化」「首启进入主页时以默认 4 枚初始化」）：
/// 1. 新装用户**没打开过**「设置→桌面与快捷方式」时，「setDynamicShortcuts」一次都
///    不会被调 → 长按图标**没有菜单**（批 1 真机门「长按菜单 4 枚」直接判不合格）；
/// 2. 系统在 App 更新/被 ROM 清理后会丢掉动态快捷方式，靠用户手动进设置页补
///    是不能接受的兜底。
///
/// 取值口径与设置页**同一读口**（`SettingsRepository.loadDesktopMenu`：缺键回落
/// `defaultDesktopMenuIds()`＝默认 4 枚），不另造一份默认值。
///
/// 一次性副作用：无常驻 Timer、无订阅；设备不具备快捷方式能力（无 `lh/desktop`
/// 通道，抛 `MissingPluginException`；含全 app widget 测试环境）静默降级，
/// 不打断启动链路。
final desktopShortcutSeedProvider = Provider<void>((ref) {
  final ids = ref.read(settingsRepositoryProvider).loadDesktopMenu();
  Future(() async {
    try {
      await syncShortcuts(ids);
    } catch (_) {
      // catch-ok: 无快捷方式能力的设备/测试环境静默降级，启动不中断；
      // 设置页自带「本机不支持」态与提示兜底（B2）。
    }
  });
});
