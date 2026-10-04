// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'ai_usage_page.dart';
import 'log_page.dart';
import 'media_clean_page.dart';
import 'notify_settings_page.dart';
import 'settings_page.dart';
import 'sync_history_page.dart';
import 'sync_page.dart';
import 'ai_page.dart';
import 'recmg_page.dart';
import 'trash_page.dart';

/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> settingsShellRoutes() => [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> settingsPageRoutes() => [
        // 提醒通知二级页（原型 p-sub-notify）。
          GoRoute(
            path: '/settings/notify',
            builder: (_, _) => const NotifySettingsPage(),
          ),
        // AI批：AI 增强二级页组（原型 p-sub-ai + aiapi 工具 + p-sub-aiPrompts/Edit）。
          GoRoute(
            path: '/settings/ai',
            builder: (_, _) => const AiSettingsPage(),
          ),
        GoRoute(
            path: '/settings/ai/verify',
            builder: (_, _) => const AiVerifyPage(),
          ),
        // V1.53 AI 使用记录（全屏明细·与日志页同交互语言·无底栏）。
          GoRoute(
            path: '/settings/ai/usage',
            builder: (_, _) => const AiUsagePage(),
          ),
        GoRoute(
            path: '/settings/ai/prompts',
            builder: (_, _) => const AiPromptsPage(),
          ),
        GoRoute(
            path: '/settings/ai/prompts/edit',
            builder: (_, s) => AiPromptEditPage(taskId: s.extra as String),
          ),
        // V1.27 P2 外观二级页（原型 p-sub-appearance：主题/深色/主题色/字号）。
          GoRoute(
            path: '/settings/appearance',
            builder: (_, _) => const AppearanceSettingsPage(),
          ),
        // V1.29批A4 记录管理二级页（原型 p-sub-recmg：四段设置归位 + 通用）。
          GoRoute(
            path: '/settings/recmg',
            builder: (_, _) => const RecmgSettingsPage(),
          ),
        // V1.60 全局回收站（原型 p-sub-trash · ?seg= 直达六类分段）。
          GoRoute(
            path: '/settings/trash',
            builder: (_, s) =>
                TrashPage(initialSeg: s.uri.queryParameters['seg']),
          ),
        // V1.41批1 Task 6 日志查看页（原型 p-log：120 条窗口/级别过滤/复制全量/
          // 保留天数滚轮；全屏栈页，设置页与将来同步历史均 context.go 跳入）。
          GoRoute(
            path: '/log',
            builder: (_, _) => const LogPage(),
          ),
        // R5c：图片存储清理页（本地孤儿图片勾选清理，设置页入口）。
          GoRoute(
            path: '/settings/media-clean',
            builder: (_, _) => const MediaCleanPage(),
          ),
        // V1.41 Task 18 /sync 主页（原型 p-sync：当前服务卡 + 容量三态 +
          // 立即同步 + 差异/备份/控流/历史/日志入口 + 切换服务列表）。
          GoRoute(
            path: '/sync',
            builder: (_, _) => const SyncPage(),
          ),
        // V1.41 Task 18 同步历史（原型 p-synchist：点击行 → /log）。
          GoRoute(
            path: '/sync/history',
            builder: (_, _) => const SyncHistoryPage(),
          )
];
