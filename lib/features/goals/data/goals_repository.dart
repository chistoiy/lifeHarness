import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/goal_calc.dart';
import '../domain/goal_models.dart';

/// 目标 OKR 仓储（仿 care/days/items 范式）。
///
/// 自动汇聚口径（模块7 · KR 绑定数据源每日 00:0 自动重算 → 本实现「每次载入重算」，
/// 语义覆盖零点场景且无常驻 Timer；归档周期冻结不再重算）：
/// - todo 待办完成数：done=1 且 updated_at 落在周期窗（自然日）；
/// - read 阅读本数：books state='已读' 且 ended_at 落窗；
/// - journal 日记篇数：journal_entries entry_date 落窗；
/// - habit 习惯打卡：habit_entries checked=1 按 (habit_id,day) 去重计数落窗；
/// - ledger 记账结余：结余率=（季收入−季支出）/季收入×100（收入 0 → 0）。
/// 源表一律只读 rawQuery（days 侧 journal/ledger_recur 先例），不 import 其它 feature。
class GoalsRepository {
  GoalsRepository(this.db);

  final Database db;

  // ==================== 加载（含自动汇聚重算） ====================

  Future<GoalsData> loadAll({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final goalRows = await db.query(DbSchema.tGoals, orderBy: 'sort ASC, id ASC');
    final krRows = await db.query(DbSchema.tGoalKrs, orderBy: 'id ASC');
    final upRows = await db.query(DbSchema.tKrUpdates, orderBy: 'created_at ASC');
    final revRows = await db.query(DbSchema.tGoalReviews, orderBy: 'period ASC');
    final perRows = await db.query(DbSchema.tGoalPeriods);

    final archived = {
      for (final r in perRows)
        if ((r['archived'] as int? ?? 0) == 1) r['period'] as String
    };

    final goals = <Goal>[];
    for (final r in goalRows) {
      final krs = <GoalKr>[];
      for (final k in krRows.where((x) => x['goal_id'] == r['id'])) {
        final src = KrSource.of(k['src'] as String);
        var cur = (k['cur'] as num).toDouble();
        if (shouldAggregate(src, archived.contains(r['period'] as String))) {
          cur = await aggregate(src, (k['label'] as String), r['period'] as String, t);
          // 汇聚值回写库（下次读取一致）+ 变化留痕（kind='auto'）
          if (cur != (k['cur'] as num).toDouble()) {
            await db.update(DbSchema.tGoalKrs, {'cur': cur},
                where: 'id = ?', whereArgs: [k['id']]);
            await db.insert(DbSchema.tKrUpdates, {
              'kr_id': k['id'],
              'cur': cur,
              'kind': 'auto',
              'note': '${src.label} · 自动汇聚',
              'created_at': t.millisecondsSinceEpoch,
            });
          }
        }
        krs.add(GoalKr.fromRow({...k, 'cur': cur}).copyWithUpds([
          for (final u in upRows.where((x) => x['kr_id'] == k['id']))
            KrUpdate.fromRow(u)
        ]));
      }
      goals.add(Goal.fromRow(r).copyWith(krs: krs));
    }
    return GoalsData(
      goals: goals,
      reviews: revRows.map(GoalReview.fromRow).toList(),
      archivedPeriods: archived,
    );
  }

  /// 单一数据源在周期窗内的实算值。
  Future<double> aggregate(KrSource src, String krLabel, String period, DateTime now) async {
    final (start, end) = GoalPeriod.range(period, now);
    final s = start.millisecondsSinceEpoch;
    final e = end.millisecondsSinceEpoch;
    final sd = _day(start), ed = _day(end.subtract(const Duration(days: 1)));
    switch (src) {
      case KrSource.todo:
        final r = await db.rawQuery(
            'SELECT COUNT(*) c FROM ${DbSchema.tTodos} WHERE done = 1 AND updated_at >= ? AND updated_at < ?',
            [s, e]);
        return (r.first['c'] as int).toDouble();
      case KrSource.read:
        final r = await db.rawQuery(
            "SELECT COUNT(*) c FROM ${DbSchema.tBooks} WHERE state = '已读' AND ended_at >= ? AND ended_at < ?",
            [s, e]);
        return (r.first['c'] as int).toDouble();
      case KrSource.journal:
        final r = await db.rawQuery(
            'SELECT COUNT(*) c FROM ${DbSchema.tJournal} WHERE entry_date >= ? AND entry_date < ?',
            [s, e]);
        return (r.first['c'] as int).toDouble();
      case KrSource.habit:
        final r = await db.rawQuery(
            'SELECT COUNT(DISTINCT habit_id || day) c FROM ${DbSchema.tHabitEntries} WHERE checked = 1 AND day >= ? AND day <= ?',
            [sd, ed]);
        return (r.first['c'] as int).toDouble();
      case KrSource.ledger:
        final r = await db.rawQuery(
            "SELECT kind, SUM(amt) t FROM ${DbSchema.tLedgerTxns} WHERE date >= ? AND date <= ? AND kind IN ('expense','income') GROUP BY kind",
            [sd, ed]);
        double inc = 0, exp = 0;
        for (final x in r) {
          final v = (x['t'] as num?)?.toDouble() ?? 0;
          if (x['kind'] == 'income') {
            inc += v;
          } else {
            exp += v;
          }
        }
        if (inc <= 0) return 0;
        return ((inc - exp) / inc * 100).round().toDouble();
      case KrSource.manual:
        return 0; // 不参与自动汇聚
    }
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ==================== 目标 / KR 写路径 ====================

  /// 新建目标（含 2~4 KR）；超限返回 null（UI toast 收敛提示）。
  Future<int?> addGoal(Goal g) async {
    final existing = (await db.query(DbSchema.tGoals,
            where: 'period = ?', whereArgs: [g.period]))
        .length;
    if (existing >= kMaxOkrPerPeriod) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final id = await txn.insert(DbSchema.tGoals, {
        'title': g.title,
        'period': g.period,
        'sort': g.sort,
        'created_at': ts,
        'updated_at': ts,
      });
      for (final k in g.krs) {
        await _insertKr(txn, id, k);
      }
      return id;
    });
  }

