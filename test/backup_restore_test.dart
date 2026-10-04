/// Task 10：`BackupService` 导出/导入恢复验收测试（ffi 文件库 + 临时目录）。
///
/// 口径（brief Step 1 + 携带修复）：
/// - 导出→改数据→导入→数据回滚，且 `auto_before_restore_` 文件存在；
/// - 口令包走 passphrase 参数链（不带口令 → needPassphrase 现库不动）；
/// - 坏包三类 code（badZip/badManifest/checksumMismatch）冒泡为
///   [LhBakException] 不半恢复——verify 前置失败时 close/自动备份都未发生；
/// - **恢复失败路径**：unpack 中途抛异常 → 已 close 的原库必须被重新打开
///   （文件数据未被事务污染），异常冒泡；
/// - saveCopyToUserLocation / pickBackupFile 经静态钩子注入 fake
///   （模式照 LhBak.snapshotFactory）；
/// - RestoreReport 携带 manifest.skippedLarge。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/app_database.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher throwsLhBak(String code) =>
    throwsA(isA<LhBakException>().having((e) => e.code, 'code', code));

String baseNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

/// 用改过的 manifest.json 重新打包（其余成员原样复制）。
String rebuildWithManifest(String pkgPath, Map<String, dynamic> manifestJson) {
  final archive = ZipDecoder().decodeBytes(File(pkgPath).readAsBytesSync());
  final out = Archive();
  final bytes = utf8.encode(jsonEncode(manifestJson));
  out.addFile(ArchiveFile('manifest.json', bytes.length, bytes));
  for (final f in archive) {
    if (f.name == 'manifest.json') continue;
    final content = f.content as List<int>;
    out.addFile(ArchiveFile(f.name, content.length, content));
  }
  final outFile = File('$pkgPath.rebuild');
  outFile.writeAsBytesSync(ZipEncoder().encode(out)!);
  return outFile.path;
}

