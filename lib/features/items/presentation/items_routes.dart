// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'item_detail_page.dart';
import 'item_settle_page.dart';
import 'item_stats_page.dart';
import 'items_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> itemsShellRoutes() => [
        // V1.42 批2：物品价值主页（底栏池栏目 · 专版 p-items）。
              GoRoute(path: '/items', builder: (_, _) => const ItemsPage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> itemsPageRoutes() => [
        // V1.42 批2：物品栈页（专版 p-itemDetail / p-itemEdit / p-itemStats / p-itemSettle）。
          GoRoute(
            path: '/items/detail',
            builder: (_, s) =>
                ItemDetailPage(itemId: int.parse(s.uri.queryParameters['id']!)),
          ),
        GoRoute(
            path: '/items/stats',
            builder: (_, _) => const ItemStatsPage(),
          ),
        GoRoute(
            path: '/items/settle',
            builder: (_, s) =>
                ItemSettlePage(itemId: int.parse(s.uri.queryParameters['id']!)),
          )
];
