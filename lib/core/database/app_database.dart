import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../logging/app_log.dart';
import 'schema.dart';

/// 应用数据库封装（sqflite）。Repository 层通过它取得 [Database]，
/// 以便日后按需切换实现（计划书风险项：DB 层隔离）。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  /// 最近一次 open 实际使用的库文件路径（close 后仍保留，供快照新鲜度判定
  /// 取 mtime；R3② 复用快照依据）。未初始化时为 null。
  String? _openedPath;
  String? get openedPath => _openedPath;

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
    _openedPath = path;
    // L1 日志批：建库/迁移/失败全程留痕（炸机排查的唯一线索）。
    // src 显式标注：onCreate/onUpgrade 走 sqflite 异步回调，调用帧里没有业务帧，
    // 自动归类会落到「系统」；日志页要按「数据库」来源筛，故显式带源。
    AppLog.addKey('数据库打开：目标版本 ${DbSchema.version}', src: '数据库');
    try {
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
          AppLog.addKey(
            '数据库建表完成：v$v · ${DbSchema.createStatements.length} 条语句',
            src: '数据库',
          );
        },
        onUpgrade: (d, oldV, newV) async {
          AppLog.addKey('数据库升级：v$oldV → v$newV', src: '数据库');
          // 迁移骨架：按版本逐级升级；预留表已在此前建好，后续里程碑补 ALTER。
          // 迁移自检（需求 8.3）：迁移前后核对行数/完整性，此处留接入点。
          await _runMigrations(d, oldV, newV);
        },
      );
    } catch (e, st) {
      AppLog.add('数据库打开失败：$e', level: LhLevel.error, src: '数据库');
      AppLog.addStack(st.toString(), src: '数据库');
      rethrow;
    }
    return _db!;
  }

  Future<void> _runMigrations(Database d, int from, int to) async {
    // 逐级执行 DbSchema.migrations；迁移自检（需求 8.3）留行数核对接入点。
    for (var v = from; v < to; v++) {
      final stmts = DbSchema.migrations[v] ?? const [];
      AppLog.addKey('迁移 v${v + 1} 开始：${stmts.length} 条语句', src: '数据库');
      final batch = d.batch();
      for (final sql in stmts) {
        batch.execute(sql);
      }
      await batch.commit(noResult: true);
      AppLog.addKey('迁移 v${v + 1} 完成', src: '数据库');
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
