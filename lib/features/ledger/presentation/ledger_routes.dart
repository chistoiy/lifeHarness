// 治理G6：自 core/router/app_router.dart 按域下沉（path/builder 零改动）。
import 'package:go_router/go_router.dart';

import 'ledger_add_page.dart';
import 'ledger_assets_page.dart';
import 'ledger_account_detail_page.dart';
import 'ledger_budget_page.dart';
import 'ledger_cats_page.dart';
import 'ledger_debt_page.dart';
import 'ledger_export_page.dart';
import 'ledger_import_page.dart';
import 'ledger_page.dart';
import 'ledger_recur_page.dart';
import 'ledger_report_page.dart';
import 'ledger_search_page.dart';
import 'ledger_set_page.dart';
import 'ledger_tx_detail_page.dart';
import 'ledger_wish_page.dart';
import 'ledger_yearly_page.dart';


/// 底部导航壳内路由（原 ShellRoute 登记 · 治理G6 下沉）
List<GoRoute> ledgerShellRoutes() => [
        // 记账批1：主页入底栏导航池（NAV_MODS p-finance 同位）。
              GoRoute(path: '/ledger', builder: (_, _) => const LedgerPage())
];

/// 全屏栈路由（治理G6 下沉）
List<GoRoute> ledgerPageRoutes() => [
        // 记账批1：记一笔（?kind/cat/date/note/edit/copy · 原型 openL2(opt)）与
          // 流水详情（全屏无底栏，同 p-txDetail 为 stack 页）。
          GoRoute(
            path: '/ledger/add',
            builder: (_, s) {
              final q = s.uri.queryParameters;
              return LedgerAddPage(
                editId: int.tryParse(q['edit'] ?? ''),
                copyId: int.tryParse(q['copy'] ?? ''),
                kind: q['kind'],
                catId: int.tryParse(q['cat'] ?? ''),
                date: q['date'],
                note: q['note'],
              );
            },
          ),
        GoRoute(
            path: '/ledger/tx/:id',
            builder: (_, s) =>
                LedgerTxDetailPage(txnId: int.parse(s.pathParameters['id']!)),
          ),
        // 记账批1d：账单导入五步向导（全屏，同 p-billImport 栈页）。
          GoRoute(
            path: '/ledger/import',
            builder: (_, _) => const LedgerImportPage(),
          ),
        // 记账批2a：L4 统计报表与 L16 年度总结（全屏，同 p-report / p-yearly 栈页）。
          GoRoute(
            path: '/ledger/report',
            builder: (_, _) => const LedgerReportPage(),
          ),
        GoRoute(
            path: '/ledger/yearly',
            builder: (_, _) => const LedgerYearlyPage(),
          ),
        // 记账批2b：L5 预算中心（含 L17 结转；全屏，同 p-budget 栈页）。
          GoRoute(
            path: '/ledger/budget',
            builder: (_, _) => const LedgerBudgetPage(),
          ),
        // 记账批2c：L6 资产总览与 L7 账户详情（含信用卡账期；全屏，同 p-assets / p-assetAcct 栈页）。
          GoRoute(
            path: '/ledger/assets',
            builder: (_, _) => const LedgerAssetsPage(),
          ),
        GoRoute(
            path: '/ledger/account/:id',
            builder: (_, s) => LedgerAccountDetailPage(
              accountId: int.parse(s.pathParameters['id']!),
            ),
          ),
        // 记账批2d：L8 分类管理与 L9 周期账单（到期批量生成；全屏，同 p-cats / p-recur 栈页）。
          GoRoute(
            path: '/ledger/cats',
            builder: (_, _) => const LedgerCatsPage(),
          ),
        GoRoute(
            path: '/ledger/recur',
            builder: (_, _) => const LedgerRecurPage(),
          ),
        // 记账批3a：L10 心愿单与 L11 借出/借入（存入取出不落流水·兑换/还款走统一写路径；全屏，同 p-wish / p-debt 栈页）。
          GoRoute(
            path: '/ledger/wish',
            builder: (_, _) => const LedgerWishPage(),
          ),
        GoRoute(
            path: '/ledger/debt',
            builder: (_, _) => const LedgerDebtPage(),
          ),
        // 记账批3b：L12 搜索筛选与 L15 数据导出（条件即时 AND 过滤 / 流式落盘；
          // 全屏，同 p-txSearch / p-export 栈页）。
          GoRoute(
            path: '/ledger/search',
            builder: (_, _) => const LedgerSearchPage(),
          ),
        GoRoute(
            path: '/ledger/export',
            builder: (_, _) => const LedgerExportPage(),
          ),
        // 记账批3c：L13 记账设置（设置 KV 全量落 DB settings 表 `ledger.` 前缀；
          // 全屏，同 p-lset 栈页）。
          GoRoute(
            path: '/ledger/set',
            builder: (_, _) => const LedgerSetPage(),
          )
];
