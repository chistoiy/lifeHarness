/// C05 收尾接线守护：可读目录扩到 物品/目标/习惯/阅读/影音游/时间。
///
/// 断言「真落盘」而非只看函数返回：CSV 表头含 v53 追加列、FORMAT.md 有
/// schema 版本与逐表字段、未选模块零文件；第二条同例验「时间谓词同源」
/// （范围内行在、范围外行不在）＝正负两档都断。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/shared/linkage/backup_read_export.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('lh_c05_wire_');
  });
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('物品/时间出 CSV；FORMAT.md 有版本与逐表字段；未选模块零文件', () async {
    final db = await openSchemaDb();
    await db.insert(DbSchema.tItemProfiles, {
      'name': '相机,备用',
      'buy_date': '2026-01-01',
      'price': 1999.0,
      'photos': jsonEncode(<String>['/x/note_images/p1.jpg']),
      'attachments': jsonEncode(<Map<String, Object?>>[
        {'kind': '发票', 'path': '/x/note_images/inv.pdf', 'name': null},
      ]),
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert(DbSchema.tTimeBlocks, {
      'day': DateTime(2026, 3, 1).millisecondsSinceEpoch,
      'start_min': 540,
      'end_min': 600,
      'created_at': 0,
      'updated_at': 0,
    });

    final outDir = p.join(temp.path, 'c05');
    final rep = await exportReadableTree(
      db: db,
      outDir: outDir,
      moduleIds: const <String>{'items', 'time'},
      assets: false,
      md: false,
      settingsMap: null,
      now: DateTime(2026, 11, 9, 12),
    );
    expect(rep.error, '');

    final csv = File(p.join(outDir, 'data', 'items', 'item_profiles.csv'));
    expect(csv.existsSync(), isTrue, reason: '正档：物品档案出 CSV');
    final text = csv.readAsStringSync();
    final header = text.split('\n').first;
    expect(header, contains('photos'), reason: '正档：表头含 v53 多图列');
    expect(header, contains('attachments'), reason: '正档：表头含 v53 凭证列');
    expect(text, contains('"相机,备用"'), reason: '正档：逗号值 CSV 转义');
    expect(File(p.join(outDir, 'data', 'items', 'items.csv')).existsSync(), isTrue,
        reason: '正档：模块内其余表同样出 CSV（空表也出表头）');

    final timeCsv = File(p.join(outDir, 'data', 'time', 'time_blocks.csv'));
    expect(timeCsv.existsSync(), isTrue, reason: '正档：时间块出 CSV');
    expect(timeCsv.readAsStringSync(), contains('540'),
        reason: '正档：时间块行已投影');

    final fmt = File(p.join(outDir, 'FORMAT.md'));
    expect(fmt.existsSync(), isTrue, reason: '正档：格式说明落盘');
    final md = fmt.readAsStringSync();
    expect(md, contains('${DbSchema.version}'), reason: '正档：DB schema 版本');
    expect(md, contains('**物品**（`items`）'),
        reason: '正档：逐模块投影含物品');
    expect(md, contains('**时间**（`time`）'),
        reason: '正档：逐模块投影含时间');
    expect(md, contains('photos'), reason: '正档：逐表字段含 v53 列');

    expect(Directory(p.join(outDir, 'data', 'goals')).existsSync(), isFalse,
        reason: '负档：未选目标不产目标文件');
    expect(Directory(p.join(outDir, 'data', 'habit')).existsSync(), isFalse,
        reason: '负档：未选习惯不产习惯文件');
    await db.close();
  });

  test('时间谓词同源：范围内行在、范围外行不在（CSV 同例正负都断）', () async {
    final db = await openSchemaDb();
    await db.insert(DbSchema.tItemUsages, {
      'item_id': 1,
      'day': '2026-05-01',
      'qty': 2,
      'created_at': 0,
    });
    await db.insert(DbSchema.tItemUsages, {
      'item_id': 1,
      'day': '2025-05-01',
      'qty': 1,
      'created_at': 0,
    });
    final outDir = p.join(temp.path, 'range');
    final rep = await exportReadableTree(
      db: db,
      outDir: outDir,
      moduleIds: const <String>{'items'},
      assets: false,
      md: false,
      settingsMap: null,
      now: DateTime(2026, 11, 9, 12),
      timeRange: (from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31)),
    );
    expect(rep.error, '');
    final csv =
        File(p.join(outDir, 'data', 'items', 'item_usages.csv')).readAsStringSync();
    expect(csv, contains('2026-05-01'),
        reason: '正档：范围内使用记录在 CSV 里');
    expect(csv, isNot(contains('2025-05-01')),
        reason: '负档：范围外记录被同一谓词筛掉');
    final md = File(p.join(outDir, 'FORMAT.md')).readAsStringSync();
    expect(md, contains('BETWEEN'), reason: '正档：FORMAT.md 写明同源谓词');
    await db.close();
  });
}
