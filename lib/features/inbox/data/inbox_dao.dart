import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/inbox_item.dart';

/// inbox_items 表数据访问对象（只列未整理；分流=打标，删除=丢弃）。
class InboxDao {
  InboxDao(this.db);

  final Database db;

  String get table => DbSchema.tInbox;

  /// 未整理条目（新→旧）。
  Future<List<InboxItem>> listPending() async =>
      (await db.query(table,
          where: 'routed_to IS NULL', orderBy: 'created_at DESC'))
          .map(InboxItem.fromRow)
          .toList();

  Future<int> insert(InboxItem item) => db.insert(table, item.toRow());

  Future<void> route(int id, String to, int? ref) => db.update(
        table,
        {'routed_to': to, 'routed_ref': ref},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> remove(int id) =>
      db.delete(table, where: 'id = ?', whereArgs: [id]);
}
