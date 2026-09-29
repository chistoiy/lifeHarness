import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../../../core/logging/app_log.dart';
import '../domain/block_ops.dart';
import '../domain/time_block.dart';

/// time_blocks 表数据访问。
class TimeBlockDao {
  TimeBlockDao(this.db);

  final Database db;

  String get table => DbSchema.tTimeBlocks;

  static int _dayMs(DateTime day) =>
      DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;

  Future<List<TimeBlock>> listByDay(DateTime day) async {
    final rows = await db.query(table,
        where: 'day = ?',
        whereArgs: [_dayMs(day)],
        orderBy: 'start_min ASC');
    return rows.map(TimeBlock.fromRow).toList();
  }

  /// 时间账本用：区间内全部块（含计时中，聚合时按已耗时计）。
  Future<List<TimeBlock>> listInRange(DateTime from, DateTime to) async {
    final rows = await db.query(table,
        where: 'day >= ? AND day <= ?',
        whereArgs: [_dayMs(from), _dayMs(to)],
        orderBy: 'day ASC, start_min ASC');
    return rows.map(TimeBlock.fromRow).toList();
  }

  Future<TimeBlock> insert(TimeBlock b) async {
    final id = await db.insert(table, b.toRow());
    return TimeBlock.fromRow({...b.toRow(), 'id': id});
  }

  /// 编辑保存（起止/分类/备注/来源）。
  Future<void> save(TimeBlock b) => db.update(table, b.toRow(),
      where: 'id = ?', whereArgs: [b.id]);

  /// V1.52：当前计时中块（全局单活；跨天时以最新一条为准）。
  Future<TimeBlock?> activeTiming() async {
    final rows = await db.query(table,
        where: 'source = ?', whereArgs: [kSrcTiming], orderBy: 'day DESC, start_min DESC', limit: 1);
    return rows.isEmpty ? null : TimeBlock.fromRow(rows.first);
  }

  /// V1.52：开一段计时（先按收口规则结束上一段，保证单活）。
  Future<TimeBlock> startTiming(DateTime day, int startMin,
      {int? catId, required String catName, String? note}) async {
    final prev = await activeTiming();
    if (prev != null && prev.id != null) {
      await db.update(
          table,
          {
            'end_min': closeMinuteForAdd(timing: prev, bStart: startMin, nowMin: startMin) ?? prev.effEnd(),
            'source': kSrcMark,
            'updated_at': DateTime.now().millisecondsSinceEpoch
          },
          where: 'id = ?', whereArgs: [prev.id]);
    }
    return insert(TimeBlock(
        day: day,
        startMin: startMin,
        endMin: startMin,
        catId: catId,
        catName: catName,
        note: note,
        source: kSrcTiming));
  }

