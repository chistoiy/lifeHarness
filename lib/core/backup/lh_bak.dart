/// `.lhbak` 备份容器（设计稿 2026-09-24-sync-log-backup §3）。
///
/// 容器 = ZIP：`manifest.json` + `db.sqlite`（sqflite `VACUUM INTO` 一致性快照，
/// 不拷活文件）+ `attachments/<相对路径>` + `logs/<文件名>`。
/// 本任务不做加密（T9 扩展 encrypted/口令档）；文件名
/// 文件名 `lifeharness_YYYYMMDD_HHmmss.lhbak`。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database/schema.dart';

/// App 版本常量（工程无 package_info_plus 依赖，直接常量注入；
/// 收口批与 pubspec version 同步）。
const String kAppVersion = '0.1.18';

/// 逐表校验和（纯函数，便于单测）：行按调用方给定顺序（本库口径 = rowid 升序）
/// 逐行拼接 `k=值;`（列名排序保证跨读取稳定），MD5 hex；空表为 `'-'`。
String tableChecksum(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return '-';
  final sb = StringBuffer();
  for (final row in rows) {
    final keys = row.keys.toList()..sort();
    for (final k in keys) {
      sb.write('$k=${_checksumValue(row[k])};');
    }
    sb.write('\n');
  }
  return md5.convert(utf8.encode(sb.toString())).toString();
}

String _checksumValue(Object? v) {
  if (v == null) return 'NULL';
  if (v is Uint8List) {
    final hex = StringBuffer();
    for (final b in v) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return '0x$hex';
  }
  return '$v';
}

/// 单表统计：行数 + 校验和（设计稿 §3 manifest「逐表行数+校验和」）。
class TableStat {
  const TableStat({required this.rows, required this.checksum});

  final int rows;
  final String checksum;

  Map<String, dynamic> toJson() => {'rows': rows, 'checksum': checksum};

  factory TableStat.fromJson(Map<String, dynamic> json) {
    final rows = json['rows'];
    final checksum = json['checksum'];
    if (rows is! int || checksum is! String) {
      throw const FormatException('TableStat 字段缺失或类型错误');
    }
    return TableStat(rows: rows, checksum: checksum);
  }

  @override
  bool operator ==(Object other) =>
      other is TableStat && other.rows == rows && other.checksum == checksum;

  @override
  int get hashCode => Object.hash(rows, checksum);

  @override
  String toString() => 'TableStat(rows: $rows, checksum: $checksum)';
}

/// `.lhbak` manifest（manifest.json 的内存形态）。
class LhBakManifest {
  LhBakManifest({
    required this.dbVersion,
    required this.appVersion,
    required this.createdAt,
    required this.tables,
    required this.excludedTables,
    required this.encrypted,
    required this.members,
    this.missingTables = const [],
  });

  int dbVersion;
  String appVersion;
  DateTime createdAt;

  /// 包内实际含有的表 → 统计（被 excludeTables 排除的表不在此列）。
  Map<String, TableStat> tables;

  /// 打包时排除的表清单（T9/同步快照按 care.syncExcluded 写入）。
  List<String> excludedTables;

  /// 是否加密（本任务恒 false；T9 AES-GCM 口令档扩展）。
  bool encrypted;

  /// zip 成员清单（含 manifest.json 自身，按打包顺序）。
  List<String> members;

  /// unpack 时填充（不参与 manifest.json 序列化）：当前 schema 有而包内没有
  /// 的表——unpack 会按当前 schema 建空表并在恢复报告中列出。
  List<String> missingTables;

  Map<String, dynamic> toJson() => {
        'dbVersion': dbVersion,
        'appVersion': appVersion,
        'createdAt': createdAt.toIso8601String(),
        'tables': {for (final e in tables.entries) e.key: e.value.toJson()},
        'excludedTables': excludedTables,
        'encrypted': encrypted,
        'members': members,
      };

  factory LhBakManifest.fromJson(Map<String, dynamic> json) {
    final dbVersion = json['dbVersion'];
    final appVersion = json['appVersion'];
    final createdAt = json['createdAt'];
    final tables = json['tables'];
    final excluded = json['excludedTables'];
    final encrypted = json['encrypted'];
    final members = json['members'];
    if (dbVersion is! int || appVersion is! String || createdAt is! String) {
      throw const FormatException('manifest 缺 dbVersion/appVersion/createdAt');
    }
    if (tables is! Map<String, dynamic> ||
        excluded is! List ||
        encrypted is! bool ||
        members is! List) {
      throw const FormatException('manifest 缺 tables/excludedTables/encrypted/members');
    }
    return LhBakManifest(
      dbVersion: dbVersion,
      appVersion: appVersion,
      createdAt: DateTime.parse(createdAt),
      tables: {
        for (final e in tables.entries)
          e.key: TableStat.fromJson(e.value as Map<String, dynamic>)
      },
      excludedTables: excluded.cast<String>().toList(),
      encrypted: encrypted,
      members: members.cast<String>().toList(),
    );
  }
}

