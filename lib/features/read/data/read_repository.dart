import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/book.dart';
import '../domain/book_dict.dart';
import '../domain/book_list.dart';
import '../domain/book_progress.dart';
import '../domain/book_quote.dart';
import '../domain/book_session.dart';
import '../domain/book_toc.dart';
import '../domain/shelf_query.dart';
import 'isbn_enrich.dart';
import 'read_import.dart';

part 'read_repo_book.dart';
part 'read_repo_session.dart';
part 'read_repo_quote.dart';
part 'read_repo_toc.dart';

/// 治理G7d④ prep：一天毫秒数从类内 static 提为库级 const（值与写法一字未改）。
/// extension 成员能裸访问宿主类的**实例**成员，但宿主类的 static 在扩展里裸名不解析；
/// _dayMs 同时被 quote 群与 imp 群裸引用，提为库级后两侧零改动可用。
const int _dayMs = 24 * 60 * 60 * 1000;
/// 阅读模块仓储（M1批3 · 计划 §2.1 三表）。
///
/// 口径：
/// - 软删除统一 deleted_at（记录管理回收站语义与其他模块一致）；
/// - 累计时长/次数不存列，由 book_sessions 聚合派生（sessionAggByBook）；
/// - last_read_at 为聚合索引列：开始/读完/摘录/会话结束四类活动取最大（§3.2）；
/// - 全局单活计时会话：开始新会话自动结束旧会话（L4 流水批2 接）。
///
/// 治理G7d④ 结构（1,955 行按域分 part）：本类只剩构造转发与公开静态 dayStartMs，
/// 实装在 `_ReadRepoBase`（枢纽层＝字段/构造 + 被跨群调用的公共入口）与同库各域
/// mixin（书籍/会话/摘录/目录/字典/书单/统计/导入/导出·缓存）中；mixin 成员经 with
/// 组合后仍是 ReadRepository 的**真实例成员**，库内库外调用写法一字不改。
/// 之所以走 mixin 而非 extension：本类是公开 API 类型，成员被 providers/UI/测试经
/// 传递来的实例调用，而 extension 成员只有在调用方**直接 import 声明库**时才可见
/// （read_log_page 等只 import read_providers → 会报 undefined_method）。
class ReadRepository extends _ReadRepoBase
    with
        _RepoBooks,
        _RepoSessions,
        _RepoQuotes,
        _RepoToc {
  ReadRepository(super.db);

  /// 自然日起点（外部 read_providers 以 ReadRepository.dayStartMs 调用，故必须留本类）。
  /// 治理G7d④ prep：库内三处裸调用相应写作 ReadRepository.dayStartMs
  /// （静态成员不随继承/mixin/扩展可见，必须类名限定）。
  static int dayStartMs(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}
/// 枢纽层：各域 mixin 唯一的 `on` 约束，只放字段/构造与被跨群调用的入口方法。
/// 判据＝「谁会被别的群调用」，故这些方法不外提到任何一个域。
abstract class _ReadRepoBase {
  _ReadRepoBase(this.db);

  final Database db;
  final Random _rng = Random();

  String _newId() =>
      'b${DateTime.now().microsecondsSinceEpoch}${_rng.nextInt(9999)}';

  // ---- 书 ----

  Future<List<Book>> allBooks() async =>
      (await db.query(DbSchema.tBooks)).map(Book.fromRow).toList();

  Future<Book?> bookById(String id) async {
    final rows = await db.query(
      DbSchema.tBooks,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  /// 作者/出版社自动登记字典（计划 §4 批2；INSERT OR IGNORE 依唯一索引去重）。
  Future<void> _registerDictFor(Book b) async {
    for (final (kind, name) in [
      (DictEntry.kAuthor, b.author),
      (DictEntry.kPublisher, b.publisher ?? ''),
    ]) {
      if (name.trim().isEmpty) continue;
      final exists = await db.query(
        DbSchema.tBookDict,
        where: 'kind = ? AND name = ?',
        whereArgs: [kind, name.trim()],
        limit: 1,
      );
      if (exists.isEmpty) {
        final maxSort =
            Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COALESCE(MAX(sort),0) FROM ${DbSchema.tBookDict} WHERE kind = ?',
                [kind],
              ),
            ) ??
            0;
        await db.insert(
          DbSchema.tBookDict,
          DictEntry(kind: kind, name: name.trim(), sort: maxSort + 1).toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  /// 活动类写入后统一刷 last_read_at（摘录新增/会话结束/状态变更）。
  Future<void> touchLastRead(String bookId, [int? ms]) async {
    final b = await bookById(bookId);
    if (b == null) return;
    final now = ms ?? DateTime.now().millisecondsSinceEpoch;
    if ((b.lastReadAt ?? 0) >= now) return;
    await db.update(
      DbSchema.tBooks,
      {
        'last_read_at': now,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<BookSession>> allSessions() async => (await db.query(
    DbSchema.tBookSessions,
    orderBy: 'started_at ASC',
  )).map(BookSession.fromRow).toList();

  Future<List<BookQuote>> quotesOf(String bookId) async => (await db.query(
    DbSchema.tBookQuotes,
    where: 'book_id = ? AND deleted_at IS NULL',
    whereArgs: [bookId],
    orderBy: 'created_at DESC',
  )).map(BookQuote.fromRow).toList();

  Future<List<BookQuote>> allQuotes() async => (await db.query(
    DbSchema.tBookQuotes,
    where: 'deleted_at IS NULL',
    orderBy: 'created_at ASC',
  )).map(BookQuote.fromRow).toList();

  // ---- 书架资料字典（§3.4 五类 CRUD · 改名事务内回写 books）----

  Future<List<DictEntry>> dictOf(String kind) async => (await db.query(
    DbSchema.tBookDict,
    where: 'kind = ?',
    whereArgs: [kind],
    orderBy: 'sort ASC, id ASC',
  )).map(DictEntry.fromRow).toList();

  Future<void> dictAdd(String kind, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await db.insert(
      DbSchema.tBookDict,
      DictEntry(kind: kind, name: n).toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 引用计数（删除前守卫）：books 直列 + tags/quotes 多值列。
  Future<int> dictRefCount(DictEntry e) async {
    switch (e.kind) {
      case DictEntry.kAuthor:
        return Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tBooks} WHERE deleted_at IS NULL AND author = ?',
                [e.name],
              ),
            ) ??
            0;
      case DictEntry.kPublisher:
        return Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tBooks} WHERE deleted_at IS NULL AND publisher = ?',
                [e.name],
              ),
            ) ??
            0;
      case DictEntry.kSource:
        return Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tBooks} WHERE deleted_at IS NULL AND source = ?',
                [e.name],
              ),
            ) ??
            0;
      case DictEntry.kGroup:
        return Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tBooks} WHERE deleted_at IS NULL AND grp = ?',
                [e.name],
              ),
            ) ??
            0;
      default:
        var n = 0;
        for (final b in (await allBooks()).where((b) => !b.isDeleted)) {
          if (b.tags.contains(e.name)) n++;
        }
        return n;
    }
  }

  /// 全值域批量引用计数（资料管理单类页 · 原型 bmCount 逐值口径）：
  /// 直列走 GROUP BY，标签展开 books.tags 逗号列累加。
  Future<Map<String, int>> dictRefCounts(String kind) async {
    if (kind == DictEntry.kTag) {
      final out = <String, int>{};
      for (final b in (await allBooks()).where((b) => !b.isDeleted)) {
        for (final t in b.tags) {
          out[t] = (out[t] ?? 0) + 1;
        }
      }
      return out;
    }
    final col = switch (kind) {
      DictEntry.kAuthor => 'author',
      DictEntry.kPublisher => 'publisher',
      DictEntry.kSource => 'source',
      _ => 'grp',
    };
    final rows = await db.rawQuery(
      'SELECT $col AS v, COUNT(*) AS n FROM ${DbSchema.tBooks} '
      'WHERE deleted_at IS NULL AND $col IS NOT NULL AND $col != \'\' '
      'GROUP BY $col',
    );
    return {
      for (final r in rows)
        r['v'] as String: (r['n'] as int?) ?? 0,
    };
  }

  /// 改名联动（事务内回写）：作者/出版社/来源/分组直列覆盖；标签走行内重算，
  /// 同步书摘 tags（笔记库按标签筛选口径一致）。
  /// e.id==null＝books 里已存在但字典缺行的合成项：只回写值域列并补登记字典。
  Future<void> dictRename(DictEntry e, String newName) async {
    final n = newName.trim();
    if (n.isEmpty || n == e.name) return;
    await db.transaction((txn) async {
      if (e.id != null) {
        await txn.update(
          DbSchema.tBookDict,
          {'name': n},
          where: 'id = ?',
          whereArgs: [e.id],
        );
      }
      final col = switch (e.kind) {
        DictEntry.kAuthor => 'author',
        DictEntry.kPublisher => 'publisher',
        DictEntry.kSource => 'source',
        DictEntry.kGroup => 'grp',
        _ => null,
      };
      if (col != null) {
        await txn.rawUpdate(
          'UPDATE ${DbSchema.tBooks} SET $col = ?, updated_at = ? WHERE $col = ?',
          [n, DateTime.now().millisecondsSinceEpoch, e.name],
        );
        return;
      }
      final rows = await txn.query(
        DbSchema.tBooks,
        columns: ['id', 'tags'],
        where: "tags LIKE ?",
        whereArgs: ['%${e.name}%'],
      );
      for (final r in rows) {
        final tags = splitTags(
          r['tags'] as String?,
        ).map((t) => t == e.name ? n : t).toList();
        await txn.update(
          DbSchema.tBooks,
          {'tags': tags.join(',')},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      final qs = await txn.query(
        DbSchema.tBookQuotes,
        columns: ['id', 'tags'],
        where: "tags LIKE ?",
        whereArgs: ['%${e.name}%'],
      );
      for (final r in qs) {
        final tags = splitTags(
          r['tags'] as String?,
        ).map((t) => t == e.name ? n : t).toList();
        await txn.update(
          DbSchema.tBookQuotes,
          {'tags': tags.join(',')},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
    });
  }

  Future<void> dictDelete(DictEntry e) async {
    if (e.id == null) return;
    await db.delete(DbSchema.tBookDict, where: 'id = ?', whereArgs: [e.id]);
  }

  // ---- 书单（批4 · 计划 §2.3：手动 items / 年度 auto_year 动态成员）----

  Future<List<BookList>> allLists() async => (await db.query(
    DbSchema.tBookLists,
    where: 'deleted_at IS NULL',
    orderBy: 'sort ASC, id DESC',
  )).map(BookList.fromRow).toList();

  Future<BookList?> findAutoYear(int year) async {
    final rows = await db.query(
      DbSchema.tBookLists,
      where: 'deleted_at IS NULL AND auto_year = ?',
      whereArgs: [year],
      limit: 1,
    );
    return rows.isEmpty ? null : BookList.fromRow(rows.first);
  }

  /// 新建书单；[autoYear] 非空时该年已读成员无需写 items（动态求）。
  Future<BookList> addList(
    BookList l, {
    List<String> bookIds = const [],
    int? autoYear,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxSort =
        Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COALESCE(MAX(sort),0) FROM ${DbSchema.tBookLists} WHERE deleted_at IS NULL',
              ),
            ) ??
            0;
    final id = await db.insert(DbSchema.tBookLists, {
      'name': l.name,
      'note': l.note,
      'auto_year': autoYear,
      'sort': maxSort + 1,
      'created_at': now,
      'updated_at': now,
    });
    if (bookIds.isNotEmpty) await setListBooks(id, bookIds);
    return (await listById(id))!;
  }

  Future<BookList?> listById(int id) async {
    final rows = await db.query(
      DbSchema.tBookLists,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : BookList.fromRow(rows.first);
  }

  Future<void> updateList(BookList l) => db.update(
    DbSchema.tBookLists,
    {
      'name': l.name,
      'note': l.note,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: [l.id],
  );

  /// 整体重排成员（选书弹层保存共用；年度自动单不调用）。
  Future<void> setListBooks(int listId, List<String> bookIds) => db.transaction(
    (txn) async {
      await txn.delete(
        DbSchema.tBookListItems,
        where: 'list_id = ?',
        whereArgs: [listId],
      );
      for (var i = 0; i < bookIds.length; i++) {
        await txn.insert(
          DbSchema.tBookListItems,
          {'list_id': listId, 'book_id': bookIds[i], 'pos': i},
        );
      }
      await txn.update(
        DbSchema.tBookLists,
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [listId],
      );
    },
  );

  Future<void> addBookToList(int listId, String bookId) async {
    final maxPos =
        Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COALESCE(MAX(pos),-1) FROM ${DbSchema.tBookListItems} WHERE list_id = ?',
                [listId],
              ),
            ) ??
            -1;
    await db.insert(
      DbSchema.tBookListItems,
      {'list_id': listId, 'book_id': bookId, 'pos': maxPos + 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 移出书单＝只删成员行，书本身保留（原型 blRm 文案口径）。
  Future<void> removeBookFromList(int listId, String bookId) => db.delete(
    DbSchema.tBookListItems,
    where: 'list_id = ? AND book_id = ?',
    whereArgs: [listId, bookId],
  );

  Future<void> softDeleteList(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbSchema.tBookLists,
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete(
      DbSchema.tBookListItems,
      where: 'list_id = ?',
      whereArgs: [id],
    );
  }

  /// 成员解析：年度单按「已读 && ended_at∈该年」动态求（[desc]＝read.yearSort）；
  /// 手动单按 items.pos 序，跳过已软删书。
  Future<List<Book>> listMembers(BookList l, {bool desc = false}) async {
    final books = await allBooks();
    if (l.autoYear != null) {
      final y = l.autoYear!;
      final done = books.where((b) {
        if (b.state != Book.kStateDone || b.isDeleted) return false;
        if (b.endedAt == null) return false;
        return DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == y;
      }).toList()
        ..sort(
          (a, b) => desc
              ? b.endedAt!.compareTo(a.endedAt!)
              : a.endedAt!.compareTo(b.endedAt!),
        );
      return done;
    }
    final rows = await db.query(
      DbSchema.tBookListItems,
      where: 'list_id = ?',
      whereArgs: [l.id],
      orderBy: 'pos ASC',
    );
    final byId = {for (final b in books) b.id: b};
    return rows
        .map((r) => byId[r['book_id'] as String])
        .whereType<Book>()
        .where((b) => !b.isDeleted)
        .toList();
  }

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

  // ---- 导入（计划 §5 · 三级去重 isbn→作者+书名归一→摘录等价键 · 整批事务 · 撤销本批）----

  /// 一、二级去重：先 ISBN 归一命中，再「作者+书名归一」；书名相同作者不同的
  /// 记为 loose（导入时优先精确、无精确才认 loose），都不中返回 null。
  Future<Book?> findBookFor({String? isbn, String? title, String? author}) async {
    final ni = normIsbn(isbn);
    final nt = normTitle(title);
    if (ni.isEmpty && nt.isEmpty) return null;
    final books = await allBooks();
    if (ni.isNotEmpty) {
      for (final b in books) {
        if (!b.isDeleted && normIsbn(b.isbn) == ni) return b;
      }
    }
    if (nt.isEmpty) return null;
    final na = normTitle(author);
    Book? loose;
    for (final b in books) {
      if (b.isDeleted || normTitle(b.title) != nt) continue;
      if (na.isEmpty || normTitle(b.author) == na) return b;
      loose ??= b;
    }
    return loose;
  }

  /// 解析 + 标注（不落库）；调用方逐行显示「新增 / 已存在 · 跳过」。
  Future<List<ImportRow>> previewImport(ImportChannel ch, String raw) async {
    final seen = <String>{};
    final rows = <ImportRow>[];
    for (final c in parseClips(ch, raw)) {
      final b = await findBookFor(isbn: c.isbn, title: c.book, author: c.author);
      var dup = false;
      if (b != null) {
        final key = quoteDedupKey(b.id, c.chapter, c.page, c.body);
        dup = !seen.add(key) ||
            (await db.query(
              DbSchema.tBookQuotes,
              where: 'dedup_hash = ? AND deleted_at IS NULL',
              whereArgs: [key],
              limit: 1,
            )).isNotEmpty;
      }
      rows.add(ImportRow(c, b?.id, dup));
    }
    return rows;
  }

  /// 整批事务落库：命中已有书补摘录；未建档的按「想读 · 来源=渠道名」自动建档；
  /// origin 记渠道便于二次清洗；导入不改 last_read_at（不挤占「最近阅读」序）。
  Future<ImportOutcome> commitImport(ImportChannel ch, String raw) async {
    final rows = await previewImport(ch, raw);
    var added = 0, skipped = 0;
    final ids = <int>[];
    final created = <Book>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final newBookCache = <String, String>{}; // 批内同书复用新建档
    await db.transaction((txn) async {
      for (final r in rows) {
        if (r.dup) {
          skipped++;
          continue;
        }
        final c = r.clip;
        var bookId = r.bookId ?? newBookCache[normTitle(c.book)];
        if (bookId == null) {
          final nb = Book(
            id: _newId(),
            title: c.book,
            author: c.author.isEmpty ? '佚名' : c.author,
            isbn: (normIsbn(c.isbn).isEmpty) ? null : c.isbn,
            source: ch.name,
            state: Book.kStateWant,
            createdAt: now,
            updatedAt: now,
            lastReadAt: now,
          );
          await txn.insert(DbSchema.tBooks, nb.toRow());
          created.add(nb);
          bookId = nb.id;
          newBookCache[normTitle(c.book)] = bookId;
        }
        final createdMs = c.at?.millisecondsSinceEpoch ?? now;
        final q = BookQuote(
          bookId: bookId,
          kind: c.body.isEmpty
              ? BookQuote.kKindThought
              : BookQuote.kKindMark,
          tag: BookQuote.kTagReso,
          body: c.body,
          thought: c.thought,
          chapter: c.chapter,
          page: c.page,
          loc: c.loc,
          origin: ch.name,
          dedupHash: quoteDedupKey(bookId, c.chapter, c.page, c.body),
          createdAt: createdMs,
          updatedAt: now,
        );
        // 事务内显式查重：唯一索引撞软删残留时 INSERT OR IGNORE 会返回
        // 陈旧 lastInsertRowId，直接吞行会让「撤销本批」删错，故先查后插。
        final clash = await txn.query(
          DbSchema.tBookQuotes,
          where: 'dedup_hash = ?',
          whereArgs: [q.dedupHash],
          limit: 1,
        );
        if (clash.isNotEmpty) {
          skipped++;
          continue;
        }
        final id = await txn.insert(DbSchema.tBookQuotes, q.toRow());
        ids.add(id);
        await txn.insert(
          DbSchema.tBookReviews,
          {'quote_id': id, 'stage': 0, 'next_at': createdMs + _dayMs},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        added++;
      }
    });
    for (final b in created) {
      await _registerDictFor(b);
    }
    return (
      added: added,
      skipped: skipped,
      booksCreated: created.length,
      ids: ids,
    );
  }

  /// 撤销本批：硬删导入行与其复习档位（撤销≠用户删除，不留回收站残骸）。
  Future<int> undoImportBatch(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final ph = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.delete(
        DbSchema.tBookReviews,
        where: 'quote_id IN ($ph)',
        whereArgs: ids,
      );
      await txn.delete(
        DbSchema.tBookQuotes,
        where: 'id IN ($ph)',
        whereArgs: ids,
      );
    });
    return ids.length;
  }

  /// 按清单建书（原型 impAll）：CSV 渠道走表头别名，其余按
  /// `书名 [作者] [ISBN]` 行式解析；一、二级去重命中即跳过；
  /// 新档＝想读 · 来源「导入清单」· 缺资料提示补齐。
  Future<({int created, int skipped})> importBookList(
    String raw, {
    ImportChannel? ch,
  }) async {
    var created = 0, skipped = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final made = <Book>[];
    final cache = <String, String>{};
    final rows = ch != null && ch.parser == 'csv'
        ? parseCsvBookList(ch, raw)
        : parseBookList(raw);
    for (final r in rows) {
      final exist = await findBookFor(isbn: r.isbn, title: r.title, author: r.author);
      if (exist != null || cache.containsKey(normTitle(r.title))) {
        skipped++;
        continue;
      }
      final b = Book(
        id: _newId(),
        title: r.title,
        author: r.author.isEmpty ? '待补' : r.author,
        isbn: r.isbn,
        source: '导入清单',
        state: Book.kStateWant,
        intro: '由书架清单导入，缺少作者与封面 · 点编辑补齐。',
        createdAt: now,
        updatedAt: now,
        lastReadAt: now,
      );
      await db.insert(DbSchema.tBooks, b.toRow());
      cache[normTitle(r.title)] = b.id;
      made.add(b);
      created++;
    }
    for (final b in made) {
      await _registerDictFor(b);
    }
    return (created: created, skipped: skipped);
  }

  // ---- 导出（计划 §6 数据与存储 · MD 按书分组 / JSON 书架备份）----

  Future<String> buildQuotesMd() async {
    final books = await allBooks();
    books.sort(
      (a, b) => (b.lastReadAt ?? b.createdAt).compareTo(
        a.lastReadAt ?? a.createdAt,
      ),
    );
    final sb = StringBuffer('# 全部书摘\n');
    for (final b in books) {
      final qs = await quotesOf(b.id);
      if (qs.isEmpty) continue;
      sb.write('\n## 《${b.title}》（${b.author}）\n');
      for (final q in qs) {
        if (q.body.isNotEmpty) sb.write('\n> ${q.body.replaceAll('\n', '\n> ')}\n');
        if (q.thought != null && q.thought!.isNotEmpty) {
          sb.write('\n想法：${q.thought}\n');
        }
        final meta = [
          if ((q.chapter ?? '').isNotEmpty) q.chapter,
          if (q.page != null) 'P${q.page}',
          DateTime.fromMillisecondsSinceEpoch(q.createdAt).toIso8601String().substring(0, 10),
          if ((q.origin ?? '').isNotEmpty) q.origin,
        ].join(' · ');
        sb.write('\n— $meta\n');
      }
    }
    return sb.toString();
  }

  /// 单本书摘录 MD（档案页「导出MD」· 批C）。
  Future<String> buildBookQuotesMd(Book b) async {
    final qs = await quotesOf(b.id);
    final sb = StringBuffer('# 《${b.title}》书摘（${b.author}）\n');
    for (final q in qs.reversed) {
      if (q.body.isNotEmpty) {
        sb.write('\n> ${q.body.replaceAll('\n', '\n> ')}\n');
      }
      if (q.thought != null && q.thought!.isNotEmpty) {
        sb.write('\n想法：${q.thought}\n');
      }
      final meta = [
        if ((q.chapter ?? '').isNotEmpty) q.chapter,
        if (q.page != null) 'P${q.page}',
        DateTime.fromMillisecondsSinceEpoch(q.createdAt)
            .toIso8601String()
            .substring(0, 10),
      ].join(' · ');
      sb.write('\n— $meta\n');
    }
    return sb.toString();
  }

  Future<String> buildBackupJson() async {
    final books = await allBooks();
    final quotes = await db.query(DbSchema.tBookQuotes);
    final lists = await allLists();
    final settings = await db.query(
      DbSchema.tSettings,
      where: "key LIKE 'read.%'",
    );
    return const JsonEncoder.withIndent(' ').convert({
      'app': 'LifeHarness',
      'kind': 'bookshelf',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'books': [for (final b in books) b.toRow()],
      'quotes': [...quotes],
      'lists': [for (final l in lists) l.toRow()],
      'settings': {for (final s in settings) s['key'] as String: s['value']},
    });
  }

  // ---- read.* 设置（settings 表 KV · 计划 §6）----

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

  /// 删除单键（批4 删除本地书回收 reader.pos./reader.cfg. 逐书键）。
  Future<void> removeKv(String key) =>
      db.delete(DbSchema.tSettings, where: 'key = ?', whereArgs: [key]);

  Future<int> kvInt(String key, int def) async =>
      int.tryParse(await kv(key) ?? '') ?? def;

  // ---- 豆瓣元数据缓存（v23 douban_meta · 防封批 2026-09-26）----
  // 只存 App 在用的最小字段集（不存整页快照），控制库体积与云备份体积；
  // 手动清理由阅读设置「清除豆瓣缓存」触发（只清表行，不动已落盘封面文件，
  // 封面清理走记录管理的文件口径）。Cookie 不落本库（存 SharedPreferences，
  // 不进 DB 快照/书架备份导出）。

  Future<Map<String, Object?>?> doubanCacheRow(String code) => db.query(
    DbSchema.tDoubanMeta,
    where: 'code = ?',
    whereArgs: [code.trim()],
    limit: 1,
  ).then((r) => r.isEmpty ? null : r.first);

  Future<void> doubanCachePut(
    String code,
    IsbnBookMeta meta, {
    String? subject,
    String? coverPath,
    bool viaSuggest = false,
  }) => db.insert(DbSchema.tDoubanMeta, {
    'code': code.trim(),
    'subject': subject,
    'title': meta.title,
    'author': meta.author,
    'publisher': meta.publisher,
    'pub_date': meta.pubDate,
    'pages': meta.pages,
    'rating': meta.rating,
    'cover_url': meta.coverUrl,
    'cover_path': coverPath,
    'via_suggest': viaSuggest ? 1 : 0,
    'fetched_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<int> doubanCacheCount() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) c FROM ${DbSchema.tDoubanMeta}',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 手动清理：整表清空（阅读设置入口 · 无按行删除需求）。
  Future<void> doubanCacheClear() => db.delete(DbSchema.tDoubanMeta);
}
