/// Task 9：`.lhbak` 可选口令加密（PBKDF2+AES-GCM）验收测试。
///
/// 口径（设计稿 §2/§3 + brief 钉死项）：
/// - encrypted=true 时密文成员为 `db.sqlite.enc`、`attachments/**.enc`；
///   manifest.json 与 logs/ 保持明文。
/// - blob = salt(16B) | nonce(12B) | 密文+tag(16B)。
/// - 口令错 → wrongPassphrase；加密包未给口令 → needPassphrase；
///   明文包给了口令 → 忽略并正常走。
/// - 附件超 maxEncryptBytes（默认 64MB）跳过并记入 manifest.skippedLarge。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

/// 取包内某成员的原始字节（成员不存在视为测试失败）。
Uint8List memberBytes(String pkgPath, String name) {
  final input = InputFileStream(pkgPath);
  try {
    final archive = ZipDecoder().decodeBuffer(input, verify: true);
    final f = archive.findFile(name);
    expect(f, isNotNull, reason: '成员缺失：$name');
    return Uint8List.fromList(f!.content as List<int>);
  } finally {
    input.closeSync();
  }
}

void main() {
  sqfliteFfiInit();
  // 生产默认走 sqflite 插件工厂；单测注入 ffi 工厂打开快照文件。
  LhBak.snapshotFactory = databaseFactoryFfi;

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lhbak_crypto_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Database> dbWithTodos() async {
    final db = await openSchemaDb();
    await db.insert(DbSchema.tTodos, {'title': '加密备份1', 'created_at': 1, 'updated_at': 1});
    await db.insert(DbSchema.tTodos, {'title': '加密备份2', 'created_at': 2, 'updated_at': 2});
    return db;
  }

  test('加密包不带口令 verify/unpack → needPassphrase；manifest.kdf 记录迭代参数', () async {
    final db = await dbWithTodos();
    final outDir = Directory('${tmp.path}/enc')..createSync();
    final res = await LhBak.create(db: db, outDirPath: outDir.path, passphrase: '口令-123');

    expect(res.manifest.encrypted, isTrue);
    expect(res.manifest.members, contains('db.sqlite.enc'));
    expect(res.manifest.members, isNot(contains('db.sqlite')));
    expect(res.manifest.kdf, isNotNull);
    expect(res.manifest.kdf!['iterations'], 100000);
    expect(res.manifest.kdf!['alg'], 'PBKDF2-HMAC-SHA256');

    expect(
      LhBak.verify(res.file.path),
      throwsLhBak(LhBakException.codeNeedPassphrase),
    );
    final target = await openSchemaDb();
    expect(
      LhBak.unpack(filePath: res.file.path, targetDb: target),
      throwsLhBak(LhBakException.codeNeedPassphrase),
    );
    await db.close();
    await target.close();
  });

  test('错口令 verify/unpack → wrongPassphrase（GCM tag 校验失败）', () async {
    final db = await dbWithTodos();
    final outDir = Directory('${tmp.path}/enc')..createSync();
    final res = await LhBak.create(db: db, outDirPath: outDir.path, passphrase: '正确口令');

    expect(
      LhBak.verify(res.file.path, passphrase: '错误口令'),
      throwsLhBak(LhBakException.codeWrongPassphrase),
    );
    final target = await openSchemaDb();
    expect(
      LhBak.unpack(filePath: res.file.path, targetDb: target, passphrase: '错误口令'),
      throwsLhBak(LhBakException.codeWrongPassphrase),
    );
    await db.close();
    await target.close();
  });

  test('对口令 create→verify→unpack 往返：逐表 checksum 与明文包一致；日志/manifest 明文；明文包给口令忽略', () async {
    final db = await dbWithTodos();
    final attach = Directory('${tmp.path}/attach')..createSync();
    final noteBytes = utf8.encode('附件明文内容-测试');
    File('${attach.path}/a.png').writeAsBytesSync(noteBytes);
    final log = File('${tmp.path}/app-x.log')..writeAsStringSync('plain log line\n');
    final plainDir = Directory('${tmp.path}/plain')..createSync();
    final encDir = Directory('${tmp.path}/enc')..createSync();

    final plain = await LhBak.create(
      db: db,
      outDirPath: plainDir.path,
      attachDirs: [attach.path],
      logFiles: [log.path],
      now: DateTime(2026, 9, 25, 1, 2, 3),
    );
    final enc = await LhBak.create(
      db: db,
      outDirPath: encDir.path,
      attachDirs: [attach.path],
      logFiles: [log.path],
      passphrase: 'p@ss',
      now: DateTime(2026, 9, 25, 1, 2, 4),
    );

    expect(enc.manifest.encrypted, isTrue);
    expect(enc.manifest.members, contains('attachments/attach/a.png.enc'));
    expect(enc.manifest.members, contains('logs/app-x.log'));
    expect(plain.manifest.members, containsAll(['db.sqlite', 'attachments/attach/a.png']));

    // logs/ 与 manifest 明文；附件成员 = salt(16)+nonce(12)+密文+tag(16)，非原样明文。
    expect(utf8.decode(memberBytes(enc.file.path, 'logs/app-x.log')), 'plain log line\n');
    expect(utf8.decode(memberBytes(enc.file.path, 'manifest.json')), contains('"encrypted": true'));
    final encAttach = memberBytes(enc.file.path, 'attachments/attach/a.png.enc');
    expect(encAttach.length, 16 + 12 + noteBytes.length + 16);

    // 逐表统计两包一致（同一活库来源）。
    for (final e in plain.manifest.tables.entries) {
      expect(enc.manifest.tables[e.key], e.value, reason: '表 ${e.key} 两包统计不一致');
    }

    final m = await LhBak.verify(enc.file.path, passphrase: 'p@ss');
    expect(m.tables[DbSchema.tTodos]!.checksum,
        plain.manifest.tables[DbSchema.tTodos]!.checksum);

    final target = await openSchemaDb();
    final um = await LhBak.unpack(
        filePath: enc.file.path, targetDb: target, passphrase: 'p@ss');
    expect(um.missingTables, isEmpty);
    for (final e in um.tables.entries) {
      final rows = await orderedRows(target, e.key);
      expect(tableChecksum(rows), e.value.checksum, reason: '表 ${e.key} 往返不一致');
      expect(rows.length, e.value.rows);
    }

    // 明文包给了口令 → 忽略，正常走。
    final pm = await LhBak.verify(plain.file.path, passphrase: '不相干口令');
    expect(pm.encrypted, isFalse);
    expect(pm.tables[DbSchema.tTodos]!.checksum,
        plain.manifest.tables[DbSchema.tTodos]!.checksum);

    await db.close();
    await target.close();
  });

  test('附件超 maxEncryptBytes → 跳过记入 skippedLarge，包仍 verify/unpack；明文包不跳过', () async {
    final db = await dbWithTodos();
    final attach = Directory('${tmp.path}/attach')..createSync();
    File('${attach.path}/small.bin').writeAsBytesSync(List<int>.filled(64, 7));
    File('${attach.path}/big.bin').writeAsBytesSync(List<int>.filled(2048, 9));
    final encDir = Directory('${tmp.path}/enc')..createSync();
    final plainDir = Directory('${tmp.path}/plain')..createSync();

    final res = await LhBak.create(
      db: db,
      outDirPath: encDir.path,
      attachDirs: [attach.path],
      passphrase: 'p',
      maxEncryptBytes: 1024,
    );
    expect(res.manifest.skippedLarge, ['attachments/attach/big.bin']);
    expect(res.manifest.members, contains('attachments/attach/small.bin.enc'));
    expect(res.manifest.members, isNot(contains('attachments/attach/big.bin.enc')));
    expect(res.manifest.members, isNot(contains('attachments/attach/big.bin')));

    await LhBak.verify(res.file.path, passphrase: 'p');
    final target = await openSchemaDb();
    final um = await LhBak.unpack(
        filePath: res.file.path, targetDb: target, passphrase: 'p');
    expect(um.skippedLarge, ['attachments/attach/big.bin']);
    expect(tableChecksum(await orderedRows(target, DbSchema.tTodos)),
        res.manifest.tables[DbSchema.tTodos]!.checksum);

    // 明文包不跳过任何附件（skippedLarge 恒 null）。
    final plain = await LhBak.create(
      db: db,
      outDirPath: plainDir.path,
      attachDirs: [attach.path],
      maxEncryptBytes: 1024,
    );
    expect(plain.manifest.skippedLarge, isNull);
    expect(plain.manifest.members, contains('attachments/attach/big.bin'));

    await db.close();
    await target.close();
  });

  test('同口令两次 create：db.sqlite.enc 密文不同（salt/nonce 随机），verify 都通过', () async {
    final db = await dbWithTodos();
    final dirA = Directory('${tmp.path}/a')..createSync();
    final dirB = Directory('${tmp.path}/b')..createSync();
    final a = await LhBak.create(
        db: db, outDirPath: dirA.path, passphrase: 'same', now: DateTime(2026, 9, 25, 8, 0, 0));
    final b = await LhBak.create(
        db: db, outDirPath: dirB.path, passphrase: 'same', now: DateTime(2026, 9, 25, 8, 0, 1));

    final ba = memberBytes(a.file.path, 'db.sqlite.enc');
    final bb = memberBytes(b.file.path, 'db.sqlite.enc');
    expect(ba.length, bb.length); // 同一快照明文字节等长
    expect(ba, isNot(bb)); // salt/nonce 随机 → 密文不同

    final ma = await LhBak.verify(a.file.path, passphrase: 'same');
    final mb = await LhBak.verify(b.file.path, passphrase: 'same');
    expect(ma.tables[DbSchema.tTodos]!.checksum,
        mb.tables[DbSchema.tTodos]!.checksum);
    await db.close();
  });
}
