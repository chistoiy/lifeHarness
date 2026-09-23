import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_dict.dart';
import '../domain/habit_entry.dart';

/// 习惯模块仓储（习惯计划 §2.1/§4 批1）。
///
/// 口径：
/// - habit_entries 按日流水是唯一真源，UNIQUE(habit_id,day) 同日二次写=改值；
/// - 每次流水写入后全量重算 streak/best 回写缓存列（§2.3 导入一致性同法）；
/// - 时钟防护（需求八章）：拒写未来日，`habit.maxSeenDay` 记录观测水位线。
class HabitRepository {
  HabitRepository(this.db);

  final Database db;
  final Random _rng = Random();

  String _newId() =>
      'h${DateTime.now().microsecondsSinceEpoch}${_rng.nextInt(9999)}';

  // ---- habits ----

  /// 未删除习惯（含归档；arch=true 只取归档）。
  Future<List<Habit>> allHabits() async {
    final rows = await db.query(
      DbSchema.tHabits,
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );
    final subs = await db.query(DbSchema.tHabitSubs, orderBy: 'sort ASC');
    final byHabit = <String, List<HabitSub>>{};
    for (final r in subs) {
      final s = HabitSub.fromRow(r);
      byHabit.putIfAbsent(r['habit_id'] as String, () => []).add(s);
    }
    return [
      for (final r in rows)
        Habit.fromRow(r).copyWith(subs: byHabit[r['id']] ?? const []),
    ];
  }

