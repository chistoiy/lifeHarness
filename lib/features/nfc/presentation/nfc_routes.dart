// 治理G6 同款：自 core/router/app_router.dart 按域下沉（本模块只加一行 `/nfc`）。
import 'package:go_router/go_router.dart';

import 'nfc_page.dart';

/// NFC 卡片模块路由（批1 · 冻结档 §6.1「路由仅加一行 `/nfc`，不动其他路由」）。
///
/// 全屏栈页（不占底栏，同 `p-sub-desktop`）⇒ 消费端必须 `push`：
/// `go` 会把栈底壳页一并换掉，页内 `pop()` 无处可去 ⇒ 返回黑屏
/// （见 `DesktopAction.fullScreen` 段注的 V1.67 真机伤）。
List<GoRoute> nfcPageRoutes() => [
      GoRoute(
        path: '/nfc',
        builder: (_, _) => const NfcSettingsPage(),
      ),
];