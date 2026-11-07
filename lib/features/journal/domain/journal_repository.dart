import 'dart:convert';

import '../../../core/logging/app_log.dart';
import '../data/journal_dao.dart';
import '../data/tag_dao.dart';
import '../domain/journal_entry.dart';

/// 日记仓库：一天多篇（V1.28）、每篇各带心情、结构化分节、连续记录、月度统计、那年今日。
class JournalRepository {
  JournalRepository(this.dao);

  final JournalDao dao;

  Future<List<JournalEntry>> list() => dao.list();

  /// UI/流畅批（2026-10-12）：关键词搜索（正文＋结构化分节）· 搜索半屏共用。
  Future<List<JournalEntry>> search(String query) => dao.search(query);

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

  /// 轮13 → 语义断链批（2026-10-12）：删除改软删进回收站（第八类·拍板「进回收站」）。
  /// 彻底删除走回收站屏的 purge（分节连带清）；图片文件保留（恢复零损耗）。
  Future<void> remove(int id) async {
    await dao.softDelete(id);
    AppLog.addKey('日记删除单篇：#$id（进回收站）');
  }

  Future<void> removeAll(Iterable<int> ids) async {
    await dao.softDeleteMany(ids.toList());
    AppLog.addKey('日记批量删除：${ids.length} 篇（进回收站）');
  }

  // ---- 回收站第八类（trash_specs 登记项回调）----

  Future<List<JournalEntry>> trashed() => dao.trash();

  Future<void> restoreJournal(int id) => dao.restore(id);

  /// 彻底删除：返回连带清除的分节行数（回执读数）。
  Future<int> purgeJournal(int id) => dao.purge(id);

  Future<int> purgeExpired(int keepDays) => dao.purgeExpired(keepDays);

  Future<List<JournalEntry>> month(DateTime any) => dao.range(
        DateTime(any.year, any.month),
        DateTime(any.year, any.month + 1),
      );

