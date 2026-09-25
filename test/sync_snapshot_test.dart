/// Task 16：`SnapshotService` 快照生成 + N 份裁剪验收测试。
///
/// 口径（设计稿 §3/§4 + 钉死）：
/// - 快照 = 备份文件：exportBackup(withLogs:true, outDirOverride:docs/sync/,
///   excludeTables: careExcluded? DbSchema.careTables : [], nameTag:'sync')；
///   T10 命名实装为 `sync_YYYYMMDD_HHMMSS[-n].lhbak`（nameTag 前置，
///   见 backup_service.dart 改名分支与 task-10 取证）；
/// - 生成后按 mtime 新→旧保最新 keepN 份（刚生成的永不裁）；
///   `auto_before_restore_` 前缀与非快照命名（logs/ 等）绝不碰；
/// - keepN 读 prefs `sync_keep_snapshots`，默认 5；
/// - careExcluded 读取抛异常（DB 未开等）→ 视为 true 保守排除 + AppLog warn；
/// - localInventory() 产台账/差异的本地侧清单（digest=null，仅展示 size/mtime）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/sync/snapshot_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  LhBak.snapshotFactory = databaseFactoryFfi;

  late Directory tmp;
  late String docsDir;
  late String syncDir;
  late String dbPath;
  late List<Database> opened;

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

  /// 预置一份「历史快照」：sync_ 命名 + 回填旧 mtime（裁剪时序可控，不靠 sleep）。
  File seedOldSnapshot(String name, DateTime mtime) {
    final f = File(p.join(syncDir, name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(5, 1));
    f.setLastModifiedSync(mtime);
    return f;
  }

  /// sync/ 顶层快照命名文件（裁剪候选口径，同 SnapshotService 内部）。
  List<String> snapshotNames() => Directory(syncDir)
      .listSync()
      .whereType<File>()
      .map((f) => p.basename(f.path))
      .where(SnapshotService.isSyncSnapshotName)
      .toList()
    ..sort();

  SnapshotService buildService(
    SharedPreferences prefs, {
    required Future<bool> Function() careExcluded,
  }) =>
      SnapshotService(
        backup: BackupService(
          exportDir: () => p.join(tmp.path, 'backup'),
          db: openApp,
        ),
        prefs: prefs,
        docsDir: () => docsDir,
        careExcluded: careExcluded,
      );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lh_snapshot_');
    docsDir = p.join(tmp.path, 'documents');
    syncDir = p.join(docsDir, 'sync');
    Directory(syncDir).createSync(recursive: true);
    dbPath = p.join(tmp.path, 'app.db');
    opened = [];
    AppLog.reset();
  });

  tearDown(() async {
    AppLog.reset();
    for (final d in opened) {
      try {
        await d.close();
      } catch (_) {
        // Windows 偶发句柄未放：不留测试假红。
      }
    }
    opened.clear();
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('build 产出快照（= 备份文件）', () {
    test('withLogs 档 · sync 命名落 <docs>/sync/ · 返回 file/manifest/pruned',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => false);
      final res = await svc.build(keepN: 5);
      expect(res.file.existsSync(), isTrue);
      expect(p.dirname(res.file.path), syncDir);
      // T10 实装命名 = nameTag 前置（backup_service.dart 改名分支：
      // 'sync' + '_YYYYMMDD_HHmmss.lhbak'），非 brief 字面的 lifeharness_*_sync*。
      expect(
          p.basename(res.file.path),
          matches(RegExp(r'^sync_\d{8}_\d{6}(-\d+)?\.lhbak$')));
      expect(res.pruned, isEmpty); // 首份无可裁
      expect(res.manifest!.members, contains('db.sqlite'));
    });

    test('careExcluded=true → manifest.excludedTables ⊇ careTables 且 sync/ 内包 verify 正常',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => true);
      final res = await svc.build(keepN: 5);
      expect(res.manifest!.excludedTables,
          containsAll(<String>[...DbSchema.careTables]));
      for (final t in DbSchema.careTables) {
        expect(res.manifest!.tables.containsKey(t), isFalse,
            reason: '排表包快照内不得有 $t（红线 7）');
      }
      // 快照就在 sync/ 目录：verify 链路照常（T17 下载后校验同源）。
      final verify = await LhBak.verify(res.file.path);
      expect(verify.excludedTables, containsAll(DbSchema.careTables));
      expect(verify.tables.containsKey(DbSchema.tTodos), isTrue);
    });

    test('T16 携带（端到端）：careExcluded=true 快照 → importBackup '
        'RestoreReport.missingTables ⊇ careTables', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => true);
      final res = await svc.build(keepN: 5);
      // verify → 自动备份 → unpack：排除表按当前 schema 建空表并进缺失清单，
      // 导入报告据此向用户列「N 张表未随包恢复」（红线 7 的可观测证据）。
      final report = await svc.backup.importBackup(res.file.path);
      expect(report.missingTables, containsAll(<String>[...DbSchema.careTables]),
          reason: '排表包恢复后呵护表必须出现在 missingTables');
      expect(report.missingTables, isNot(contains(DbSchema.tTodos)),
          reason: '未排除的表不在缺失清单');
      expect(report.autoBackupPath, isNotNull);
    });

    test('careExcluded=false → 全量（呵护表在包内，excludedTables 空）',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => false);
      final res = await svc.build(keepN: 5);
      expect(res.manifest!.excludedTables, isEmpty);
      for (final t in DbSchema.careTables) {
        expect(res.manifest!.tables.containsKey(t), isTrue,
            reason: '本机快照默认全量：$t 应在（红线 7 排除的是同步开关置位时）');
      }
    });

    test('careExcluded 读取抛异常 → 视为 true 保守排除 + AppLog warn', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async {
        throw StateError('DB 未开');
      });
      final res = await svc.build(keepN: 5);
      expect(res.manifest!.excludedTables, containsAll(DbSchema.careTables));
      expect(
          AppLog.lines.any((l) =>
              l.level == LhLevel.warn && l.text.contains('care.syncExcluded')),
          isTrue,
          reason: '保守排除必须留 warn 痕');
    });
  });

  group('keepN 裁剪（时间序保最新 keepN 份）', () {
    test('keepN=3：第 4 份生成后最旧 2 份被裁；刚生成的在；auto_before_restore_ 不碰',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => false);
      final d1 = seedOldSnapshot('lifeharness_sync_20200101_000001.lhbak',
          DateTime(2020, 1, 1));
      final d2 = seedOldSnapshot('lifeharness_sync_20200102_000002.lhbak',
          DateTime(2020, 1, 2));
      final d3 = seedOldSnapshot('lifeharness_sync_20200103_000003.lhbak',
          DateTime(2020, 1, 3));
      final d4 = seedOldSnapshot('lifeharness_sync_20200104_000004.lhbak',
          DateTime(2020, 1, 4));
      // 防御项：auto_before_restore_ 前缀（本不该出现在 sync/）与非快照命名。
      final auto = File(p.join(syncDir, 'auto_before_restore_20200105_000000.lhbak'))
        ..writeAsBytesSync([1])
        ..setLastModifiedSync(DateTime(2019));
      final notes = File(p.join(syncDir, 'readme.txt'))..writeAsStringSync('x');

      final res = await svc.build(keepN: 3); // 目录内第 5 份候选 → 保 3 裁 2
      expect(res.pruned,
          unorderedEquals([p.basename(d1.path), p.basename(d2.path)]));
      expect(res.file.existsSync(), isTrue); // 刚生成的永不裁
      expect(File(d3.path).existsSync(), isTrue);
      expect(File(d4.path).existsSync(), isTrue);
      expect(File(auto.path).existsSync(), isTrue);
      expect(File(notes.path).existsSync(), isTrue);
      expect(snapshotNames(), hasLength(3));
      expect(snapshotNames(), contains(p.basename(res.file.path)));
    });

    test('连发 build 各自裁剪：目录内快照数恒不超 keepN，最新者始终在场',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => false);
      final generated = <String>[];
      for (var i = 0; i < 3; i++) {
        final res = await svc.build(keepN: 2);
        generated.add(p.basename(res.file.path));
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(snapshotNames().length, lessThanOrEqualTo(2));
        expect(File(p.join(syncDir, generated.last)).existsSync(), isTrue);
      }
      // 3 连发 + keepN=2 → 最旧两份（其一）已被后两轮裁掉。
      expect(generated.where((n) => snapshotNames().contains(n)).length, 2);
    });

    test('刚生成的即使 mtime 最旧也受 protect 豁免（防御性）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => false);
      // 现状：「刚生成」的一份 mtime 被拨到最旧（模拟时钟回拨），两份历史档
      // 反而更新 → 若无 protect 它会被裁；keepN=2 时只应留最新历史档 + 它。
      final cur = seedOldSnapshot('lifeharness_sync_20000101_000000.lhbak',
          DateTime(2000));
      final newer = seedOldSnapshot('lifeharness_sync_20300102_000000.lhbak',
          DateTime(2030, 1, 2));
      final mid = seedOldSnapshot('lifeharness_sync_20300101_000000.lhbak',
          DateTime(2030, 1, 1));
      final pruned =
          await svc.pruneSnapshots(keepN: 2, protect: cur.path);
      expect(pruned, [p.basename(mid.path)]);
      expect(cur.existsSync(), isTrue); // protect 永不裁
      expect(newer.existsSync(), isTrue); // 最新 keepN-1 份保留
      expect(File(mid.path).existsSync(), isFalse);
    });

    test('keepN 读 prefs sync_keep_snapshots 覆盖默认；非法值落回 5', () async {
      SharedPreferences.setMockInitialValues({'sync_keep_snapshots': 2});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => false);
      seedOldSnapshot('lifeharness_sync_20200101_000001.lhbak',
          DateTime(2020, 1, 1));
      seedOldSnapshot('lifeharness_sync_20200102_000002.lhbak',
          DateTime(2020, 1, 2));
      seedOldSnapshot('lifeharness_sync_20200103_000003.lhbak',
          DateTime(2020, 1, 3));
      final res = await svc.build(); // 不带 keepN 形参 → 读 prefs=2
      expect(res.pruned, hasLength(2)); // 4 份候选保 2 裁 2
      expect(snapshotNames(), hasLength(2));

      // 默认 5：4 份旧档 + 1 新生成 = 5 候选，恰保不裁。
      SharedPreferences.setMockInitialValues({});
      final prefs2 = await SharedPreferences.getInstance();
      final svc2 = buildService(prefs2, careExcluded: () async => false);
      for (final n in Directory(syncDir)
          .listSync()
          .whereType<File>()
          .where((f) => SnapshotService.isSyncSnapshotName(p.basename(f.path)))
          .toList()) {
        n.deleteSync();
      }
      for (var i = 1; i <= 4; i++) {
        seedOldSnapshot('lifeharness_sync_2020010${i}_00000$i.lhbak',
            DateTime(2020, 1, i));
      }
      final res2 = await svc2.build();
      expect(res2.pruned, isEmpty);
      expect(snapshotNames(), hasLength(5));

      // 非法值（0/负数/字符串）→ 落回默认 5，不炸不裁光。
      SharedPreferences.setMockInitialValues({'sync_keep_snapshots': 0});
      final prefs3 = await SharedPreferences.getInstance();
      final svc3 = buildService(prefs3, careExcluded: () async => false);
      final res3 = await svc3.build(); // 6 候选保 5 裁最旧 1
      expect(res3.pruned, hasLength(1));
      expect(snapshotNames(), hasLength(5));
    });
  });

  group('localInventory（台账/差异本地侧清单）', () {
    test('扫 sync/ 全树产 FileEntry：posix 相对路径 + size + mtime，digest=null',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => false);
      File(p.join(syncDir, 'lifeharness_sync_a.lhbak')).writeAsBytesSync([1, 2, 3, 4]);
      File(p.join(syncDir, 'logs', 'lh-2026-09-25.log'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([7, 8]);
      final inv = await svc.localInventory();
      expect(inv.map((e) => e.relativePath),
          ['lifeharness_sync_a.lhbak', 'logs/lh-2026-09-25.log']);
      expect(inv.every((e) => e.digest == null), isTrue);
      expect(inv.first.size, 4);
      expect(inv.first.modified, isNotNull);
    });

    test('目录不存在 → 空清单不抛（首次开机前无 sync/）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = SnapshotService(
        backup: BackupService(exportDir: () => docsDir, db: openApp),
        prefs: prefs,
        docsDir: () => p.join(tmp.path, 'no-such-docs'),
        careExcluded: () async => false,
      );
      expect(await svc.localInventory(), isEmpty);
    });

    test('build 后清单可见新快照（relativePath 非空，可直喂台账/diff）',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = buildService(prefs, careExcluded: () async => false);
      final res = await svc.build(keepN: 5);
      final inv = await svc.localInventory();
      expect(
          inv.any((e) => e.relativePath == p.basename(res.file.path)), isTrue);
      expect(inv.every((e) => e.relativePath.isNotEmpty), isTrue);
    });
  });

  group('R3② 快照复用（活库无新写入不再每点必出新包）', () {
    SnapshotService svcWithDb(SharedPreferences prefs) => SnapshotService(
          backup: BackupService(
            exportDir: () => p.join(tmp.path, 'backup'),
            db: openApp,
          ),
          prefs: prefs,
          docsDir: () => docsDir,
          careExcluded: () async => false,
          dbFile: () => File(dbPath),
        );

    test('首建后库无写入 · 二次 build 复用（reused=true · manifest=null · '
        '文件数不涨 · 路径不变）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = svcWithDb(prefs);
      final first = await svc.build(keepN: 5);
      expect(first.reused, isFalse);
      final namesBefore = snapshotNames();
      final second = await svc.build(keepN: 5);
      expect(second.reused, isTrue);
      expect(second.manifest, isNull, reason: '复用未打包，无新 manifest');
      expect(second.file.path, first.file.path);
      expect(snapshotNames(), namesBefore,
          reason: 'R3②：连点同步不得每点多了个 lhbak');
    });

    test('库mtime晚于最新快照（有新写入）→ 必出新包（reused=false）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = svcWithDb(prefs);
      final first = await svc.build(keepN: 5);
      // 不靠 sleep：直接把库 mtime 回填到快照之后，模拟「快照后又有写入」。
      File(dbPath).setLastModifiedSync(
          first.file.lastModifiedSync().add(const Duration(seconds: 5)));
      final second = await svc.build(keepN: 5);
      expect(second.reused, isFalse);
      expect(second.file.path, isNot(first.file.path));
      expect(second.manifest, isNotNull);
    });

    test('force=true 跳过复用必出新包；未注入 dbFile 永不复用（旧行为）',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = svcWithDb(prefs);
      final first = await svc.build(keepN: 5);
      final forced = await svc.build(keepN: 5, force: true);
      expect(forced.reused, isFalse);
      expect(forced.file.path, isNot(first.file.path));
      // 无 dbFile 的旧装配：连续 build 行为与 R3 前一致（每点必出）。
      final legacy = buildService(prefs, careExcluded: () async => false);
      final a = await legacy.build(keepN: 5);
      final b = await legacy.build(keepN: 5);
      expect(a.reused, isFalse);
      expect(b.reused, isFalse, reason: 'dbFile 缺省 → 保守走真实生成');
    });
  });

  group('R5a 附件同步根（attachments/ 前缀文件级增量）', () {
    SnapshotService svcWithAttach(SharedPreferences prefs) => SnapshotService(
          backup: BackupService(
            exportDir: () => p.join(tmp.path, 'backup'),
            db: openApp,
          ),
          prefs: prefs,
          docsDir: () => docsDir,
          careExcluded: () async => false,
          attachRoots: [
            AttachRoot(
                cloudName: 'note_images',
                localDir: p.join(docsDir, 'note_images')),
            AttachRoot(
                cloudName: 'book_covers',
                localDir: p.join(docsDir, 'book_covers')),
          ],
        );

    test('localInventory 含附件（attachments/ 前缀）+ resolveLocal 映射回媒体目录',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final imgDir = Directory(p.join(docsDir, 'note_images'))
        ..createSync(recursive: true);
      File(p.join(imgDir.path, 'abc.jpg')).writeAsBytesSync([1, 2, 3]);
      final svc = svcWithAttach(prefs);
      final inv = await svc.localInventory();
      final e = inv.firstWhere((x) => x.relativePath == 'attachments/note_images/abc.jpg');
      expect(e.size, 3);
      expect(svc.resolveLocal('attachments/note_images/abc.jpg'),
          p.joinAll([docsDir, 'note_images', 'abc.jpg']));
      // 非附件路径仍落 sync/。
      expect(svc.resolveLocal('x/y.lhbak'),
          p.joinAll([syncDir, 'x', 'y.lhbak']));
    });

    test('resolveDownload：附件直落媒体目录；同名不同大小→null 隔离 exports；非附件→null',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final imgDir = Directory(p.join(docsDir, 'note_images'))
        ..createSync(recursive: true);
      final svc = svcWithAttach(prefs);
      // 不存在 → 给出媒体目录目标。
      final dest = svc.resolveDownload('attachments/note_images/n.jpg', 5);
      expect(dest, p.joinAll([docsDir, 'note_images', 'n.jpg']));
      // 同名同大小 → 同路径（幂等跳过由编排层判）。
      File(dest!).writeAsBytesSync(List.filled(5, 7));
      expect(svc.resolveDownload('attachments/note_images/n.jpg', 5), dest);
      // 同名不同大小 → null（exports 隔离，绝不覆盖）。
      expect(svc.resolveDownload('attachments/note_images/n.jpg', 9), isNull);
      // 非附件 → null。
      expect(svc.resolveDownload('sync_x.lhbak', 1), isNull);
    });

    test('同步快照 = 纯 DB：包内无 logs/ 与 attachments/ 成员', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final imgDir = Directory(p.join(docsDir, 'note_images'))
        ..createSync(recursive: true);
      File(p.join(imgDir.path, 'z.jpg')).writeAsBytesSync([9]);
      final svc = svcWithAttach(prefs);
      final res = await svc.build(keepN: 5);
      final verify = await LhBak.verify(res.file.path);
      expect(verify.members.any((m) => m.startsWith('logs/')), isFalse,
          reason: 'R5a 快照去日志');
      expect(verify.members.any((m) => m.startsWith('attachments/')), isFalse,
          reason: 'R5a 附件脱离快照包，走文件级增量');
      expect(verify.members, contains('db.sqlite'));
    });
  });
}
