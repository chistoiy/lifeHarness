/// 轮7 拍板（2026-10-04）：X-Ray 派生数据生命周期 + 备份排除 常驻回归。
///
/// 口径：
/// - X-Ray `mention/entity/task` ＝ 可再生派生数据（按书从源 EPUB 重解析），
///   不进备份/同步快照（`kRegenerableExcluded` 恒排除）；
/// - 用户词典 `xray_userdict` 分两作用域：`GLOBAL`（b 类，全局公共实体，永久保留）
///   与 `scope=书 md5`（a 类，仅本书，随书彻底删除）；
/// - v35 迁移清扫「所属书已彻底删除」的历史孤行（软删书的 md5 仍在 books 表 → 保留）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _schemaDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DbSchema.version,
        onCreate: (d, v) async {
          final batch = d.batch();
          for (final sql in DbSchema.createStatements) {
            batch.execute(sql);
          }
          await batch.commit(noResult: true);
        },
      ),
    );

Future<int> _count(Database db, String sql) async =>
    (await db.rawQuery(sql)).first.values.first as int;

Future<void> _seedBook(Database db, String id,
    {String? md5, int? deletedAt}) {
  return db.insert(DbSchema.tBooks, {
    'id': id,
    'title': '书$id',
    'md5': md5,
    'deleted_at': deletedAt,
    'created_at': 1,
    'updated_at': 1,
  });
}

/// 给某 md5 铺满四张 X-Ray 表各一行（含 a 类按书词库）。
Future<void> _seedXray(Database db, String md5) async {
  await db.insert(DbSchema.tXrayTask,
      {'book_md5': md5, 'status': 'success', 'update_time': 1});
  final eid = await db.insert(DbSchema.tXrayEntity,
      {'book_md5': md5, 'name': '词', 'type': 'per'});
  await db.insert(
      DbSchema.tXrayMention, {'entity_id': eid, 'book_md5': md5, 'ch': 1, 'para': 1});
  await db.insert(DbSchema.tXrayUserdict,
      {'scope': md5, 'word': '养成的词', 'action': 'add', 'create_time': 1});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late Directory work;

  setUp(() async {
    LhBak.snapshotFactory = databaseFactoryFfi;
    db = await _schemaDb();
    work = await Directory.systemTemp.createTemp('xray_life_');
  });
  tearDown(() async {
    await db.close();
    try {
      work.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('v35 迁移：清扫所属书已消失的 X-Ray 孤行', () {
    test('GLOBAL 与在册/垃圾箱书的行保留，仅无书引用的 md5 行被删', () async {
      await _seedBook(db, 'live', md5: 'm-live');
      await _seedBook(db, 'trash', md5: 'm-trash', deletedAt: 5);
      await _seedXray(db, 'm-live');
      await _seedXray(db, 'm-trash');
      await _seedXray(db, 'm-gone'); // 书已彻底删除 → 孤行
      await db.insert(DbSchema.tXrayUserdict, {
        'scope': 'GLOBAL',
        'word': '全局词',
        'action': 'add',
        'create_time': 1,
      });

      for (final sql in DbSchema.migrations[34]!) {
        await db.execute(sql);
      }

      expect(await _count(db, "SELECT COUNT(*) FROM xray_mention WHERE book_md5='m-gone'"), 0);
      expect(await _count(db, "SELECT COUNT(*) FROM xray_entity WHERE book_md5='m-gone'"), 0);
      expect(await _count(db, "SELECT COUNT(*) FROM xray_task WHERE book_md5='m-gone'"), 0);
      expect(await _count(db, "SELECT COUNT(*) FROM xray_userdict WHERE scope='m-gone'"), 0);
      // 在册 + 垃圾箱书的派生数据保留（可恢复）；GLOBAL 词库永不被扫。
      expect(await _count(db, "SELECT COUNT(*) FROM xray_mention WHERE book_md5 IN ('m-live','m-trash')"), 2);
      expect(await _count(db, "SELECT COUNT(*) FROM xray_userdict WHERE scope='GLOBAL'"), 1);
    });
  });

  group('purgeBook 连带：a 类随书删·b 类 GLOBAL 保留·同 md5 他书引用则留', () {
    test('彻底删除唯一持指纹的书 → 该书 X-Ray 派生与按书词库清空，GLOBAL 不动',
        () async {
      await _seedBook(db, 'only', md5: 'm-only');
      await _seedXray(db, 'm-only');
      await db.insert(DbSchema.tXrayUserdict,
          {'scope': 'GLOBAL', 'word': 'g', 'action': 'add', 'create_time': 1});

      await ReadRepository(db).purgeBook('only');

      expect(await _count(db, 'SELECT COUNT(*) FROM xray_mention'), 0);
      expect(await _count(db, 'SELECT COUNT(*) FROM xray_entity'), 0);
      expect(await _count(db, 'SELECT COUNT(*) FROM xray_task'), 0);
      expect(await _count(db, "SELECT COUNT(*) FROM xray_userdict WHERE scope='m-only'"), 0);
      expect(await _count(db, "SELECT COUNT(*) FROM xray_userdict WHERE scope='GLOBAL'"), 1);
    });

    test('同 md5 仍有另一书行 → 派生数据保留（不误删共存书）', () async {
      await _seedBook(db, 'dup-a', md5: 'm-dup');
      await _seedBook(db, 'dup-b', md5: 'm-dup');
      await _seedXray(db, 'm-dup');

      await ReadRepository(db).purgeBook('dup-a');

      expect(await _count(db, "SELECT COUNT(*) FROM xray_mention WHERE book_md5='m-dup'"), 1);
      await ReadRepository(db).purgeBook('dup-b'); // 最后一本才清
      expect(await _count(db, "SELECT COUNT(*) FROM xray_mention WHERE book_md5='m-dup'"), 0);
    });

    test('无 md5 的旧书行删除不炸（懒补算指纹前形态）', () async {
      await _seedBook(db, 'nomd5', md5: null);
      await _seedXray(db, 'm-other');
      await _seedBook(db, 'other', md5: 'm-other');
      await ReadRepository(db).purgeBook('nomd5');
      expect(await _count(db, 'SELECT COUNT(*) FROM xray_mention'), 1);
    });
  });

  group('备份恒排除可再生派生表', () {
    test('exportBackup 落 manifest.excludedTables 含三表，包内快照无 xray_mention',
        () async {
      await _seedBook(db, 'b1', md5: 'm1');
      await _seedXray(db, 'm1');
      final svc = BackupService(
        exportDir: () => work.path,
        db: () async => db,
      );
      final res = await svc.exportBackup();
      expect(res.manifest.excludedTables,
          containsAll(['xray_mention', 'xray_entity', 'xray_task']));
      // userdict 不在排除列（用户养成数据照常入包）。
      expect(res.manifest.excludedTables, isNot(contains('xray_userdict')));
      // 快照库内确实无这三张派生表（DROP 后打包），verify 仍通过。
      await LhBak.verify(res.file.path);
      final m = res.manifest;
      expect(m.tables.containsKey('xray_mention'), isFalse);
    });
  });
}
