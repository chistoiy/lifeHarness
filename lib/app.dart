import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/ai/ai_review.dart' show aiRootNavKey;
import 'core/providers.dart';
import 'features/read/presentation/open_with.dart' show brOpenConsumeOnce;
import 'shared/linkage/habit_mounts.dart';
import 'shared/linkage/ledger_mounts.dart';

/// 应用根 Widget：主题三件套（light/dark/mode）+ go_router。
/// V1.53.4⑥：兼作系统「打开方式」EPUB 意图的消费点——冷启动首帧后取一次，
/// 热启动（singleTop onNewIntent 入队）在 resumed 时再取；弹层挂根 Navigator
/// （aiRootNavKey 同源，分支页要盖住底栏，参照 R14 弹层三成因护栏）。
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
    // 冷启动：首帧后路由与根 Navigator 均已就绪，再消费入队意图。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFrameDone = true;
      _consumeEpub();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _firstFrameDone) _consumeEpub();
  }

  Future<void> _consumeEpub() async {
    if (_consuming) return; // 弹层在途时 resumed 不重入
    _consuming = true;
    try {
      final navCtx = aiRootNavKey.value?.currentState?.context;
      if (navCtx != null && navCtx.mounted) {
        await brOpenConsumeOnce(navCtx, ref);
      }
    } finally {
      _consuming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // L10 习惯联动订阅（待办完成 → 打卡回写 · 应用全程存活）。
    ref.watch(habitLinkageProvider);
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
