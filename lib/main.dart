import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers.dart';
import 'core/settings/settings_repository.dart';
import 'core/theme/theme_repository.dart';
import 'features/todo/data/todo_dao.dart';
import 'features/todo/domain/todo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) 设置键值（主题/导航/提醒）就绪。
  final prefs = await SharedPreferences.getInstance();

  // 2) 主题设计令牌全量载入（assets/themes/）。
  final registry = await const ThemeRepository().loadAll();

  // 3) 数据库建库（验收：启动即建库；核心表+预留表+plugin_* 规范见 DbSchema）。
  await AppDatabase.instance.open();

  // 4) 通知基建（M0末A）：初始化 + 恢复每日节律 + 重排未完成的待办提醒。
  //    组合根允许触达 feature DAO（R2 白名单同 app_router）。
  await NotificationService.init();
  final settings = SettingsRepository(prefs).load();
  NotificationService.todoEnabled = settings.notify.todoEvent;
  await NotificationService.syncDaily(
    inboxClean: settings.notify.inboxClean,
    diaryReview: settings.notify.diaryReview,
    diaryTime: settings.notify.diaryTime,
  );
  if (NotificationService.ready && settings.notify.todoEvent) {
    for (final Todo t in await TodoDao(AppDatabase.instance.db).list()) {
      if (!t.done && t.remindAt != null) {
        await NotificationService.scheduleTodo(
            id: t.id!, title: t.title, remindAt: t.remindAt);
      }
    }
  }

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