/// 容器校验/操作异常。code ∈ {badZip, badManifest, versionMismatch, checksumMismatch}。
class LhBakException implements Exception {
  const LhBakException(this.code, [this.message = '']);

  static const String codeBadZip = 'badZip';
  static const String codeBadManifest = 'badManifest';
  static const String codeVersionMismatch = 'versionMismatch';
  static const String codeChecksumMismatch = 'checksumMismatch';

  final String code;
  final String message;

  @override
  String toString() => 'LhBakException($code): $message';
}

/// [LhBak.create] 返回值：生成的备份文件 + 其 manifest。
class LhBakCreateResult {
  const LhBakCreateResult(this.file, this.manifest);

  final File file;
  final LhBakManifest manifest;
}

/// `.lhbak` 容器：打包（create）/ 校验（verify）/ 解包恢复（unpack）。
class LhBak {
  LhBak._();

  /// 快照库打开工厂：生产默认 sqflite 插件全局工厂；
  /// 单元测试注入 databaseFactoryFfi 以打开临时快照文件。
  static DatabaseFactory snapshotFactory = databaseFactory;

  /// 生成备份包：活库 `VACUUM INTO` 快照 → 计算逐表统计 → zip 打包。
  ///
  /// - [attachDirs]：附件根目录，成员名 `attachments/<目录名>/<相对路径>`；
  ///   不存在则跳过。
  /// - [logFiles]：随包日志（成员名 `logs/<文件名>`），不存在则跳过。
  /// - [excludeTables]：从包中剔除的表（快照文件内直接 DROP，满足
  ///   「排表包快照里没有该表」口径）；清单写入 manifest.excludedTables。
  static Future<LhBakCreateResult> create({
    required Database db,
    required String outDirPath,
    List<String> attachDirs = const [],
    List<String> logFiles = const [],
    List<String> excludeTables = const [],
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now();
    final temp = Directory.systemTemp.createTempSync('lhbak_create_');
    try {
      final snapshotPath = p.join(temp.path, 'db.sqlite');
      // 1) 活库一致性快照（设计稿 §3：不拷活文件）。
      await db.execute("VACUUM INTO '${_sqlQuote(snapshotPath)}'");
      final liveTables = await _tableNames(db);
      final excluded =
          liveTables.where((t) => excludeTables.contains(t)).toList()..sort();

      // 2) 快照内剔除 excludeTables 后逐表算行数+校验和。
      final tables = <String, TableStat>{};
      Database? snap;
      try {
        snap = await snapshotFactory.openDatabase(snapshotPath,
            options: OpenDatabaseOptions(singleInstance: false));
        for (final t in excluded) {
          await snap.execute('DROP TABLE IF EXISTS "$t"');
        }
        for (final t in (await _tableNames(snap))) {
          final rows = await _tableRows(snap, t);
          tables[t] = TableStat(rows: rows.length, checksum: tableChecksum(rows));
        }
      } finally {
        await snap?.close();
      }

      // 3) 成员表：db.sqlite + attachments/* + logs/*（确定序）。
      final memberFiles = <String, String>{'db.sqlite': snapshotPath};
      for (final dirPath in attachDirs) {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) continue;
        final dirName = p.basename(dirPath);
        final files = dir
            .listSync(recursive: true)
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          final rel = p.posix
              .joinAll(p.split(p.relative(f.path, from: dirPath)));
          memberFiles['attachments/$dirName/$rel'] = f.path;
        }
      }
      for (final logPath in logFiles) {
        if (File(logPath).existsSync()) {
          memberFiles['logs/${p.basename(logPath)}'] = logPath;
        }
      }

      final manifest = LhBakManifest(
        dbVersion: DbSchema.version,
        appVersion: kAppVersion,
        createdAt: ts,
        tables: tables,
        excludedTables: excluded,
        encrypted: false,
        members: ['manifest.json', ...memberFiles.keys],
      );

      // 4) zip 落盘（大文件成员走 InputFileStream 流式，不整读内存）。
      Directory(outDirPath).createSync(recursive: true);
      final outPath = p.join(outDirPath, _backupFileName(ts));
      final encoder = ZipFileEncoder();
      encoder.create(outPath);
      try {
        final mBytes = utf8.encode(
            const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
        encoder.addArchiveFile(
            ArchiveFile('manifest.json', mBytes.length, mBytes));
        for (final e in memberFiles.entries) {
          await encoder.addFile(File(e.value), e.key);
        }
      } finally {
        await encoder.close();
      }
      return LhBakCreateResult(File(outPath), manifest);
    } finally {
      _deleteQuietly(temp);
    }
  }

