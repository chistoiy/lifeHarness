import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// 应用数据库封装（sqflite）。Repository 层通过它取得 [Database]，
/// 以便日后按需切换实现（计划书风险项：DB 层隔离）。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('AppDatabase 尚未初始化，请先调用 open()。');
    }
    return d;
  }

  bool get isInitialized => _db != null;

  /// 打开（并按需建表/迁移）。[pathOverride] 供测试注入内存库路径。
  Future<Database> open({String? pathOverride}) async {
    if (_db != null) return _db!;
    final dir = pathOverride ?? await getDatabasesPath();
    final path = p.join(dir, DbSchema.fileName);
    _db = await openDatabase(
      path,
      version: DbSchema.version,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (d, v) async {
        final batch = d.batch();
        for (final sql in DbSchema.createStatements) {
          batch.execute(sql);
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (d, oldV, newV) async {
        // 迁移骨架：按版本逐级升级；预留表已在此前建好，后续里程碑补 ALTER。
        // 迁移自检（需求 8.3）：迁移前后核对行数/完整性，此处留接入点。
        await _runMigrations(d, oldV, newV);
      },
    );
    return _db!;
  }

  Future<void> _runMigrations(Database d, int from, int to) async {
    // 逐级执行 DbSchema.migrations；迁移自检（需求 8.3）留行数核对接入点。
    for (var v = from; v < to; v++) {
      final stmts = DbSchema.migrations[v] ?? const [];
      final batch = d.batch();
      for (final sql in stmts) {
        batch.execute(sql);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// 通用 DAO 基类：子类声明 [table] 即可获得基础 CRUD，减少样板。
abstract class DaoBase<T> {
  DaoBase(this.db);

  final Database db;

  /// 表名。
  String get table;

  Future<List<Map<String, Object?>>> rawAll({String? where, List<Object?>? args, String? orderBy}) =>
      db.query(table, where: where, whereArgs: args, orderBy: orderBy);

  Future<Map<String, Object?>?> rawById(Object id) =>
      db.query(table, where: 'id = ?', whereArgs: [id], limit: 1).then((r) => r.isEmpty ? null : r.first);

  Future<Object> insert(Map<String, Object?> values) => db.insert(table, values);

  Future<int> update(Object id, Map<String, Object?> values) =>
      db.update(table, values, where: 'id = ?', whereArgs: [id]);

  Future<int> delete(Object id) => db.delete(table, where: 'id = ?', whereArgs: [id]);

  /// 行模型转换由子类实现。
  T fromRow(Map<String, Object?> row);
}
