import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/backup/backup_service.dart';
import 'core/database/app_database.dart';
import 'core/logging/app_log.dart';
import 'core/logging/error_capture.dart';
import 'core/logging/file_log_sink.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers.dart';
import 'core/settings/settings_repository.dart';
import 'core/theme/theme_repository.dart';
import 'features/habit/data/habit_repository.dart';
import 'features/habit/domain/habit_calc.dart';
import 'features/read/data/read_repository.dart';
import 'features/todo/data/todo_dao.dart';
import 'features/todo/domain/todo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 0) 三处全局错误捕获先行挂上（R1 启动即记，先于一切初始化）。
  installGlobalErrorLogging();

  // 0b) 日志落盘基建（设计稿 §2）：应用文档目录 logs/ 子目录，按天一个文件、
  //     单文件封顶 5MB 滚动、保留天数读 SharedPreferences 持久化值（Task 6
  //     日志页滚轮配置 · 默认 14 天）；init 前已进环形缓冲的行（错误捕获
  //     抢跑那段）在此补写一次，之后由 AppLog.onLine 自动续写。
  final prefs = await SharedPreferences.getInstance();
  final docsPath = (await getApplicationDocumentsDirectory()).path;
  final logDir = p.join(docsPath, 'logs');
  await FileLogSink.init(logDir,
      retentionDays: FileLogSink.readRetentionDays(prefs));
  for (final line in AppLog.lines.toList()) {
    FileLogSink.write(line);
  }
  await FileLogSink.flush();

  // 1) 主题设计令牌全量载入（assets/themes/）。
  final registry = await const ThemeRepository().loadAll();

  // 2) 数据库建库（验收：启动即建库；核心表+预留表+plugin_* 规范见 DbSchema）。
  await AppDatabase.instance.open();

  // 3) 通知基建（M0末A）：初始化 + 恢复每日节律 + 重排未完成的待办提醒。
  //    组合根允许触达 feature DAO（R2 白名单同 app_router）。
  await NotificationService.init();
  final settings = SettingsRepository(prefs).load();
  NotificationService.todoEnabled = settings.notify.todoEvent;
  await NotificationService.syncDaily(
    inboxClean: settings.notify.inboxClean,
    diaryReview: settings.notify.diaryReview,
    diaryTime: settings.notify.diaryTime,
  );
  // 阅读晚间补记提醒（read.dailyQ · 默认开 · 计划 §6）。
  await NotificationService.syncReadDaily(
    on: ((await ReadRepository(AppDatabase.instance.db).kv('read.dailyQ')) ??
            'true') ==
        'true',
  );
  // 4) 习惯提醒注册（习惯计划 §6/§7：remindAll 总开关 × dnd 免打扰双门控；
  //    逐习惯 remindAt 与晚间未打卡 nightAt 一并重排，可跨重启取消）。
  final hRepo = HabitRepository(AppDatabase.instance.db);
  final hRemindAll = await hRepo.kvBool('habit.remindAll', true);
  final hDnd = await hRepo.kvInt('habit.dnd', 1);
  final nightAt = kHabitNightAts[
      (await hRepo.kvInt('habit.nightAt', 1)).clamp(0, kHabitNightAts.length - 1)];
  await NotificationService.syncHabitNightly(
    on: hRemindAll &&
        await hRepo.kvBool('habit.nightRemind', true) &&
        !habitInDnd(hDnd, nightAt),
    at: nightAt,
  );
  for (final h in await hRepo.allHabits()) {
    await NotificationService.registerHabitReminder(
      habitId: h.id,
      title: h.name,
      hhmm: h.remindAt,
      enabled: hRemindAll &&
          !h.isArchived &&
          (h.remindAt?.isNotEmpty ?? false) &&
          !habitInDnd(hDnd, h.remindAt ?? ''),
    );
  }
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
        // V1.41 Task 10：备份服务组合根装配。attachDirs 取证 = 应用文档目录下
        // 实际落盘的附件子目录（note_images: shared/image_attach 日记/笔记插图；
        // book_covers: read isbn_enrich 封面；exports: journal note_sheets 导出；
        // share: read 书摘/书单导出）。
        backupServiceProvider.overrideWithValue(BackupService(
          exportDir: () => p.join(docsPath, 'backup'),
          db: () => AppDatabase.instance.open(),
          attachDirs: [
            p.join(docsPath, 'note_images'),
            p.join(docsPath, 'book_covers'),
            p.join(docsPath, 'exports'),
            p.join(docsPath, 'share'),
          ],
          prefs: prefs,
        )),
      ],
      child: const LifeHarnessApp(),
    ),
  );
}
