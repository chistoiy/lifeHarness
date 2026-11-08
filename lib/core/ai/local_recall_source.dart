/// C11 · 本地召回源装配（只读本地库已有表，零网络、零索引服务）。
///
/// 把「笔记」「书摘」两处本地内容映射成 [RecallDoc]，交给
/// `local_recall.dart` 的关键词内核打分。这里只负责取数与字段映射：
/// 不做向量、不建索引、不上传；`DbLocalRecallSource` 是唯一触库实现，
/// 单测可注入 [LocalRecallSource] 假源，避免真实 I/O。
library;

import 'package:sqflite/sqflite.dart';

import '../database/schema.dart';
import '../logging/app_log.dart';
import 'local_recall.dart';

/// 召回源：一次给出当前本地可召回的文档快照。
abstract class LocalRecallSource {
  Future<List<RecallDoc>> load();
}

/// 从活库读取笔记与书摘（各取最近 [maxDocs] 条，避免全库扫描）。
///
/// 口径：
/// - notes：排除归档与回收站，`title` 空时给「未命名笔记」；
/// - book_quotes：排除回收站，来源名用「书名 · 章节」（章节可空）；
/// - 任一表读取失败只降级该表，不影响另表，更不影响 AI 主链路。
class DbLocalRecallSource implements LocalRecallSource {
  DbLocalRecallSource(this._db, {this.maxDocs = 200});

  final Database _db;
  final int maxDocs;

  @override
  Future<List<RecallDoc>> load() async {
    final out = <RecallDoc>[];
    try {
      final rows = await _db.query(
        DbSchema.tNotes,
        columns: ['id', 'title', 'content'],
        where: 'archived = 0 AND deleted_at IS NULL',
        orderBy: 'updated_at DESC',
        limit: maxDocs,
      );
      for (final r in rows) {
        final body = (r['content'] as String?)?.trim() ?? '';
        if (body.isEmpty) continue;
        final title = (r['title'] as String?)?.trim() ?? '';
        out.add(RecallDoc(
          id: 'note:${r['id']}',
          title: title.isEmpty ? '未命名笔记' : title,
          body: body,
        ));
      }
    } catch (e) {
      AppLog.add('本地召回源·笔记读取失败：$e', level: LhLevel.warn);
    }
    try {
      final rows = await _db.rawQuery(
        'SELECT q.id, q.body, q.chapter, b.title AS book_title '
        'FROM ${DbSchema.tBookQuotes} q '
        'LEFT JOIN ${DbSchema.tBooks} b ON b.id = q.book_id '
        'WHERE q.deleted_at IS NULL '
        'ORDER BY q.created_at DESC LIMIT ?',
        [maxDocs],
      );
      for (final r in rows) {
        final body = (r['body'] as String?)?.trim() ?? '';
        if (body.isEmpty) continue;
        final book = (r['book_title'] as String?)?.trim() ?? '';
        final chapter = (r['chapter'] as String?)?.trim() ?? '';
        final title = [book, chapter].where((s) => s.isNotEmpty).join(' · ');
        out.add(RecallDoc(
          id: 'quote:${r['id']}',
          title: title.isEmpty ? '书摘' : title,
          body: body,
        ));
      }
    } catch (e) {
      AppLog.add('本地召回源·书摘读取失败：$e', level: LhLevel.warn);
    }
    return out;
  }
}

/// 用户输入 → 召回查询串：把本次能力点的变量值拼起来（纯函数，便于守护）。
/// 只用于切词打分，不改变实际发送的 vars；超长值截断避免无谓开销。
String recallQueryFromVars(Map<String, String> vars) {
  final buf = StringBuffer();
  for (final v in vars.values) {
    var s = v.trim();
    if (s.isEmpty) continue;
    if (s.length > 800) s = s.substring(0, 800);
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(s);
    if (buf.length >= 4000) break;
  }
  return buf.toString();
}
