import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/note.dart';

/// notes 表数据访问对象（M0 最小集：写入与列表；M1 补编辑器全套）。
class NoteDao {
  NoteDao(this.db);

  final Database db;

  String get table => DbSchema.tNotes;

  Future<List<Note>> list() async =>
      (await db.query(table, orderBy: 'pinned DESC, updated_at DESC'))
          .map(Note.fromRow)
          .toList();

  Future<int> insert(Note n) => db.insert(table, n.toRow());
}
