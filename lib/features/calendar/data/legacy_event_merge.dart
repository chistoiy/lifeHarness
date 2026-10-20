import 'package:sqflite/sqflite.dart';
import '../../../core/database/schema.dart';
import '../domain/time_block.dart';

/// 旧 events 行的最小解析投影（仅供搬移换算；CalEvent 类已随 events 面退役删除，
/// 这里不复活领域模型——只读行字段，映射口径与原 CalEvent.fromRow 一致）。
class _LegacyEventRow {
  _LegacyEventRow(Map<String, Object?> r)
      : id = r['id'] as int,
        title = r['title'] as String,
        start = DateTime.fromMillisecondsSinceEpoch(r['start_at'] as int),
        end = r['end_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['end_at'] as int),
        allDay = (r['all_day'] as int? ?? 0) == 1,
        // 0=planning 1=active 2=done（原 EventStatus 序）。
        status = (r['status'] as int? ?? 0).clamp(0, 2),
        durationMin = r['duration_min'] as int?,
        catId = r['cat_id'] as int?;

  final int id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final int status;
  final int? durationMin;
  final int? catId;
}

/// B10（时间模块·产品裁决 2026-10-13「搬，旧表不维护了」）：旧 `events` 表
/// **一次性并入 `time_blocks`** 后退役——编辑动作自此改写为时间块，**禁新写 events**。
///
/// ## 为什么在 Dart 层搬而不是 SQL 迁移
/// blocks.day=本地当日 00:00 的 epoch ms（ADR D13）。SQLite 侧把 epoch ms 折算
/// 本地日界要靠 `localtime` 修饰符再反解析，时区/DST 坑多（本仓 6109/时区前科）；
/// Dart 侧直接复用 `DateTime` 本地历法，与 endActive 的 L4 回填同一套换算。
///
/// ## 幂等护栏＝搬完删行，免标志位
/// 事务内「读 events→插 blocks→DELETE events」。搬完旧表恒空：重复触发、
/// 双入口竞争（static 串行）、甚至恢复旧备份后再进模块都会自然重跑或空跑，
/// 不需要任何「已搬」标记位（标记位若存 prefs，备份回滚后会漏搬）。
///
/// ## 换算口径
/// - planning：有 end 用计划窗；无 end 兜底 60 分钟（轴视图旧展示同口径）。
/// - active：收口至当前时刻（C7 reconcile 同语义，但不要求计时块在跑），
///   之后事件侧再无 active 行。
/// - done：end_at ?? start+duration_min ?? start+60。
/// - 跨天（B8 同款记账）：按日拆段——首日 start..1440、整日 0..1440、末日 0..end。
/// - all_day：每日 0..1440 全天段。
/// - category：cat_id→categories.name，未命中落 kCatOther；note=title。
/// - source='event'、event_id 保留原 id（审计可溯）。
/// - **不清重叠手动标记**（endActive 的 L4 回填会覆盖，这里是历史数据搬家，
///   用户手动标记与旧日程并存属合法事实，不裁剪）。
class LegacyEventMerge {
  LegacyEventMerge._();

  /// 双入口（现仅日历页 init）未来扩多处时防并发双插。
  static Future<void>? _inflight;

  /// 返回搬移的事件条数（空表=0，无副作用）。
  static Future<int> run(Database db) => _inflight = _run(db, _inflight);

  static Future<int> _run(Database db, Future<void>? prev) async {
    await prev;
    final rows = await db.query(DbSchema.tEvents, orderBy: 'start_at ASC');
    if (rows.isEmpty) return 0;
    final events = rows.map(_LegacyEventRow.new).toList();

    // cat_id→name 映射（blocks 的 category 列存名称做展示兜底）。
    final catRows = await db.query(DbSchema.tCategories);
    final catNameById = <int, String>{
      for (final r in catRows) r['id'] as int: (r['name'] as String?) ?? kCatOther,
    };

    var moved = 0;
    await db.transaction((txn) async {
      final now = DateTime.now();
      for (final e in events) {
        // active(status=1) 收口：结束时刻=当前（跨 0 点照跨天拆段处理）。
        final end = e.status == 1
            ? now
            : (e.end ??
                (e.durationMin != null
                    ? e.start.add(Duration(minutes: e.durationMin!))
                    : e.start.add(const Duration(hours: 1))));
        if (!end.isAfter(e.start)) continue; // 零长/负窗（脏行）不搬。

        final start0 = DateTime(e.start.year, e.start.month, e.start.day);
        final end0 = DateTime(end.year, end.month, end.day);
        final dayCount = end0.difference(start0).inDays + 1;
        final sMin0 = e.start.hour * 60 + e.start.minute;
        final eMin0 = end.hour * 60 + end.minute;

        for (var i = 0; i < dayCount; i++) {
          final day = start0.add(Duration(days: i));
          final int sMin;
          final int eMin;
          if (e.allDay) {
            sMin = 0;
            eMin = 1440;
          } else if (i == 0 && dayCount == 1) {
            sMin = sMin0;
            eMin = eMin0 == 0 ? 1440 : eMin0; // 末日整点 00:00 视为跨到当日末。
          } else if (i == 0) {
            sMin = sMin0;
            eMin = 1440;
          } else if (i == dayCount - 1) {
            if (eMin0 <= 0) continue; // 末日 00:00 整＝前一日已收满。
            sMin = 0;
            eMin = eMin0;
          } else {
            sMin = 0;
            eMin = 1440;
          }
          if (eMin <= sMin) continue;
          await txn.insert(DbSchema.tTimeBlocks, TimeBlock(
            day: day,
            startMin: sMin,
            endMin: eMin,
            catId: e.catId,
            catName: e.catId == null ? kCatOther : (catNameById[e.catId!] ?? kCatOther),
            note: e.title,
            source: kSrcEvent,
            eventId: e.id,
          ).toRow());
          moved++;
        }
      }
      // 护栏闭环：搬完删行（事务内，任一步失败整体回滚，数据不丢）。
      await txn.delete(DbSchema.tEvents);
    });
    return moved;
  }
}
