import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/platform/desktop_widget.dart';
import '../../core/providers.dart';
import '../../core/theme/theme_repository.dart';
import '../../features/ledger/presentation/ledger_add_page.dart';
import '../../features/ledger/presentation/ledger_providers.dart'
    show ledgerDataProvider;
import 'desktop_widget_mounts.dart' show ledgerWidgetCells;

/// 4×1「记一笔」弹窗的**独立引擎装配**（工单 §7.1 · 首选路②：对话框 Activity
/// 内嵌 Flutter 渲染记账页同一份表单）。
///
/// ## 为什么是独立引擎而不是复用主引擎
///
/// 点击发生在桌面上，App 可能压根没起过（进程已被系统回收）。复用主引擎得先
/// 起 `MainActivity`——那正是产品要避免的「打开 App」。这里起一个只挂记账表单
/// 的引擎，用完即销毁：宿主 Activity 带 `excludeFromRecents`＋`noHistory`
/// ⇒ 最近任务里不留痕、返回即消。
///
/// ## 初始化只做三件事
///
/// prefs → 开库 → 主题令牌。**不跑 `main()` 的其余初始化**（通知重排、备份
/// 服务、图片迁移…）：弹窗只记账，多余初始化既拖慢冷启，也会与主进程重复做
/// 副作用（提醒重排、垃圾箱清理）。
///
/// ⚠ **首行必须 `ensureInitialized`**（2026-10-18 真机报障「点记一笔没反应」根因）：
/// 自定义入口点不像 `main()` 那样有框架替它建 binding，而下面第一句
/// `SharedPreferences.getInstance()` 就走平台通道 ⇒ binding 未初始化时抛
/// `Binding has not yet been initialized`，`runApp` 根本执行不到。宿主是
/// **透明对话框主题**，于是「窗口起来了但一个字都没画」＝用户眼里完全没反应
/// （不是闪退、也没有崩溃日志——异常在引擎的 zone 里被吞成一行红字）。
Future<void> runWidgetQuickAddApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await AppDatabase.instance.open();
  final registry = await const ThemeRepository().loadAll();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
      ],
      child: const _QuickAddApp(),
    ),
  );
}

/// 弹窗根：只挂一个 [LedgerAddPage]（`dialogMode`），主题与整页同源。
class _QuickAddApp extends ConsumerWidget {
  const _QuickAddApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 保存后桌面读数要跟着变：本引擎没有 App 的 `desktopWidgetSyncProvider`
    // 挂载点（那是 app.dart 的事），故在此听一次。
    //
    // ⚠ **只推记账三键**：本引擎拿不到待办/习惯域（那两个 provider 从未被
    // watch，`valueOrNull` 是 null），整包下发会把待办卡与打卡卡推成空值——
    // 与批A 交互闭环层踩过的是同一个坑（见 `pushWidgetHabitSnapshot` 注释）。
    ref.listen(ledgerDataProvider, (_, next) {
      final d = next.valueOrNull;
      if (d == null) return;
      final hide = ref.read(settingsRepositoryProvider).loadDesktopHideAmount();
      final cells = ledgerWidgetCells(d, DateTime.now(), hideAmount: hide);
      Future(
        () => pushWidgetLedgerSnapshot(
          amountCell: cells.amount,
          monthAmountCell: cells.month,
          balanceCell: cells.balance,
        ),
      );
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      // 拍板件 §三：弹窗跟随**系统**深浅（不吃 App 内四主题的 mode 选择）。
      themeMode: ThemeMode.system,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            // 与原型 `.qp-mask` 的 24 留白同口径：卡片四周留出桌面可见的边，
            // 用户一眼能看出「这是个浮在桌面上的弹窗」，不是切了个页面。
            padding: const EdgeInsets.all(24),
            child: LedgerAddPage(
              dialogMode: true,
              onDialogClose: () => SystemNavigator.pop(),
            ),
          ),
        ),
      ),
    );
  }
}
