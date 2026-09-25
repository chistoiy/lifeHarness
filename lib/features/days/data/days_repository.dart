import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/day_models.dart';
import '../domain/lunar.dart';

/// 日子模块仓储（仿 care/ledger 范式：单 Repository 直持 Database，loadAll 全域快照）。
///
/// 口径：
/// - 删日子＝彻底删除（入口仅在归档态详情，二次确认）；preps 同事务级联；
/// - 提醒中心派生条目（sub/warranty）按 source_key upsert 随源刷新，
///   源到期日推进时重置 handled（进入新周期）；手动证件条目独立可删；
/// - 「改提醒日」只写 snooze 列，不改原始 due_date（审计留痕）；
/// - 「已处理」静默归档保留行与 handled_at（审计）。
class DaysRepository {
  DaysRepository(this.db);

  final Database db;

  // ==================== 加载 ====================

  Future<DaysData> loadAll({DateTime? now}) async {
    await syncDerived(now: now);
    final dayRows = await db
        .query(DbSchema.tDays, orderBy: 'pinned DESC, id ASC');
    final prepRows = await db.query(DbSchema.tDayPreps, orderBy: 'id ASC');
    final remRows =
        await db.query(DbSchema.tReminderItems, orderBy: 'due_date ASC, id ASC');
    final preps = prepRows.map(DayPrep.fromRow).toList();
    return DaysData(
      days: dayRows
          .map((r) => _dayFromRow(r, preps.where((p) => p.dayId == r['id']).toList()))
          .toList(),
      reminders: remRows.map(ReminderItem.fromRow).toList(),
    );
  }

  DayEntry _dayFromRow(Map<String, Object?> r, List<DayPrep> preps) => DayEntry(
        id: r['id'] as int,
        title: r['title'] as String,
        iconId: r['icon'] as String,
        colorKey: r['color'] as String,
        category: r['category'] as String,
        repeat: DayRepeat.of(r['rep_mode'] as String),
        targetDate: r['target_date'] == null ? null : _ymd(r['target_date'] as String),
        lunarMonth: r['lunar_month'] as int?,
        lunarDay: r['lunar_day'] as int?,
        monthDay: r['month_day'] as int?,
        remOffsets: (jsonDecode(r['rem_offsets'] as String? ?? '[7,0]') as List)
            .map((e) => e as int)
            .toList(),
        note: r['note'] as String?,
        pinned: (r['pinned'] as int? ?? 0) == 1,
        archived: (r['archived'] as int? ?? 0) == 1,
        linkDiary: (r['link_diary'] as int? ?? 1) == 1,
        prepToTodo: (r['prep_to_todo'] as int? ?? 1) == 1,
        preps: preps,
      );

