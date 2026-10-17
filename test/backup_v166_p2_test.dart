/// V1.66 备份格式四件套批2常驻用例（工单 20261013 执行面板·批2 第三行）：
/// - 模块子集打包＝活库表名差集法（范围外表进 excludedTables、范围附件目录按模块映射）；
/// - notes/ md 投影与 config/settings.json 入包且恒明文（extraFiles 通道）；
/// - readMemberText 往返（含成员缺失 → null）；
/// - 导入应用 config（旧 v1 包无该成员＝configRestored false，不炸恢复）；
/// - SettingsRepository exportAll ↔ importAll 往返。
library;

import 'dart:convert';
import 'dart:math' show Random;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/shared/linkage/backup_projection.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 按 V1.66 全量 schema 建内存库（同 backup_v166_test 建法）。
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

/// 按 V1.66 全量 schema 建文件库（importBackup 的整库替换要在真文件上跑；
/// singleInstance:false——服务注入每次新开连接，别共享缓存句柄）。
Future<Database> openSchemaDbFile(String path) =>
    databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: DbSchema.version,
        onCreate: (d, v) async {
          for (final sql in DbSchema.createStatements) {
            await d.execute(sql);
          }
        },
      ),
    );

Archive zipOf(File f) => ZipDecoder().decodeBytes(f.readAsBytesSync());

