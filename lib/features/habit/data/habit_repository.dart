import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../../../core/logging/app_log.dart';
import '../domain/habit.dart';
import '../domain/habit_calc.dart';
import '../domain/habit_dict.dart';
import '../domain/habit_entry.dart';
import '../domain/habit_slip.dart';

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
    final prev = h.id.isEmpty ? null : await habitById(h.id);
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
    // 改目标/单位 → 登记生效历史（统计按该日生效目标判定，不追改历史）。
    if (prev != null && (prev.goal != h.goal || prev.unit != h.unit)) {
      await addGoalHist(
        saved.id,
        goal: h.goal,
        unit: h.unit,
        effectiveFrom: dayKey(DateTime.now()),
      );
    }
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

  // ---- V1.60 全局回收站：垃圾箱三件套 + 到期清理 ----

  /// 垃圾箱里的习惯（按删除时间倒序）。
  Future<List<Habit>> trashedHabits() async {
    final rows = await db.query(
      DbSchema.tHabits,
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC, id DESC',
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

  /// 恢复＝deleted_at 置空，回习惯列表（定义与流水原样，不新建）。
  Future<void> restoreHabit(String id) => db.update(
    DbSchema.tHabits,
    {'deleted_at': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// 彻底删除：只清定义与子项；按日流水按计划 §2.1「历史流水保留」口径留下
  /// （纪录墙与统计仍能追溯到已下架习惯的历史值）。
  Future<void> purgeHabit(String id) => db.transaction((txn) async {
    await txn.delete(DbSchema.tHabitSubs,
        where: 'habit_id = ?', whereArgs: [id]);
    await txn.delete(
        DbSchema.tHabitGoalHist, where: 'habit_id = ?', whereArgs: [id]);
    await txn.delete(DbSchema.tHabits, where: 'id = ?', whereArgs: [id]);
  });

  /// 到期自动清理：删早于保留期的垃圾箱习惯；[keepDays]<=0＝不清理。返回删除数。
  Future<int> purgeExpiredHabits(int keepDays) async {
    if (keepDays <= 0) return 0;
    final cutoff =
        DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    final ids = (await db.query(DbSchema.tHabits,
            columns: ['id'],
            where: 'deleted_at IS NOT NULL AND deleted_at < ?',
            whereArgs: [cutoff]))
        .map((r) => r['id'] as String)
        .toList();
    for (final id in ids) {
      await purgeHabit(id);
    }
    return ids.length;
  }

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
      AppLog.add('习惯未来日写入被拒（时钟防护）：$day > $today',
          level: LhLevel.warn);
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
        // 兼容 UNIQUE(habit_id,day) 冲突（如撤销宽限/覆盖补记行）：先清旧行再插。
        await txn.delete(
          DbSchema.tHabitEntries,
          where: 'habit_id = ? AND day = ?',
          whereArgs: [habitId, day],
        );
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
    final stats = await recomputeStats(habitId);
    // 一次打卡＝一条留痕，且把结算值直接写进行文：事后不必再翻流水重算。
    AppLog.addKey('习惯落账：$habitId · $day · checked=${checked ?? '不改'} '
        'value=${clearValue ? '清空' : (value ?? '不改')} · origin=$origin '
        '· 结算 streak=${stats.$1}/best=${stats.$2}');
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
    final stats = await recomputeStats(habitId);
    AppLog.addKey('习惯撤销流水：$habitId · $day · 结算 streak=${stats.$1}/best=${stats.$2}');
  }

  /// 补记流水条数（hero「补卡 N」徽标 · 原型 h.bf 计数）。
  Future<int> backfillCount(String habitId) async => Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${DbSchema.tHabitEntries} WHERE habit_id = ? AND backfilled = 1',
          [habitId],
        ),
      ) ??
      0;

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

  // ---- habit_slips（负向触发 · 批2）----

  /// 记一次触发（原型 tgSave 口径）：当日流水 checked=0（一等数据，不剔除）、
  /// 有单位时量累加；触发即断连（recomputeStats 自然归零）。
  Future<void> recordTrigger(
    String habitId, {
    required String day,
    double? amount,
    String? amountText,
    List<String> reasons = const [],
    String? note,
    String? checkAt,
  }) async {
    final prev = (await entriesOf(habitId))[day];
    await upsertEntry(
      habitId,
      day: day,
      checked: false,
      value: amount == null ? null : (prev?.value ?? 0) + amount,
      origin: HabitEntry.oManual,
      checkAt: checkAt,
      note: note,
    );
    await db.insert(DbSchema.tHabitSlips, {
      'habit_id': habitId,
      'day': day,
      'check_at': checkAt,
      'amount': amount,
      'amount_text': amountText,
      'reasons': reasons.join(','),
      'note': note,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    // 落账行已由 upsertEntry 出，这里只补「触发」这层语义（负向习惯的主数据）。
    AppLog.addKey('习惯触发登记：$habitId · $day · 量=${amount ?? amountText ?? '-'} '
        '原因=${reasons.join('/')}');
  }

  /// 触发记录（新→旧）。
  Future<List<HabitSlip>> slipsOf(String habitId) async {
    final rows = await db.query(
      DbSchema.tHabitSlips,
      where: 'habit_id = ?',
      whereArgs: [habitId],
      orderBy: 'day DESC, id DESC',
    );
    return [for (final r in rows) HabitSlip.fromRow(r)];
  }

  Future<void> deleteSlip(int slipId) => db.delete(
    DbSchema.tHabitSlips,
    where: 'id = ?',
    whereArgs: [slipId],
  );

  Future<int> slipCountIn(String habitId, String fromDay, String toDay) async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${DbSchema.tHabitSlips} WHERE habit_id = ? AND day >= ? AND day <= ?',
          [habitId, fromDay, toDay],
        ),
      ) ??
      0;

  // ---- habit_freezes（宽限卡 · 批2）----

  /// 本月剩余宽限张数（计划 §2.1：余额按 月已用 计数推导，不存列）。
  Future<int> graceLeft(Habit h) async {
    final limit = await kvInt('habit.grace', 1);
    if (limit <= 0) return 0;
    final now = DateTime.now();
    final used =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM ${DbSchema.tHabitFreezes} WHERE habit_id = ? AND day LIKE ?",
            [h.id, '${now.year}-${now.month.toString().padLeft(2, '0')}-%'],
          ),
        ) ??
        0;
    return (limit - used).clamp(0, limit);
  }

  /// 用一张宽限抵今日断签：frozen=1 只保连续、不算达成（§5-6）。
  Future<void> useFreeze(Habit h, {required String day}) async {
    await db.transaction((txn) async {
      await txn.insert(DbSchema.tHabitFreezes, {
        'habit_id': h.id,
        'day': day,
        'used_at': DateTime.now().millisecondsSinceEpoch,
        'source': 'grace',
      });
      await txn.insert(
        DbSchema.tHabitEntries,
        {
          'habit_id': h.id,
          'day': day,
          'checked': 0,
          'origin': HabitEntry.oManual,
          'backfilled': 0,
          'frozen': 1,
          'note': '使用宽限卡',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    final stats = await recomputeStats(h.id);
    AppLog.addKey('习惯用宽限抵签：${h.id} · $day · frozen 只保连续不算达成 '
        '· 结算 streak=${stats.$1}/best=${stats.$2}');
  }

  Future<List<String>> freezesOf(String habitId) async => [
    for (final r in await db.query(
      DbSchema.tHabitFreezes,
      where: 'habit_id = ?',
      whereArgs: [habitId],
      orderBy: 'day ASC',
    ))
      r['day'] as String,
  ];

  // ---- habit_goal_hist（目标生效历史 · 表先建，批4 消费）----

  /// 改目标时登记一条生效历史（goalHist 口径：不追改历史）。
  Future<void> addGoalHist(
    String habitId, {
    required double? goal,
    String? unit,
    String? subGoal,
    required String effectiveFrom,
  }) => db.insert(DbSchema.tHabitGoalHist, {
    'habit_id': habitId,
    'goal': goal,
    'unit': unit,
    'sub_goal': subGoal,
    'effective_from': effectiveFrom,
  });

  Future<List<Map<String, Object?>>> goalHistOf(String habitId) => db.query(
    DbSchema.tHabitGoalHist,
    where: 'habit_id = ?',
    whereArgs: [habitId],
    orderBy: 'effective_from ASC',
  );

  // ---- habit_dict 管理（改名事务迁移 / 引用守卫 / 迁移并删除 · 批2）----

  /// 被引用处数：分类=habits.cat；单位=habits.unit + habit_subs.unit。
  Future<int> dictRefCount(String kind, String name) async =>
      kind == HabitDict.kUnit
      ? Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT (SELECT COUNT(*) FROM ${DbSchema.tHabits} WHERE unit = ? AND deleted_at IS NULL)'
            ' + (SELECT COUNT(*) FROM ${DbSchema.tHabitSubs} WHERE unit = ?)',
            [name, name],
          ),
        ) ??
        0
      : Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${DbSchema.tHabits} WHERE cat = ? AND deleted_at IS NULL',
            [name],
          ),
        ) ??
        0;

  /// 改名：事务内同步 habits / habit_subs / habit_goal_hist 引用（计划 §2.1）。
  /// 同名或空名返回 false 不动库。
  Future<bool> renameDict(String kind, int id, String newName) async {
    final rows = await db.query(
      DbSchema.tHabitDict,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final old = rows.first['name'] as String;
    final n = newName.trim();
    if (n.isEmpty || n == old) return false;
    final dup = await db.query(
      DbSchema.tHabitDict,
      where: 'kind = ? AND name = ? AND id <> ?',
      whereArgs: [kind, n, id],
      limit: 1,
    );
    if (dup.isNotEmpty) return false;
    await db.transaction((txn) async {
      await txn.update(
        DbSchema.tHabitDict,
        {'name': n},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (kind == HabitDict.kUnit) {
        await txn.update(
          DbSchema.tHabits,
          {'unit': n},
          where: 'unit = ?',
          whereArgs: [old],
        );
        await txn.update(
          DbSchema.tHabitSubs,
          {'unit': n},
          where: 'unit = ?',
          whereArgs: [old],
        );
        await txn.update(
          DbSchema.tHabitGoalHist,
          {'unit': n},
          where: 'unit = ?',
          whereArgs: [old],
        );
      } else {
        await txn.update(
          DbSchema.tHabits,
          {'cat': n},
          where: 'cat = ?',
          whereArgs: [old],
        );
      }
    });
    return true;
  }

  /// 把 from 的引用整体迁到 to（分类或单位），随后删除 from。
  Future<int> mergeDict(String kind, String from, String to) async {
    final n = to.trim();
    if (n.isEmpty || n == from) return 0;
    final cnt = await dictRefCount(kind, from);
    await db.transaction((txn) async {
      if (kind == HabitDict.kUnit) {
        await txn.update(
          DbSchema.tHabits,
          {'unit': n},
          where: 'unit = ?',
          whereArgs: [from],
        );
        await txn.update(
          DbSchema.tHabitSubs,
          {'unit': n},
          where: 'unit = ?',
          whereArgs: [from],
        );
        await txn.update(
          DbSchema.tHabitGoalHist,
          {'unit': n},
          where: 'unit = ?',
          whereArgs: [from],
        );
      } else {
        await txn.update(
          DbSchema.tHabits,
          {'cat': n},
          where: 'cat = ?',
          whereArgs: [from],
        );
      }
      await txn.delete(
        DbSchema.tHabitDict,
        where: 'kind = ? AND name = ?',
        whereArgs: [kind, from],
      );
    });
    return cnt;
  }

  /// 上移/下移一位（与相邻交换 sort）。
  Future<void> moveDict(String kind, int id, int delta) async {
    final rows = await db.query(
      DbSchema.tHabitDict,
      where: 'kind = ?',
      whereArgs: [kind],
      orderBy: 'sort ASC',
    );
    final i = rows.indexWhere((r) => r['id'] == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= rows.length) return;
    await db.transaction((txn) async {
      await txn.update(
        DbSchema.tHabitDict,
        {'sort': rows[j]['sort']},
        where: 'id = ?',
        whereArgs: [rows[i]['id']],
      );
      await txn.update(
        DbSchema.tHabitDict,
        {'sort': rows[i]['sort']},
        where: 'id = ?',
        whereArgs: [rows[j]['id']],
      );
    });
  }

  /// 删除字典项（调用方须先过 dictRefCount 引用守卫）。
  Future<void> deleteDict(String kind, int id) => db.delete(
    DbSchema.tHabitDict,
    where: 'kind = ? AND id = ?',
    whereArgs: [kind, id],
  );

  // ---- habit_pend（自动达成待确认队列 · 批5 · AC 杀进程重启仍在）----

  Future<void> addPend(
    String habitId, {
    required String day,
    required String src,
    double? value,
  }) => db.insert(DbSchema.tHabitPend, {
    'habit_id': habitId,
    'day': day,
    'src': src,
    'value': value,
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'state': 'pending',
  });

  Future<List<Map<String, Object?>>> pends({String state = 'pending'}) => db
      .query(
        DbSchema.tHabitPend,
        where: 'state = ?',
        whereArgs: [state],
        orderBy: 'id ASC',
      );

  Future<void> setPendState(int id, String state) => db.update(
    DbSchema.tHabitPend,
    {'state': state},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// 自动达成源 → origin 通道（§5-8 必写来源）。
  static String originForSrc(String src) => switch (src) {
    '待办勾选' => HabitEntry.oAutoTodo,
    '番茄完成' => HabitEntry.oAutoPomo,
    '阅读计时' => HabitEntry.oAutoRead,
    '日程事件' => HabitEntry.oAutoSchedule,
    _ => HabitEntry.oManual,
  };

  /// 确认一条待确认达成：出队 + 落流水（origin=来源 · check_at=回报时刻）。
  Future<void> confirmPend(Map<String, Object?> p) async {
    await setPendState(p['id'] as int, 'confirmed');
    final at = p['created_at'] as int?;
    await upsertEntry(
      p['habit_id'] as String,
      day: p['day'] as String,
      checked: true,
      value: (p['value'] as num?)?.toDouble(),
      origin: originForSrc(p['src'] as String),
      checkAt: at == null
          ? null
          : _hhmm(DateTime.fromMillisecondsSinceEpoch(at)),
    );
    AppLog.addKey('习惯待确认达成入账：pend#${p['id']} · ${p['habit_id']} · '
        '${p['day']} · 来源=${p['src']}（落账行随后）');
  }

  /// 忽略一条待确认达成（只出队，不落流水）。
  Future<void> ignorePend(int id) => setPendState(id, 'ignored');

  /// 自动达成源回报一次达成（原型 syncHabit 三分叉）。
  /// 返回 null＝已直接打卡/已入待确认队列；否则为拦截原因文案。
  Future<String?> autoIngest(
    Habit h, {
    required String src,
    String? day,
    double? value,
    String? at,
  }) async {
    if (!await kvBool('habit.autoChk', true)) {
      return '自动打卡已关闭 · 请到习惯页手动打卡';
    }
    final d = day ?? dayKey(DateTime.now());
    final e = (await entriesOf(h.id))[d];
    if (e != null && habitOkAt(h, e)) return '今天已打卡 · 自动源未重复计入';
    if ((await kvInt('habit.autoMode', 0)) == 1) {
      await addPend(h.id, day: d, src: src, value: value);
      return null;
    }
    await upsertEntry(
      h.id,
      day: d,
      checked: true,
      value: value,
      origin: originForSrc(src),
      checkAt: at,
    );
    return null;
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

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

extension on HabitEntry {  HabitEntry subValuesView(Map<int, double> v) => HabitEntry(
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