  /// 校验包：zip 结构 → manifest → 版本 → 成员清单 → 快照逐表重算校验和。
  /// 坏包抛 [LhBakException]，code 见四类。
  static Future<LhBakManifest> verify(String filePath) async {
    final zip = _openZip(filePath);
    try {
      final archive = zip.archive;
      final manifest = _parseManifest(archive);
      if (manifest.dbVersion > DbSchema.version) {
        throw LhBakException(
          LhBakException.codeVersionMismatch,
          '包 dbVersion ${manifest.dbVersion} > 当前 ${DbSchema.version}',
        );
      }
      for (final name in manifest.members) {
        if (archive.findFile(name) == null) {
          throw LhBakException(
              LhBakException.codeBadManifest, '成员缺失：$name');
        }
      }
      final temp = Directory.systemTemp.createTempSync('lhbak_verify_');
      Database? snap;
      try {
        final snapPath = p.join(temp.path, 'db.sqlite');
        _extractMember(archive, 'db.sqlite', snapPath);
        snap = await snapshotFactory.openDatabase(snapPath,
            options: OpenDatabaseOptions(singleInstance: false));
        final snapTables = (await _tableNames(snap)).toSet();
        for (final e in manifest.tables.entries) {
          if (!snapTables.contains(e.key)) {
            throw LhBakException(LhBakException.codeChecksumMismatch,
                '快照缺表 ${e.key}（manifest 有记录）');
          }
          final rows = await _tableRows(snap, e.key);
          final actual =
              TableStat(rows: rows.length, checksum: tableChecksum(rows));
          if (actual != e.value) {
            throw LhBakException(LhBakException.codeChecksumMismatch,
                '表 ${e.key} 校验和不一致（期望 ${e.value.checksum}，实际 ${actual.checksum}）');
          }
        }
        for (final t in snapTables) {
          if (!manifest.tables.containsKey(t)) {
            throw LhBakException(LhBakException.codeChecksumMismatch,
                '快照含未登记于 manifest 的表 $t');
          }
        }
        return manifest;
      } finally {
        await snap?.close();
        _deleteQuietly(temp);
      }
    } finally {
      zip.close();
    }
  }

  /// 解包恢复到 [targetDb]（整库替换，不做记录级合并，设计稿 §3 口径）：
  /// 删旧表 → 按快照 sqlite_master 重建 → ATTACH 快照 → 逐表 INSERT → DETACH。
  ///
  /// 包内缺失（excludeTables 产物）的当前 schema 表按 DDL 建空表，
  /// 列在返回 manifest 的 [LhBakManifest.missingTables]。
  /// 附件/日志的落盘恢复属导入 UI 任务（T10），此处只恢复 DB。
  static Future<LhBakManifest> unpack({
    required String filePath,
    required Database targetDb,
  }) async {
    final manifest = await verify(filePath);
    final zip = _openZip(filePath);
    final temp = Directory.systemTemp.createTempSync('lhbak_unpack_');
    final snapPath = p.join(temp.path, 'db.sqlite');
    try {
      _extractMember(zip.archive, 'db.sqlite', snapPath);
    } finally {
      zip.close();
    }
    final snapName = 'lhbak_snap';
    await targetDb.execute("ATTACH DATABASE '${_sqlQuote(snapPath)}' AS $snapName");
    final attached = true;
    try {
      final snapDdl = await targetDb.rawQuery(
          "SELECT name, sql FROM $snapName.sqlite_master "
          "WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
      final snapAux = await targetDb.rawQuery(
          "SELECT sql FROM $snapName.sqlite_master "
          "WHERE type IN ('index','trigger') AND sql IS NOT NULL ORDER BY name");
      final snapTables = snapDdl.map((r) => r['name'] as String).toSet();
      final targetTables = await _tableNames(targetDb);
      final schemaDdl = _schemaTableDdl();
      final missing = schemaDdl.keys.toSet().difference(snapTables).toList()
        ..sort();

      await targetDb.transaction((txn) async {
        for (final t in targetTables) {
          await txn.execute('DROP TABLE IF EXISTS main."$t"');
        }
        for (final r in snapDdl) {
          await txn.execute(_qualifyMain(r['sql'] as String));
        }
        for (final t in missing) {
          await txn.execute(schemaDdl[t]!);
        }
        for (final r in snapDdl) {
          final t = r['name'] as String;
          await txn.execute('INSERT INTO main."$t" SELECT * FROM $snapName."$t"');
        }
        for (final r in snapAux) {
          await txn.execute(_qualifyMain(r['sql'] as String));
        }
      });
      manifest.missingTables = missing;
      return manifest;
    } finally {
      if (attached) {
        try {
          await targetDb.execute('DETACH DATABASE $snapName');
        } catch (_) {
          // 恢复失败时连接可能已不可用，忽略。
        }
      }
      _deleteQuietly(temp);
    }
  }

  // ---------- 内部工具 ----------

  /// zip 解码（结构损坏/文件不可读 → badZip）。返回体持有底层
  /// [InputFileStream]，成员内容惰性读取，用完必须 [zip.close()]。
  static _OpenedZip _openZip(String filePath) {
    InputFileStream? input;
    try {
      input = InputFileStream(filePath);
      return _OpenedZip(ZipDecoder().decodeBuffer(input, verify: true), input);
    } catch (e) {
      try {
        input?.closeSync();
      } catch (_) {}
      throw LhBakException(LhBakException.codeBadZip, 'ZIP 无法解析：$e');
    }
  }

  static LhBakManifest _parseManifest(Archive archive) {
    final entry = archive.findFile('manifest.json');
    if (entry == null) {
      throw const LhBakException(LhBakException.codeBadManifest, '缺 manifest.json');
    }
    try {
      final raw = utf8.decode(entry.content as List<int>);
      return LhBakManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      throw LhBakException(LhBakException.codeBadManifest, 'manifest 非法：$e');
    }
  }

  /// 单成员流式落盘（db.sqlite 大文件不整读进内存）。
  static void _extractMember(Archive archive, String name, String outPath) {
    final entry = archive.findFile(name);
    if (entry == null) {
      throw LhBakException(LhBakException.codeBadManifest, '成员缺失：$name');
    }
    final output = OutputFileStream(outPath);
    try {
      entry.writeContent(output);
    } finally {
      output.closeSync();
    }
  }

  /// 活库/快照库的实表名（排除 sqlite_ 内部表）。
  static Future<List<String>> _tableNames(Database db) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
    return rows.map((r) => r['name'] as String).toList();
  }

