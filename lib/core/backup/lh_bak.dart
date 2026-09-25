/// `.lhbak` 备份容器（设计稿 2026-09-24-sync-log-backup §3）。
///
/// 容器 = ZIP：`manifest.json` + `db.sqlite`（sqflite `VACUUM INTO` 一致性快照，
/// 不拷活文件）+ `attachments/<相对路径>` + `logs/<文件名>`。
/// T9 口令档：create 传 [passphrase] 时 `db.sqlite.enc`、`attachments/**.enc`
/// 为密文 blob `salt(16B)|nonce(12B)|密文+tag`（PBKDF2-HMAC-SHA256 + AES-GCM，
/// KDF 参数记入 manifest.kdf）；manifest 本体与 logs/ 保持明文（恢复需先读
/// manifest 拿 KDF 参数；日志无敏感数据且同步侧需明文可查，设计稿 §2/§3）。
/// 文件名 `lifeharness_YYYYMMDD_HHmmss.lhbak`。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database/schema.dart';

/// App 版本常量（工程无 package_info_plus 依赖，直接常量注入；
/// 收口批与 pubspec version 同步）。
const String kAppVersion = '0.1.22';

/// 口令加密参数（口径钉死于 T9 实施口径）。
const int kPbkdf2Iterations = 100000;
const int kMaxEncryptBytes = 64 * 1024 * 1024;

/// 解侧 KDF 轮数封顶区间（Task 10 携带修复：坏 manifest 给 10^9 轮会让
/// verify/unpack 在派生密钥处拒绝服务）——超界一律 badManifest 拒绝。
const int kKdfIterationsMin = 10000;
const int kKdfIterationsMax = 1000000;
const int _saltLength = 16;
const int _nonceLength = 12;
const int _tagLength = 16; // AES-GCM 标准 tag 长

final Random _secureRandom = Random.secure();

Uint8List _randomBytes(int length) {
  final b = Uint8List(length);
  for (var i = 0; i < length; i++) {
    b[i] = _secureRandom.nextInt(256);
  }
  return b;
}

/// 逐表校验和（纯函数，便于单测）：行按调用方给定顺序（本库口径 = rowid 升序）
/// 逐行拼接 `k=编码值;`（列名排序保证跨读取稳定），MD5 hex；空表为 `'-'`。
///
/// 值编码长度前缀化（Task 10 携带修复，替代 T8 的裸 `k=值;`）：
/// - NULL → `N`，文本 `'NULL'` → `4:NULL`——修复旧口径下两者同串的歧义；
/// - 其余 → `<字符长度>:<值>`，值内含 `;` `=` 换行都不与分隔符/后续字段碰撞
///   （旧口径 `x=a=b;` 与列名 `x=a` 值 `b` 可碰撞）；
/// - BLOB → `0x<hex>`（前缀唯一不与长度前缀形态碰撞）。
/// 注意：本改造改变校验和字节，V1.41 未发布无历史包袱，不做旧包兼容。
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
  if (v == null) return 'N';
  if (v is Uint8List) {
    final hex = StringBuffer();
    for (final b in v) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return '0x$hex';
  }
  final s = '$v';
  return '${s.length}:$s';
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
    this.kdf,
    this.skippedLarge,
  });

  int dbVersion;
  String appVersion;
  DateTime createdAt;

  /// 包内实际含有的表 → 统计（被 excludeTables 排除的表不在此列）。
  Map<String, TableStat> tables;

  /// 打包时排除的表清单（T9/同步快照按 care.syncExcluded 写入）。
  List<String> excludedTables;

  /// 是否口令加密档（create 传 passphrase 时 true，成员含 .enc 密文 blob）。
  bool encrypted;

  /// zip 成员清单（含 manifest.json 自身，按打包顺序）。
  List<String> members;

  /// KDF 参数（仅 encrypted=true 写入）：
  /// `{'alg': 'PBKDF2-HMAC-SHA256', 'iterations': 100000}`。
  Map<String, Object>? kdf;

  /// 加密档因超 [kMaxEncryptBytes]/[LhBak.create] maxEncryptBytes 被跳过的
  /// 附件成员名（不含 .enc 后缀）；明文包恒 null。
  List<String>? skippedLarge;

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
        if (kdf != null) 'kdf': kdf,
        if (skippedLarge != null) 'skippedLarge': skippedLarge,
      };

  factory LhBakManifest.fromJson(Map<String, dynamic> json) {
    final dbVersion = json['dbVersion'];
    final appVersion = json['appVersion'];
    final createdAt = json['createdAt'];
    final tables = json['tables'];
    final excluded = json['excludedTables'];
    final encrypted = json['encrypted'];
    final members = json['members'];
    final kdf = json['kdf'];
    final skippedLarge = json['skippedLarge'];
    if (dbVersion is! int || appVersion is! String || createdAt is! String) {
      throw const FormatException('manifest 缺 dbVersion/appVersion/createdAt');
    }
    if (tables is! Map<String, dynamic> ||
        excluded is! List ||
        encrypted is! bool ||
        members is! List) {
      throw const FormatException('manifest 缺 tables/excludedTables/encrypted/members');
    }
    if (kdf != null && kdf is! Map<String, dynamic>) {
      throw const FormatException('manifest.kdf 类型错误');
    }
    if (skippedLarge != null && skippedLarge is! List) {
      throw const FormatException('manifest.skippedLarge 类型错误');
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
      kdf: kdf == null ? null : Map<String, Object>.from(kdf),
      skippedLarge:
          skippedLarge == null ? null : (skippedLarge as List).cast<String>().toList(),
    );
  }
}

