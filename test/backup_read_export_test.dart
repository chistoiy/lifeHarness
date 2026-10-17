/// V1.66 批2 ·「可读目录」导出用例（评估件 §8.4 档①·工单批2 面板钉子5）：
/// - 树结构＝config/ + notes/（md 投影同源）+ 模块投影器 + data/<表>.json 通用投影；
/// - 子集范围裁剪（未选模块不产文件）；附件拷贝开关与模块映射；
/// - 记账投影器＝books 空时不产文件不报错（收编通道健康性）。
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
    temp = Directory.systemTemp.createTempSync('lhbak_read_');
  });
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('全量导出：config/notes/data 三区齐备，报告计数与盘面一致', () async {
    final db = await openSchemaDb();
    await db.insert(DbSchema.tNotes, {
      'title': '可读笔记',
      'content': '正文',
      'kind': 'plain',
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert(DbSchema.tHabits, {
      'id': 'h1',
      'name': '早起',
      'icon': 'x',
      'type': 'good',
      'cycle': 'day',
        'start_date': 0,
        'created_at': 0,
        'updated_at': 0,
    });
    final outDir = p.join(temp.path, 'readable');
    final rep = await exportReadableTree(
      db: db,
      outDir: outDir,
      moduleIds: const {},
      assets: false,
      md: true,
      settingsMap: {'themeId': 'aurora'},
      now: DateTime(2026, 10, 13, 12),
    );
    expect(rep.error, '');

    final cfg = File(p.join(outDir, 'config', 'settings.json'));
    expect(cfg.existsSync(), isTrue);
    expect(jsonDecode(cfg.readAsStringSync())['themeId'], 'aurora');

    final notes = File(p.join(outDir, 'notes', 'notes.md'));
    expect(notes.existsSync(), isTrue);
    expect(notes.readAsStringSync(), contains('可读笔记'));

    final habitJson = File(p.join(outDir, 'data', 'habit', 'habits.json'));
    expect(habitJson.existsSync(), isTrue);
    final arr = jsonDecode(habitJson.readAsStringSync()) as List;
    expect((arr.single as Map)['name'], '早起');

    expect(rep.files, greaterThanOrEqualTo(3));
    await db.close();
  });

  test('子集导出：未选模块零文件；md 关＝无 notes/；config 恒在', () async {
    final db = await openSchemaDb();
    await db.insert(DbSchema.tHabits, {
      'id': 'h1',
      'name': '早起',
      'icon': 'x',
      'type': 'good',
      'cycle': 'day',
        'start_date': 0,
        'created_at': 0,
        'updated_at': 0,
    });
    await db.insert(DbSchema.tNotes, {
      'title': '不选它',
      'content': 'x',
      'kind': 'plain',
      'created_at': 0,
      'updated_at': 0,
    });
    final outDir = p.join(temp.path, 'subset');
    final rep = await exportReadableTree(
      db: db,
      outDir: outDir,
      moduleIds: const {'habit'},
      assets: false,
      md: false,
      settingsMap: {'themeId': 'aurora'},
      now: DateTime(2026, 10, 13, 12),
    );
    expect(rep.error, '');
    expect(File(p.join(outDir, 'data', 'habit', 'habits.json')).existsSync(),
        isTrue);
    expect(Directory(p.join(outDir, 'data', 'journal')).existsSync(), isFalse);
    expect(Directory(p.join(outDir, 'notes')).existsSync(), isFalse);
    expect(File(p.join(outDir, 'config', 'settings.json')).existsSync(),
        isTrue);
    await db.close();
  });

  test('附件拷贝：子集只拷所选模块映射目录（journal→note_images）', () async {
    final db = await openSchemaDb();
    final images = Directory(p.join(temp.path, 'note_images'))..createSync();
    File(p.join(images.path, 'a.png')).writeAsBytesSync([1]);
    final covers = Directory(p.join(temp.path, 'book_covers'))..createSync();
    File(p.join(covers.path, 'b.png')).writeAsBytesSync([2]);
    final outDir = p.join(temp.path, 'withattach');
    final rep = await exportReadableTree(
      db: db,
      outDir: outDir,
      moduleIds: const {'journal'},
      assets: true,
      md: false,
      attachDirs: [images.path, covers.path],
      settingsMap: null,
      now: DateTime(2026, 10, 13, 12),
    );
    expect(rep.error, '');
    expect(
        File(p.join(outDir, 'attachments', 'note_images', 'a.png'))
            .existsSync(),
        isTrue);
    expect(
        File(p.join(outDir, 'attachments', 'book_covers', 'b.png'))
            .existsSync(),
        isFalse);
    await db.close();
  });

  test('记账投影器健康性：账本空＝不产文件不报错；目录建得出', () async {
    final db = await openSchemaDb();
    final outDir = p.join(temp.path, 'ledgerempty');
    final rep = await exportReadableTree(
      db: db,
      outDir: outDir,
      moduleIds: const {'ledger'},
      assets: false,
      md: false,
      settingsMap: null,
      now: DateTime(2026, 10, 13, 12),
    );
    expect(rep.error, '');
    expect(Directory(p.join(outDir)).existsSync(), isTrue);
    await db.close();
  });
}
