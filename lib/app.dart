import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'shared/linkage/habit_mounts.dart';

/// 应用根 Widget：主题三件套（light/dark/mode）+ go_router。
class LifeHarnessApp extends ConsumerWidget {
  const LifeHarnessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // L10 习惯联动订阅（待办完成 → 打卡回写 · 应用全程存活）。
    ref.watch(habitLinkageProvider);
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