/// 容器校验/操作异常。code ∈ {badZip, badManifest, versionMismatch,
/// checksumMismatch, needPassphrase, wrongPassphrase}。
class LhBakException implements Exception {
  const LhBakException(this.code, [this.message = '']);

  static const String codeBadZip = 'badZip';
  static const String codeBadManifest = 'badManifest';
  static const String codeVersionMismatch = 'versionMismatch';
  static const String codeChecksumMismatch = 'checksumMismatch';
  static const String codeNeedPassphrase = 'needPassphrase';
  static const String codeWrongPassphrase = 'wrongPassphrase';

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
  /// - [attachFiles]：按文件名收集的散装附件（Task 10 评审修复：记账导出
  ///   `lifeharness_ledger.csv/.json` 直落 documents 根，不在子目录）；
  ///   成员名 `attachments/<文件名>`，加密/超限跳过口径与 [attachDirs] 一致；
  ///   不存在则跳过。
  /// - [logFiles]：随包日志（成员名 `logs/<文件名>`），不存在则跳过。
  /// - [excludeTables]：从包中剔除的表（快照文件内直接 DROP，满足
  ///   「排表包快照里没有该表」口径）；清单写入 manifest.excludedTables。
  /// - [passphrase]：口令加密档（T9）。给出口令时 `db.sqlite.enc` 与
  ///   `attachments/**.enc` 逐文件加密为 blob `salt(16)|nonce(12)|密文+tag`；
  ///   manifest 本体与 logs/ 保持明文；KDF 参数写入 manifest.kdf。
  ///   为空则与 T8 明文包行为一致。
  /// - [maxEncryptBytes]：加密档下单个附件超过该字节数则不打包，成员名
  ///   （不含 .enc）记入 manifest.skippedLarge；默认 [kMaxEncryptBytes]。
  static Future<LhBakCreateResult> create({
    required Database db,
    required String outDirPath,
    List<String> attachDirs = const [],
    List<String> attachFiles = const [],
    List<String> logFiles = const [],
    List<String> excludeTables = const [],
    String? passphrase,
    int maxEncryptBytes = kMaxEncryptBytes,
    DateTime? now,
  }) async {
    final encrypted = passphrase != null;
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

      // 3) 成员表：db.sqlite(.enc) + attachments/*(.enc) + logs/*（确定序）。
      //    加密档：db 与附件成员名带 .enc 并整文件读入加密（GCM 单块上限远
      //    大于本项目文件尺寸）；logs 与 manifest 恒明文。
      final memberFiles = <String, String>{}; // 成员名 → 磁盘路径
      final encryptNames = <String>{};
      final skippedLarge = <String>[];
      final dbMemberName = encrypted ? 'db.sqlite.enc' : 'db.sqlite';
      memberFiles[dbMemberName] = snapshotPath;
      if (encrypted) encryptNames.add(dbMemberName);
      // 附件成员收口（目录递归 / 散文件共用）：加密档统一 .enc 命名与
      // 单文件超限跳过口径。
      void addAttachment(String memberName, File f) {
        if (!encrypted) {
          memberFiles[memberName] = f.path;
          return;
        }
        if (f.lengthSync() > maxEncryptBytes) {
          skippedLarge.add(memberName); // 记原始成员名（不含 .enc）
          return;
        }
        memberFiles['$memberName.enc'] = f.path;
        encryptNames.add('$memberName.enc');
      }

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
          addAttachment('attachments/$dirName/$rel', f);
        }
      }
      // 根目录散文件（记账 lifeharness_ledger.csv/.json 等，评审修复）。
      for (final fpath in attachFiles) {
        final f = File(fpath);
        if (!f.existsSync()) continue;
        addAttachment('attachments/${p.basename(fpath)}', f);
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
        encrypted: encrypted,
        members: ['manifest.json', ...memberFiles.keys],
        kdf: encrypted
            ? {
                'alg': 'PBKDF2-HMAC-SHA256',
                'iterations': kPbkdf2Iterations,
              }
            : null,
        skippedLarge: skippedLarge.isEmpty ? null : skippedLarge,
      );

      // 4) zip 落盘（明文大文件成员走 InputFileStream 流式；密文成员整读
      //    加密后作为 ArchiveFile 写入，尺寸已受 maxEncryptBytes 约束）。
      Directory(outDirPath).createSync(recursive: true);
      final outPath =
          p.join(outDirPath, uniqueFileNameInDir(outDirPath, _backupFileName(ts)));
      final encoder = ZipFileEncoder();
      encoder.create(outPath);
      final cipher = passphrase != null ? _BlobCipher(passphrase) : null;
      try {
        final mBytes = utf8.encode(
            const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
        encoder.addArchiveFile(
            ArchiveFile('manifest.json', mBytes.length, mBytes));
        for (final e in memberFiles.entries) {
          if (encryptNames.contains(e.key)) {
            final plain = await File(e.value).readAsBytes();
            final blob = await cipher!.encrypt(plain);
            encoder.addArchiveFile(ArchiveFile(e.key, blob.length, blob));
          } else {
            await encoder.addFile(File(e.value), e.key);
          }
        }
      } finally {
        await encoder.close();
      }
      return LhBakCreateResult(File(outPath), manifest);
    } finally {
      _deleteQuietly(temp);
    }
  }

  /// 校验包：zip 结构 → manifest → 口令档检查 → 版本 → 成员清单 →
  /// 快照逐表重算校验和（加密档先解密 db.sqlite.enc 到临时文件再开快照库）。
  ///
  /// - 加密包（manifest.encrypted=true）未给 [passphrase] → needPassphrase；
  ///   口令错（GCM tag 校验失败）→ wrongPassphrase。
  /// - 明文包给了 [passphrase] → 忽略口令，正常校验（幂等）。
  /// 坏包抛 [LhBakException]，code 见六类。
  static Future<LhBakManifest> verify(String filePath,
      {String? passphrase}) async {
    final zip = _openZip(filePath);
    try {
      final archive = zip.archive;
      final manifest = _parseManifest(archive);
      if (manifest.encrypted && passphrase == null) {
        throw const LhBakException(LhBakException.codeNeedPassphrase,
            '加密包需口令才能校验/恢复');
      }
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
        await _materializeDbMember(archive, manifest, passphrase, snapPath);
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
  /// 加密档需给 [passphrase]（口径同 [verify]）：db.sqlite.enc 先解密写入
  /// 临时文件再 ATTACH，临时目录随本方法结束删除。
  /// 包内缺失（excludeTables 产物）的当前 schema 表按 DDL 建空表，
  /// 列在返回 manifest 的 [LhBakManifest.missingTables]。
  /// 附件/日志的落盘恢复属导入 UI 任务（T10），此处只恢复 DB。
  static Future<LhBakManifest> unpack({
    required String filePath,
    required Database targetDb,
    String? passphrase,
  }) async {
    final manifest = await verify(filePath, passphrase: passphrase);
    final zip = _openZip(filePath);
    final temp = Directory.systemTemp.createTempSync('lhbak_unpack_');
    final snapPath = p.join(temp.path, 'db.sqlite');
    try {
      await _materializeDbMember(zip.archive, manifest, passphrase, snapPath);
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

      // Task 10 携带修复（T8 遗留）：删旧表→重建→逐表 INSERT 期间表序任意，
      // 未来 schema 引入 FK 表后单事务内会出现外键瞬时违规；defer_foreign_keys
      // 把 FK 检查推迟到事务提交（对无 FK 的当前 schema 是无害空转）。
      await targetDb.execute('PRAGMA defer_foreign_keys=ON');
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

  /// 把包内 db 成员还原为可用 sqlite 文件 [outPath]：明文包直接落盘；
  /// 加密包读 `db.sqlite.enc` blob（salt|nonce|密文+tag）解密后落盘。
  /// 口令错 → GCM tag 校验失败 → wrongPassphrase。
  static Future<void> _materializeDbMember(Archive archive,
      LhBakManifest manifest, String? passphrase, String outPath) async {
    if (!manifest.encrypted) {
      _extractMember(archive, 'db.sqlite', outPath);
      return;
    }
    final entry = archive.findFile('db.sqlite.enc');
    if (entry == null) {
      throw const LhBakException(LhBakException.codeBadManifest,
          '成员缺失：db.sqlite.enc');
    }
    // Task 10 携带修复：KDF 算法白名单 + 轮数封顶区间，坏 manifest 直接
    // badManifest 拒绝，绝不拿超界轮数去派生密钥（拒绝服务防线）。
    // alg 口径 = T9 写入值 'PBKDF2-HMAC-SHA256'（即 PBKDF2-SHA256 全称）。
    final alg = manifest.kdf?['alg'];
    if (alg != 'PBKDF2-HMAC-SHA256') {
      throw const LhBakException(LhBakException.codeBadManifest,
          'manifest.kdf.alg 非 PBKDF2-HMAC-SHA256');
    }
    final iterations = manifest.kdf?['iterations'];
    if (iterations is! int ||
        iterations < kKdfIterationsMin ||
        iterations > kKdfIterationsMax) {
      throw const LhBakException(LhBakException.codeBadManifest,
          'manifest.kdf.iterations 缺失或超出合法区间 '
          '[$kKdfIterationsMin, $kKdfIterationsMax]');
    }
    final blob = entry.content as List<int>;
    if (blob.length < _saltLength + _nonceLength + _tagLength) {
      throw const LhBakException(
          LhBakException.codeBadManifest, '加密成员长度非法');
    }
    final salt = blob.sublist(0, _saltLength);
    final nonce = blob.sublist(_saltLength, _saltLength + _nonceLength);
    final cipherText =
        blob.sublist(_saltLength + _nonceLength, blob.length - _tagLength);
    final mac = Uint8List.fromList(blob.sublist(blob.length - _tagLength));
    final key = await Pbkdf2.hmacSha256(iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: passphrase!, nonce: salt);
    final List<int> plain;
    try {
      plain = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      throw const LhBakException(LhBakException.codeWrongPassphrase,
          '口令错误或包被篡改（GCM tag 校验失败）');
    }
    File(outPath).writeAsBytesSync(plain);
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

/// 目标目录内不重名的备份文件名：同秒二次导出（如导入恢复的
/// `auto_before_restore` 紧跟手动导出）不覆盖既有包——覆盖 = 静默毁包，
/// 属备份红线。首名保持规范口径，冲突依次 `-2`、`-3` 后缀。
String uniqueFileNameInDir(String dirPath, String fileName) {
  if (!File(p.join(dirPath, fileName)).existsSync()) return fileName;
  final dot = fileName.lastIndexOf('.');
  final stem = dot < 0 ? fileName : fileName.substring(0, dot);
  final ext = dot < 0 ? '' : fileName.substring(dot);
  for (var n = 2;; n++) {
    final candidate = '$stem-$n$ext';
    if (!File(p.join(dirPath, candidate)).existsSync()) return candidate;
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

/// 一次 create 的加密器：全包共用一个随机 salt（PBKDF2 派生只做一次并缓存），
/// 每个成员用独立随机 nonce；blob = salt(16)|nonce(12)|密文+tag(16)。
class _BlobCipher {
  _BlobCipher(this._passphrase) : _salt = _randomBytes(_saltLength);

  final String _passphrase;
  final Uint8List _salt;
  SecretKey? _key;

  Future<SecretKey> _deriveKey() async {
    return _key ??= await Pbkdf2.hmacSha256(
      iterations: kPbkdf2Iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: _passphrase, nonce: _salt);
  }

  Future<Uint8List> encrypt(List<int> plain) async {
    final key = await _deriveKey();
    final nonce = _randomBytes(_nonceLength);
    final box = await AesGcm.with256bits()
        .encrypt(plain, secretKey: key, nonce: nonce);
    final mac = box.mac.bytes;
    final out = Uint8List(
        _saltLength + _nonceLength + box.cipherText.length + mac.length);
    var o = 0;
    out.setRange(o, o + _saltLength, _salt);
    o += _saltLength;
    out.setRange(o, o + _nonceLength, nonce);
    o += _nonceLength;
    out.setRange(o, o + box.cipherText.length, box.cipherText);
    o += box.cipherText.length;
    out.setRange(o, o + mac.length, mac);
    return out;
  }
}
