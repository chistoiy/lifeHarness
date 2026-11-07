/// B-4 数据层验收（工单 §7-7）：ffi 内存库灌多表多行 → scan 计数/分组/
/// 可再生占比正确、空表归并；另验备份包体积读数与 latestBackupSizeBytes。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/db_overview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('DbOverviewScanner.scan', () {
    late Database db;

    Future<void> seed() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE books (id INTEGER PRIMARY KEY)');
      await db.execute('CREATE TABLE xray_mention (id INTEGER PRIMARY KEY)');
      await db.execute('CREATE TABLE xray_task (id INTEGER PRIMARY KEY)');
      await db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY)');
      await db.execute('CREATE TABLE ledger_txns (id INTEGER PRIMARY KEY)');
      // 词表外的运行期兜底路径：schema 没有的表不得炸屏。
      await db.execute('CREATE TABLE foo_bar (id INTEGER PRIMARY KEY)');
      for (var i = 0; i < 3; i++) {
        await db.insert('books', {'id': i});
      }
      for (var i = 0; i < 5; i++) {
        await db.insert('xray_mention', {'id': i});
      }
      for (var i = 0; i < 2; i++) {
        await db.insert('xray_task', {'id': i});
      }
      for (var i = 0; i < 4; i++) {
        await db.insert('notes', {'id': i});
      }
      await db.insert('foo_bar', {'id': 0});
      // ledger_txns 留空 → 空表归并面。
    }

      setUp(seed);
      tearDown(() => db.close());

    test('总行数/可再生行数与占比按实表计', () async {
      final o = await DbOverviewScanner(db: db).scan();
      expect(o.totalRows, 15);
      expect(o.regenerableRows, 7); // xray_mention 5 + xray_task 2
      expect(o.regenerableRatio, closeTo(7 / 15, 1e-9));
    });

    test('逐表行按行数降序、人话标签取词表、词表外表兜底归「其他」', () async {
      final o = await DbOverviewScanner(db: db).scan();
      expect(o.rows.map((r) => r.table).toList(),
          ['xray_mention', 'notes', 'books', 'xray_task', 'foo_bar']);
      final books = o.rows.firstWhere((r) => r.table == 'books');
      expect(books.label, '书籍在册');
      expect(books.module, '阅读');
      final unknown = o.rows.firstWhere((r) => r.table == 'foo_bar');
      expect(unknown.label, 'foo_bar');
      expect(unknown.module, '其他');
    });

    test('空表不逐条展示，并入 emptyTableCount', () async {
      final o = await DbOverviewScanner(db: db).scan();
      expect(o.rows.any((r) => r.table == 'ledger_txns'), isFalse);
      expect(o.emptyTableCount, 1);
    });

    test('按模块聚合：行数合计 + 非空表数，降序', () async {
      final o = await DbOverviewScanner(db: db).scan();
      expect(o.byModule.map((m) => (m.module, m.rows, m.tables)).toList(), [
        ('阅读', 10, 3),
        ('笔记', 4, 1),
        ('其他', 1, 1),
      ]);
    });
  });

  group('buildOverview 纯函数边界', () {
    test('空库：totalRows=0 且占比 0（不除零）', () {
      final o = buildOverview(const {});
      expect(o.totalRows, 0);
      expect(o.regenerableRatio, 0);
      expect(o.rows, isEmpty);
      expect(o.byModule, isEmpty);
    });
  });

  group('latestBackupSizeBytes', () {
    test('目录不存在 → null（UI 隐藏该格，不编造）', () async {
      expect(
          await latestBackupSizeBytes('${Directory.systemTemp.path}/lh-no-such-dir-b4'),
          isNull);
    });

    test('只认 .lhbak，取 mtime 最新一份的大小', () async {
      final dir = await Directory.systemTemp.createTemp('lh-b4-bak');
      try {
        final older = File('${dir.path}/a_old.lhbak');
        await older.writeAsBytes(List.filled(11, 0));
        await older.setLastModified(DateTime(2020));
        final newer = File('${dir.path}/b_new.lhbak');
        await newer.writeAsBytes(List.filled(222, 0));
        // 干扰项：非备份扩展名与更大但更旧的包都不许选中。
        final noise = File('${dir.path}/c.zip');
        await noise.writeAsBytes(List.filled(9999, 0));
        expect(await latestBackupSizeBytes(dir.path), 222);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