  Future<Habit?> habitById(String id) async {
    final rows = await db.query(
      DbSchema.tHabits,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final subs = await db.query(
      DbSchema.tHabitSubs,
      where: 'habit_id = ?',
      whereArgs: [id],
      orderBy: 'sort ASC',
    );
    return Habit.fromRow(rows.first)
        .copyWith(subs: [for (final r in subs) HabitSub.fromRow(r)]);
  }

  /// 新建/编辑（组子项整组替换写回）；返回带 id 的习惯。
  Future<Habit> saveHabit(Habit h) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var row = h.toRow();
    if (h.id.isEmpty) {
      row['id'] = _newId();
      row['created_at'] = now;
    }
    row['updated_at'] = now;
    final saved = Habit.fromRow(row).copyWith(subs: h.subs);
    await db.transaction((txn) async {
      await txn.insert(
        DbSchema.tHabits,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final id = row['id']! as String;
      await txn.delete(DbSchema.tHabitSubs, where: 'habit_id = ?', whereArgs: [id]);
      var sort = 0;
      for (final s in h.subs) {
        if (s.name.trim().isEmpty) continue;
        await txn.insert(DbSchema.tHabitSubs, {
          'habit_id': id,
          'name': s.name.trim(),
          'unit': s.unit,
          'goal': s.goal,
          'sort': sort++,
        });
      }
    });
    await recomputeStats(saved.id);
    return (await habitById(saved.id)) ?? saved;
  }

  Future<void> setArchived(String id, bool on) => db.update(
    DbSchema.tHabits,
    {
      'archived_at': on ? DateTime.now().millisecondsSinceEpoch : null,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  /// 软删除（原型口径：历史流水保留，纪录墙仍可查）。
  Future<void> deleteHabit(String id) => db.update(
    DbSchema.tHabits,
    {'deleted_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [id],
  );

  // ---- habit_entries（★ 按日流水）----

  /// 该习惯全流水 day→entry（含组子项值）。
  Future<Map<String, HabitEntry>> entriesOf(String habitId) async {
    final rows = await db.query(
      DbSchema.tHabitEntries,
      where: 'habit_id = ?',
      whereArgs: [habitId],
    );
    if (rows.isEmpty) return {};
    final ids = [for (final r in rows) r['id'] as int];
    final subs = await db.query(
      DbSchema.tHabitEntrySubs,
      where: 'entry_id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
    );
    final byEntry = <int, Map<int, double>>{};
    for (final r in subs) {
      byEntry
          .putIfAbsent(r['entry_id'] as int, () => {})
          [r['sub_id'] as int] = (r['value'] as num?)?.toDouble() ?? 0;
    }
    return {
      for (final r in rows)
        r['day'] as String: HabitEntry.fromRow(r)
            .subValuesView(byEntry[r['id']] ?? const {}),
    };
  }

  /// 全部习惯某区间流水：habitId → (day → entry)（hero/日期速览一次取齐）。
  Future<Map<String, Map<String, HabitEntry>>> entriesByHabit({
    String? fromDay,
    String? toDay,
  }) async {
    final where = <String>[], args = <Object?>[];
    if (fromDay != null) {
      where.add('day >= ?');
      args.add(fromDay);
    }
    if (toDay != null) {
      where.add('day <= ?');
      args.add(toDay);
    }
    final rows = await db.query(
      DbSchema.tHabitEntries,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
    );
    final out = <String, Map<String, HabitEntry>>{};
    final entryIds = <int, String>{};
    for (final r in rows) {
      final e = HabitEntry.fromRow(r);
      out.putIfAbsent(e.habitId, () => {})[e.day] = e;
      entryIds[r['id'] as int] = e.habitId;
    }
    if (entryIds.isEmpty) return out;
    final subs = await db.query(
      DbSchema.tHabitEntrySubs,
      where: 'entry_id IN (${entryIds.keys.map((_) => '?').join(',')})',
      whereArgs: entryIds.keys.toList(),
    );
    for (final r in subs) {
      final hab = entryIds[r['entry_id'] as int];
      final day = rows
          .firstWhere((x) => x['id'] == r['entry_id'])['day'] as String;
      final e = out[hab]![day]!;
      out[hab]![day] = e.subValuesView(
        {...e.subValues, r['sub_id'] as int: (r['value'] as num?)?.toDouble() ?? 0},
      );
    }
    return out;
  }

  /// 写一日流水（同日=改值不新增）。未来日拒写（时钟防护）。
  /// [replaceValue] 组/单值语义由调用方决定；subValues=null 表示不动子项行。
  Future<void> upsertEntry(
    String habitId, {
    required String day,
    bool? checked,
    double? value,
    bool clearValue = false,
    Map<int, double>? subValues,
    String origin = HabitEntry.oManual,
    String? checkAt,
    bool? backfilled,
    bool? frozen,
    String? note,
  }) async {
    final today = dayKey(DateTime.now());
    if (day.compareTo(today) > 0) {
      throw ArgumentError('未来日不可写入（时钟防护）：$day > $today');
    }
    await db.transaction((txn) async {
      final old = await txn.query(
        DbSchema.tHabitEntries,
        where: 'habit_id = ? AND day = ?',
        whereArgs: [habitId, day],
        limit: 1,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final prev = old.isEmpty ? null : HabitEntry.fromRow(old.first);
      final row = <String, Object?>{
        'habit_id': habitId,
        'day': day,
        'checked': (checked ?? prev?.checked ?? true) ? 1 : 0,
        'value': clearValue ? null : (value ?? prev?.value),
        'origin': origin,
        'check_at': checkAt ?? prev?.checkAt,
        'backfilled': (backfilled ?? prev?.backfilled ?? false) ? 1 : 0,
        'frozen': (frozen ?? prev?.frozen ?? false) ? 1 : 0,
        'note': note ?? prev?.note,
        'created_at': prev?.createdAt ?? now,
        'updated_at': now,
      };
      int entryId;
      if (prev != null) {
        row['id'] = prev.id;
        await txn.update(
          DbSchema.tHabitEntries,
          row,
          where: 'id = ?',
          whereArgs: [prev.id],
        );
        entryId = prev.id;
      } else {
        entryId = await txn.insert(DbSchema.tHabitEntries, row);
      }
      if (subValues != null) {
        await txn.delete(
          DbSchema.tHabitEntrySubs,
          where: 'entry_id = ?',
          whereArgs: [entryId],
        );
        subValues.forEach((subId, v) {
          txn.insert(DbSchema.tHabitEntrySubs, {
            'entry_id': entryId,
            'sub_id': subId,
            'value': v,
          });
        });
      }
    });
    await _touchWatermark(day);
    await recomputeStats(habitId);
  }

  /// 撤销某日流水（打卡按钮二次点 / 流水垃圾桶 / 补卡记录删除共用）。
  Future<void> deleteEntry(String habitId, String day) async {
    await db.transaction((txn) async {
      final old = await txn.query(
        DbSchema.tHabitEntries,
        where: 'habit_id = ? AND day = ?',
        whereArgs: [habitId, day],
        limit: 1,
      );
      if (old.isEmpty) return;
      await txn.delete(
        DbSchema.tHabitEntrySubs,
        where: 'entry_id = ?',
        whereArgs: [old.first['id']],
      );
      await txn.delete(
        DbSchema.tHabitEntries,
        where: 'id = ?',
        whereArgs: [old.first['id']],
      );
    });
    await recomputeStats(habitId);
  }

  /// 全量重算 streak/best 缓存列（§2.3 导入后自检同入口）。
  /// 返回 (streak, best)，供「重算==缓存列」一致性断言。
  Future<(int, int)> recomputeStats(String habitId) async {
    final h = await habitById(habitId);
    if (h == null) return (0, 0);
    final entries = await entriesOf(habitId);
    final today = dayKey(DateTime.now());
    final maxDay = entries.keys.fold<String>(
      '',
      (a, b) => b.compareTo(a) > 0 ? b : a,
    );
    // 回拨防护：历史流水可能晚于设备今天，best 以两者较大日为扫描右界。
    final right = maxDay.compareTo(today) > 0 ? maxDay : today;
    final streak = habitStreak(h, entries, parseDay(right));
    final best = habitBestStreak(h, entries, parseDay(right));
    await db.update(
      DbSchema.tHabits,
      {'streak': streak, 'best': best},
      where: 'id = ?',
      whereArgs: [habitId],
    );
    return (streak, best);
  }

  /// 日期水位线（需求八章）：观测到的最大自然日；只进不退。
  Future<String> maxSeenDay() async =>
      (await kv('habit.maxSeenDay')) ?? '';
  Future<void> _touchWatermark(String day) async {
    final old = await maxSeenDay();
    if (day.compareTo(old) > 0) await setKv('habit.maxSeenDay', day);
  }

  // ---- habit_dict ----

  Future<List<HabitDict>> dictOf(String kind) async {
    final rows = await db.query(
      DbSchema.tHabitDict,
      where: 'kind = ?',
      whereArgs: [kind],
      orderBy: 'sort ASC',
    );
    return [for (final r in rows) HabitDict.fromRow(r)];
  }

  Future<HabitDict?> addDict(String kind, String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final maxSort = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(MAX(sort),0) FROM ${DbSchema.tHabitDict} WHERE kind = ?',
            [kind],
          ),
        ) ??
        0;
    await db.insert(
      DbSchema.tHabitDict,
      HabitDict(kind: kind, name: n, sort: maxSort + 1).toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final rows = await db.query(
      DbSchema.tHabitDict,
      where: 'kind = ? AND name = ?',
      whereArgs: [kind, n],
      limit: 1,
    );
    return rows.isEmpty ? null : HabitDict.fromRow(rows.first);
  }

  // ---- habit.* 设置（settings 表 KV · 计划 §6）----

  Future<String?> kv(String key) async {
    final rows = await db.query(
      DbSchema.tSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setKv(String key, String value) => db.insert(
    DbSchema.tSettings,
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<int> kvInt(String key, int def) async =>
      int.tryParse(await kv(key) ?? '') ?? def;

  Future<bool> kvBool(String key, bool def) async {
    final v = await kv(key);
    return v == null ? def : v == 'true';
  }
}

extension on HabitEntry {
  HabitEntry subValuesView(Map<int, double> v) => HabitEntry(
    id: id,
    habitId: habitId,
    day: day,
    checked: checked,
    value: value,
    origin: origin,
    checkAt: checkAt,
    backfilled: backfilled,
    frozen: frozen,
    note: note,
    createdAt: createdAt,
    updatedAt: updatedAt,
    subValues: v,
  );
}