ArchiveFile? member(Archive zip, String name) => zip.findFile(name);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    // 钩子是 static：用例各自设置，必须还原防串场。
    BackupService.projectionHook = null;
  });

  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('lhbak_v166p2_');
  });
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('批2 · 模块子集打包（面板变异刀①）', () {
    test('modules=[read] 只含阅读表：范围外表进 excludedTables、附件只收映射目录',
        () async {
      final db = await openSchemaDb();
      await db.insert(DbSchema.tBooks,
          {'id': 'b1', 'title': '测试之书', 'created_at': 0, 'updated_at': 0});
      await db.insert(DbSchema.tNotes, {
        'title': '不该出现的笔记',
        'content': 'hello',
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert(DbSchema.tHabits, {
        'id': 'h1',
        'name': '习惯',
        'icon': 'x',
        'type': 'good',
        'cycle': 'day',
        'start_date': 0,
        'created_at': 0,
        'updated_at': 0,
      });
      // 附件目录：book_covers 属阅读、note_images 属日记——子集只收前者。
      final covers = Directory(p.join(temp.path, 'book_covers'))
        ..createSync();
      File(p.join(covers.path, 'c.png')).writeAsBytesSync([1, 2, 3]);
      final images = Directory(p.join(temp.path, 'note_images'))
        ..createSync();
      File(p.join(images.path, 'n.png')).writeAsBytesSync([4, 5, 6]);
      final outDir = p.join(temp.path, 'out');

      final svc = BackupService(
        exportDir: () => outDir,
        db: () async => db,
        attachDirs: [covers.path, images.path],
      );
      final res = await svc.exportBackup(
          modules: ['read'], withAttachments: true);

      final zip = zipOf(res.file);
      final manifest = res.manifest;
      expect(manifest.tables.keys, contains(DbSchema.tBooks));
      expect(manifest.tables.keys, isNot(contains(DbSchema.tNotes)));
      expect(manifest.tables.keys, isNot(contains(DbSchema.tHabits)));
      expect(manifest.excludedTables, contains(DbSchema.tNotes));
      expect(manifest.excludedTables, contains(DbSchema.tHabits));
      // 套包排除/可读成员缺席：子集包默认无投影（withProjection 未开）。
      expect(member(zip, 'attachments/book_covers/c.png'), isNotNull);
      expect(member(zip, 'attachments/note_images/n.png'), isNull);
      expect(member(zip, 'config/settings.json'), isNull);
      await db.close();
    });

    test('modules 空表＝全量：注册表之外的未归属表照常进包', () async {
      final db = await openSchemaDb();
      final svc = BackupService(
          exportDir: () => p.join(temp.path, 'out'), db: () async => db);
      final res = await svc.exportBackup(modules: const []);
      expect(res.manifest.tables.keys, contains(DbSchema.tHabits));
      expect(res.manifest.tables.keys, contains(DbSchema.tNotes));
      await db.close();
    });
  });

  group('批2 · 可读成员入包（notes/config·恒明文）', () {
    test('withProjection=true：config/settings.json 入包可解析、notes 投影随 md 开关',
        () async {
      SharedPreferences.setMockInitialValues({
        'lh.theme_id': 'aurora',
        'lh.trash_keep_days': 90,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = await openSchemaDb();
      await db.insert(DbSchema.tNotes, {
        'title': '投影我',
        'content': '# 标题\n正文一',
        'kind': 'plain',
        'created_at': 0,
        'updated_at': 0,
      });
      BackupService.projectionHook = buildNoteProjectionMembers;
      final svc = BackupService(
        exportDir: () => p.join(temp.path, 'out'),
        db: () async => db,
        prefs: prefs,
      );
      final res = await svc.exportBackup(withProjection: true, withMd: true);
      final zip = zipOf(res.file);

      final cfg = member(zip, 'config/settings.json');
      expect(cfg, isNotNull);
      final cfgMap =
          jsonDecode(utf8.decode(cfg!.content as List<int>)) as Map;
      expect(cfgMap['themeId'], 'aurora');
      expect(cfgMap['trashKeepDays'], 90);
      // 凭据防线：settings.json 不得出现任何 token/密码形键。
      expect(cfgMap.keys.any((k) => '$k'.toLowerCase().contains('token')),
          isFalse);

      final notes = member(zip, 'notes/notes.md');
      expect(notes, isNotNull);
      final notesText = utf8.decode(notes!.content as List<int>);
      expect(notesText, contains('投影我'));

      // withMd=false：config 在、notes 成员缺席。
      final res2 = await svc.exportBackup(withProjection: true, withMd: false);
      final zip2 = zipOf(res2.file);
      expect(member(zip2, 'config/settings.json'), isNotNull);
      expect(member(zip2, 'notes/notes.md'), isNull);
      await db.close();
    });

    test('readMemberText：成员往返、缺失 → null、extraFiles 恒明文', () async {
      final db = await openSchemaDb();
      final res = await LhBak.create(
        db: db,
        outDirPath: temp.path,
        extraFiles: {'config/settings.json': '{"themeId":"aurora"}'},
        now: DateTime(2026, 10, 13, 12),
      );
      expect(
          await readMemberText(
              res.file.path, 'config/settings.json'),
          '{"themeId":"aurora"}');
      expect(
          await readMemberText(res.file.path, 'notes/none.md'), isNull);
      // 加密包通道同 API：历史加密包若含 config 也读得到（此处验明文包给口令幂等）。
      expect(
          await readMemberText(res.file.path, 'config/settings.json',
              passphrase: 'x'),
          '{"themeId":"aurora"}');
      await db.close();
    });
  });

  group('批2 · 恢复侧 config 应用（面板变异刀②）', () {
    test('v2 包导入后口径设置还原；旧 v1 包 configRestored=false 不炸恢复', () async {
      // 活库（文件库，importBackup 走 close→unpack→reopen 注入路径）。
      final dbPath = p.join(temp.path, 'live.db');
      final db = await openSchemaDbFile(dbPath);
      SharedPreferences.setMockInitialValues({'lh.theme_id': 'aurora'});
      final prefs = await SharedPreferences.getInstance();
      final docs = Directory(p.join(temp.path, 'docs'))..createSync();
      final svc = BackupService(
        exportDir: () => p.join(temp.path, 'out'),
        db: () async => openSchemaDbFile(dbPath),
        attachDirs: const [],
        prefs: prefs,
      );
      // 先改口径（导出后对比用），再出全量 v2 包。
      final repo = SettingsRepository(prefs);
      await repo.save(repo.load().copyWith(themeId: 'aurora', trashKeepDays: 7));
      final pack = await svc.exportBackup(withProjection: true, withMd: false);
      // 换一套口径，模拟「别的机器」。
      await repo.save(repo.load().copyWith(themeId: 'minimal', trashKeepDays: 7));
      expect(repo.load().themeId, 'minimal');

      final report = await svc.importBackup(pack.file.path);
      expect(report.configRestored, isTrue);
      final applied = SettingsRepository(prefs).load();
      expect(applied.themeId, 'aurora');
      expect(applied.trashKeepDays, 7);
      await db.close();

      // 旧 v1 包（手工打包·无 config 成员）：恢复成功且 configRestored=false。
      final v1 = await packRawV1(
          outPath: p.join(temp.path, 'v1.lhbak'), dbPath: dbPath);
      final report2 = await svc.importBackup(v1);
      expect(report2.configRestored, isFalse);
      // v1 恢复不回写口径（还是 aurora）。
      expect(SettingsRepository(prefs).load().themeId, 'aurora');
    });
  });

  group('批2 · SettingsRepository 整包序列化', () {
    test('exportAll ↔ importAll 往返：口径字段全量还原', () async {
      SharedPreferences.setMockInitialValues({
        'lh.theme_id': 'aurora',
        'lh.note_latex': true,
        'lh.weather_city': '上海',
        'lh.trash_keep_days': 30,
      });
      final prefs1 = await SharedPreferences.getInstance();
      final exported = SettingsRepository(prefs1).exportAll();
      expect(exported['themeId'], 'aurora');
      expect(exported['weatherCity'], '上海');
      // 缺键兜 defaults；未知键忽略。
      final round = Map<String, Object?>.from(exported)
        ..['unknownFutureKey'] = 'x'
        ..remove('noteLatex');
      SharedPreferences.setMockInitialValues({});
      final prefs2 = await SharedPreferences.getInstance();
      await SettingsRepository(prefs2).importAll(round);
      final s = SettingsRepository(prefs2).load();
      expect(s.themeId, 'aurora');
      expect(s.weatherCity, '上海');
      expect(s.trashKeepDays, 30);
      // 缺键走 defaults（noteLatex 缺席 → 默认 false）。
      expect(s.noteLatex, isFalse);
    });
  });

  group('批2 · 预估测量器（6120 装机回知·预估37MB实包2.5MB）', () {
    test('measureIncludedDbBytes＝快照 DROP 恒排除表后压缩实测', () async {
      final db = await openSchemaDb();
      // 可再生腿：xray_mention 塞 2MB 级真随机文本（真机口径＝占库 97.3%）。
      // 必须不可压缩——周期性/重复串会被 gzip 打到近零，剔除断言失效（变异刀实证）。
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final rng = Random(20261013);
      String rnd(int len) =>
          List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();
      for (var i = 0; i < 1000; i++) {
        await db.insert(DbSchema.tXrayMention, {
          'entity_id': 1,
          'book_md5': 'm$i',
          'ch': i,
          'para': i,
          'snippet': rnd(2000),
        });
      }
      // 在包腿：书架 200 行随机标题（≈100KB 文本）。
      for (var i = 0; i < 200; i++) {
        await db.insert(DbSchema.tBooks, {
          'id': 'b$i',
          'title': rnd(500),
          'created_at': 0,
          'updated_at': 0,
        });
      }
      final svc = BackupService(
          exportDir: () => p.join(temp.path, 'est_out'),
          db: () async => db);
      final measured = await svc.measureIncludedDbBytes(db);
      // 2MB 可再生文本不入包：实测落在书架腿量级（若误含 xray 会 ≥1MB）。
      expect(measured, greaterThan(10 * 1000));
      expect(measured, lessThan(500 * 1000));
      // 预估口径排除集与测量器 DROP 集同源（子集比例分母用）。
      expect(svc.estimateExcludedTables(), contains(DbSchema.tXrayMention));
      await db.close();
    });

    test('treeDisplayName：tree URI 解析人话目录名（去卷前缀·容错）', () {
      expect(
          BackupService.treeDisplayName(
              'content://com.android.externalstorage.documents/'
              'tree/primary%3ADownload%2FlifeHarness'),
          'Download/lifeHarness');
      expect(BackupService.treeDisplayName('content://x/tree/home%3Afiles'),
          'files');
      expect(BackupService.treeDisplayName('not-a-uri'), '所选目录');
    });
  });
}

/// 旧口径 v1 包（无 config/notes 成员·structVersion=1）——手工打包同 backup_v166_test。
Future<String> packRawV1(
    {required String outPath, required String dbPath}) async {
  final statDb = await databaseFactoryFfi.openDatabase(dbPath,
      options: OpenDatabaseOptions(singleInstance: false));
  final names = (await statDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"))
      .map((r) => r['name'] as String)
      .toList();
  final tables = <String, dynamic>{};
  for (final t in names) {
    // 校验和必须按 lh_bak 同口径实算（verify 逐表重算双向核对，'-' 会红）。
    final rows = await statDb.rawQuery(
        'SELECT rowid AS _r, * FROM "$t" ORDER BY rowid');
    final plain = rows
        .map((r) => <String, Object?>{
              for (final e in r.entries)
                if (e.key != '_r') e.key: e.value,
            })
        .toList();
    tables[t] = {'rows': plain.length, 'checksum': tableChecksum(plain)};
  }
  await statDb.close();
  final manifest = {
    'dbVersion': DbSchema.version,
    'appVersion': '0.1.0',
    'createdAt': DateTime(2026, 9, 1).toIso8601String(),
    'structVersion': 1,
    'tables': tables,
    'excludedTables': <String>[],
    'encrypted': false,
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
