import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';

/// 阅读模块批1 · F1-4 编辑保存后重算与刷新（doc 冻结方案 §2.1 F1-4 · §6.4）。
///
/// 口径：`Book.percent` 是**派生 getter**（读 pages/readPages 现算），
/// 结构上不可能与落库值不同步——本用例钉住「改页数/已读页后同帧一致」。
void main() {
  sqfliteFfiInit();

  late Database db;
  late ReadRepository repo;
  final now = DateTime(2026, 10, 14).millisecondsSinceEpoch;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  test('F1-4a 改总页数 → percent 同帧重算', () async {
    final b = await repo.addBook(Book(
        title: '书', pages: 100, readPages: 50, createdAt: now, updatedAt: now));
    expect(b.percent, 50);
    await repo.updateBook(b.copyWith(pages: 200));
    final r = await repo.bookById(b.id);
    expect(r!.percent, 25, reason: '50/200 = 25%，派生 getter 即刻一致');
  });

  test('F1-4b 改已读页 → percent 上升且不超 100', () async {
    final b = await repo.addBook(Book(
        title: '书', pages: 100, readPages: 10, createdAt: now, updatedAt: now));
    await repo.updateBook(b.copyWith(readPages: 100));
    expect((await repo.bookById(b.id))!.percent, 100);
    await repo.updateBook(b.copyWith(readPages: 130)); // 越界夹取
    expect((await repo.bookById(b.id))!.percent, 100);
  });

  test('F1-4c 详情节/书架行读同一行：percent 单源不分叉', () async {
    final b = await repo.addBook(Book(
        title: '书', pages: 320, readPages: 80, createdAt: now, updatedAt: now));
    // 书架取数（allBooks）与详情取数（bookById）同源同一行
    final shelf = (await repo.allBooks()).firstWhere((x) => x.id == b.id);
    final detail = await repo.bookById(b.id);
    expect(shelf.percent, detail!.percent);
    expect(shelf.percent, 25);
  });
}