  /// 保存：id=null → 当日新增一篇（一天多篇）；id!=null → 更新该篇。
  /// 结构化篇：分节写 journal_sections，content 存渲染快照（预览/☐/#标签仍可用）。
  Future<JournalEntry> save(JournalEntry e) async {
    final now = DateTime.now();
    // 编辑页每次手动保存都会走这里（自动保存不写库），频率可控。
    AppLog.addKey('日记保存落库：${e.id == null ? '新增一篇' : '更新 #${e.id}'} · '
        '日 ${e.day.toString().substring(0, 10)} · 结构化=${e.structured}');
    final content = e.structured ? JournalEntry.renderSections(e.sections) : e.content;
    final base = e.copyWith(content: content);
    // 批2b（2026-10-19）标签口径改「双源合并」：显式选择的标签（编辑页标签行）
    // ∪ 正文里的 #词。
    //
    // 与旧口径的差别只有一条：**正文删掉 #词不再自动删标签**。旧实现把「正文 #词」
    // 当唯一来源（删词即删标签），是因为当时没有打标签的入口、死标签只能靠这条
    // 减法兜住；现在标签是一等公民（编辑页标签行可见、可 ✕），删词仍留标签是
    // 用户看得见的选择，不是隐形残留。反过来「正文写了 #新词」仍自动并入，
    // 保留手写标签的老习惯。
    final tags = <String>[];
    for (final raw in [...e.tags, ...base.hashTags()]) {
      final n = tagNameNormalize(raw);
      if (n.isNotEmpty && !tags.contains(n)) tags.add(n);
    }
    final tagDao = TagDao(dao.db);
    if (e.id == null) {
      final fresh = base.copyWith(tags: tags, createdAt: now, updatedAt: now);
      final id = await dao.insert(fresh);
      if (base.structured) {
        await dao.replaceSections(id, base.sections, now.millisecondsSinceEpoch);
      }
      // 真源写关联表（顺带把行内快照对齐）；池里没有的名字就地补建。
      await tagDao.setItemTags('diary', id, tags);
      return fresh.copyWith(id: id);
    }
    await dao.updateById(e.id!, {
      'content': content,
      'mood': e.mood,
      'template_id': e.templateId,
      'tags': tags.isEmpty ? null : jsonEncode(tags),
      'kind': e.kind, // M1批2a：富文本类型随保存同步（笔记同款口径）
      // M1批2e：天气快照随保存同步（页面持有当前值·含载入时自动抓取结果）
      'weather_code': e.weatherCode,
      'temp_max': e.tempMax,
      'temp_min': e.tempMin,
      'weather_manual': e.weatherManual ? 1 : 0,
      'updated_at': now.millisecondsSinceEpoch,
    });
    await tagDao.setItemTags('diary', e.id!, tags);
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

  /// M1批2e：天气快照直写（自动抓取/手动覆盖即时落库·不动正文与 updated_at，
  /// 避免打乱「更新时间」排序语义）。
  Future<void> attachWeather(int id,
          {int? code, double? tmax, double? tmin, bool manual = false}) =>
      dao.updateById(id, {
        'weather_code': code,
        'temp_max': tmax,
        'temp_min': tmin,
        'weather_manual': manual ? 1 : 0,
      });

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

  /// 语义断链批（2026-10-12）·L3 反向回勾：待办完成 → 日记正文同名 ☐ 行置 ☑。
  /// 命中最新一篇含该 ☐ 行的在库篇（链路唯一真源＝标题约定，同 habit_mounts L10）。
  /// rich=Delta 属性 todo→checked；纯文本/分节=文本替换；结构化同步重渲快照。
  /// 返回命中与否（未命中静默，不报错——待办可能已与日记解钩）。
  Future<bool> tickTodoLine(String title) async {
    final t = title.trim();
    if (t.isEmpty) return false;
    final entries = await dao.list(); // 新→旧
    for (final e in entries) {
      if (e.kind == 'rich') {
        final hit = _tickRich(e.content, t);
        if (hit == null) continue;
        await dao.updateById(e.id!, {
          'content': hit,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
        return true;
      }
      if (e.templateId != null) {
        final secs = await dao.sectionsOf(e.id!);
        var changed = false;
        final newSecs = <DiarySection>[];
        for (final s in secs) {
          final hit = _tickPlain(s.body, t);
          if (hit == null) {
            newSecs.add(s);
          } else {
            changed = true;
            newSecs.add(DiarySection(title: s.title, body: hit));
          }
        }
        if (!changed) continue;
        final now = DateTime.now().millisecondsSinceEpoch;
        await dao.updateById(
            e.id!, {'content': JournalEntry.renderSections(newSecs), 'updated_at': now});
        await dao.replaceSections(e.id!, newSecs, now);
        return true;
      }
      final hit = _tickPlain(e.content, t);
      if (hit == null) continue;
      await dao.updateById(e.id!, {
        'content': hit,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    }
    return false;
  }

  /// 纯文本正文/分节：行级 ☐→☑（仅整行标题匹配，不误伤同词正文）。
  /// 注意：raw string 不做插值（r'...${...}' 里 ${} 是字面量）——标题须用拼接并入。
  static String? _tickPlain(String body, String title) {
    final re = RegExp(
        r'^(\s*(?:[-*]\s*)?)☐(\s*' + RegExp.escape(title) + r'\s*)$');
    var changed = false;
    final out = body.split('\n').map((l) {
      final m = re.firstMatch(l);
      if (m == null) return l;
      changed = true;
      return '${m.group(1)}☑${m.group(2)}';
    }).toList();
    return changed ? out.join('\n') : null;
  }

  /// rich（Quill Delta JSON）：list 属性 todo/unchecked → checked（渲染与 richToPlain 同出 ☑）。
  static String? _tickRich(String content, String title) {
    try {
      final ops = jsonDecode(content);
      if (ops is! List) return null;
      var changed = false;
      for (final op in ops) {
        if (op is! Map || op['insert'] is! String) continue;
        final attrs = op['attributes'];
        if (attrs is! Map) continue;
        final list = attrs['list'];
        if ((list == 'todo' || list == 'unchecked') &&
            (op['insert'] as String).trim() == title) {
          attrs['list'] = 'checked';
          changed = true;
        }
      }
      return changed ? jsonEncode(ops) : null;
    } catch (_) {
      return null; // 正文非 Delta JSON：不猜，不写（防损稿）
    }
  }
}
