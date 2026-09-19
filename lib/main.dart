import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/providers.dart';
import 'core/theme/theme_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) 设置键值（主题/导航）就绪。
  final prefs = await SharedPreferences.getInstance();

  // 2) 主题设计令牌全量载入（assets/themes/）。
  final registry = await const ThemeRepository().loadAll();

  // 3) 数据库建库（验收：启动即建库；核心表+预留表+plugin_* 规范见 DbSchema）。
  await AppDatabase.instance.open();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
      ],
      child: const LifeHarnessApp(),
    ),
  );
}
