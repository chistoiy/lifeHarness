/// V1.66 备份格式四件套批1常驻用例（工单 20261013 执行面板第三行）：
/// - structVersion=2 入 manifest；
/// - P0-2 退版包恢复＝当前 schema DDL 重建＋列交集拷贝（旧列值不丢、
///   新列带 DDL 默认/NULL、user_version 钉当前、退役表保数据迁入）；
/// - P0-1 附件落盘还原（目录组清旧目录、散件覆盖、加密包解密、路径穿越跳过）；
/// - P0-3 `.lhbak` 套包排除。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 按 V1.66 全量 schema 建一个内存库（同 backup_lh_bak_test 建法）。
Future<Database> openSchemaDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DbSchema.version,
        onCreate: (d, v) async {
          for (final sql in DbSchema.createStatements) {
            await d.execute(sql);
          }
        },
      ),
    );

/// 与 LhBak 内部同口径的逐表统计（verify 双向核对要求 manifest.tables
/// 如实登记快照全部表，手工造包必须先算这步）。
Future<Map<String, TableStat>> _statDb(Database d) async {
  final names = (await d.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"))
      .map((r) => r['name'] as String)
      .toList();
  final out = <String, TableStat>{};
  for (final t in names) {
    final rows = await d.rawQuery(
        'SELECT rowid AS _lhbak_rid, * FROM "$t" ORDER BY rowid');
    final plain = rows
        .map((r) => <String, Object?>{
              for (final e in r.entries)
                if (e.key != '_lhbak_rid') e.key: e.value,
            })
        .toList();
    out[t] = TableStat(rows: plain.length, checksum: tableChecksum(plain));
  }
  return out;
}

/// 手工打包：db 文件 + 实测 manifest（verify 双向口径）。
Future<String> packRaw({
  required String outPath,
  required String dbPath,
  required int dbVersion,
  bool encrypted = false,
}) async {
  final statDb = await databaseFactoryFfi.openDatabase(dbPath,
      options: OpenDatabaseOptions(singleInstance: false));
  final tables = await _statDb(statDb);
  await statDb.close();
  final manifest = {
    'dbVersion': dbVersion,
    'appVersion': '0.2.0',
    'createdAt': DateTime(2026, 9, 1).toIso8601String(),
    'structVersion': 1,
    'tables': {for (final e in tables.entries) e.key: e.value.toJson()},
    'excludedTables': <String>[],
    'encrypted': encrypted,
    'members': ['manifest.json', 'db.sqlite'],
  };
  final encoder = ZipFileEncoder();
  encoder.create(outPath);
  final mBytes = utf8.encode(jsonEncode(manifest));
  encoder.addArchiveFile(ArchiveFile('manifest.json', mBytes.length, mBytes));
  await encoder.addFile(File(dbPath), 'db.sqlite');
  await encoder.close();
  return outPath;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('lhbak_v166_');
  });
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('新包 manifest 带 structVersion=2', () async {
    final db = await openSchemaDb();
    final res = await LhBak.create(
        db: db, outDirPath: temp.path, now: DateTime(2026, 10, 13, 12));
    final zip = ZipDecoder().decodeBytes(res.file.readAsBytesSync());
    final manifest = jsonDecode(
            utf8.decode(zip.findFile('manifest.json')!.content as List<int>))
        as Map<String, dynamic>;
    expect(manifest['structVersion'], 2);
    await db.close();
  });

  test('P0-3：attachDirs 内的 .lhbak 不入包（套包排除）', () async {
    final db = await openSchemaDb();
    final exports = Directory(p.join(temp.path, 'exports'))
      ..createSync(recursive: true);
    File(p.join(exports.path, 'old_backup.lhbak')).writeAsBytesSync([1, 2, 3]);
    File(p.join(exports.path, 'keep.png')).writeAsBytesSync([9, 9]);
    final res = await LhBak.create(
        db: db,
        outDirPath: temp.path,
        attachDirs: [exports.path],
        now: DateTime(2026, 10, 13, 12));
    final zip = ZipDecoder().decodeBytes(res.file.readAsBytesSync());
    final names = zip.files.map((f) => f.name).toList();
    expect(names.where((n) => n.endsWith('.lhbak')), isEmpty,
        reason: '备份包内不得再出现 .lhbak（套包）');
    expect(names.contains('attachments/exports/keep.png'), isTrue,
        reason: '非 .lhbak 附件照常入包');
    await db.close();
  });

  test('P0-2：退版包（旧列集+dbVersion=45）恢复后旧列值在、新列带默认、user_version 钉当前',
      () async {
    final db = await openSchemaDb();
    final probe = DbSchema.tTodos;
    final info = (await db.rawQuery('PRAGMA table_info("$probe")'))
        .map((r) => r as Map<String, dynamic>)
        .toList();
    // 「新列」＝可空非主键列（真实迁移加列都是这种；砍 NOT NULL 无默认列
    // 属测试造伪——列交集拷贝本就无法凭空满足无默认 NOT NULL，批1 首跑实钉）。
    final nullable = info
        .where((c) => (c['notnull'] as int) == 0 && (c['pk'] as int) == 0)
        .map((c) => c['name'] as String)
        .toList();
    expect(nullable, isNotEmpty, reason: 'todos 应有可空列');
    final newCol = nullable.first;
    final tableNames = DbSchema.createStatements
        .map((s) =>
            RegExp(r'CREATE TABLE (?:IF NOT EXISTS )?([A-Za-z_][A-Za-z0-9_]*)',
                    caseSensitive: false)
                .firstMatch(s)
                ?.group(1))
        .whereType<String>()
        .toSet();
    // 造「v45 快照库」：其余表按当前 DDL；todos 按 table_info 砍掉新列，插一行。
    final snapDbPath = p.join(temp.path, 'v45.db');
    final snapDb = await databaseFactoryFfi.openDatabase(snapDbPath,
        options: OpenDatabaseOptions(singleInstance: false, version: 1,
            onCreate: (d, v) async {
      for (final t in tableNames) {
        if (t == probe) continue;
        await d.execute(DbSchema.createStatements.firstWhere((s) =>
            RegExp('CREATE TABLE (?:IF NOT EXISTS )?$t\\b',
                    caseSensitive: false)
                .hasMatch(s)));
      }
      final kept = info.where((c) => c['name'] != newCol).map((c) {
        final notnull = (c['notnull'] as int) == 1 ? ' NOT NULL' : '';
        final pk = (c['pk'] as int) > 0 ? ' PRIMARY KEY' : '';
        return '"${c['name']}" ${c['type']}$pk$notnull';
      }).join(', ');
      await d.execute('CREATE TABLE "$probe" ($kept)');
      final names = info
          .where((c) => c['name'] != newCol)
          .map((c) => '"${c['name']}"')
          .join(',');
      final vals = info.where((c) => c['name'] != newCol).map((c) {
        final isInt = (c['type'] as String).toUpperCase().contains('INT');
        final notnull = (c['notnull'] as int) == 1;
        return isInt ? 1 : (notnull ? 'legacy-val' : null);
      }).toList();
      await d.execute(
          'INSERT INTO "$probe"($names) VALUES(${vals.map((_) => '?').join(',')})',
          vals);
    }));
    await snapDb.close();
    final pkgPath = await packRaw(
        outPath: p.join(temp.path, 'old_v45.lhbak'),
        dbPath: snapDbPath,
        dbVersion: 45);
    await LhBak.unpack(filePath: pkgPath, targetDb: db);
    final afterCols = (await db.rawQuery('PRAGMA table_info("$probe")'))
        .map((r) => r['name'] as String)
        .toList();
    expect(afterCols, containsAll(['title', newCol]),
        reason: '恢复按当前 schema 终态 DDL 重建——新列必须回来');
    final row = await db.rawQuery('SELECT * FROM "$probe"');
    expect(row, hasLength(1));
    expect(row.first[newCol], isNull, reason: '快照缺的可空列落 NULL');
    expect(row.first['title'], 'legacy-val', reason: '旧列值不丢');
    final uv = await db.rawQuery('PRAGMA user_version');
    expect(uv.first['user_version'], DbSchema.version);
    await db.close();
  });

  test('P0-2：退役表（快照有、当前 schema 无）保数据迁入', () async {
    final db = await openSchemaDb();
    final legacyDbPath = p.join(temp.path, 'legacy.db');
    final legacy = await databaseFactoryFfi.openDatabase(legacyDbPath,
        options: OpenDatabaseOptions(singleInstance: false, version: 1,
            onCreate: (d, v) async {
      for (final sql in DbSchema.createStatements) {
        await d.execute(sql);
      }
      await d.execute(
          'CREATE TABLE "retired_events" (id INTEGER PRIMARY KEY, note TEXT)');
      await d
          .execute("INSERT INTO retired_events(note) VALUES ('kept-legacy')");
    }));
    await legacy.close();
    final pkgPath = await packRaw(
        outPath: p.join(temp.path, 'legacy.lhbak'),
        dbPath: legacyDbPath,
        dbVersion: DbSchema.version);
    await LhBak.unpack(filePath: pkgPath, targetDb: db);
    final rows = await db.rawQuery('SELECT note FROM retired_events');
    expect(rows, hasLength(1));
    expect(rows.first['note'], 'kept-legacy');
    await db.close();
  });

  test('P0-1：附件落盘还原——目录组清旧目录、散件覆盖', () async {
    final db = await openSchemaDb();
    final noteImages = Directory(p.join(temp.path, 'note_images'))
      ..createSync(recursive: true);
    File(p.join(noteImages.path, 'fresh.png')).writeAsBytesSync([7, 7, 7]);
    final docs = Directory(p.join(temp.path, 'docs'))
      ..createSync(recursive: true);
    File(p.join(docs.path, 'lifeharness_ledger.csv'))
        .writeAsBytesSync(utf8.encode('packed,bytes'));
    final res = await LhBak.create(
        db: db,
        outDirPath: temp.path,
        attachDirs: [noteImages.path],
        attachFiles: [p.join(docs.path, 'lifeharness_ledger.csv')],
        now: DateTime(2026, 10, 13, 12));
    final targetNoteImages = p.join(temp.path, 'restore', 'note_images');
    Directory(targetNoteImages).createSync(recursive: true);
    File(p.join(targetNoteImages, 'stale.png')).writeAsBytesSync([1]);
    final n = await LhBak.restoreAttachments(
      filePath: res.file.path,
      dirTargets: {'note_images': targetNoteImages},
      rootFilesTarget: docs.path,
    );
    expect(n, 2, reason: '目录组 1 个 + 散件 1 个');
    expect(File(p.join(targetNoteImages, 'stale.png')).existsSync(), isFalse,
        reason: '组在包内才清旧目录——陈旧文件不得残留');
    expect(File(p.join(targetNoteImages, 'fresh.png')).readAsBytesSync(),
        [7, 7, 7]);
    expect(File(p.join(docs.path, 'lifeharness_ledger.csv')).readAsStringSync(),
        'packed,bytes', reason: '散件按包内容覆盖');
    await db.close();
  });

  test('P0-1：加密包附件逐成员解密落盘', () async {
    final db = await openSchemaDb();
    final covers = Directory(p.join(temp.path, 'book_covers'))
      ..createSync(recursive: true);
    File(p.join(covers.path, 'a.png')).writeAsBytesSync([7, 7, 7]);
    final res = await LhBak.create(
        db: db,
        outDirPath: temp.path,
        attachDirs: [covers.path],
        passphrase: 'pw-v166',
        now: DateTime(2026, 10, 13, 12));
    expect(res.manifest.encrypted, isTrue, reason: '旧口令档能力保留（纯明文指新包默认）');
    final target = p.join(temp.path, 'restore', 'book_covers');
    final n = await LhBak.restoreAttachments(
      filePath: res.file.path,
      dirTargets: {'book_covers': target},
      passphrase: 'pw-v166',
    );
    expect(n, 1);
    expect(File(p.join(target, 'a.png')).readAsBytesSync(), [7, 7, 7]);
    await db.close();
  });

  test('P0-1：恶意成员名（.. 段）跳过不落盘、不穿越', () async {
    final out = Archive();
    final mBytes = utf8.encode(jsonEncode({
      'dbVersion': DbSchema.version,
      'appVersion': '0.2.0',
      'createdAt': DateTime(2026, 9, 1).toIso8601String(),
      'structVersion': 1,
      'tables': <String, dynamic>{},
      'excludedTables': <String>[],
      'encrypted': false,
      'members': ['manifest.json'],
    }));
    out.addFile(ArchiveFile('manifest.json', mBytes.length, mBytes));
    out.addFile(
        ArchiveFile('attachments/note_images/../../evil.txt', 3, [1, 2, 3]));
    final pkgPath = p.join(temp.path, 'evil.lhbak');
    File(pkgPath).writeAsBytesSync(ZipEncoder().encode(out)!);
    final target = p.join(temp.path, 'restore_evil');
    final n = await LhBak.restoreAttachments(
        filePath: pkgPath, dirTargets: {'note_images': target});
    expect(n, 0);
    expect(File(p.join(temp.path, 'evil.txt')).existsSync(), isFalse);
    expect(File(p.join(target, 'evil.txt')).existsSync(), isFalse);
  });
}
