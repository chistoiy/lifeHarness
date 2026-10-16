import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/shared/linkage/nfc_mounts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// NFC 卡片批1 · 跨模块出口守护（工单 §2 F1-4 · 冻结档 §6.1 守 R1）。
///
/// `features/nfc/**` **禁止 import** `features/calendar/**` 与 `features/read/**`；
/// 目标选择器的分类/书目数据**一律经** `shared/linkage/nfc_mounts.dart`。
/// 反向也禁（守护 R1 的反向条文由 `architecture_test` 覆盖，本文件补语义侧）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('nfc_mounts 读取转发口（批1 两个；两个 toggle 口属批2）', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // 只建本测试要读的两张表：分类（core 域）＋ 书目（read 域）。
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbSchema.tCategories} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          parent_id INTEGER,
          name TEXT NOT NULL,
          color TEXT,
          tag TEXT,
          sort INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbSchema.tBooks} (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          author TEXT NOT NULL DEFAULT '佚名',
          deleted_at INTEGER
        )
      ''');
    });

    tearDown(() async => db.close());

    test('nfcCategoryOptions 返回分类且带父级路径（B23：显示「工作 › 开会」）',
        () async {
      await db.insert(DbSchema.tCategories,
          {'name': '工作', 'sort': 0});
      await db.insert(DbSchema.tCategories,
          {'name': '开会', 'parent_id': 1, 'sort': 0});
      await db.insert(DbSchema.tCategories,
          {'name': '学习', 'sort': 1});

      final cats = await nfcCategoryOptions(db);
      expect(cats.length, 3);
      final primary = cats.firstWhere((c) => c.name == '工作');
      expect(primary.parentId, isNull);
      expect(primary.path, '工作', reason: '一级分类无父级前缀');

      final child = cats.firstWhere((c) => c.name == '开会');
      expect(child.parentId, 1);
      expect(child.path, '工作 › 开会', reason: '多级分类须显父级路径，否则同名分类无法分辨');
    });

    test('同名分类按 id 区分（B23：卡片只存 catId 不存名）', () async {
      await db.insert(DbSchema.tCategories, {'name': '运动', 'sort': 0});
      await db.insert(DbSchema.tCategories, {'name': '运动', 'sort': 1});
      final cats = await nfcCategoryOptions(db);
      final sameName = cats.where((c) => c.name == '运动').toList();
      expect(sameName.length, 2);
      expect(sameName[0].id, isNot(sameName[1].id),
          reason: '同名分类必须靠 id 区分，否则两张卡会绑到同一处');
    });

    test('nfcBookOptions 只返回在册书（B24：移出书架视图但仍在库＝有效）', () async {
      await db.insert(DbSchema.tBooks, {'id': 'bk1', 'title': '活着', 'author': '余华'});
      await db.insert(DbSchema.tBooks,
          {'id': 'bk2', 'title': '已删', 'author': 'x', 'deleted_at': 1700000000000});

      final books = await nfcBookOptions(db);
      expect(books.length, 1);
      expect(books.first.id, 'bk1');
      expect(books.first.title, '活着');
      expect(await nfcBookExists('bk1', db), isTrue);
      expect(await nfcBookExists('bk2', db), isFalse, reason: '真删的书＝目标已失效');
    });

    test('书目标题为空回落「未命名」（不留空白 chip）', () async {
      await db.insert(DbSchema.tBooks, {'id': 'bk3', 'title': '   ', 'author': ''});
      final books = await nfcBookOptions(db);
      expect(books.first.title, '未命名');
    });

    test('分类已删即失效（C24/B9：贴卡时给「已经不在了」而不是崩）', () async {
      await db.insert(DbSchema.tCategories, {'name': '临时', 'sort': 0});
      expect(await nfcCategoryExists(1, db), isTrue);
      await db.delete(DbSchema.tCategories, where: 'id = ?', whereArgs: [1]);
      expect(await nfcCategoryExists(1, db), isFalse);
    });
  });
}