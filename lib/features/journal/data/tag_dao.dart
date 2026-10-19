import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../../../core/logging/app_log.dart';
import '../domain/journal_entry.dart';
import '../domain/note.dart';
import '../domain/tag.dart';

/// 标签池数据访问（批2b）。
///
/// 两张表的分工见 `core/database/schema/tag.dart` 文件头：
/// `tags` 是池本体，`tag_links` 是「标签 ↔ 某模块某条内容」的按 id 关联。
///
/// **所有写操作都在这里做**，UI 层只读结果——口径①「池全局唯一」最省的落地方式
/// 就是「只留一个写口」。日记页的选标签弹层也不例外（它只调 [setItemTags]）。
class TagDao {
  TagDao(this.db);

  final Database db;

  /// 池（含全仓引用计数），按 `sort,id` 升序——**这个序同时决定标签色**（[tagToneAt]）。
  Future<List<Tag>> list() async {
    final rows = await db.rawQuery(
      'SELECT t.id, t.name, t.scopes, t.sort, t.builtin,'
      ' (SELECT COUNT(*) FROM ${DbSchema.tTagLinks} l WHERE l.tag_id = t.id) AS use_count'
      ' FROM ${DbSchema.tTags} t ORDER BY t.sort, t.id',
    );
    return rows.map(Tag.fromRow).toList();
  }

  /// 只取某模块可用的标签（口径③：各功能页只展示本模块启用的标签）。
  Future<List<Tag>> listFor(String module) async =>
      (await list()).where((t) => t.appliesTo(module)).toList();

  Future<Tag?> byName(String name) async {
    final n = tagNameNormalize(name);
    if (n.isEmpty) return null;
    final rows = await db.query(DbSchema.tTags,
        where: 'LOWER(name) = ?', whereArgs: [n.toLowerCase()], limit: 1);
    return rows.isEmpty ? null : Tag.fromRow(rows.first);
  }

