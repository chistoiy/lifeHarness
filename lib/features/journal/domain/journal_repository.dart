import 'dart:convert';

import '../data/journal_dao.dart';
import '../domain/journal_entry.dart';

/// 日记仓库：一天多篇（V1.28）、每篇各带心情、结构化分节、连续记录、月度统计、那年今日。
class JournalRepository {
  JournalRepository(this.dao);

  final JournalDao dao;

  Future<List<JournalEntry>> list() => dao.list();

  /// 当日全部篇（新→旧）；结构化篇装配分节（单日篇数小，逐条水合可接受）。
  Future<List<JournalEntry>> listByDay(DateTime day) async {
    final list = await dao.listByDay(day);
    return [for (final e in list) e.templateId == null ? e : (await dao.hydrate(e)) ?? e];
  }

  Future<JournalEntry?> byDay(DateTime day) => dao.byDay(day);

  /// 打开某篇（含分节装配）。
  Future<JournalEntry?> open(int id) async {
    final e = await dao.byId(id);
    return e == null ? null : dao.hydrate(e);
  }

  Future<List<JournalEntry>> month(DateTime any) => dao.range(
        DateTime(any.year, any.month),
        DateTime(any.year, any.month + 1),
      );

  /// 保存：id=null → 当日新增一篇（一天多篇）；id!=null → 更新该篇。
  /// 结构化篇：分节写 journal_sections，content 存渲染快照（预览/☐/#标签仍可用）。
  Future<JournalEntry> save(JournalEntry e) async {
    final now = DateTime.now();
    final content = e.structured ? JournalEntry.renderSections(e.sections) : e.content;
    final base = e.copyWith(content: content);
    final tags = {...e.tags, ...base.hashTags()}.toList();
    if (e.id == null) {
      final fresh = base.copyWith(tags: tags, createdAt: now, updatedAt: now);
      final id = await dao.insert(fresh);
      if (base.structured) {
        await dao.replaceSections(id, base.sections, now.millisecondsSinceEpoch);
      }
      return fresh.copyWith(id: id);
    }
    await dao.updateById(e.id!, {
      'content': content,
      'mood': e.mood,
      'template_id': e.templateId,
      'tags': tags.isEmpty ? null : jsonEncode(tags),
      'kind': e.kind, // M1批2a：富文本类型随保存同步（笔记同款口径）
      'updated_at': now.millisecondsSinceEpoch,
    });
    await dao.replaceSections(
        e.id!, base.structured ? base.sections : const [], now.millisecondsSinceEpoch);
    return (await dao.byId(e.id!))!.copyWith(sections: base.sections);
  }

  /// 仪表盘心情打卡（L4）：当日有空白篇则改其心情，否则新增一篇仅含心情的（不动既有正文）。
  Future<void> setMoodOfDay(DateTime day, int mood) async {
    final entries = await dao.listByDay(day);
    final blank = entries.where((e) => e.content.isEmpty).toList();
    if (blank.isNotEmpty) {
      await dao.updateById(blank.first.id!,
          {'mood': mood, 'updated_at': DateTime.now().millisecondsSinceEpoch});
    } else {
      final now = DateTime.now();
      await dao.insert(JournalEntry(
          day: day, mood: mood, content: '', createdAt: now, updatedAt: now));
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
