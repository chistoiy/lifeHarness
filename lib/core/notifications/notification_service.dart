import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../logging/app_log.dart';

/// 通知与定时提醒基建（M0末A）。
///
/// 渠道：reminders（待办/日程精确提醒）· daily（收集箱整理/日记复盘每日节律）。
/// 调度用 inexactAllowWhileIdle（免特殊权限；分钟级偏差可接受，正式精确闹钟随发布工程评估）。
/// 测试/无平台通道环境全部静默降级（[ready]=false 即 no-op），不影响单测。
///
/// 日志口径（L2 批·只加日志零行为改动）：降级链与排程成败落 AppLog（来源＝通知），
/// 取消/开关关等常规静默路径不落，避免启动批量重排刷满环形缓冲。

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
      } catch (e) {
        // 拿不到 IANA 时区名时保持 UTC 回退（提醒时间可能偏移，功能不崩）。
        AppLog.add('通知时区未取得，提醒按 UTC 排程可能偏移：$e',
            level: LhLevel.warn);
      }
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      ready = await plugin.initialize(settings) ?? false;
      if (ready) {
        AppLog.addKey('通知初始化：平台就绪');
      } else {
        AppLog.add('通知初始化：插件未就绪，全部提醒降级为不排程',
            level: LhLevel.warn);
      }
    } catch (e) {
      ready = false;
      AppLog.add('通知初始化异常，提醒全部降级为不排程：$e',
          level: LhLevel.error);
    }
  }

  /// Android 13+ 运行时通知权限（用户拒绝时返回 false，调用方给提示）。
  static Future<bool> ensurePermission() async {
    if (!ready) return false;
    final android =
        plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted =
        await android?.requestNotificationsPermission() ?? false;
    if (!granted) {
      AppLog.add('通知权限未授予：提醒不会出现在通知栏', level: LhLevel.warn);
    }
    return granted;
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
    try {
      await plugin.zonedSchedule(
        id,
        '任务提醒',
        title,
        when,
        const NotificationDetails(android: _remindersCh),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'todo:$id',
      );
      AppLog.add('待办提醒已排程：#$id · ${title.length > 12 ? '${title.substring(0, 12)}…' : title} · $when');
    } catch (e) {
      AppLog.add('待办提醒排程失败：#$id $e', level: LhLevel.error);
      rethrow;
    }
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

  static const int habitNightlyId = 900004;

  /// 打卡成功即时回执（2026-10-17 产品令）。
  ///
  /// **为什么用通知而不是 toast**：打卡完成后用户常把手机放下／切去别的 App，
  /// AppToast 是 Flutter 内的 SnackBar，只在 App 前台可见——那一下的「成了没」
  /// 就没人确认。走 high 渠道系统会弹 **Heads-Up 横幅**，锁屏/别处也看得见。
  ///
  /// **独立渠道**（不复用 `reminders`）：语义是「回执」不是「提醒」，用户能在
  /// 系统设置里单独关掉打卡回执而不影响待办/日程提醒。
  static const int habitCheckedId = 900005;

  static const _habitCheckCh = AndroidNotificationDetails(
    'habit_checkin',
    '打卡回执',
    channelDescription: '打卡成功后的即时确认',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// 打卡成功横幅。`ready=false`（单测/平台未就绪）静默降级，不抛。
  static Future<void> showHabitChecked({
    required String habitName,
    required int streak,
  }) async {
    if (!ready) return;
    try {
      await plugin.show(
        habitCheckedId,
        '打卡成功',
        streak > 0 ? '$habitName · 连续 $streak 天' : habitName,
        const NotificationDetails(android: _habitCheckCh),
      );
    } catch (e) {
      // 通知失败绝不能影响打卡本身（已落库）——只留痕。
      AppLog.add('打卡成功通知展示失败：$e', level: LhLevel.error);
    }
  }

  /// 打卡成功横幅 · **退到后台后再发**（批3 · 2026-10-17 真机实锤）。
  ///
  /// 场景＝贴卡打卡：App 被 NFC 拉起 → 执行打卡 → 立刻 `moveTaskToBack` 退回桌面。
  /// 若横幅在「App 还在前台那一瞬间」发出去，系统会把它压成一条**静默的通知栏
  /// 条目**，横幅根本不弹（8161 实测：同样的打卡，8160 App 留在前台时横幅正常，
  /// 8161 加了 moveTaskToBack 后横幅消失）。
  ///
  /// 故这里等一小会儿再发——那时 App 已退到后台，横幅必然弹出。
  /// **只给「用户不在 App 里」的场景用**；App 内点打卡仍走 [showHabitChecked]（即时）。
  static Future<void> showHabitCheckedAfterBack({
    required String habitName,
    required int streak,
    Duration after = const Duration(milliseconds: 700),
  }) async {
    await Future<void>.delayed(after);
    await showHabitChecked(habitName: habitName, streak: streak);
  }

  // ---- V1.57 B 批：记账超支/月度小结 · 呵护儿保体检 ----

  static const int ledgerDigestId = 900010;
  static const int ledgerBud80Id = 900011;
  static const int ledgerBud100Id = 900012;
  static const int careCheckupId = 900020;

  /// 全局免打扰固定时段 23:00–07:00（NotifySettings.dnd 开启时生效）。
  static bool inDndWindow(DateTime t) => t.hour >= 23 || t.hour < 7;

  /// 落在免打扰窗内的时刻顺延到最近的 07:00（窗内任意时刻同点顺延）。
  static DateTime deferOutOfDnd(DateTime when) =>
      when.hour >= 23 ? DateTime(when.year, when.month, when.day + 1, 7)
      : when.hour < 7 ? DateTime(when.year, when.month, when.day, 7)
      : when;

  /// 一次性排程（月度小结/体检节点用：内容在排程时算好，重启后重排刷新）。
  /// 已过的时点不排；ready=false 静默降级。
  static Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    bool dnd = false,
  }) async {
    if (!ready) return;
    await plugin.cancel(id);
    var target = when;
    if (dnd && inDndWindow(target)) target = deferOutOfDnd(target);
    final z = tz.TZDateTime.from(target, tz.local);
    if (!z.isAfter(tz.TZDateTime.now(tz.local))) return;
    try {
      await plugin.zonedSchedule(
        id,
        title,
        body,
        z,
        const NotificationDetails(android: _remindersCh),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'fixed:$id',
      );
      AppLog.add('单次提醒已排程：$title · $z');
    } catch (e) {
      AppLog.add('单次提醒排程失败：$title（$when）$e', level: LhLevel.error);
      rethrow;
    }
  }

  /// 预算超支提示：记账保存当刻触发。免打扰开启且此刻在窗内 → 改排当日/次日 07:00；
  /// 否则立即送达。ready=false 静默降级。
  static Future<void> showBudgetAlert({
    required int id,
    required String body,
    required bool dnd,
  }) async {
    if (!ready) return;
    await plugin.cancel(id);
    final now = DateTime.now();
    if (dnd && inDndWindow(now)) {
      final z = tz.TZDateTime.from(deferOutOfDnd(now), tz.local);
      try {
        await plugin.zonedSchedule(
          id,
          '预算超支提醒',
          body,
          z,
          const NotificationDetails(android: _remindersCh),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'fixed:$id',
        );
        AppLog.add('预算超支提醒已顺延排程：$z · $body');
      } catch (e) {
        AppLog.add('预算超支提醒顺延排程失败：$e', level: LhLevel.error);
        rethrow;
      }
      return;
    }
    try {
      await plugin.show(id, '预算超支提醒', body,
          const NotificationDetails(android: _remindersCh));
      AppLog.add('预算超支提醒已送达：$body');
    } catch (e) {
      AppLog.add('预算超支提醒展示失败：$e', level: LhLevel.error);
      rethrow;
    }
  }

  // ---- 日子多级提前提醒（V1.42 模块11 · id 段 830000+） ----

  /// 提前提醒档位固定六档（编辑屏 chips），id 由 日子id×档 直算可撤销。
  static const List<int> dayOffsetSlots = [30, 15, 7, 3, 1, 0];

  static int dayNotifId(int dayId, int offset) =>
      830000 + ((dayId * 16 + offset) % 60000);

  /// 注册一条日子提醒（remindDay=触发日零点；当天 09:00 触发；已过不排）。
  static Future<void> registerDayReminder({
    required int dayId,
    required int offset,
    required String title,
    required DateTime remindDay,
  }) async {
    final id = dayNotifId(dayId, offset);
    if (!ready) return;
    await plugin.cancel(id);
    final now = tz.TZDateTime.now(tz.local);
    final when = tz.TZDateTime(
        tz.local, remindDay.year, remindDay.month, remindDay.day, 9, 0);
    if (!when.isAfter(now)) return;
    try {
      await plugin.zonedSchedule(
        id,
        '日子提醒',
        offset == 0 ? '「$title」就是今天' : '「$title」还有 $offset 天',
        when,
        const NotificationDetails(android: _remindersCh),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'day:$dayId:$offset',
      );
      AppLog.add('日子提醒已排程：「$title」提前 $offset 天 · $when');
    } catch (e) {
      AppLog.add('日子提醒排程失败：「$title」提前 $offset 天 $e',
          level: LhLevel.error);
      rethrow;
    }
  }

  static Future<void> cancelDayReminder(int dayId, int offset) async {
    if (!ready) return;
    await plugin.cancel(dayNotifId(dayId, offset));
  }

  /// 习惯文本 → 稳定通知 id（跨进程重启可取消重排；String.hashCode 不保证稳定）。
  static int habitNotifId(String habitId) {
    var h = 0x811c9dc5;
    for (final c in habitId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return 810000 + h % 80000;
  }

  /// 晚间未打卡提醒（habit.nightRemind × remindAll × dnd 三重门控后传入 on）。
  static Future<void> syncHabitNightly({
    required bool on,
    required String at,
  }) async {
    if (!ready) return;
    await _syncDailyAt(habitNightlyId, on, at, '习惯晚间打卡',
        '到点仍有习惯未打卡 · 补一个，连续就还在');
  }

  /// 逐习惯提醒注册（remindAt 有值且门控开=排程；否则取消）。
  static Future<void> registerHabitReminder({
    required String habitId,
    required String title,
    String? hhmm,
    bool enabled = true,
  }) async {
    if (!ready) return;
    final id = habitNotifId(habitId);
    await plugin.cancel(id);
    if (!enabled || hhmm == null || hhmm.isEmpty) return;
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 8;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    try {
      await plugin.zonedSchedule(
        id,
        '习惯提醒',
        '「$title」到点该打卡了',
        next,
        const NotificationDetails(android: _remindersCh),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      AppLog.add('习惯提醒已排程：$title · 每日 $hhmm');
    } catch (e) {
      AppLog.add('习惯提醒排程失败：$title（$hhmm）$e', level: LhLevel.error);
      rethrow;
    }
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
    try {
      await plugin.zonedSchedule(
        id,
        title,
        body,
        next,
        const NotificationDetails(android: _dailyCh),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      AppLog.add('每日提醒已排程：$title · $hhmm');
    } catch (e) {
      AppLog.add('每日提醒排程失败：$title（$hhmm）$e', level: LhLevel.error);
      rethrow;
    }
  }
}
