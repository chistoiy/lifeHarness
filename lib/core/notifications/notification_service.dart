import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 通知与定时提醒基建（M0末A）。
///
/// 渠道：reminders（待办/日程精确提醒）· daily（收集箱整理/日记复盘每日节律）。
/// 调度用 inexactAllowWhileIdle（免特殊权限；分钟级偏差可接受，正式精确闹钟随发布工程评估）。
/// 测试/无平台通道环境全部静默降级（[ready]=false 即 no-op），不影响单测。
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  /// 平台侧初始化成功才允许调度（单测/桌面为 false）。
  static bool ready = false;

  /// 待办提醒总开关（NotifySettings.todoEvent 镜像；关闭时排程一律跳过）。
  static bool todoEnabled = true;

  /// 固定 id 段：每日节律用保留区，待办提醒用 todo.id（<100 万）。
  static const int inboxDailyId = 900001;
  static const int diaryDailyId = 900002;
  static const int readDailyId = 900003;

  static const _remindersCh = AndroidNotificationDetails(
    'reminders',
    '任务提醒',
    channelDescription: '待办与日程的定点提醒',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _dailyCh = AndroidNotificationDetails(
    'daily',
    '每日节律',
    channelDescription: '收集箱整理与日记复盘提醒',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static Future<void> init() async {
    if (ready || kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
      } catch (_) {
        // 拿不到 IANA 时区名时保持 UTC 回退（提醒时间可能偏移，功能不崩）。
      }
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      ready = await plugin.initialize(settings) ?? false;
    } catch (_) {
      ready = false;
    }
  }

  /// Android 13+ 运行时通知权限（用户拒绝时返回 false，调用方给提示）。
  static Future<bool> ensurePermission() async {
    if (!ready) return false;
    final android =
        plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static Future<void> cancel(int id) async {
    if (!ready) return;
    await plugin.cancel(id);
  }

  /// 待办 remind_at 排程（id=todo.id；过期时间不排）。
  static Future<void> scheduleTodo({
    required int id,
    required String title,
    DateTime? remindAt,
  }) async {
    if (!ready) return;
    await plugin.cancel(id);
    if (!todoEnabled || remindAt == null) return;
    final when = tz.TZDateTime.from(remindAt, tz.local);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await plugin.zonedSchedule(
      id,
      '任务提醒',
      title,
      when,
      const NotificationDetails(android: _remindersCh),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'todo:$id',
    );
  }

  /// 同步每日节律提醒（收集箱 21:00 固定 + 日记复盘可配时间）。
  static Future<void> syncDaily({
    required bool inboxClean,
    required bool diaryReview,
    required String diaryTime,
  }) async {
    if (!ready) return;
    await _syncDailyAt(inboxDailyId, inboxClean, '21:00', '收集箱整理',
        '今天还有未整理的想法 · 每条 10 秒分流完成');
    await _syncDailyAt(diaryDailyId, diaryReview, diaryTime, '日记复盘',
        '到了回顾今天的时间，写几句吧');
  }

  /// 阅读晚间补记提醒（计划 §6 read.dailyQ · 21:30 · 默认开）。
  static Future<void> syncReadDaily({required bool on}) async {
    if (!ready) return;
    await _syncDailyAt(readDailyId, on, '21:30', '阅读补记',
        '今天还没有计时 · 想起一段也值得记一条摘录');
  }

  static Future<void> _syncDailyAt(
      int id, bool on, String hhmm, String title, String body) async {
    await plugin.cancel(id);
    if (!on) return;
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 21;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await plugin.zonedSchedule(
      id,
      title,
      body,
      next,
      const NotificationDetails(android: _dailyCh),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
