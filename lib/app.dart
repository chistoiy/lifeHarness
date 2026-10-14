import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/ai/ai_review.dart' show aiRootNavKey;
import 'core/platform/open_intent.dart'
    show classifyOpenIntent, kOpenUnsupportedToast, takeOpenFile;
import 'core/providers.dart';
import 'features/journal/presentation/note_open_with.dart' show noteOpenConsume;
import 'features/read/presentation/open_with.dart' show handleOpenWithEpub;
import 'shared/linkage/habit_mounts.dart';
import 'shared/linkage/journal_mounts.dart';
import 'shared/linkage/ledger_mounts.dart';
import 'shared/linkage/sys_pill_sync.dart'
    show drainPillEvents, sysPillAppActiveProvider, sysPillSyncProvider;
import 'shared/widgets/ui_kit.dart' show AppToast;

/// 应用根 Widget：主题三件套（light/dark/mode）+ go_router。
/// V1.53.4⑥：兼作系统「打开方式」EPUB 意图的消费点——冷启动首帧后取一次，
/// 热启动（singleTop onNewIntent 入队）在 resumed 时再取；弹层挂根 Navigator
/// （aiRootNavKey 同源，分支页要盖住底栏，参照 R14 弹层三成因护栏）。
/// V1.64 批1：通道泛化为多类型——分派在组合根（R1：read/journal 互不 import），
/// epub→读库导入、note→笔记「系统打开」归集、''→统一人话拒收提示。
class LifeHarnessApp extends ConsumerStatefulWidget {
  const LifeHarnessApp({super.key});

  @override
  ConsumerState<LifeHarnessApp> createState() => _LifeHarnessAppState();
}

class _LifeHarnessAppState extends ConsumerState<LifeHarnessApp>
    with WidgetsBindingObserver {
  bool _firstFrameDone = false;
  bool _consuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 批B：系统悬浮窗同步器保活（listenManual＝订阅但不重建 UI；
    // 内部挂秒级 ticker，逐 tick 推内容/收视图/消费 ■结束 事件）。
    ref.listenManual(sysPillSyncProvider, (_, _) {});
    // 冷启动：首帧后路由与根 Navigator 均已就绪，再消费入队意图。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFrameDone = true;
      _consumeOpen();
      // 批B：冷启动经 ■结束 意图入队的场景，首帧即探一次悬浮窗事件。
      drainPillEvents(ref);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _firstFrameDone) {
      _consumeOpen();
      // 批B：回前台时补消费一次悬浮窗事件（冷启动经 ■结束 意图入队的场景，
      // 同步器尚未起 tick 也要兜住）。
      drainPillEvents(ref);
    }
    // 批B：app 前台时系统悬浮窗隐藏（免与 app 内胶囊重复），退后台恢复。
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) {
      ref.read(sysPillAppActiveProvider.notifier).state =
          state == AppLifecycleState.resumed;
    }
  }

  Future<void> _consumeOpen() async {
    if (_consuming) return; // 弹层在途时 resumed 不重入
    _consuming = true;
    try {
      final f = await takeOpenFile();
      final kind = classifyOpenIntent(f);
      if (kind == null || f == null) return;
      final navCtx = aiRootNavKey.value?.currentState?.context;
      if (navCtx == null || !navCtx.mounted) return;
      if (kind.isEmpty) {
        AppToast.show(navCtx, kOpenUnsupportedToast);
      } else if (kind == 'note') {
        await noteOpenConsume(navCtx, ref, f);
      } else {
        await handleOpenWithEpub(navCtx, ref, f.path);
      }
    } finally {
      _consuming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // L10 习惯联动订阅（待办完成 → 打卡回写 · 应用全程存活）。
    ref.watch(habitLinkageProvider);
    // L3 日记联动订阅（语义断链批：待办完成 → 日记 ☐ 行回勾 · 应用全程存活）。
    ref.watch(journalLinkageProvider);
    // 记账批2d §5：周期账单 App 启动到期扫尾（一次性静默生成，无常驻 Timer）。
    ref.watch(ledgerRecurMountProvider);
    return MaterialApp.router(
      title: 'LifeHarness',
      debugShowCheckedModeBanner: false,
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: ref.watch(appThemeModeProvider),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
