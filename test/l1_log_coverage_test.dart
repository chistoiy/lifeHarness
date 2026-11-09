/// L1 日志批验收钉桩（docs/日志覆盖工单-20260929.md §三·L1）：
/// core/database 与 core/backup 的失败路径必须落日志（只加日志零行为改动批）。
///  - 备份校验失败（坏包）→ error「备份校验失败」，且不触发现库；
///  - 备份解包中途失败 → error「备份解包失败」+ 堆栈行，原库重开冒泡；
///  - 迁移逐级 → key「迁移 vN 开始/完成」与「数据库升级：v旧 → v新」；
///  - 数据库打开失败 → error「数据库打开失败」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/database/app_database.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<String> logTexts() => AppLog.lines.map((l) => l.text).toList();

bool logged(String contains, {bool errorOnly = false}) => AppLog.lines.any(
      (l) =>
          l.text.contains(contains) && (!errorOnly || l.level.name == 'error'),
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;
  late String dbPath;
  late String outDir;
  late List<Database> opened;

  // 与 AppDatabase.open 同一落点：<dir>/lifeharness.db（若各开各的文件，
  // sqflite 会把它当目录并自动建库，导致「迁移用例不触发 onUpgrade」）。
  String appDbFile(String dir) =>
      '$dir${Platform.pathSeparator}${DbSchema.fileName}';

  Future<Database> openAt(String path) =>
      databaseFactoryFfi.openDatabase(
        path,
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

  setUp(() {
    AppLog.reset();
    tmp = Directory.systemTemp.createTempSync('lh_l1log_');
    dbPath = appDbFile(tmp.path);
    outDir = tmp.path;
    opened = [];
  });

  tearDown(() async {
    for (final d in opened) {
      await d.close();
    }
    await AppDatabase.instance.close();
    BackupService.unpackOverride = null;
    AppLog.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('L1 · 备份校验失败（坏包）落 error 日志', () async {
    final svc = BackupService(
      exportDir: () => outDir,
      db: () => openAt(dbPath),
    );
    await openAt(dbPath); // 建好库，保证导出通道可用
    final bad = File('${tmp.path}/bad.lhbak')..writeAsBytesSync([1, 2, 3]);
    await expectLater(svc.importBackup(bad.path), throwsA(anything));
    expect(
      logged('备份校验失败', errorOnly: true),
      isTrue,
      reason: logTexts().join(' | '),
    );
    // 来源归类＝备份（日志页筛选口径）。
    expect(
      AppLog.lines.where((l) => l.text.contains('备份')).every((l) => l.src == '备份'),
      isTrue,
      reason: AppLog.lines.map((l) => l.src).toSet().join(','),
    );
    // 前置失败不触碰现场：不应出现「解包失败」
    expect(logged('备份解包失败'), isFalse);
  });

  test('L1 · 备份解包中途失败落 error 日志并留堆栈', () async {
    final svc = BackupService(
      exportDir: () => outDir,
      db: () => openAt(dbPath),
    );
    final pkg = await svc.exportBackup();
    BackupService.unpackOverride =
        ({required filePath, required targetDb, passphrase}) async =>
            throw StateError('unpack 注入失败');
    await expectLater(
      svc.importBackup(pkg.file.path),
      throwsA(isA<StateError>()),
    );
    expect(
      logged('备份解包失败', errorOnly: true),
      isTrue,
      reason: logTexts().join(' | '),
    );
    // 堆栈行也入缓冲（addStack：error 级、前 14 行以 | 压平）
    expect(
      AppLog.lines.any(
        (l) => l.level.name == 'error' && l.text.contains('#0'),
      ),
      isTrue,
    );
  });

  test('L1 · 迁移前后 key 日志（v1 老库升上来）', () async {
    // 预置 v1 老库（todos 无 tag 列）+ user_version=1 → AppDatabase.open 触发
    // onUpgrade 逐级迁移。老库缺后续 ALTER 目标表，链会在中途炸掉——本例只钉
    // 「升级/迁移开始/迁移完成/失败」是否按序落缓冲（迁移日志与 SQL 成败无关）。
    final raw = await databaseFactoryFfi.openDatabase(dbPath);
    await raw.execute(
      'CREATE TABLE todos (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'title TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0, '
      'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
    );
    await raw.execute('PRAGMA user_version = 1');
    await raw.close();
    AppLog.reset();
    await expectLater(
      AppDatabase.instance.open(pathOverride: tmp.path),
      throwsA(anything),
    );
    final texts = logTexts();
    expect(
      texts.any((t) => t.startsWith('数据库升级：v1 →')),
      isTrue,
      reason: texts.join(' | '),
    );
    expect(texts.any((t) => t.startsWith('迁移 v2 开始：1 条语句')), isTrue);
    expect(texts.any((t) => t.startsWith('迁移 v2 完成')), isTrue);
    // 中途失败同样留痕（open 的 catch 路径）。
    expect(texts.any((t) => t.contains('数据库打开失败')), isTrue);
    // 验收口径：日志页可按「数据库」来源筛出这些真条目（异步回调帧里没有
    // 业务帧，故 database 侧显式带 src）。
    for (final l in AppLog.lines.where(
      (l) => l.text.startsWith('数据库升级：') || l.text.startsWith('迁移 v'),
    )) {
      expect(l.src, '数据库', reason: l.text);
    }
  });

  test('L1 · 数据库打开失败落 error 日志', () async {
    // 先正常建库再毁文件 → 重开必炸（sqflite 报 file is not a database）。
    final d = await openAt(dbPath);
    final v = await d.getVersion();
    await d.close();
    opened.remove(d);
    File(dbPath).writeAsBytesSync(List.filled(64, 0));
    await expectLater(
      AppDatabase.instance.open(pathOverride: tmp.path),
      throwsA(anything),
    );
    expect(
      logged('数据库打开', errorOnly: true),
      isTrue,
      reason: '${logTexts().join(" | ")} · v$v',
    );
  });
}
