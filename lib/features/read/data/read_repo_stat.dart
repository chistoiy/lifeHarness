part of 'read_repository.dart';

// 治理G7d④：统计聚合群（p-readstat 数据源）移入同库 mixin（行为零改动·成员经 with 组合后仍是 ReadRepository 的实例成员）。
// 逐日分钟/逐日摘录/时段直方/费用/字数/本月摘录/本年读完；跨群只调类内枢纽。
mixin _RepoStats on _ReadRepoBase {
  // ---- 统计聚合（批4 · p-readstat 数据源）----

  /// 全年逐日分钟账（缺失日补 0）。
  Future<List<({DateTime day, int minutes})>> dayLogYear(int year) async {
    final byDay = <DateTime, int>{};
    for (final s in await allSessions()) {
      if (s.endedAt == null) continue; // 在跑的会话不入历史账
      final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      if (d.year != year) continue;
      final key = DateTime(d.year, d.month, d.day);
      byDay[key] = (byDay[key] ?? 0) + s.minutes;
    }
    final first = DateTime(year);
    final days = DateTime(year, 12, 31).difference(first).inDays + 1;
    return [
      for (var i = 0; i < days; i++)
        (
          day: first.add(Duration(days: i)),
          minutes:
              byDay[first.add(Duration(days: i))] ?? 0,
        ),
    ];
  }

  /// 逐日摘录条数（当年）。
  Future<Map<DateTime, int>> dayQuotesYear(int year) async {
    final out = <DateTime, int>{};
    for (final q in await allQuotes()) {
      final d = DateTime.fromMillisecondsSinceEpoch(q.createdAt);
      if (d.year != year) continue;
      final key = DateTime(d.year, d.month, d.day);
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  /// 时段分布（24 桶；会话分钟整体记在开始时段，原型 hrs 口径）。
  Future<List<int>> hourHistogram(int year) async {
    final hrs = List<int>.filled(24, 0);
    for (final s in await allSessions()) {
      if (s.endedAt == null) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      if (d.year != year) continue;
      hrs[d.hour] += s.minutes;
    }
    return hrs;
  }

  /// 购书支出合计（未删书 fee 求和）。
  Future<({double fee, int paid})> feeTotals() async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(fee),0) s, COUNT(*) c FROM ${DbSchema.tBooks} '
      'WHERE deleted_at IS NULL AND fee > 0',
    );
    final m = rows.first;
    return (fee: (m['s'] as num).toDouble(), paid: m['c'] as int);
  }

  /// 完读书字数（页数折算 · 原型 pg*520）与完读书累计分钟。
  Future<({int words, int rdMin})> doneWords() async {
    var words = 0;
    var min = 0;
    final agg = sessionAggByBook(await allSessions());
    for (final b in await allBooks()) {
      if (b.isDeleted || b.state != Book.kStateDone) continue;
      words += b.pages * 520;
      min += agg[b.id]?.minutes ?? 0;
    }
    return (words: words, rdMin: min);
  }

  /// 本月摘录数（L7 目标第五路）。
  Future<int> quotesThisMonth() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month).millisecondsSinceEpoch;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM ${DbSchema.tBookQuotes} WHERE deleted_at IS NULL AND created_at >= ?',
            [start],
          ),
        ) ??
        0;
  }

  /// 本年读完本数（ended_at 落在今年）。
  Future<int> doneThisYear() async {
    final y = DateTime.now().year;
    return (await allBooks())
        .where(
          (b) =>
              !b.isDeleted &&
              b.state == Book.kStateDone &&
              b.endedAt != null &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == y,
        )
        .length;
  }
}