/// 用 donor 包的 db.sqlite 替换 base 包（其余成员原样）→ 旧 manifest 对新数据。
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
  // AppDatabase.open() 走 sqflite 全局 openDatabase——测试环境把全局工厂
  // 指到 ffi（生产由插件注册），句柄缓存回归用例需要。
  databaseFactory = databaseFactoryFfi;
  LhBak.snapshotFactory = databaseFactoryFfi;

  late Directory tmp;
  late String dbPath;
  late String outDir;
  late String attachDir;
  late List<Database> opened;
  late BackupService service;

  /// 每次调用开一条新连接（singleInstance=false），并登记以便 tearDown 关净。
  Future<Database> openApp() => databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: DbSchema.version,
          singleInstance: false,
          onCreate: (d, v) async {
            final batch = d.batch();
            for (final sql in DbSchema.createStatements) {
              batch.execute(sql);
            }
            await batch.commit(noResult: true);
          },
        ),
      ).then((d) {
        opened.add(d);
        return d;
      });

  Future<void> insertTodo(String title) async {
    final d = await openApp();
    await d.insert(
        DbSchema.tTodos, {'title': title, 'created_at': 1, 'updated_at': 1});
    await d.close();
  }

  Future<List<String>> todoTitles() async {
    final d = await openApp();
    final rows = await d.query(DbSchema.tTodos, orderBy: 'id');
    await d.close();
    return rows.map((r) => r['title'] as String).toList();
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lh_backup_svc_');
    dbPath = '${tmp.path}/app.db';
    outDir = '${tmp.path}/backup';
    attachDir = '${tmp.path}/note_images';
    Directory(attachDir).createSync();
    opened = [];
    service = BackupService(
      exportDir: () => outDir,
      db: openApp,
      attachDirs: [attachDir],
      // 评审修复（Important）：documents 根直落文件（记账 lifeharness_ledger
      // .csv/.json）浅扫白名单入包。tmp 即「documents 根」替身。
      attachRootDirs: [tmp.path],
    );
    AppLog.reset();
  });

  tearDown(() async {
    // AppDatabase 单例兜底复位（句柄缓存回归用例可能留有连接）。
    try {
      await AppDatabase.instance.close();
    } catch (_) {}
    await FileLogSink.dispose();
    AppLog.reset();
    for (final d in opened) {
      try {
        await d.close();
      } catch (_) {
        // Windows 偶发句柄未放：不留测试假红。
      }
    }
    opened.clear();
    // 静态钩子一律复位（防跨用例串扰）。
    BackupService.saveAsDialog = BackupService.defaultSaveAsDialog;
    BackupService.pickFileHook = BackupService.defaultPickFile;
    BackupService.unpackOverride = null;
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('exportBackup', () {
    test('写应用导出目录 · 附件入包 members · 默认不带日志', () async {
      await insertTodo('导出前1');
      File('$attachDir/a.png').writeAsBytesSync([1, 2, 3]);

      final res = await service.exportBackup();
      expect(res.file.existsSync(), isTrue);
      expect(baseNameOf(res.file.path), startsWith('lifeharness_'));
      expect(baseNameOf(res.file.path), endsWith('.lhbak'));
      expect(baseNameOf(res.file.path),
          matches(RegExp(r'^lifeharness_\d{8}_\d{6}\.lhbak$')));
      expect(res.file.path.replaceAll('\\', '/'), contains('/backup/'));
      expect(res.manifest.members,
          contains('attachments/note_images/a.png'));
      expect(res.manifest.members.any((m) => m.startsWith('logs/')), isFalse);
    });

    test('withLogs=true 随包 FileLogSink.dayFiles（落盘目录拼接）', () async {
      await insertTodo('导出前2');
      final logDir = Directory('${tmp.path}/logs')..createSync();
      await FileLogSink.init(logDir.path);
      AppLog.add('备份随包日志行');
      await FileLogSink.flush();

      final res = await service.exportBackup(withLogs: true);
      final names = await FileLogSink.dayFiles();
      expect(names, isNotEmpty);
      for (final n in names) {
        expect(res.manifest.members, contains('logs/$n'));
      }
    });

    test('excludeTables + outDirOverride + nameTag 自动备份命名', () async {
      await insertTodo('导出前3');
      final alt = '${tmp.path}/alt_out';
      final res = await service.exportBackup(
        outDirOverride: alt,
        nameTag: 'auto_before_restore',
        excludeTables: [DbSchema.tCareLogs],
      );
      final name = baseNameOf(res.file.path);
      // 命名口径 auto_before_restore_*.lhbak（原型 s-backup 同源）
      expect(name, matches(RegExp(r'^auto_before_restore_\d{8}_\d{6}\.lhbak$')));
      expect(res.file.existsSync(), isTrue);
      expect(res.file.path.replaceAll('\\', '/'), contains('/alt_out/'));
      expect(res.manifest.excludedTables, contains(DbSchema.tCareLogs));
      expect(res.manifest.tables.containsKey(DbSchema.tCareLogs), isFalse);
    });

    test('withAttachments=false 不落附件成员', () async {
      File('$attachDir/skip.png').writeAsBytesSync([9]);
      final res = await service.exportBackup(withAttachments: false);
      expect(res.manifest.members.any((m) => m.startsWith('attachments/')),
          isFalse);
    });

    test('评审修复·documents 根记账导出（csv/json）入包，非白名单不收', () async {
      await insertTodo('根导出1');
      // ledger_export.dart:127 生产落点 = documents 根 · lifeharness_ledger.$fmt
      File('${tmp.path}/lifeharness_ledger.csv').writeAsStringSync('a,b\n');
      File('${tmp.path}/lifeharness_ledger.json').writeAsStringSync('[]');
      // 干扰项：非白名单扩展名 + 子目录（浅扫只收根一层白名单文件）
      File('${tmp.path}/notes.txt').writeAsStringSync('x');
      File('$attachDir/sub/deep.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('y');

      final res = await service.exportBackup();
      expect(res.manifest.members,
          containsAll(<String>[
            'attachments/lifeharness_ledger.csv',
            'attachments/lifeharness_ledger.json',
          ]),
          reason: '记账根目录导出必须入包（评审 Important 修复）');
      expect(res.manifest.members, isNot(contains('attachments/notes.txt')));
      expect(res.manifest.members, isNot(contains('attachments/deep.md')));
      // withAttachments=false 同样关闭根浅扫通道
      final off = await service.exportBackup(withAttachments: false);
      expect(off.manifest.members.any((m) => m.startsWith('attachments/')),
          isFalse);
    });
  });

  group('saveCopyToUserLocation / pickBackupFile（fake 钩子）', () {
    test('saveFile 钩子返回路径 → 透传 + prefs 记 backup_last_save_hint；取消=null', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = BackupService(
          exportDir: () => outDir, db: openApp, prefs: prefs);
      final res = await svc.exportBackup();
      String? srcSeen;
      BackupService.saveAsDialog = (src) async {
        srcSeen = src;
        return '/storage/emulated/0/Download/${baseNameOf(src)}';
      };
      final saved = await svc.saveCopyToUserLocation(res.file.path);
      expect(srcSeen, res.file.path);
      expect(saved, endsWith('.lhbak'));
      expect(prefs.getString('backup_last_save_hint'), saved);

      BackupService.saveAsDialog = (_) async => null;
      expect(await svc.saveCopyToUserLocation(res.file.path), isNull);
      // 取消不覆写上次成功提示
      expect(prefs.getString('backup_last_save_hint'), saved);
    });

    test('pickBackupFile 钩子：返回选中路径 / 取消 null', () async {
      BackupService.pickFileHook = () async => '/sdcard/x/lifeharness_1.lhbak';
      expect(await service.pickBackupFile(), '/sdcard/x/lifeharness_1.lhbak');
      BackupService.pickFileHook = () async => null;
      expect(await service.pickBackupFile(), isNull);
    });
  });

  group('importBackup', () {
    test('导出→改数据→导入→数据回滚 + auto_before_restore 存在', () async {
      await insertTodo('包内1');
      await insertTodo('包内2');
      final res = await service.exportBackup();

      await insertTodo('恢复前新增');
      expect(await todoTitles(), hasLength(3));

      final report = await service.importBackup(res.file.path);
      expect(report.tableCount, res.manifest.tables.length);
      expect(report.totalRows,
          res.manifest.tables.values.fold<int>(0, (a, t) => a + t.rows));
      // 轮7 拍板：X-Ray 派生表恒不进包 → 恢复时按当前 schema 建空表，如实入 missingTables。
      expect(report.missingTables, unorderedEquals(kRegenerableExcluded));
      expect(report.skippedLarge, isEmpty);
      expect(await todoTitles(), unorderedEquals(['包内1', '包内2']));

      // 恢复前自动备份：命名 + 落应用导出目录（永不进同步目录）
      expect(report.autoBackupPath, isNotNull);
      expect(File(report.autoBackupPath!).existsSync(), isTrue);
      expect(baseNameOf(report.autoBackupPath!),
          startsWith('auto_before_restore_'));
      final auto = Directory(outDir)
          .listSync()
          .whereType<File>()
          .where((f) => baseNameOf(f.path).startsWith('auto_before_restore_'))
          .toList();
      expect(auto, hasLength(1));
      // 自动备份发生在 close/替换之前：包内是「恢复前新增」还在的现场
      final autoManifest =
          await LhBak.verify(auto.single.path);
      expect(autoManifest.tables[DbSchema.tTodos]!.rows, 3);
    });

    test('口令包：不带口令 needPassphrase 现库不动 → 带口令恢复成功', () async {
      await insertTodo('加密1');
      final res = await service.exportBackup(passphrase: 's3cret!');
      await insertTodo('加密后新增');

      await expectLater(
          service.importBackup(res.file.path),
          throwsLhBak(LhBakException.codeNeedPassphrase));
      // 前置校验失败：现库未动，自动备份未发生
      expect(await todoTitles(), containsAll(['加密1', '加密后新增']));
      expect(
          Directory(outDir)
              .listSync()
              .where((f) => baseNameOf(f.path).contains('auto_before_restore')),
          isEmpty);

      final report =
          await service.importBackup(res.file.path, passphrase: 's3cret!');
      expect(report.tableCount, greaterThan(0));
      expect(await todoTitles(), unorderedEquals(['加密1']));
    });

    test('坏包三类 code 冒泡 LhBakException · 不半恢复（现库未 close 未替换）', () async {
      await insertTodo('完好1');
      final good = await service.exportBackup();
      await insertTodo('完好2');

      // badZip：尾部截断
      final bytes = good.file.readAsBytesSync();
      final cut = File('${tmp.path}/cut.lhbak')
        ..writeAsBytesSync(bytes.sublist(0, bytes.length - 30));
      // badManifest：声明不存在的成员
      final mJson = jsonDecode(
              utf8.decode(ZipDecoder()
                      .decodeBytes(good.file.readAsBytesSync())
                      .findFile('manifest.json')!
                      .content as List<int>))
          as Map<String, dynamic>;
      (mJson['members'] as List).add('attachments/ghost.bin');
      final ghost = rebuildWithManifest(good.file.path, mJson);
      // checksumMismatch：旧 manifest 对上改后数据
      final newer = await service.exportBackup();
      final spliced = spliceDbFrom(good.file.path, newer.file.path);

      final openedBefore = opened.length;
      await expectLater(
          service.importBackup(cut.path), throwsLhBak(LhBakException.codeBadZip));
      await expectLater(
          service.importBackup(ghost),
          throwsLhBak(LhBakException.codeBadManifest));
      await expectLater(
          service.importBackup(spliced),
          throwsLhBak(LhBakException.codeChecksumMismatch));
      // 现库不动：数据仍在 + 未发生 close→reopen（除自查外连接数零增长）
      expect(await todoTitles(), unorderedEquals(['完好1', '完好2']));
      expect(opened.length, openedBefore + 1);
    });

    test('unpack 中途失败：原库重开可用 · 数据未变 · 自动备份已在', () async {
      await insertTodo('现场1');
      final res = await service.exportBackup();
      await insertTodo('现场2');

      BackupService.unpackOverride =
          ({required String filePath, required Database targetDb, String? passphrase}) async {
        // 评审修复（Minor）：仿真实 unpack 的事务结构——事务内先写入哨兵
        // 数据再抛（transaction<Never> 回滚后重抛），让「原库未污染」断言
        // 真正演练回滚路径。
        await targetDb.transaction<Never>((txn) async {
          await txn.insert(DbSchema.tTodos, {
            'title': '污染哨兵',
            'created_at': 1,
            'updated_at': 1,
          });
          throw StateError('unpack 中途失败');
        });
      };

      await expectLater(service.importBackup(res.file.path),
          throwsStateError);
      BackupService.unpackOverride = null;

      // 失败路径已重开原库：数据未变（哨兵行随事务回滚）、连接可查、
      // 后续导出照常。
      expect(await todoTitles(), unorderedEquals(['现场1', '现场2']));
      expect(await todoTitles(), isNot(contains('污染哨兵')));
      final again = await service.exportBackup();
      expect(again.file.existsSync(), isTrue);
      expect(
          Directory(outDir)
              .listSync()
              .where((f) => baseNameOf(f.path).contains('auto_before_restore')),
          isNotEmpty);
    });

    test('RestoreReport.skippedLarge 携带 manifest 超大附件跳过清单', () async {
      await insertTodo('大附件1');
      File('$attachDir/big.bin').writeAsBytesSync(List.filled(64, 7));
      final pkg = await LhBak.create(
        db: await openApp(),
        outDirPath: outDir,
        attachDirs: [attachDir],
        passphrase: 'pw',
        maxEncryptBytes: 16, // big.bin（64B）必被跳过
      );
      expect(pkg.manifest.skippedLarge,
          ['attachments/note_images/big.bin']);

      final report = await service.importBackup(pkg.file.path, passphrase: 'pw');
      expect(report.skippedLarge, ['attachments/note_images/big.bin']);
    });
  });

  group('AppDatabase 句柄缓存（评审 Critical 修复回归）', () {
    test('open→close→再 open：_db 置空语义，死句柄不再被返回', () async {
      final d1 = await AppDatabase.instance.open(pathOverride: tmp.path);
      expect(d1.isOpen, isTrue);
      await d1.insert(DbSchema.tTodos, {
        'title': 'close 前写入',
        'created_at': 1,
        'updated_at': 1,
      });
      await AppDatabase.instance.close();
      expect(d1.isOpen, isFalse);
      // _db 已置空：db getter 抛 StateError，而不是返回缓存旧句柄。
      expect(() => AppDatabase.instance.db, throwsStateError);
      final d2 = await AppDatabase.instance.open(pathOverride: tmp.path);
      expect(identical(d1, d2), isFalse); // 旧句柄不再被返回
      expect(d2.isOpen, isTrue);
      final rows = await d2.query(DbSchema.tTodos,
          where: 'title = ?', whereArgs: ['close 前写入']);
      expect(rows, hasLength(1)); // 新连接可用、数据仍在
    });

    test('生产接线 importBackup（db=instance.open + closeDb=instance.close）',
        () async {
      // 回归（评审 Critical）：修复前 importBackup 裸调 Database.close，
      // AppDatabase.open() 对非空 _db 短路返回死句柄 → close 后 db() 拿到的
      // 仍是已关连接，unpack 在死库上执行。现生产注入走 closeDb（close 后
      // 置空 _db），db() 重开拿到可用新连接。
      final svc = BackupService(
        exportDir: () => outDir,
        db: () => AppDatabase.instance.open(pathOverride: tmp.path),
        closeDb: AppDatabase.instance.close,
        attachDirs: [attachDir],
      );
      final live = await AppDatabase.instance.open(pathOverride: tmp.path);
      Future<void> addTodo(String title) => live.insert(DbSchema.tTodos,
          {'title': title, 'created_at': 1, 'updated_at': 1});
      await addTodo('生产接线1');
      final res = await svc.exportBackup();
      await addTodo('恢复后应消失');

      final report = await svc.importBackup(res.file.path);
      expect(report.tableCount, greaterThan(0));
      // 导入后实例连接是「重开的新句柄」且数据已回滚——死句柄场景此步即炸。
      expect(AppDatabase.instance.isInitialized, isTrue);
      expect(AppDatabase.instance.db.isOpen, isTrue);
      final rows = await AppDatabase.instance.db.query(DbSchema.tTodos);
      expect(rows.map((r) => r['title']), unorderedEquals(['生产接线1']));
    });

    test('生产接线 importBackup 失败路径（closeDb 注入）：重开是新可用句柄',
        () async {
      // 回归（评审修复轮2 · Important）：失败分支曾裸调 working.close()——
      // AppDatabase._db 仍缓存已关句柄，其后 db() 的 open() 对非空 _db
      // 短路返回死句柄，「重开原库恢复现场」失效。现失败分支与成功路径
      // 同走 closeDb（置空缓存）后再 db() 重开。
      final svc = BackupService(
        exportDir: () => outDir,
        db: () => AppDatabase.instance.open(pathOverride: tmp.path),
        closeDb: AppDatabase.instance.close,
        attachDirs: [attachDir],
      );
      final live = await AppDatabase.instance.open(pathOverride: tmp.path);
      Future<void> addTodo(String title) => live.insert(DbSchema.tTodos,
          {'title': title, 'created_at': 1, 'updated_at': 1});
      await addTodo('失败接线1');
      final res = await svc.exportBackup();
      await addTodo('失败接线2');

      Database? unpackTarget;
      BackupService.unpackOverride =
          ({required String filePath, required Database targetDb, String? passphrase}) async {
        unpackTarget = targetDb;
        // 仿真实 unpack 事务结构：写入哨兵再抛（回滚重抛）。
        await targetDb.transaction<Never>((txn) async {
          await txn.insert(DbSchema.tTodos, {
            'title': '污染哨兵',
            'created_at': 1,
            'updated_at': 1,
          });
          throw StateError('unpack 中途失败');
        });
      };

      await expectLater(svc.importBackup(res.file.path), throwsStateError);
      BackupService.unpackOverride = null;

      // 失败分支重开走 closeDb：原 unpack 目标（已关）被换掉，实例持有的
      // 是新可用句柄且原库数据完好——修复前 instance.db 即该死句柄，查询即炸。
      expect(AppDatabase.instance.isInitialized, isTrue);
      expect(unpackTarget, isNotNull);
      expect(unpackTarget!.isOpen, isFalse);
      expect(identical(AppDatabase.instance.db, unpackTarget), isFalse);
      expect(AppDatabase.instance.db.isOpen, isTrue);
      final rows = await AppDatabase.instance.db.query(DbSchema.tTodos,
          orderBy: 'id');
      expect(rows.map((r) => r['title']),
          unorderedEquals(['失败接线1', '失败接线2']));
      expect(rows.map((r) => r['title']), isNot(contains('污染哨兵')));
      // 现场恢复后服务照常可用：再导出成功。
      final again = await svc.exportBackup();
      expect(again.file.existsSync(), isTrue);
    });
  });
}
