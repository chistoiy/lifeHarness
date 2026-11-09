/// 余量批4 · **部分恢复（A1 按模块整组替换）** 验收测试。
///
/// 口径（工单 §4）：恢复侧读 `manifest.scope`——
/// - 无 `scope` / `scope.modules` 为空 ⇒ **全量替换**（原路径，向后兼容）；
/// - 有 `scope` ⇒ 只对 scope 涉及的表 `DROP`+按终态 DDL 重建+灌入，
///   **其他模块本机数据一行不动**；
/// - 反复恢复**幂等**（第二次不产生重复行）；
/// - 子集包不应用 `config/settings.json`、不碰别的模块的附件目录；
/// - 恢复前自动备份恒为**全量**（回退件不能只回那几个模块）。
///
/// 变异刀靶点（本文件钉住）：摘掉 unpack 里的 `belongsTo` 归属判据 ⇒
/// 子集包误走全库清空 ⇒ 第 ①组必红。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/shared/linkage/export_units.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Matcher throwsLhBak(String code) =>
    throwsA(isA<LhBakException>().having((e) => e.code, 'code', code));

String baseNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  LhBak.snapshotFactory = databaseFactoryFfi;

  late Directory tmp;
  late String dbPath;
  late String outDir;
  late String habitAttach;
  late String journalAttach;
  late String bookAttach;
  late List<Database> opened;
  late BackupService service;

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

  Future<void> exec(Future<void> Function(Database d) fn) async {
    final d = await openApp();
    await fn(d);
    await d.close();
  }

  /// 习惯打卡行（「习惯」单元的表，用作被整组替换的那一模块）。
  Future<void> addHabit(String habitId, String day) => exec((d) => d.insert(
        DbSchema.tHabitEntries,
        {
          'habit_id': habitId,
          'day': day,
          'checked': 1,
          'origin': 'manual',
          'created_at': 1,
          'updated_at': 1,
        },
      ));

  Future<List<String>> habitDays() async {
    final d = await openApp();
    final rows = await d.query(DbSchema.tHabitEntries, orderBy: 'day');
    await d.close();
    return rows.map((r) => r['day'] as String).toList();
  }

  Future<int> countOf(String table) async {
    final d = await openApp();
    final rows =
        await d.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
    await d.close();
    return rows.first['c'] as int;
  }

  /// 日记条目（另一个模块的数据，用来验「一行不动」）。`entry_date` 是
  /// 毫秒时间戳 INTEGER（不是 TEXT 日），`content` 是正文列。
  Future<void> addJournal(String day, String content) => exec((d) => d.insert(
        DbSchema.tJournal,
        {
          'entry_date': day,
          'content': content,
          'created_at': 1,
          'updated_at': 1,
        },
      ));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lh_restore_scope_');
    dbPath = '${tmp.path}/app.db';
    outDir = '${tmp.path}/backup';
    habitAttach = '${tmp.path}/habit_icons';
    journalAttach = '${tmp.path}/note_images';
    Directory(habitAttach).createSync(recursive: true);
    bookAttach = '${tmp.path}/book_covers';
    Directory(journalAttach).createSync(recursive: true);
    Directory(bookAttach).createSync(recursive: true);
    opened = [];
    service = BackupService(
      exportDir: () => outDir,
      db: openApp,
      attachDirs: [habitAttach, journalAttach, bookAttach],
    );
    AppLog.reset();
  });

  tearDown(() async {
    AppLog.reset();
    for (final d in opened) {
      try {
        await d.close();
      } catch (_) {
        // Windows 偶发句柄未放。
      }
    }
    opened.clear();
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('① 子集包按模块整组替换（其他模块一行不动）', () {
    test('只恢复所选模块 · 其他模块数据与本机新增全保留', () async {
      // 现场：日记 3 条、习惯打卡 2 条，两模块各有附件目录
      await addJournal('2026-10-01', '日记A');
      await addJournal('2026-10-02', '日记B');
      await addJournal('2026-10-03', '日记C');
      await addHabit('h1', '2026-10-01');
      await addHabit('h1', '2026-10-02');
      File('$habitAttach/a.png').writeAsBytesSync([1]);
      File('$journalAttach/j.png').writeAsBytesSync([2]);

      // 只导出「习惯」单元的子集包
      final pkg = await service.exportBackup(modules: ['habit']);
      expect(pkg.manifest.scope, isNotNull, reason: '子集包必须写 scope 段');
      expect(pkg.manifest.scope!['modules'], ['habit']);

      // 导出之后本机继续动：习惯加一条（会被包内版本覆盖），日记加一条（不许动）
      await addHabit('h1', '2026-10-05');
      await addJournal('2026-10-04', '日记D');
      expect(await countOf(DbSchema.tJournal), 4);

      final report = await service.importBackup(pkg.file.path);

      // 习惯＝按包内整组替换：本机导出后新增的那条消失，包内两条还在
      expect(await habitDays(), unorderedEquals(['2026-10-01', '2026-10-02']));

      // 日记＝一行不动（含导出后才新增的那条）
      expect(await countOf(DbSchema.tJournal), 4,
          reason: '子集恢复动了别的模块＝A1 题眼失守');
      final d = await openApp();
      final contents = (await d.query(DbSchema.tJournal, columns: ['content']))
          .map((r) => r['content'] as String)
          .toSet();
      await d.close();
      expect(contents, containsAll(['日记A', '日记B', '日记C', '日记D']));

      expect(report.isPartial, isTrue);
      expect(report.scopeModules, ['habit']);
    });

    test('子集包只还原本模块的附件目录，别的模块的连清都不清', () async {
      // 阅读与日记是全库唯二带附件目录的单元，正好互为对照。
      File('$bookAttach/cover.png').writeAsBytesSync([1]);
      File('$journalAttach/keep.png').writeAsBytesSync([2]);
      await addJournal('2026-10-01', '带附件的日记');
      final pkg = await service.exportBackup(modules: ['journal']);
      expect(pkg.manifest.scope!['modules'], ['journal']);

      // 导出后两个目录各加一个新文件：子集恢复只能动 diary 那一侧
      File('$journalAttach/after.png').writeAsBytesSync([3]);
      File('$bookAttach/later.png').writeAsBytesSync([4]);
      await service.importBackup(pkg.file.path);

      // 本模块目录＝整目录删除重建（陈旧文件 after.png 被清掉，只剩包内那份）
      expect(File('$journalAttach/keep.png').existsSync(), isTrue);
      expect(File('$journalAttach/after.png').existsSync(), isFalse,
          reason: '本模块附件走全量替换口径：包外的陈旧文件不该残留');
      // 别的模块目录＝一行不动（连清理都不该发生）
      expect(File('$bookAttach/cover.png').existsSync(), isTrue);
      expect(File('$bookAttach/later.png').existsSync(), isTrue,
          reason: '整目录删除重建是全量替换语义，子集包不许清别的模块附件');
    });
    test('包内混带别模块附件时，只还原本模块那组（第二道防线：目标映射收窄）',
        () async {
      // 前一条用例靠「包内本来就没有别人目录」过关——那只是第一道防线。
      // 这条直接把别人的附件**塞进包内**，逼恢复侧回答：映射收窄是否真生效。
      // 手造包：db 与 scope 都按「日记」单元，附件目录却给了两个。
      File('$bookAttach/cover.png').writeAsBytesSync([1]);
      File('$journalAttach/keep.png').writeAsBytesSync([2]);
      await addJournal('2026-10-01', '日记');
      final d = await openApp();
      final pkg = await LhBak.create(
        db: d,
        outDirPath: outDir,
        attachDirs: [bookAttach, journalAttach],
        excludeTables: const [],
        scope: {
          'modules': ['journal'],
          'withAttachments': true,
        },
      );
      await d.close();
      // 包内确实两组都在（否则这条用例测不到东西）
      expect(pkg.manifest.members, contains('attachments/book_covers/cover.png'));
      expect(pkg.manifest.members,
          contains('attachments/note_images/keep.png'));

      // 恢复前给两侧各加一个新文件
      File('$bookAttach/after.png').writeAsBytesSync([3]);
      File('$journalAttach/after.png').writeAsBytesSync([4]);
      await service.importBackup(pkg.file.path);

      // 本模块那组＝整目录重建（陈旧文件被清、包内文件在）
      expect(File('$journalAttach/keep.png').existsSync(), isTrue);
      expect(File('$journalAttach/after.png').existsSync(), isFalse);
      // 别模块那组＝一个字节都不动（照抄也砸不下去）
      expect(File('$bookAttach/after.png').existsSync(), isTrue,
          reason: '包内混带别模块附件时，子集恢复仍不许动别的模块目录');
    });

    test('附件目标映射只含本包模块的目录（第二道防线：组不在包内也不该被登记）', () async {
      // 上一条验的是「包内没有别人目录 ⇒ restoreAttachments 不动作」（第一道
      // 防线，靠组内无成员）。这一条直接钉第二道：**目标映射本身**就不许
      // 含别的模块的目录——两道防线任一失守都得红。
      File('$bookAttach/cover.png').writeAsBytesSync([1]);
      File('$journalAttach/keep.png').writeAsBytesSync([2]);
      await addJournal('2026-10-01', '日记');
      final pkg = await service.exportBackup(modules: ['journal']);
      await service.importBackup(pkg.file.path);

      // 若映射含 book_covers，整目录删除重建会清掉 cover.png
      expect(File('$bookAttach/cover.png').existsSync(), isTrue,
          reason: '目标映射含了别模块的目录 ⇒ 一旦包内恰好带该组就会清空它');
      expect(exportAttachDirsForModules(['journal']), isNot(contains('book_covers')));
      expect(exportAttachDirsForModules(['journal']), contains('note_images'));
    });

    test('config/settings.json 随包：全量包应用、子集包不应用（两档对照）', () async {
      // 这条必须**两档对照**才有效：只验子集包 false 的话，「压根没进
      // config 分支」也能 false，用例等于空转（变异测不出）。
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = BackupService(
        exportDir: () => outDir,
        db: openApp,
        attachDirs: [habitAttach, journalAttach, bookAttach],
        prefs: prefs,
      );
      await addHabit('h1', '2026-10-01');
      // 包内带 config 成员（withProjection＝true 时 exportBackup 会写）
      final subset = await svc.exportBackup(modules: ['habit'], withProjection: true);
      final full = await svc.exportBackup(withProjection: true);
      bool hasCfg(LhBakManifest m) =>
          m.members.contains('config/settings.json');
      expect(hasCfg(subset.manifest), isTrue,
          reason: '前提不成立（包内没 config 成员）这条用例就是空转');
      expect(hasCfg(full.manifest), isTrue);

      // 子集包：不套用全局口径（false）
      expect((await svc.importBackup(subset.file.path)).configRestored, isFalse);
      // 全量包：照旧套用（true）——两档不同才说明判据在起作用
      expect((await svc.importBackup(full.file.path)).configRestored, isTrue);
    });
  });

  group('② 反复恢复幂等（不产生重复行）', () {
    test('同一子集包连恢复两次，行数不变', () async {
      await addHabit('h1', '2026-10-01');
      await addHabit('h2', '2026-10-02');
      final pkg = await service.exportBackup(modules: ['habit']);

      await service.importBackup(pkg.file.path);
      final once = await habitDays();
      await service.importBackup(pkg.file.path);
      final twice = await habitDays();

      expect(twice, unorderedEquals(once));
      expect(twice, hasLength(2), reason: '第二次恢复不得叠成 4 行');
    });
  });

  group('③ 恢复前自动备份恒为全量（回退件不能只回几个模块）', () {
    test('子集恢复的 auto_before_restore 包无 scope 段且含其他模块数据', () async {
      await addJournal('2026-10-01', '回退用日记');
      await addHabit('h1', '2026-10-01');
      final pkg = await service.exportBackup(modules: ['habit']);

      final report = await service.importBackup(pkg.file.path);
      final auto = await LhBak.verify(report.autoBackupPath!);
      expect(auto.scope, isNull,
          reason: '自动备份是全量包，恢复它必须走整库替换');
      expect(auto.tables.containsKey(DbSchema.tJournal), isTrue);
      expect(auto.tables[DbSchema.tJournal]!.rows, 1);
    });

    test('回退件真能回退：用自动备份再恢复一次，回到动手前现场', () async {
      await addHabit('h1', '2026-10-01');
      final pkg = await service.exportBackup(modules: ['habit']);
      await addHabit('h1', '2026-10-09');
      expect(await habitDays(), hasLength(2));

      final report = await service.importBackup(pkg.file.path);
      expect(await habitDays(), unorderedEquals(['2026-10-01']));

      await service.importBackup(report.autoBackupPath!);
      expect(await habitDays(),
          unorderedEquals(['2026-10-01', '2026-10-09']));
    });
  });

  group('④ 无 scope 的老包/全量包走整库替换（向后兼容）', () {
    test('全量包恢复＝其他模块也被包内版本覆盖', () async {
      await addHabit('h1', '2026-10-01');
      await addJournal('2026-10-01', '全量日记');
      final pkg = await service.exportBackup();
      expect(pkg.manifest.scope, isNull, reason: '全量包不写 scope 段');

      await addJournal('2026-10-02', '恢复前新增日记');
      final report = await service.importBackup(pkg.file.path);

      expect(report.isPartial, isFalse);
      expect(report.scopeModules, isEmpty);
      expect(await countOf(DbSchema.tJournal), 1,
          reason: '整库替换下「恢复前新增日记」应被包内版本覆盖掉');
    });

    test('modules 为空列表的 scope 段按全量处理（兼容手改包）', () async {
      final scope = LhBakRestoreScope.fromManifest(manifestWith({
        'modules': <String>[],
        'withAttachments': true,
      }));
      expect(scope, isNull);
    });
  });

  group('⑤ 范围解析（LhBakRestoreScope.fromManifest）', () {
    test('多模块并集去重：模块表清单不重复', () {
      final s = LhBakRestoreScope.fromManifest(manifestWith({
        'modules': ['habit', 'journal'],
        'withAttachments': true,
      }))!;
      expect(s.moduleIds, ['habit', 'journal']);
      expect(s.tableNames, contains(DbSchema.tHabitEntries));
      expect(s.tableNames, contains(DbSchema.tJournal));
      // 每个表只登记一次（表→模块清单里没有同一 id 重复）
      for (final owners in s.tables.values) {
        expect(owners.toSet().length, owners.length);
      }
    });

    test('认不出任何模块 id ⇒ badManifest（不许静默按全量清库）', () {
      expect(
          () => LhBakRestoreScope.fromManifest(manifestWith({
                'modules': ['ghost_module_xyz'],
              })),
          throwsLhBak(LhBakException.codeBadManifest));
    });

    test('时间区间与附件开关如实解析', () {
      final s = LhBakRestoreScope.fromManifest(manifestWith({
        'modules': ['habit'],
        'from': '2025-10-15T00:00:00.000',
        'to': '2026-10-15T23:59:59.999',
        'withAttachments': false,
      }))!;
      expect(s.from, DateTime(2025, 10, 15));
      expect(s.to!.year, 2026);
      expect(s.withAttachments, isFalse);
    });

    test('坏 scope 在 close 之前就拒绝：现库与自动备份都不动', () async {
      await addHabit('h1', '2026-10-01');
      final pkg = await service.exportBackup();
      // 手改 manifest：塞一个认不出的模块 id
      final bad = File('${tmp.path}/bad_scope.lhbak');
      bad.writeAsBytesSync(_rewriteScope(pkg.file.path, {
        'modules': ['ghost_module_xyz'],
      }));

      final openedBefore = opened.length;
      await expectLater(service.importBackup(bad.path),
          throwsLhBak(LhBakException.codeBadManifest));
      expect(await habitDays(), unorderedEquals(['2026-10-01']));
      expect(opened.length, openedBefore + 1, reason: '未发生 close→reopen');
      final autos = Directory(outDir)
          .listSync()
          .whereType<File>()
          .where((f) => baseNameOf(f.path).startsWith('auto_before_restore_'));
      expect(autos, isEmpty, reason: '判据在自动备份之前，坏 scope 不该留回退件');
    });
  });
}

/// 造一份只带 scope 段的空 manifest（只验解析，不碰真实库）。
LhBakManifest manifestWith(Map<String, dynamic>? scope) => LhBakManifest(
      dbVersion: 1,
      appVersion: 'x',
      createdAt: DateTime(2026),
      tables: const {},
      excludedTables: const [],
      encrypted: false,
      members: const [],
      scope: scope,
    );

/// 改写包内 manifest 的 scope 段（其余成员原样），用于构造坏 scope 包。
List<int> _rewriteScope(String pkgPath, Map<String, dynamic> scope) {
  final archive = ZipDecoder().decodeBytes(File(pkgPath).readAsBytesSync());
  final out = Archive();
  for (final f in archive) {
    final content = f.content as List<int>;
    if (f.name != 'manifest.json') {
      out.addFile(ArchiveFile(f.name, content.length, content));
      continue;
    }
    final json = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
    json['scope'] = scope;
    final enc = utf8.encode(jsonEncode(json));
    out.addFile(ArchiveFile('manifest.json', enc.length, enc));
  }
  return ZipEncoder().encode(out)!;
}