  /// 全表行（rowid 升序；剥离辅助 rowid 列），create/verify 共用同一口径。
  static Future<List<Map<String, Object?>>> _tableRows(
      Database db, String table) async {
    final rows = await db.rawQuery(
        'SELECT rowid AS _lhbak_rid, * FROM "$table" ORDER BY rowid');
    return rows
        .map((r) => <String, Object?>{
              for (final e in r.entries)
                if (e.key != '_lhbak_rid') e.key: e.value,
            })
        .toList();
  }

  static final RegExp _createTableRe = RegExp(
      r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false);

  /// 当前 schema 的表名 → 建表语句（来自 DbSchema.createStatements）。
  static Map<String, String> _schemaTableDdl() {
    final map = <String, String>{};
    for (final sql in DbSchema.createStatements) {
      final m = _createTableRe.firstMatch(sql);
      if (m != null) map.putIfAbsent(m.group(1)!, () => sql);
    }
    return map;
  }

  static final RegExp _qualifyTargetRe = RegExp(
      r'^(\s*CREATE\s+(?:TABLE|UNIQUE\s+TABLE|INDEX|UNIQUE\s+INDEX|TRIGGER)\s+)((?:IF\s+NOT\s+EXISTS\s+)?)(\S)',
      caseSensitive: false);

  /// ATTACH 期间未限定名可能命中快照库，DDL 统一补 `main.` 前缀。
  static String _qualifyMain(String ddl) {
    final m = _qualifyTargetRe.firstMatch(ddl);
    if (m == null) return ddl;
    final head = m.group(3)!;
    if (head.startsWith('main.') || head.startsWith('"main.')) return ddl;
    final insertAt = m.end - head.length; // group(3) 起点（\S 捕获 1 字符）
    return '${ddl.substring(0, insertAt)}main.${ddl.substring(insertAt)}';
  }

  /// SQL 字符串字面量转义（单引号翻倍；路径含反斜杠对 SQLite 无害）。
  static String _sqlQuote(String raw) => raw.replaceAll("'", "''");

  static String _backupFileName(DateTime ts) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'lifeharness_${ts.year}${two(ts.month)}${two(ts.day)}'
        '_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}.lhbak';
  }

  static void _deleteQuietly(Directory dir) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // 临时目录清理失败不影响结果（Windows 偶发文件占用）。
    }
  }
}

/// 已解码 zip + 其底层文件流（成员惰性读取；close 后文件锁释放）。
class _OpenedZip {
  const _OpenedZip(this.archive, this._input);

  final Archive archive;
  final InputFileStream _input;

  void close() {
    try {
      _input.closeSync();
    } catch (_) {
      // 已关闭则忽略。
    }
  }
}
