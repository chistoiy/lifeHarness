import 'dart:async';
import 'dart:io' show File;
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/ai/ai_providers.dart';
import 'core/ai/ai_vault.dart';
import 'core/backup/backup_files.dart';
import 'core/backup/backup_service.dart';
import 'core/backup/db_overview.dart';
import 'core/backup/lh_bak.dart' show LhBak;
import 'shared/linkage/backup_projection.dart' show buildNoteProjectionMembers;
import 'shared/linkage/widget_checkin_mounts.dart' show runWidgetHabitCheckin;
import 'shared/linkage/widget_quick_add_mounts.dart'
    show runWidgetQuickAddApp;
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
import 'features/health/data/health_settings.dart';
import 'features/ledger/data/ledger_repository.dart';
import 'features/ledger/presentation/ledger_notify.dart';
import 'features/read/data/isbn_enrich.dart';
import 'features/read/data/read_repository.dart';
import 'features/read/domain/s2t_map.dart';
import 'features/todo/data/todo_dao.dart';
import 'features/todo/domain/todo.dart';
import 'shared/trash/trash_repository.dart';

/// 小组件打卡的**后台 isolate 入口**（批A 交互闭环层·原生
/// `HabitCheckReceiver` 起无头引擎时跑这里，`main()` 不执行）。
///
/// ## 为什么必须是根库顶层函数
///
/// 原生侧 `DartExecutor.DartEntrypoint(bundlePath, "widgetBackgroundMain")`
/// 按**函数名**在根库解析；`@pragma('vm:entry-point')` 告诉编译器别把它当死
/// 代码摇掉（release 树摇后全仓无引用点，不加 pragma 上线即「点了没反应」）。
///
/// ## B8 纪律：不初始化任何 UI 依赖
///
/// 本 isolate 没有 FlutterView/WidgetsBinding——只用方法通道调
/// [runWidgetHabitCheckin]（开库→写库→推习惯三键→收敛重绘）。失败由原生
/// 回滚显示态并入队，App 启动排空兜底。
@pragma('vm:entry-point')
void widgetBackgroundMain() {
  const channel = MethodChannel(kWidgetBgChannel);
  channel.setMethodCallHandler((call) async {
    if (call.method == kWidgetBgCheckin) {
      final args = call.arguments;
      final name = args is Map ? args['habit'] as String? : null;
      // 计数型（批D）：本次提交量。有值 ⇒ 绝对量写（步进行中间格那一刻的值）；
      // 无值 ⇒ 老口径（布尔打卡／加一档）。
      final raw = args is Map ? args['value'] : null;
      return runWidgetHabitCheckin(
        name ?? '',
        amount: raw is num ? raw.toDouble() : null,
      );
    }
    throw MissingPluginException('No handler for ${call.method} on $kWidgetBgChannel');
  });
}

/// 4×1「记一笔」弹窗的 **UI 入口点**（工单 §7.1 · 原生 `QuickAddActivity`
/// 起独立引擎时按函数名解析到这里）。
///
/// 与 [widgetBackgroundMain] 的区别：那个是**无头** isolate（不初始化 UI），
/// 这个是**有界面**的（跑 [runWidgetQuickAddApp] 起一棵只含记账表单的
/// widget 树）。两者都用 `@pragma('vm:entry-point')` 保命——release 树摇后
/// 全仓无静态引用，不加就被摇掉，真机表现是「点了没反应」。
@pragma('vm:entry-point')
void widgetQuickAddMain() => runWidgetQuickAddApp();

/// 后台 isolate 通道名（原生 `HabitCheckReceiver` 逐字一致·守护测试交叉核对）。
const String kWidgetBgChannel = 'lh/widget_bg';

/// 后台 isolate 方法名（打卡一站式：写库＋快照收敛）。
const String kWidgetBgCheckin = 'habitCheckin';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 0) 三处全局错误捕获先行挂上（R1 启动即记，先于一切初始化）。
  installGlobalErrorLogging();

  // R3-6 简繁显示层：词表随启动预热一次（126KB JSON，读盘＋建表约毫秒级）。
  // 不挂进阅读器装载链——rootBundle 走资源通道，widget 测试的 FakeAsync 下
  // 永不返回，await 会把整组阅读器用例挂死；这里 fire-and-forget，
  // 阅读器真正用到时表早已就位（冷启动首屏最坏是闪一下原文，随后重建）。
  unawaited(S2t.ensureLoaded());

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

  // 4.4b) V1.57 E 批立、V1.60 扩表：回收站到期自动清理（保留期读「记录管理 · 通用」
  //       档位，0＝不清理）。范围从「仅待办」扩到全部六类纳入党表（待办/笔记/
  //       习惯/书籍/划线书摘/书单），只真 DELETE 已过期的软删条目，失败不阻断启动。
  try {
    final per = await TrashRepository(AppDatabase.instance.db)
        .purgeExpiredByTable(settings.trashKeepDays);
    final n = per.values.fold(0, (a, b) => a + b);
    final detail = per.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    AppLog.addKey(
        '垃圾箱自动清理：删除 $n 条 · 保留期 ${settings.trashKeepDays > 0 ? '${settings.trashKeepDays} 天' : '不清理'}'
        '${detail.isEmpty ? '' : ' · 明细 $detail'}');
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
  //    轮6 ANR 根治：zip 打包/附件收集/加密整体挪进后台 isolate（默认内联是
  //    测试路径），UI isolate 不再被压缩卡死十几秒 → 不再触发 bg ANR 杀进程。
  LhBak.packRunner = Isolate.run;
  // V1.66 批2：md 投影钩子组合根装配（core 不碰 features，投影器在
  // shared/linkage；notes/config 可读成员随 withProjection 开关入包）。
  BackupService.projectionHook = buildNoteProjectionMembers;  final backupExportDir = p.join(docsPath, 'backup');
  final backup = BackupService(
    exportDir: () => backupExportDir,
    db: () => AppDatabase.instance.open(),
    closeDb: AppDatabase.instance.close,
    // 批6b 组合根接线：健康的「随本地备份」开关（core 不得 import features，
    // 形状照下方 SnapshotService 的 careExcluded）。关掉时 health_* 十四表整模块
    // 不进 .lhbak；只管本地包，同步快照那条腿自己传 applyHealthExclusion:false。
    healthExcluded: () => !HealthSettings(prefs).includeInBackup(),
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
        // B-1：备份文件屏的扫描器——只扫 exports/ 浅层（同步下载与本地导出都落这里），
        // 来源角标读「云端下载台账」（SyncOrchestrator 落盘成功时记名）。
        // 真机 6080：两个落点都要扫——`backup/`＝本机导出与恢复前自动，
        // `exports/`＝云同步下载落点；只扫后者会让本屏看不见自己导出的包。
        backupFileScannerProvider.overrideWithValue(
            BackupFileScanner(
                dirs: [backupExportDir, p.join(docsPath, 'exports')],
                prefs: prefs)),
        // B-4 数据库概览扫描器（工单 §7-3）：活库直连，只数行不取字节。
        dbOverviewScannerProvider
            .overrideWithValue(DbOverviewScanner(db: AppDatabase.instance.db)),
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