  Future<Tag?> byId(int id) async {
    final rows = await db.query(DbSchema.tTags, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Tag.fromRow(rows.first);
  }

  /// 新建标签（口径②：不传 scopes 时默认三个模块全勾）。
  ///
  /// 返回 `(ok, msg, tag)`：与原型 `tgAddTag` 同形——重名/空名/超长都是**用户可见的
  /// 拒绝理由**，不能静默失败（原型踩过「第一次改名静默失败」）。
  Future<({bool ok, String msg, Tag? tag})> create(
      String rawName, {Set<String>? scopes}) async {
    final name = tagNameNormalize(rawName);
    if (name.isEmpty) return (ok: false, msg: '请填写标签名称', tag: null);
    if (name.length > kTagNameMax) return (ok: false, msg: '名称最多 $kTagNameMax 个字', tag: null);
    if (await byName(name) != null) return (ok: false, msg: '标签「$name」已存在', tag: null);
    final sc = (scopes == null || scopes.isEmpty)
        ? kTagScopes.toSet()
        : scopes.where(kTagScopes.contains).toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert(DbSchema.tTags, {
      'name': name,
      'scopes': tagScopesEncode(sc),
      'sort': await _nextSort(),
      'builtin': 0,
      'created_at': now,
    });
    AppLog.addKey('标签新建：「$name」· ${sc.isEmpty ? '未选模块' : tagScopesEncode(sc)}');
    return (ok: true, msg: '', tag: Tag(id: id, name: name, scopes: sc, sort: 0));
  }

  /// 改名（口径④前半）：所有模块里的这个名字一起变。
  ///
  /// 关联表按 id 存，故**不用搬引用**；要补的是 `journal_entries.tags` 快照
  /// （见文件头「列降级为快照」）。改名撞名一律拒绝，不做「自动合并」——
  /// 合并是用户显式选择的另一个动作。
  Future<({bool ok, String msg})> rename(int id, String rawName) async {
    final t = await byId(id);
    if (t == null) return (ok: false, msg: '找不到标签');
    final name = tagNameNormalize(rawName);
    if (name.isEmpty) return (ok: false, msg: '名称不能为空');
    if (name.length > kTagNameMax) return (ok: false, msg: '名称最多 $kTagNameMax 个字');
    final dup = await byName(name);
    if (dup != null && dup.id != id) return (ok: false, msg: '已有同名标签');
    if (name == t.name) return (ok: true, msg: '');
    await db.update(DbSchema.tTags, {'name': name}, where: 'id = ?', whereArgs: [id]);
    await resyncSnapshots(await _itemsOfTag(id, 'diary'));
    AppLog.addKey('标签改名：「${t.name}」→「$name」');
    return (ok: true, msg: '');
  }

  /// 改「适用模块」（口径②的可改属性）。
  ///
  /// 取消某模块**只影响选择列表**：已绑定的内容保留（原型编辑弹层同款注释）。
  /// 至少保留一个模块——一个模块都不适用的标签在任何页面都选不到，
  /// 只会在管理页变成点不回来的死行。
  Future<({bool ok, String msg})> setScopes(int id, Set<String> scopes) async {
    final t = await byId(id);
    if (t == null) return (ok: false, msg: '找不到标签');
    final sc = scopes.where(kTagScopes.contains).toSet();
    if (sc.isEmpty) return (ok: false, msg: '至少保留一个适用模块');
    await db.update(DbSchema.tTags, {'scopes': tagScopesEncode(sc)},
        where: 'id = ?', whereArgs: [id]);
    return (ok: true, msg: '');
  }

  /// 删除（口径④后半）：所有模块**解除关联**，内容本身不删。
  Future<void> deleteTag(int id) async {
    final t = await byId(id);
    if (t == null) return;
    final affected = await _itemsOfTag(id, 'diary');
    await db.delete(DbSchema.tTagLinks, where: 'tag_id = ?', whereArgs: [id]);
    await db.delete(DbSchema.tTags, where: 'id = ?', whereArgs: [id]);
    await resyncSnapshots(affected);
    AppLog.addKey('标签删除：「${t.name}」· 三模块引用已解除（内容不删）');
  }

  /// 合并（拍板①：**归属模块取并集**，不取交集、不以目标为准）。
  ///
  /// 关联用 `INSERT OR IGNORE` 搬：同一篇内容同时挂源与目标时，
  /// 直接 `UPDATE tag_id` 会撞主键（(tag_id,module,item_id) 三元组重复）。
  Future<({bool ok, String msg})> merge(int fromId, int toId) async {
    if (fromId == toId) return (ok: false, msg: '合并目标无效');
    final a = await byId(fromId);
    final b = await byId(toId);
    if (a == null || b == null) return (ok: false, msg: '合并目标无效');
    final affected = await _itemsOfTag(fromId, 'diary');
    final batch = db.batch();
    batch.rawInsert(
      'INSERT OR IGNORE INTO ${DbSchema.tTagLinks} (tag_id, module, item_id)'
      ' SELECT ?, module, item_id FROM ${DbSchema.tTagLinks} WHERE tag_id = ?',
      [toId, fromId],
    );
    batch.delete(DbSchema.tTagLinks, where: 'tag_id = ?', whereArgs: [fromId]);
    batch.delete(DbSchema.tTags, where: 'id = ?', whereArgs: [fromId]);
    await batch.commit(noResult: true);
    final union = {...a.scopes, ...b.scopes};
    await db.update(DbSchema.tTags, {'scopes': tagScopesEncode(union)},
        where: 'id = ?', whereArgs: [toId]);
    await resyncSnapshots(affected);
    AppLog.addKey('标签合并：「${a.name}」→「${b.name}」· 模块取并集');
    return (ok: true, msg: '');
  }

  /// 某条内容挂了哪些标签（名字，按池内次序）。
  Future<List<String>> namesOf(String module, int itemId) async {
    final rows = await db.rawQuery(
      'SELECT t.name n FROM ${DbSchema.tTagLinks} l JOIN ${DbSchema.tTags} t ON t.id = l.tag_id'
      ' WHERE l.module = ? AND l.item_id = ? ORDER BY t.sort, t.id',
      [module, itemId],
    );
    return [for (final r in rows) r['n'] as String];
  }

  /// 批量读「多条内容各自挂了哪些标签」——日记列表一次问完，避免逐篇 N 次查询。
  Future<Map<int, List<String>>> namesOfMany(String module, List<int> itemIds) async {
    if (itemIds.isEmpty) return const {};
    final holes = List.filled(itemIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT l.item_id i, t.name n FROM ${DbSchema.tTagLinks} l'
      ' JOIN ${DbSchema.tTags} t ON t.id = l.tag_id'
      ' WHERE l.module = ? AND l.item_id IN ($holes) ORDER BY t.sort, t.id',
      [module, ...itemIds],
    );
    final out = <int, List<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r['i'] as int, () => []).add(r['n'] as String);
    }
    return out;
  }

  /// 设置某条内容的标签（**日记页唯一的写口**）。
  ///
  /// 池里没有的名字按「就地补建」处理（scopes 只含本模块）——正文里写 `#新词`
  /// 然后保存的路径不能因为「池里没这个词」就把标签吞掉（原型 `dtagEnsure` 同口径）。
  Future<void> setItemTags(String module, int itemId, List<String> names) async {
    final clean = <String>[];
    for (final raw in names) {
      final n = tagNameNormalize(raw);
      if (n.isEmpty || clean.contains(n)) continue;
      clean.add(n);
    }
    final batch = db.batch();
    batch.delete(DbSchema.tTagLinks,
        where: 'module = ? AND item_id = ?', whereArgs: [module, itemId]);
    for (final n in clean) {
      final id = await _ensureTag(n, module);
      batch.insert(
        DbSchema.tTagLinks,
        {'tag_id': id, 'module': module, 'item_id': itemId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    if (module == 'diary') await resyncSnapshots([itemId]);
  }

  /// 内容被**彻底删除**时清关联（软删保留：回收站恢复后标签要跟着回来）。
  Future<void> removeItem(String module, int itemId) async {
    await db.delete(DbSchema.tTagLinks,
        where: 'module = ? AND item_id = ?', whereArgs: [module, itemId]);
  }

  /// 把日记行里的标签快照按关联表重写一遍（受影响的篇目）。
  ///
  /// 为什么需要：`journal_entries.tags` 是**读侧回落源**（关联表尚无该篇行时用它），
  /// 池侧改名/合并/删除若不同步，回落场景会读到旧名字；更糟的是「删光标签后
  /// 旧快照会把标签复活」（`seedFromJournalTags` 的判据就是「关联表为空且快照非空」）。
  Future<void> resyncSnapshots(Iterable<int> entryIds) async {
    final ids = entryIds.toSet().toList();
    if (ids.isEmpty) return;
    final names = await namesOfMany('diary', ids);
    final batch = db.batch();
    for (final id in ids) {
      final list = names[id] ?? const <String>[];
      batch.update(
        DbSchema.tJournal,
        {'tags': list.isEmpty ? null : jsonEncode(list)},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// 历史标签懒导入（v50 建表后第一次进标签相关界面时跑）。
  ///
  /// 判据＝「关联表里一条日记关联都没有，但 `journal_entries.tags` 有值」：
  /// - 全新库：两边都空 ⇒ 不跑；
  /// - 老库升级：快照有值、关联表空 ⇒ 跑一次，之后关联表非空 ⇒ 不再跑；
  /// - 用户删光所有标签：删除动作会把快照一并清空 ⇒ 不复活。
  ///
  /// 返回导入的（标签名, 篇目）对数，仅用于日志与断言读数。
  Future<int> seedFromJournalTags() async {
    final linked = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM ${DbSchema.tTagLinks} WHERE module = ?',
          ['diary'],
        )) ??
        0;
    if (linked > 0) return 0;
    final rows = await db.query(DbSchema.tJournal,
        columns: ['id', 'tags'], where: "tags IS NOT NULL AND tags != ''");
    if (rows.isEmpty) return 0;
    var n = 0;
    for (final r in rows) {
      final id = r['id'] as int;
      final names = _decodeNames(r['tags'] as String?);
      if (names.isEmpty) continue;
      for (final name in names) {
        final tid = await _ensureTag(name, 'diary');
        await db.insert(
          DbSchema.tTagLinks,
          {'tag_id': tid, 'module': 'diary', 'item_id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        n++;
      }
    }
    if (n > 0) AppLog.addKey('标签池首次导入历史标签：$n 条关联');
    return n;
  }

  /// 跨模块搜索（口径④）：命中标签 + 三模块里带该标签或含关键词的内容。
  ///
  /// 搜索结果**忽略作用域**——搜的是「池」，不是「本模块能选什么」。
  /// 内容侧三路：日记正文（富文本按 plainBody 出摘要）／笔记标题与正文／时间块备注。
  /// 时间模块目前没有标签属性，所以它只可能因**关键词**命中，不会因标签命中。
  Future<({List<Tag> tags, List<TagSearchHit> rows})> search(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) {
      return (tags: const <Tag>[], rows: const <TagSearchHit>[]);
    }
    final lower = q.toLowerCase();
    final pool = await list();
    final hits = [for (final t in pool) if (t.name.toLowerCase().contains(lower)) t];
    final hitNames = {for (final t in hits) t.name};
    final rows = <TagSearchHit>[];
    // 日记：正文含关键词，或挂着命中标签
    final diaryRows = await db.query(DbSchema.tJournal,
        columns: ['id', 'entry_date', 'content', 'created_at', 'updated_at', 'mood'],
        where: 'deleted_at IS NULL AND content LIKE ?',
        whereArgs: ['%$q%'],
        orderBy: 'entry_date DESC',
        limit: 8);
    final diaryHits = <int, JournalEntry>{};
    for (final r in diaryRows) {
      final e = JournalEntry.fromRow(r);
      diaryHits[e.id!] = e;
    }
    if (hitNames.isNotEmpty) {
      final ids = <int>{};
      for (final t in hits) {
        ids.addAll(await _itemsOfTag(t.id, 'diary'));
      }
      if (ids.isNotEmpty) {
        final more = await db.query(DbSchema.tJournal,
            columns: ['id', 'entry_date', 'content', 'created_at', 'updated_at', 'mood'],
            where: 'deleted_at IS NULL AND id IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: ids.toList(),
            orderBy: 'entry_date DESC',
            limit: 8);
        for (final r in more) {
          final e = JournalEntry.fromRow(r);
          diaryHits[e.id!] = e;
        }
      }
    }
    final diaryTags = await namesOfMany('diary', diaryHits.keys.toList());
    for (final e in diaryHits.values) {
      final body = e.plainBody.replaceAll('\n', ' ');
      rows.add(TagSearchHit(
        module: 'diary',
        title: '${e.day.year}-${_two(e.day.month)}-${_two(e.day.day)} 日记',
        sub: body.length <= 42 ? body : '${body.substring(0, 42)}…',
        tags: (diaryTags[e.id] ?? const []).join(' · '),
      ));
    }
    // 笔记：标题或正文含关键词（富文本转纯文本再比）
    final noteRows = await db.query(DbSchema.tNotes,
        columns: ['id', 'title', 'content', 'kind'],
        where: 'deleted_at IS NULL AND (title LIKE ? OR content LIKE ?)',
        whereArgs: ['%$q%', '%$q%'],
        orderBy: 'updated_at DESC',
        limit: 8);
    for (final r in noteRows) {
      final rawContent = (r['content'] as String?) ?? '';
      final body = (r['kind'] as String?) == 'rich'
          ? Note.richToPlain(rawContent)
          : Note.stripMdImages(rawContent);
      final one = body.replaceAll('\n', ' ');
      rows.add(TagSearchHit(
        module: 'note',
        title: ((r['title'] as String?) ?? '').trim().isEmpty
            ? '未命名笔记'
            : (r['title'] as String).trim(),
        sub: one.length <= 42 ? one : '${one.substring(0, 42)}…',
      ));
    }
    // 时间块：只按备注关键词（时间模块没有标签属性）
    final blockRows = await db.query(DbSchema.tTimeBlocks,
        columns: ['id', 'note', 'category', 'start_min'],
        where: 'note LIKE ?',
        whereArgs: ['%$q%'],
        orderBy: 'day DESC',
        limit: 6);
    for (final r in blockRows) {
      final min = (r['start_min'] as int?) ?? 0;
      rows.add(TagSearchHit(
        module: 'time',
        title: '${_two(min ~/ 60)}:${_two(min % 60)} · ${(r['category'] as String?) ?? ''}',
        sub: ((r['note'] as String?) ?? '').replaceAll('\n', ' '),
      ));
    }
    return (tags: hits, rows: rows.take(12).toList());
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// 取/建：按名字（不区分大小写）找池内标签，没有就建一枚只属 [module] 的。
  Future<int> _ensureTag(String name, String module) async {
    final t = await byName(name);
    if (t != null) return t.id;
    return db.insert(DbSchema.tTags, {
      'name': tagNameNormalize(name),
      'scopes': tagScopesEncode({module}),
      'sort': await _nextSort(),
      'builtin': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> _nextSort() async {
    final v = Sqflite.firstIntValue(
            await db.rawQuery('SELECT MAX(sort) FROM ${DbSchema.tTags}')) ??
        0;
    return v + 10;
  }

  Future<List<int>> _itemsOfTag(int tagId, String module) async {
    final rows = await db.query(DbSchema.tTagLinks,
        columns: ['item_id'],
        where: 'tag_id = ? AND module = ?',
        whereArgs: [tagId, module]);
    return [for (final r in rows) r['item_id'] as int];
  }

  static List<String> _decodeNames(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final out = <String>[];
    void take(String s) {
      final n = tagNameNormalize(s);
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }

    try {
      final l = jsonDecode(raw);
      if (l is List) {
        for (final e in l) {
          take('$e');
        }
        return out;
      }
    } catch (_) {
      // 老数据/手工改库可能写成逗号串——与 `JournalEntry._decodeTags` 同兜底。
    }
    for (final s in raw.split(',')) {
      take(s);
    }
    return out;
  }
}

/// 名字规范化：去首尾空白、去前导 `#`（原型 `replace(/^#+/,'')`）。
///
/// 池内名字**一律不带 `#`**——`#` 只在渲染时加。历史筛选键里带 `#` 的由
/// `diaryHit` 兼容，不靠池里存两种写法。
String tagNameNormalize(String raw) =>
    raw.trim().replaceFirst(RegExp(r'^#+'), '').trim();