  Future<void> _insertKr(Transaction txn, int goalId, GoalKr k) async {
    final id = await txn.insert(DbSchema.tGoalKrs, {
      'goal_id': goalId,
      'label': k.label,
      'target': k.target,
      'unit': k.unit,
      'src': k.source.wire,
      'cur': k.cur,
    });
    if (k.id == null && k.cur > 0) {
      await txn.insert(DbSchema.tKrUpdates, {
        'kr_id': id,
        'cur': k.cur,
        'kind': 'manual',
        'note': '建档初值',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// 全量覆盖更新（KR 整组替换，同 days preps 先例；id 命中保留更新留痕）。
  Future<void> updateGoal(Goal g) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update(DbSchema.tGoals,
          {'title': g.title, 'period': g.period, 'sort': g.sort, 'updated_at': ts},
          where: 'id = ?', whereArgs: [g.id]);
      final oldKrs =
          await txn.query(DbSchema.tGoalKrs, where: 'goal_id = ?', whereArgs: [g.id]);
      final keepIds = g.krs.map((x) => x.id).whereType<int>().toSet();
      // 只删未保留行（含其留痕），保留行原地更新（id 命中 → kr_updates 链不断）
      for (final o in oldKrs) {
        if (!keepIds.contains(o['id'])) {
          await txn.delete(DbSchema.tKrUpdates,
              where: 'kr_id = ?', whereArgs: [o['id']]);
          await txn.delete(DbSchema.tGoalKrs, where: 'id = ?', whereArgs: [o['id']]);
        }
      }
      for (final k in g.krs) {
        final keep = oldKrs.any((o) => o['id'] == k.id);
        if (keep) {
          await txn.update(DbSchema.tGoalKrs, {
            'label': k.label,
            'target': k.target,
            'unit': k.unit,
            'src': k.source.wire,
            'cur': k.cur,
          }, where: 'id = ?', whereArgs: [k.id]);
        } else {
          await _insertKr(txn, g.id!, k);
        }
      }
    });
  }

  Future<void> removeGoal(int id) => db.transaction((txn) async {
        final krs = await txn.query(DbSchema.tGoalKrs,
            where: 'goal_id = ?', whereArgs: [id]);
        await txn.delete(DbSchema.tGoalKrs, where: 'goal_id = ?', whereArgs: [id]);
        for (final k in krs) {
          await txn.delete(DbSchema.tKrUpdates, where: 'kr_id = ?', whereArgs: [k['id']]);
        }
        await txn.delete(DbSchema.tGoals, where: 'id = ?', whereArgs: [id]);
      });

  /// 手动回填（关闭自动汇聚即转 manual；自动源也允许随时回填 → 留痕）。
  Future<void> bumpKr(int krId, double cur, {String? note}) => db.transaction((txn) async {
        await txn.update(DbSchema.tGoalKrs, {'cur': cur},
            where: 'id = ?', whereArgs: [krId]);
        await txn.insert(DbSchema.tKrUpdates, {
          'kr_id': krId,
          'cur': cur,
          'kind': 'manual',
          'note': note ?? '手动回填',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      });

  // ==================== 复制清零（上期整组 / 单目标） ====================

  /// 复制自周期 → 目标周期，进度清零成草稿（原型 goalCopyPrev）。返回条数；超上限截断并回实际条数。
  Future<int> copyGoals(String fromPeriod, String toPeriod) async {
    final src = (await db.query(DbSchema.tGoals,
        where: 'period = ?', whereArgs: [fromPeriod], orderBy: 'sort ASC, id ASC'));
    final existing = (await db.query(DbSchema.tGoals,
            where: 'period = ?', whereArgs: [toPeriod]))
        .length;
    final ts = DateTime.now().millisecondsSinceEpoch;
    var copied = 0;
    for (final r in src) {
      if (existing + copied >= kMaxOkrPerPeriod) break;
      await db.transaction((txn) async {
        final id = await txn.insert(DbSchema.tGoals, {
          'title': _retitle(r['title'] as String, existing + copied + 1),
          'period': toPeriod,
          'sort': r['sort'] ?? 0,
          'created_at': ts,
          'updated_at': ts,
        });
        final krs = await txn.query(DbSchema.tGoalKrs,
            where: 'goal_id = ?', whereArgs: [r['id']]);
        for (final k in krs) {
          await txn.insert(DbSchema.tGoalKrs, {
            'goal_id': id,
            'label': k['label'],
            'target': k['target'],
            'unit': k['unit'],
            'src': k['src'],
            'cur': 0,
          });
        }
      });
      copied++;
    }
    return copied;
  }

  /// 复制单个目标（归档态默认复制到现在周期，原型 goalCopy）。
  Future<int?> copySingleGoal(int goalId, String toPeriod) async {
    final r = (await db.query(DbSchema.tGoals, where: 'id = ?', whereArgs: [goalId])).firstOrNull;
    if (r == null) return null;
    final existing = (await db.query(DbSchema.tGoals,
            where: 'period = ?', whereArgs: [toPeriod]))
        .length;
    if (existing >= kMaxOkrPerPeriod) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final id = await txn.insert(DbSchema.tGoals, {
        'title': r['title'],
        'period': toPeriod,
        'sort': 0,
        'created_at': ts,
        'updated_at': ts,
      });
      final krs = await txn.query(DbSchema.tGoalKrs,
          where: 'goal_id = ?', whereArgs: [goalId]);
      for (final k in krs) {
        await txn.insert(DbSchema.tGoalKrs, {
          'goal_id': id,
          'label': k['label'],
          'target': k['target'],
          'unit': k['unit'],
          'src': k['src'],
          'cur': 0,
        });
      }
      return id;
    });
  }

  static String _retitle(String t, int n) =>
      RegExp(r'^O\d+').hasMatch(t) ? t.replaceFirst(RegExp(r'^O\d+'), 'O$n') : t;

  // ==================== 周期归档 ====================

  Future<void> setPeriodArchived(String period, bool archived) => db.insert(
        DbSchema.tGoalPeriods,
        {
          'period': period,
          'archived': archived ? 1 : 0,
          'archived_at': archived ? DateTime.now().millisecondsSinceEpoch : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ==================== KPT 复盘（每季一份） ====================

  /// 保存并归档（撰写中→只读）。archived=false 仅存草稿内容。
  Future<void> saveReview(GoalReview r, {bool asArchived = true}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query(DbSchema.tGoalReviews,
        where: 'period = ?', whereArgs: [r.period], limit: 1);
    if (existing.isEmpty) {
      await db.insert(DbSchema.tGoalReviews, {
        'period': r.period,
        'keep': r.keep,
        'problem': r.problem,
        'trial': r.trial,
        'archived': asArchived ? 1 : 0,
        'created_at': ts,
        'updated_at': ts,
      });
    } else {
      await db.update(DbSchema.tGoalReviews, {
        'keep': r.keep,
        'problem': r.problem,
        'trial': r.trial,
        'archived': (asArchived || r.archived) ? 1 : 0,
        'updated_at': ts,
      }, where: 'period = ?', whereArgs: [r.period]);
    }
  }

  /// Try → 下季草稿（原型 grDraft：取 Try 首行生成一个 O + 单 KR）。
  Future<int?> tryToNextDraft(String fromPeriod, String trialText) async {
    final to = GoalPeriod.nextQuarter(fromPeriod, DateTime.now());
    final firstLine = trialText
        .split(RegExp(r'[\n；;。]'))
        .map((x) => x.trim())
        .firstWhere((x) => x.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final existing =
        (await db.query(DbSchema.tGoals, where: 'period = ?', whereArgs: [to])).length;
    if (existing >= kMaxOkrPerPeriod) return null;
    return db.transaction((txn) async {
      final id = await txn.insert(DbSchema.tGoals, {
        'title': 'O${existing + 1} 由 $fromPeriod 复盘 Try 生成',
        'period': to,
        'sort': 0,
        'created_at': ts,
        'updated_at': ts,
      });
      await txn.insert(DbSchema.tGoalKrs, {
        'goal_id': id,
        'label': firstLine.length > 18 ? '${firstLine.substring(0, 18)}…' : firstLine,
        'target': 1,
        'unit': '项',
        'src': 'manual',
        'cur': 0,
      });
      return id;
    });
  }
}

extension on GoalKr {
  GoalKr copyWithUpds(List<KrUpdate> updates) => GoalKr(
        id: id,
        goalId: goalId,
        label: label,
        target: target,
        unit: unit,
        source: source,
        cur: cur,
        updates: updates,
      );
}
