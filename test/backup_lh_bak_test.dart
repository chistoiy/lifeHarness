import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 从 DbSchema.createStatements 解析「实表名」集合（CREATE TABLE 后的裸名）。
final RegExp _createTableRe =
    RegExp(r'CREATE TABLE (?:IF NOT EXISTS )?([A-Za-z_][A-Za-z0-9_]*)', caseSensitive: false);

Set<String> schemaTableNames() {
  final names = <String>{};
  for (final sql in DbSchema.createStatements) {
    final m = _createTableRe.firstMatch(sql);
    if (m != null) names.add(m.group(1)!);
  }
  return names;
}

/// 按 V19 全量 schema 建一个内存库（同 database_schema_test 的建法）。
Future<Database> openSchemaDb() => databaseFactoryFfi.openDatabase(
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

/// 按 rowid 序取全表行（与 LhBak 内部取数口径一致，用于往返比对）。
Future<List<Map<String, Object?>>> orderedRows(Database db, String table) async {
  final rows = await db.rawQuery('SELECT rowid AS _lh_rid, * FROM "$table" ORDER BY rowid');
  return rows
      .map((r) => <String, Object?>{
            for (final e in r.entries)
              if (e.key != '_lh_rid') e.key: e.value,
          })
      .toList();
}

Matcher throwsLhBak(String code) =>
    throwsA(isA<LhBakException>().having((e) => e.code, 'code', code));

/// 用改过的 manifest.json 重新打包（其余成员原样复制），返回新文件路径。
String rebuildWithManifest(String pkgPath, Map<String, dynamic> manifestJson,
    {bool dropManifest = false, String? manifestRaw}) {
  final archive = ZipDecoder().decodeBytes(File(pkgPath).readAsBytesSync());
  final out = Archive();
  if (!dropManifest) {
    final bytes = utf8.encode(manifestRaw ?? jsonEncode(manifestJson));
    out.addFile(ArchiveFile('manifest.json', bytes.length, bytes));
  }
  for (final f in archive) {
    if (f.name == 'manifest.json') continue;
    final content = f.content as List<int>;
    out.addFile(ArchiveFile(f.name, content.length, content));
  }
  final zipBytes = ZipEncoder().encode(out)!;
  final outFile = File('$pkgPath.rebuild');
  outFile.writeAsBytesSync(zipBytes);
  return outFile.path;
}

/// 用 donor 包的 db.sqlite 替换 base 包的 db.sqlite（其余成员原样），返回新文件路径。
String spliceDbFrom(String basePkg, String donorPkg) {
  final base = ZipDecoder().decodeBytes(File(basePkg).readAsBytesSync());
  final donor = ZipDecoder().decodeBytes(File(donorPkg).readAsBytesSync());
  final donorDb = donor.findFile('db.sqlite')!.content as List<int>;
  final out = Archive();
  for (final f in base) {
    final content = f.name == 'db.sqlite' ? donorDb : f.content as List<int>;
    out.addFile(ArchiveFile(f.name, content.length, content));
  }
  final outFile = File('$basePkg.spliced');
  outFile.writeAsBytesSync(ZipEncoder().encode(out)!);
  return outFile.path;
}

void main() {
  sqfliteFfiInit();
  // 生产默认走 sqflite 插件工厂；单测注入 ffi 工厂打开快照文件。
  LhBak.snapshotFactory = databaseFactoryFfi;

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lhbak_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Database> dbWithTodos() async {
    final db = await openSchemaDb();
    await db.insert(DbSchema.tTodos, {'title': '备份测试1', 'created_at': 1, 'updated_at': 1});
    await db.insert(DbSchema.tTodos, {'title': '备份测试2', 'created_at': 2, 'updated_at': 2});
    return db;
  }

  test('tableChecksum 纯函数：空表 "-"，列序稳定，值敏感，MD5 hex', () {
    expect(tableChecksum([]), '-');
    final a = tableChecksum([
      {'a': 1, 'b': 'x'}
    ]);
    final b = tableChecksum([
      {'b': 'x', 'a': 1}
    ]);
    expect(a, b);
    expect(a, isNot(tableChecksum([
      {'a': 1, 'b': 'y'}
    ])));
    expect(a, isNot(tableChecksum([
      {'a': null, 'b': 'x'}
    ])));
    expect(a, hasLength(32)); // MD5 hex
    expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  // Task 10 携带修复（T8 遗留 Minor）：值长度前缀化消除旧 `k=值;` 歧义。
  test('tableChecksum 转义：文本"NULL"≠NULL · 值含分号/键含等号不碰撞', () {
    // 旧口径两者都渲染 'a=NULL;' 碰撞；新口径 NULL→'N'，文本→'4:NULL'。
    expect(tableChecksum([
      {'a': null}
    ]), isNot(tableChecksum([
      {'a': 'NULL'}
    ])));
    // 值含分号：'x;y' 不得与拆成两列/两行的形态碰撞。
    expect(tableChecksum([
      {'a': 'x;y'}
    ]), isNot(tableChecksum([
      {'a': 'x', 'b': 'y'}
    ])));
    expect(tableChecksum([
      {'a': 'x;y'}
    ]), isNot(tableChecksum([
      {'a': 'x'},
      {'a': 'y'}
    ])));
    // 旧口径两行都渲染 'x=a=b;'（键含 = 与值含 = 碰撞）；长度前缀后区分。
    expect(tableChecksum([
      {'x=a': 'b'}
    ]), isNot(tableChecksum([
      {'x': 'a=b'}
    ])));
  });

  test('create→verify 往返：默认全量打包（含 care 表），manifest 表数==建表语句实表数', () async {
    final db = await dbWithTodos();
    final attachDir = Directory('${tmp.path}/attach')..createSync();
    File('${attachDir.path}/notes_a.png').writeAsBytesSync([1, 2, 3]);
    final sub = Directory('${attachDir.path}/habits')..createSync();
    File('${sub.path}/h.jpg').writeAsBytesSync([4]);
    final log = File('${tmp.path}/app-2026-09-25.log')..writeAsStringSync('info line\n');
    final outDir = Directory('${tmp.path}/out')..createSync();

    final res = await LhBak.create(
      db: db,
      outDirPath: outDir.path,
      attachDirs: [attachDir.path],
      logFiles: [log.path],
      now: DateTime(2026, 9, 25, 14, 30, 22),
    );

    expect(res.file.existsSync(), isTrue);
    expect(baseNameOf(res.file.path), 'lifeharness_20260925_143022.lhbak');
    expect(res.manifest.dbVersion, DbSchema.version);
    expect(res.manifest.appVersion, kAppVersion);
    expect(res.manifest.encrypted, isFalse);
    expect(res.manifest.excludedTables, isEmpty);
    expect(res.manifest.tables.keys.toSet(), schemaTableNames());
    // 备份红线：呵护表默认在包内（排除的是同步，不是备份）
    expect(res.manifest.tables.containsKey(DbSchema.tCareLogs), isTrue);
    expect(res.manifest.tables[DbSchema.tTodos]!.rows, 2);
    expect(res.manifest.tables[DbSchema.tTodos]!.checksum, isNot('-'));
    expect(res.manifest.tables[DbSchema.tCareBabies]!.checksum, '-'); // 空表
    // 成员清单
    expect(res.manifest.members.first, 'manifest.json');
    expect(res.manifest.members, contains('db.sqlite'));
    expect(res.manifest.members, contains('attachments/attach/notes_a.png'));
    expect(res.manifest.members, contains('attachments/attach/habits/h.jpg'));
    expect(res.manifest.members, contains('logs/app-2026-09-25.log'));

    final m = await LhBak.verify(res.file.path);
    expect(m.dbVersion, DbSchema.version);
    expect(m.createdAt, res.manifest.createdAt);
    expect(m.tables[DbSchema.tTodos]!.checksum, res.manifest.tables[DbSchema.tTodos]!.checksum);
    expect(m.tables.length, res.manifest.tables.length);
    await db.close();
  });

  test('打包后改 1 行 → 旧包（旧 manifest + 改后数据）verify 报 checksumMismatch', () async {
    final db = await dbWithTodos();
    final outDir = Directory('${tmp.path}/out')..createSync();
    final old = await LhBak.create(
      db: db,
      outDirPath: outDir.path,
      now: DateTime(2026, 9, 25, 10, 0, 0),
    );
    // 改 1 行后重新打包（新快照）；把旧包的 db.sqlite 换成新快照 =
    // 「旧 manifest 对上改后数据」，verify 重算校验和必须报不一致。
    await db.insert(DbSchema.tTodos, {'title': '备份后新增', 'created_at': 3, 'updated_at': 3});
    final newer = await LhBak.create(
      db: db,
      outDirPath: outDir.path,
      now: DateTime(2026, 9, 25, 10, 0, 5),
    );
    final spliced = spliceDbFrom(old.file.path, newer.file.path);
    expect(
      LhBak.verify(spliced),
      throwsLhBak(LhBakException.codeChecksumMismatch),
    );
    await db.close();
  });

  test('zip 尾部截断 → badZip', () async {
    final db = await dbWithTodos();
    final outDir = Directory('${tmp.path}/out')..createSync();
    final res = await LhBak.create(db: db, outDirPath: outDir.path);
    final bytes = res.file.readAsBytesSync();
    final cut = File('${tmp.path}/truncated.lhbak');
    cut.writeAsBytesSync(bytes.sublist(0, bytes.length - 30));
    expect(LhBak.verify(cut.path), throwsLhBak(LhBakException.codeBadZip));
    await db.close();
  });

  test('manifest dbVersion 高于当前 → versionMismatch；不高于当前 → 放行', () async {
    final db = await dbWithTodos();
    final outDir = Directory('${tmp.path}/out')..createSync();
    final res = await LhBak.create(db: db, outDirPath: outDir.path);

    final future = rebuildWithManifest(res.file.path, _manifestJson(res, dbVersionOverride: 9999));
    expect(LhBak.verify(future), throwsLhBak(LhBakException.codeVersionMismatch));

    // 包版本 ≤ App 当前版本（历史包）允许
    final older = rebuildWithManifest(res.file.path, _manifestJson(res, dbVersionOverride: DbSchema.version - 1));
    final m = await LhBak.verify(older);
    expect(m.dbVersion, DbSchema.version - 1);
    await db.close();
  });

  test('manifest 缺失 / 非法 JSON → badManifest；成员与包不一致 → badManifest', () async {
    final db = await dbWithTodos();
    final outDir = Directory('${tmp.path}/out')..createSync();
    final res = await LhBak.create(db: db, outDirPath: outDir.path);

    final noManifest = rebuildWithManifest(res.file.path, {}, dropManifest: true);
    expect(LhBak.verify(noManifest), throwsLhBak(LhBakException.codeBadManifest));

    final badJson = rebuildWithManifest(res.file.path, {}, manifestRaw: '{oops');
    expect(LhBak.verify(badJson), throwsLhBak(LhBakException.codeBadManifest));

    // 声明了包里没有的成员
    final ghost = rebuildWithManifest(res.file.path, _manifestJson(res, extraMember: 'attachments/ghost.png'));
    expect(LhBak.verify(ghost), throwsLhBak(LhBakException.codeBadManifest));
    await db.close();
  });

  test('excludeTables 排表：manifest 记排除、快照无该表；unpack 建空表并报告 missingTables', () async {
    final db = await dbWithTodos();
    await db.insert(DbSchema.tCareLogs, {
      'baby_id': 1,
      'day': '2026-09-25',
      'k': 'sleep',
      's': '20:00',
      'created_at': 1,
    });
    final outDir = Directory('${tmp.path}/out')..createSync();
    final res = await LhBak.create(
      db: db,
      outDirPath: outDir.path,
      excludeTables: [DbSchema.tCareLogs],
    );
    expect(res.manifest.excludedTables, contains(DbSchema.tCareLogs));
    expect(res.manifest.tables.containsKey(DbSchema.tCareLogs), isFalse);
    // 排表包依然可验（表清单 == manifest）
    await LhBak.verify(res.file.path);

    final target = await openSchemaDb();
    final m = await LhBak.unpack(filePath: res.file.path, targetDb: target);
    expect(m.missingTables, [DbSchema.tCareLogs]);
    final exists = await target.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", [DbSchema.tCareLogs]);
    expect(exists, hasLength(1), reason: '缺失表应按当前 schema 建空表');
    expect(await target.query(DbSchema.tCareLogs), isEmpty);
    // 其余表数据照常恢复
    final todos = await orderedRows(target, DbSchema.tTodos);
    expect(tableChecksum(todos), res.manifest.tables[DbSchema.tTodos]!.checksum);
    await db.close();
    await target.close();
  });

  test('unpack 整库覆盖恢复：目标旧数据被替换，往返逐表 checksum 一致', () async {
    final src = await dbWithTodos();
    final outDir = Directory('${tmp.path}/out')..createSync();
    final res = await LhBak.create(db: src, outDirPath: outDir.path);

    final target = await openSchemaDb();
    // 目标库预置本机旧数据：恢复后必须消失
    await target.insert(DbSchema.tTodos, {'title': '本机旧数据将被覆盖', 'created_at': 99, 'updated_at': 99});

    final m = await LhBak.unpack(filePath: res.file.path, targetDb: target);
    expect(m.missingTables, isEmpty);

    final todos = await orderedRows(target, DbSchema.tTodos);
    expect(todos.map((r) => r['title']), unorderedEquals(['备份测试1', '备份测试2']));
    // 逐表校验和与 manifest 一致
    for (final e in m.tables.entries) {
      final rows = await orderedRows(target, e.key);
      expect(tableChecksum(rows), e.value.checksum, reason: '表 ${e.key} 往返不一致');
      expect(rows.length, e.value.rows);
    }
    await src.close();
    await target.close();
  });

  // Task 10 携带修复（Important）：解侧 KDF 参数封顶 + alg 白名单，
  // 拒绝造 10^9 轮 manifest 的包（否则 verify 在 PBKDF2 派生处被拒绝服务）。
  test('manifest.kdf 封顶：10^9 轮/非法 alg 的加密包 → badManifest 拒验', () async {
    final db = await dbWithTodos();
    final outDir = Directory('${tmp.path}/out')..createSync();
    final res =
        await LhBak.create(db: db, outDirPath: outDir.path, passphrase: 'p@ss');
    // 原包（100000 轮，区间 [10_000, 1_000_000] 内）照常可验。
    await LhBak.verify(res.file.path, passphrase: 'p@ss');

    final tooBig = _manifestJson(res);
    (tooBig['kdf'] as Map<String, dynamic>)['iterations'] = 1000000000;
    expect(
      LhBak.verify(rebuildWithManifest(res.file.path, tooBig),
          passphrase: 'p@ss'),
      throwsLhBak(LhBakException.codeBadManifest),
    );

    final belowMin = _manifestJson(res);
    (belowMin['kdf'] as Map<String, dynamic>)['iterations'] = 9999;
    expect(
      LhBak.verify(rebuildWithManifest(res.file.path, belowMin),
          passphrase: 'p@ss'),
      throwsLhBak(LhBakException.codeBadManifest),
    );

    final badAlg = _manifestJson(res);
    (badAlg['kdf'] as Map<String, dynamic>)['alg'] = 'scrypt';
    expect(
      LhBak.verify(rebuildWithManifest(res.file.path, badAlg),
          passphrase: 'p@ss'),
      throwsLhBak(LhBakException.codeBadManifest),
    );
    await db.close();
  });

  // Task 10 评审修复轮1（Important）：uniqueFileNameInDir 零测试补齐——
  // 备份红线「同秒二次产包不覆盖」的去重命名口径要有回归锚点。
  test('uniqueFileNameInDir：同名已存在 → -2；-2 也在 → -3', () {
    final dir = Directory.systemTemp.createTempSync('lh_uniq_name_');
    try {
      const name = 'auto_before_restore_20260925_120000.lhbak';
      // 无冲突：首名保持规范口径。
      expect(uniqueFileNameInDir(dir.path, name), name);
      // 已存在同名 → -2 后缀。
      File('${dir.path}/$name').createSync();
      expect(uniqueFileNameInDir(dir.path, name),
          'auto_before_restore_20260925_120000-2.lhbak');
      // -2 也已存在 → -3。
      File('${dir.path}/auto_before_restore_20260925_120000-2.lhbak')
          .createSync();
      expect(uniqueFileNameInDir(dir.path, name),
          'auto_before_restore_20260925_120000-3.lhbak');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

/// 从 create 结果还原 manifest JSON（可按需改字段），供重打包造坏包用例。
Map<String, dynamic> _manifestJson(LhBakCreateResult res, {int? dbVersionOverride, String? extraMember}) {
  final j = jsonDecode(utf8.decode(() {
    final archive = ZipDecoder().decodeBytes(res.file.readAsBytesSync());
    return (archive.findFile('manifest.json')!.content as List<int>);
  }())) as Map<String, dynamic>;
  if (dbVersionOverride != null) j['dbVersion'] = dbVersionOverride;
  if (extraMember != null) (j['members'] as List).add(extraMember);
  return j;
}

String baseNameOf(String path) => path.split(RegExp(r'[\\/]')).last;
