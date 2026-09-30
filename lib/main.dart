import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/ai/ai_providers.dart';
import 'core/ai/ai_vault.dart';
import 'core/backup/backup_service.dart';
import 'core/database/app_database.dart';
import 'core/logging/app_log.dart';
import 'core/logging/error_capture.dart';
import 'core/logging/file_log_sink.dart';
import 'core/media/media_hash_migrator.dart';
import 'core/media/media_usage_scanner.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers.dart';
import 'core/settings/settings_repository.dart';
import 'core/sync/snapshot_service.dart';
import 'core/sync/sync_providers.dart';
import 'core/theme/theme_repository.dart';
import 'features/care/data/care_repository.dart';
import 'features/care/presentation/care_notify.dart';
import 'features/habit/data/habit_repository.dart';
import 'features/habit/domain/habit_calc.dart';
import 'features/ledger/data/ledger_repository.dart';
import 'features/ledger/presentation/ledger_notify.dart';
import 'features/read/data/isbn_enrich.dart';
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
  // init 前已入缓冲的早行（错误捕获抢跑那段）先取快照：回填历史之后不能再拿
  // 全量列表去补写，否则会把上一进程的历史行重复写盘。
  final earlyLines = AppLog.lines.toList();
  await FileLogSink.init(logDir,
      retentionDays: FileLogSink.readRetentionDays(prefs));
  // 先把上一次进程落盘的尾部行回填进内存缓冲（日志页跨重启可见）。
  await FileLogSink.loadRecent();
  for (final line in earlyLines) {
    FileLogSink.write(line);
  }
  await FileLogSink.flush();

  // 1) 主题设计令牌全量载入（assets/themes/）。
  final registry = await const ThemeRepository().loadAll();

  // 1b) AI 默认提示词包载入（assets/ai_prompts/ · 用户覆盖在 prefs，不动资产）。
  final aiPack = await loadAiPromptPack();

  // 1c) 豆瓣防封批（2026-09-26）组合根：从本机 prefs 恢复登录 Cookie 与
  //     熔断冷却。Cookie 只落 SharedPreferences（只存本机：不进 DB、不进
  //     备份导出、不进日志）；熔断到期点经 persist 钩子写回 prefs。
  DoubanCookie.set(prefs.getString('read.dbCookie'));
  DoubanGuard.persist = (untilMs) => prefs.setInt('read.dbBlockUntil', untilMs);
  DoubanGuard.restore(prefs.getInt('read.dbBlockUntil'));

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

  // 4.4) V1.57 B 批：记账月度小结 + 呵护儿保体检节点按当前设置重排
  //      （开关关＝取消排程；开＝刷新下一送达时点与内容；免打扰顺延）。
  //      失败只 warn 不阻断启动（提醒属可降级旁路）。
  try {
    await syncMonthlyDigest(LedgerRepository(AppDatabase.instance.db),
        dnd: settings.notify.dnd);
    await syncCareCheckup(CareRepository(AppDatabase.instance.db),
        dnd: settings.notify.dnd);
  } catch (e) {
    AppLog.add('启动提醒重排失败（小结/体检）：$e', level: LhLevel.warn);
  }

  // 4.4b) V1.57 E 批：垃圾箱到期自动清理（保留期读「记录管理 · 通用」档位，
  //       0＝不清理）。只真 DELETE 已过期的软删条目，失败不阻断启动。
  try {
    final n = await TodoDao(AppDatabase.instance.db)
        .purgeExpired(settings.trashKeepDays);
    AppLog.addKey(
        '垃圾箱自动清理：删除 $n 条 · 保留期 ${settings.trashKeepDays > 0 ? '${settings.trashKeepDays} 天' : '不清理'}');
  } catch (e) {
    AppLog.add('垃圾箱自动清理失败：$e', level: LhLevel.warn);
  }

  // 4.5) R5b：note_images 存量一次性收编为 SHA256 内容寻址命名（幂等标志，
  //    失败不阻断启动——迁移器内部逐文件 try，整体异常只 warn）。
  if (prefs.getBool('media.hashMigrate.v1') != true) {
    try {
      await MediaHashMigrator(
        db: AppDatabase.instance.db,
        noteImagesDir: p.join(docsPath, 'note_images'),
      ).migrate();
      await prefs.setBool('media.hashMigrate.v1', true);
    } catch (e) {
      AppLog.add('图片哈希迁移整体失败（下次启动重试）：$e',
          level: LhLevel.warn);
    }
  }

  // 5) V1.41 Task 10/18 组合根：备份服务实例（Task 18 同步快照复用同一实例，
  //    故提到 runApp 之前构造）。
  final backup = BackupService(
    exportDir: () => p.join(docsPath, 'backup'),
    db: () => AppDatabase.instance.open(),
    closeDb: AppDatabase.instance.close,
    attachDirs: [
      p.join(docsPath, 'note_images'),
      p.join(docsPath, 'book_covers'),
      p.join(docsPath, 'exports'),
      p.join(docsPath, 'share'),
    ],
    attachRootDirs: [docsPath],
    prefs: prefs,
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
        // AI 批：默认提示词包 + Key 保险箱组合根装配（测试注入内存版）。
        aiPromptPackProvider.overrideWithValue(aiPack),
        aiKeyVaultProvider.overrideWithValue(AiKeyVault()),
        // V1.41 Task 10：备份服务组合根装配。attachDirs 取证 = 应用文档目录下
        // 实际落盘的附件子目录（note_images: shared/image_attach 日记/笔记插图；
        // book_covers: read isbn_enrich 封面；exports: journal note_sheets 导出；
        // share: read 书摘/书单导出）。attachRootDirs = documents 根目录浅扫
        // 白名单（评审修复：记账导出 lifeharness_ledger.csv/.json 直落根目录，
        // ledger_export_page/ledger_export）。closeDb 走 AppDatabase.instance
        // .close（评审 Critical 修复：close 后置空 _db 缓存，db() 重开才拿到
        // 可用新连接，而非裸 Database.close 留下的死句柄）。
        backupServiceProvider.overrideWithValue(backup),
        // R5c：图片存储清理扫描器（媒体根 = note_images / book_covers）。
        mediaScannerProvider.overrideWithValue(MediaUsageScanner(
          db: AppDatabase.instance.db,
          mediaDirs: [
            p.join(docsPath, 'note_images'),
            p.join(docsPath, 'book_covers'),
          ],
        )),
        // V1.41 Task 18：同步快照服务组合根装配（R2 白名单先例照上方
        // backupServiceProvider——core 不得 import features，careExcluded
        // 在此接线 CareRepository；快照复用 BackupService 同一实例，
        // 「快照 = 备份文件」口径）。
        snapshotServiceProvider.overrideWithValue(SnapshotService(
          backup: backup,
          prefs: prefs,
          docsDir: () => docsPath,
          careExcluded: () => CareRepository(AppDatabase.instance.db).syncExcluded(),
          // R3②：活库文件（mtime 用于「无新写入则复用快照」判定，close 后
          // openedPath 仍保留）。
          dbFile: () {
            final path = AppDatabase.instance.openedPath;
            return path == null ? null : File(path);
          },
          // R5a：附件目录以文件级增量并入差异集（图片不再随快照包重传）。
          attachRoots: [
            AttachRoot(
                cloudName: 'note_images',
                localDir: p.join(docsPath, 'note_images')),
            AttachRoot(
                cloudName: 'book_covers',
                localDir: p.join(docsPath, 'book_covers')),
          ],
        )),
      ],
      child: const LifeHarnessApp(),
    ),
  );
}