  /// V1.52：■ 结束计时——落实际结束时刻并转回普通块。
  Future<TimeBlock?> endTiming(int? id, int atMin) async {
    if (id == null) return null;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final b = TimeBlock.fromRow(rows.first);
    final e = atMin.clamp(b.startMin + 1, 1440);
    await db.update(
        table,
        {'end_min': e, 'source': kSrcMark, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
    AppLog.addKey('日程计时收口：块 #$id '
        '${fmtMin(b.startMin)}→${fmtMin(e)}（请求 ${fmtMin(atMin)}）');
    return b.copyWith(endMin: e, source: kSrcMark);
  }

  /// V1.27 C3：某月内有块的「日」集合（月历点=事件/块任一存在，四视图同一数据源）。
  Future<Set<int>> daysWithBlocks(int y, int m) async {
    final start = DateTime(y, m, 1).millisecondsSinceEpoch;
    final end = DateTime(y, m + 1, 1).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
        'SELECT DISTINCT day FROM $table WHERE day >= ? AND day < ?',
        [start, end]);
    return rows
        .map((r) => DateTime.fromMillisecondsSinceEpoch(r['day'] as int).day)
        .toSet();
  }

  /// V1.52：月内有「计时中」块的日集合（月历红脉冲点=最高优先级）。
  Future<Set<int>> daysWithTiming(int y, int m) async {
    final rows = await db.rawQuery(
        'SELECT day FROM $table WHERE day >= ? AND day < ? AND source = ?',
        [
          DateTime(y, m, 1).millisecondsSinceEpoch,
          DateTime(y, m + 1, 1).millisecondsSinceEpoch,
          kSrcTiming
        ]);
    return rows
        .map((r) => DateTime.fromMillisecondsSinceEpoch(r['day'] as int).day)
        .toSet();
  }

  Future<void> remove(int id) => db.delete(table, where: 'id = ?', whereArgs: [id]);

  /// V1.52 撤销用：整日块快照读出后原样回写（拆分/合并/删除的一键回滚）。
  Future<List<TimeBlock>> snapshotDay(DateTime day) => listByDay(day);

  Future<void> restoreDay(DateTime day, List<TimeBlock> rows) async {
    final dayMs = _dayMs(day);
    await db.transaction((txn) async {
      await txn.delete(table, where: 'day = ?', whereArgs: [dayMs]);
      for (final b in rows) {
        await txn.insert(table, b.toRow());
      }
    });
    AppLog.addKey('日程撤销回写：日 $dayMs 恢复 ${rows.length} 段');
  }

  /// 速记接龙：上一段"记到此刻"块截止到新时刻。
  Future<void> updateEnd(int id, int endMin) => db.update(
      table, {'end_min': endMin, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?', whereArgs: [id]);

  /// 与日程事件区间重叠的标记块（事件回填时避免重复着色）。
  Future<void> removeOverlapping(DateTime day, int startMin, int endMin) =>
      db.delete(
        table,
        where:
            'day = ? AND source = ? AND start_min < ? AND end_min > ?',
        whereArgs: [
          DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
          'mark',
          endMin,
          startMin,
        ],
      );

  /// 选块即标记（V1.21）：交叠部分被新分类替换，原块非交叠段自动保留（拆分），
  /// 相邻同分类同备注块合并；仅作用于 source=mark，事件回填块不动。
  /// V1.52：同日内新段起始 ≥ 计时中块起始 → 计时块按规则自动收口。
  Future<void> markRange(DateTime day, int startMin, int endMin,
      {int? catId, String catName = '其他', String? note}) async {
    final dayMs = _dayMs(day);
    final t = await activeTiming();
    if (t != null && _dayMs(t.day) == dayMs) {
      final now = DateTime.now();
      final cut = closeMinuteForAdd(
          timing: t, bStart: startMin, nowMin: now.hour * 60 + now.minute);
      if (cut != null) await endTiming(t.id, cut);
    }
    await db.transaction((txn) async {
      final rows = await txn.query(table,
          where: 'day = ? AND source = ?',
          whereArgs: [dayMs, 'mark'],
          orderBy: 'start_min ASC');
      final keep = <TimeBlock>[];
      for (final b in rows.map(TimeBlock.fromRow)) {
        if (b.endMin <= startMin || b.startMin >= endMin) {
          keep.add(b.copyWith(id: b.id));
          continue;
        }
        if (b.startMin < startMin) {
          keep.add(TimeBlock(day: day, startMin: b.startMin, endMin: startMin,
              catId: b.catId, catName: b.catName, note: b.note, source: b.source, eventId: b.eventId));
        }
        if (b.endMin > endMin) {
          keep.add(TimeBlock(day: day, startMin: endMin, endMin: b.endMin,
              catId: b.catId, catName: b.catName, note: b.note, source: b.source, eventId: b.eventId));
        }
      }
      keep.add(TimeBlock(
          day: day, startMin: startMin, endMin: endMin, catId: catId, catName: catName, note: note));
      keep.sort((a, b) => a.startMin.compareTo(b.startMin));
      final merged = <TimeBlock>[];
      for (final b in keep) {
        if (merged.isNotEmpty) {
          final l = merged.last;
          if (l.catName == b.catName && l.note == b.note && l.endMin == b.startMin) {
            merged[merged.length - 1] = l.copyWith(endMin: b.endMin);
            continue;
          }
        }
        merged.add(b);
      }
      final batch = txn.batch()
        ..delete(table, where: 'day = ? AND source = ?', whereArgs: [dayMs, 'mark']);
      for (final b in merged) {
        batch.insert(table, b.toRow());
      }
      await batch.commit(noResult: true);
      // 段数前后对照：V1.52 真机「合并丢块」就是这里少写了一段，
      // 只靠 toast 复盘不出来。
      AppLog.addKey('日程标记落库：${fmtMin(startMin)}-${fmtMin(endMin)} · $catName '
          '· 日内 mark 段 ${rows.length}→${merged.length}');
    });
  }
}
