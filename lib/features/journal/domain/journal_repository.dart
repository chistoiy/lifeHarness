import 'dart:convert';

import '../data/journal_dao.dart';
import '../domain/journal_entry.dart';

/// 日记仓库：按日 upsert、连续记录、月度心情统计、那年今日。
class JournalRepository {
  JournalRepository(this.dao);

  final JournalDao dao;

  Future<List<JournalEntry>> list() => dao.list();

  Future<JournalEntry?> byDay(DateTime day) => dao.byDay(day);

  Future<List<JournalEntry>> month(DateTime any) => dao.range(
        DateTime(any.year, any.month),
        DateTime(any.year, any.month + 1),
      );

  /// 保存（一天一篇）：已有则更新内容/心情/标签，保留回望态与创建时间。
  Future<JournalEntry> save(JournalEntry e) async {
    final now = DateTime.now();
    final tags = {...e.tags, ...e.hashTags()}.toList();
    final existing = await dao.byDay(e.day);
    if (existing == null) {
      final fresh = e.copyWith(tags: tags, createdAt: now, updatedAt: now);
      final id = await dao.insert(fresh);
      return fresh.copyWith(id: id);
    }
    final merged = existing.copyWith(
      content: e.content,
      mood: e.mood ?? existing.mood,
      tags: tags,
      updatedAt: now,
    );
    await dao.updateById(existing.id!, {
      'content': merged.content,
      'mood': merged.mood,
      'tags': merged.tags.isEmpty ? null : jsonEncode(merged.tags),
      'updated_at': now.millisecondsSinceEpoch,
    });
    return merged;
  }

  /// 仪表盘心情打卡（L4：写入今晚日记的 mood，不覆盖正文）。
  Future<void> setMoodOfDay(DateTime day, int mood) async {
    final existing = await dao.byDay(day);
    if (existing == null) {
      final now = DateTime.now();
      await dao.insert(JournalEntry(
          day: day, mood: mood, content: '', createdAt: now, updatedAt: now));
    } else {
      await dao.updateById(existing.id!, {'mood': mood, 'updated_at': DateTime.now().millisecondsSinceEpoch});
    }
  }

  Future<void> setFlags(int id, {bool? starred, bool? liked}) =>
      dao.setFlags(id, starred: starred, liked: liked);

  Future<void> markViewed(int id) => dao.incView(id);

  /// 连续记录天数（从今天或昨天往前数，活动日=有正文或心情）。
  Future<int> streak() async {
    final days = (await dao.activeDays()).map(DateTime.fromMillisecondsSinceEpoch).toSet();
    if (days.isEmpty) return 0;
    var cur = JournalEntry.dayStart(DateTime.now());
    if (!days.contains(cur)) cur = cur.subtract(const Duration(days: 1));
    if (!days.contains(cur)) return 0;
    var n = 0;
    while (days.contains(cur)) {
      n++;
      cur = cur.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// 那年今日：去年同月同日条目。
  Future<JournalEntry?> onThisDayLastYear() {
    final now = DateTime.now();
    return dao.byDay(DateTime(now.year - 1, now.month, now.day));
  }
}