  static DateTime _ymd(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static String _d(DateTime d) => fmtDateYmd(d);

  Map<String, Object?> _dayToRow(DayEntry d, int ts) => {
        'title': d.title,
        'icon': d.iconId,
        'color': d.colorKey,
        'category': d.category,
        'rep_mode': d.repeat.wire,
        'target_date': d.targetDate == null ? null : _d(d.targetDate!),
        'lunar_month': d.lunarMonth,
        'lunar_day': d.lunarDay,
        'month_day': d.monthDay,
        'rem_offsets': jsonEncode(d.remOffsets),
        'note': d.note,
        'pinned': d.pinned ? 1 : 0,
        'archived': d.archived ? 1 : 0,
        'link_diary': d.linkDiary ? 1 : 0,
        'prep_to_todo': d.prepToTodo ? 1 : 0,
        'updated_at': ts,
      };

  // ==================== 日子 CRUD ====================

  /// 新建（含准备事项，单事务）。返回新 id。
  Future<int> addDay(DayEntry d) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final id = await txn.insert(DbSchema.tDays, {..._dayToRow(d, ts), 'created_at': ts});
      for (final p in d.preps) {
        await txn.insert(DbSchema.tDayPreps,
            {'day_id': id, 'label': p.text, 'done': p.done ? 1 : 0, 'todo_id': p.todoId});
      }
      return id;
    });
  }

  /// 全量覆盖更新（准备事项整组替换：删旧插新，未变条目按文本保 todo_id 链）。
  Future<void> updateDay(DayEntry d) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update(DbSchema.tDays, _dayToRow(d, ts),
          where: 'id = ?', whereArgs: [d.id]);
      final oldRows = await txn.query(DbSchema.tDayPreps,
          where: 'day_id = ?', whereArgs: [d.id]);
      final oldTodoByLabel = <String, int?>{
        for (final r in oldRows) r['label'] as String: r['todo_id'] as int?
      };
      await txn.delete(DbSchema.tDayPreps, where: 'day_id = ?', whereArgs: [d.id]);
      for (final p in d.preps) {
        await txn.insert(DbSchema.tDayPreps, {
          'day_id': d.id,
          'label': p.text,
          'done': p.done ? 1 : 0,
          'todo_id': p.todoId ?? oldTodoByLabel[p.text],
        });
      }
    });
  }

  Future<void> setPinned(int id, bool pinned) => db.update(
      DbSchema.tDays, {'pinned': pinned ? 1 : 0},
      where: 'id = ?', whereArgs: [id]);

  /// 归档↔恢复（归档解除提醒由 presentation 层重排通知完成）。
  Future<void> setArchived(int id, bool archived) => db.update(
      DbSchema.tDays,
      {'archived': archived ? 1 : 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id]);

  /// 彻底删除（仅归档态入口；preps 级联）。
  Future<void> purgeDay(int id) => db.transaction((txn) async {
        await txn.delete(DbSchema.tDayPreps, where: 'day_id = ?', whereArgs: [id]);
        await txn.delete(DbSchema.tDays, where: 'id = ?', whereArgs: [id]);
      });

  // ==================== 准备事项（详情页就地勾选） ====================

  Future<void> togglePrep(int prepId, bool done) => db.update(
      DbSchema.tDayPreps, {'done': done ? 1 : 0},
      where: 'id = ?', whereArgs: [prepId]);

  Future<void> setPrepTodo(int prepId, int todoId) => db.update(
      DbSchema.tDayPreps, {'todo_id': todoId},
      where: 'id = ?', whereArgs: [prepId]);

  // ==================== 提醒中心 ====================

  /// 手动建档证件提醒。
  Future<int> addCertReminder({
    required String title,
    required DateTime due,
    String? tip,
    String iconId = 'id',
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return db.insert(DbSchema.tReminderItems, {
      'kind': 'cert',
      'title': title,
      'icon': iconId,
      'due_date': _d(due),
      'tip': tip,
      'created_at': ts,
      'updated_at': ts,
    });
  }

  Future<void> removeReminder(int id) =>
      db.delete(DbSchema.tReminderItems, where: 'id = ?', whereArgs: [id]);

  /// 改提醒日（就地三滚轮落点：日期+时）。
  Future<void> setSnooze(int id, DateTime date, int hour) => db.update(
      DbSchema.tReminderItems,
      {'snooze_date': _d(date), 'snooze_hour': hour,
       'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id]);

  Future<void> clearSnooze(int id) => db.update(DbSchema.tReminderItems,
      {'snooze_date': null, 'snooze_hour': null},
      where: 'id = ?', whereArgs: [id]);

  /// 已处理＝静默归档保留审计（派生条目在源推进前不再出现在待关注）。
  Future<void> markHandled(int id) => db.update(DbSchema.tReminderItems, {
        'handled': 1,
        'handled_at': DateTime.now().millisecondsSinceEpoch,
      }, where: 'id = ?', whereArgs: [id]);

  // ==================== 派生同步（订阅←记账周期账单 · 保修←物品档案） ====================

  /// 每次 loadAll 前刷新派生条目：
  /// - sub：ledger_recur active=1 逐条 upsert（source_key=`recur:周期账单id`，meta 带金额/频率）；
  /// - warranty：批2 item_profiles 建表后自动生效（sqlite_master 探测，未建表静默跳过）；
  /// - 源消失（周期账单停用/删除）→ 派生行连带删除。
  Future<void> syncDerived({DateTime? now}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // —— 订阅 ← ledger_recur ——
    List<Map<String, Object?>> recurs;
    try {
      recurs = await db.rawQuery(
          'SELECT id, name, amt, freq, next_date FROM ${DbSchema.tLedgerRecur} WHERE active = 1');
    } catch (_) {
      recurs = const [];
    }
    final keepSub = <String>{};
    for (final r in recurs) {
      final key = 'recur:${r['id']}';
      keepSub.add(key);
      final due = (r['next_date'] as String?) ?? _d((now ?? DateTime.now()).add(const Duration(days: 7)));
      final meta = '¥${r['amt']} / ${r['freq']} · 记账周期账单自动生成';
      final existing = await db.query(DbSchema.tReminderItems,
          where: 'source_key = ?', whereArgs: [key], limit: 1);
      if (existing.isEmpty) {
        await db.insert(DbSchema.tReminderItems, {
          'kind': 'sub',
          'title': r['name'],
          'icon': 'sub',
          'due_date': due,
          'meta': meta,
          'source_key': key,
          'created_at': ts,
          'updated_at': ts,
        });
      } else {
        final row = existing.first;
        final advanced = (row['due_date'] as String) != due;
        await db.update(DbSchema.tReminderItems, {
          'title': r['name'],
          'due_date': due,
          'meta': meta,
          // 源到期日推进＝新周期，撤销「已处理」与改期
          if (advanced) ...{'handled': 0, 'handled_at': null, 'snooze_date': null, 'snooze_hour': null},
          'updated_at': ts,
        }, where: 'id = ?', whereArgs: [row['id']]);
      }
    }
    if (keepSub.isEmpty) {
      await db.delete(DbSchema.tReminderItems,
          where: "kind = 'sub' AND source_key IS NOT NULL");
    } else {
      await db.delete(DbSchema.tReminderItems,
          where:
              "kind = 'sub' AND source_key NOT IN (${List.filled(keepSub.length, '?').join(',')})",
          whereArgs: keepSub.toList());
    }
    // —— 保修 ← item_profiles（批2 建表后生效） ——
    final hasItemTable = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='item_profiles'")
        .then((v) => v.isNotEmpty);
    if (hasItemTable) {
      await _syncWarranty(ts);
    }
  }

  Future<void> _syncWarranty(int ts) async {
    List<Map<String, Object?>> items;
    try {
      items = await db.rawQuery(
          'SELECT id, name, warranty FROM item_profiles WHERE warranty IS NOT NULL AND warranty <> \'\'');
    } catch (_) {
      return;
    }
    final keep = <String>{};
    for (final it in items) {
      final key = 'item:${it['id']}';
      keep.add(key);
      final due = it['warranty'] as String;
      final meta = '物品档案汇入';
      final existing = await db.query(DbSchema.tReminderItems,
          where: 'source_key = ?', whereArgs: [key], limit: 1);
      if (existing.isEmpty) {
        await db.insert(DbSchema.tReminderItems, {
          'kind': 'warranty',
          'title': '${it['name']} 保修',
          'icon': 'warranty',
          'due_date': due,
          'meta': meta,
          'source_key': key,
          'created_at': ts,
          'updated_at': ts,
        });
      } else {
        final row = existing.first;
        final advanced = (row['due_date'] as String) != due;
        await db.update(DbSchema.tReminderItems, {
          'title': '${it['name']} 保修',
          'due_date': due,
          'meta': meta,
          if (advanced) ...{'handled': 0, 'handled_at': null, 'snooze_date': null, 'snooze_hour': null},
          'updated_at': ts,
        }, where: 'id = ?', whereArgs: [row['id']]);
      }
    }
    if (keep.isEmpty) {
      await db.delete(DbSchema.tReminderItems,
          where: "kind = 'warranty' AND source_key IS NOT NULL");
    } else {
      await db.delete(DbSchema.tReminderItems,
          where:
              "kind = 'warranty' AND source_key NOT IN (${List.filled(keep.length, '?').join(',')})",
          whereArgs: keep.toList());
    }
  }

  // ==================== 去年今日（联动 L5 · 只读日记） ====================

  /// 与 (month, day) 同号的历史年份日记（不含今年）。
  Future<List<DiaryEcho>> anniversaryEntries(int month, int day, int beforeYear) async {
    final rows = await db.rawQuery(
        'SELECT id, entry_date, mood, content FROM ${DbSchema.tJournal} ORDER BY entry_date DESC');
    final out = <DiaryEcho>[];
    for (final r in rows) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['entry_date'] as int);
      if (d.year < beforeYear && d.month == month && d.day == day) {
        out.add(DiaryEcho(
          date: DateTime(d.year, d.month, d.day),
          text: (r['content'] as String? ?? '').trim(),
          mood: r['mood'] as int?,
        ));
      }
    }
    return out;
  }

  /// 某日子「每年此日回看往年记录」：锚点发生的月/日号历史日记。
  Future<List<DiaryEcho>> diaryForDay(DayEntry d, DateTime now) async {
    final occ = nextOccurrenceMonthDay(d, now);
    return anniversaryEntries(occ.$1, occ.$2, now.year);
  }

  /// 日子的发生日月/日号（今年口径；lunar 按今年换算，monthly 直接用日号）。
  (int, int) nextOccurrenceMonthDay(DayEntry d, DateTime now) {
    switch (d.repeat) {
      case DayRepeat.once:
      case DayRepeat.solarYear:
        return (d.targetDate!.month, d.targetDate!.day);
      case DayRepeat.lunar:
        final solar = lunarToSolarInYear(now.year, d.lunarMonth!, d.lunarDay!) ??
            lunarToSolarInYear(now.year + 1, d.lunarMonth!, d.lunarDay!);
        return (solar!.month, solar.day);
      case DayRepeat.monthly:
        return (now.month, d.monthDay!);
    }
  }
}

/// 日记回响（去年今日/日子回看只读投影）。
class DiaryEcho {
  const DiaryEcho({required this.date, required this.text, this.mood});
  final DateTime date;
  final String text;
  final int? mood;
}
