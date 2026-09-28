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
part 'read_repo_dict.dart';
part 'read_repo_list.dart';
part 'read_repo_stat.dart';
part 'read_repo_import.dart';
part 'read_repo_export.dart';
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
        _RepoToc,
        _RepoDict,
        _RepoLists,
        _RepoStats,
        _RepoImport,
        _RepoExport,
        _RepoDouban {
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

  // ---- 书单（批4 · 计划 §2.3：手动 items / 年度 auto_year 动态成员）----

  Future<List<BookList>> allLists() async => (await db.query(
    DbSchema.tBookLists,
    where: 'deleted_at IS NULL',
    orderBy: 'sort ASC, id DESC',
  )).map(BookList.fromRow).toList();

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
}
