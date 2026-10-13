import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_dict.dart';

/// 阅读模块批1 · F1-2 书架生态删除真生效（doc 冻结方案 §2.1 F1-2 · §6.4）。
///
/// 口径：
/// - 删除词典项＝真删 `book_dict` 源行（`dictDelete`），列表/引用计数即时刷新；
/// - 引用守卫：仍有书在用（`dictRefCount > 0`）→ 不可删；
/// - 撤销：`dictAdd(kind, name)` 回填同名项（原型 bmDelCommit toast 撤销口径）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late ReadRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  test('F1-2a dictDelete 真删源行：列表即时少一条', () async {
    await repo.dictAdd(DictEntry.kSource, '得到');
    await repo.dictAdd(DictEntry.kSource, '自购');
    var list = await repo.dictOf(DictEntry.kSource);
    expect(list.map((e) => e.name), containsAll(['得到', '自购']));
    final target = list.firstWhere((e) => e.name == '得到');
    await repo.dictDelete(target);
    list = await repo.dictOf(DictEntry.kSource);
    expect(list.map((e) => e.name), isNot(contains('得到')));
    expect(list.map((e) => e.name), contains('自购'));
  });

  test('F1-2b 引用守卫：被书引用时计数 > 0（删前必查）', () async {
    await repo.dictAdd(DictEntry.kSource, '得到');
    final src = (await repo.dictOf(DictEntry.kSource))
        .firstWhere((e) => e.name == '得到');
    // 无书引用 → 计数 0，可删
    expect(await repo.dictRefCount(src), 0);
    // 加一本来源=得到的书 → 计数 1
    await repo.addBook(Book(
        title: '书', source: '得到', createdAt: 0, updatedAt: 0));
    expect(await repo.dictRefCount(src), 1,
        reason: '有 1 本书在用 → 守卫应拦下删除');
  });

  test('F1-2c 撤销回填：dictAdd 复原同名项（真改源数组）', () async {
    await repo.dictAdd(DictEntry.kTag, '心理学');
    final e = (await repo.dictOf(DictEntry.kTag))
        .firstWhere((x) => x.name == '心理学');
    await repo.dictDelete(e);
    expect((await repo.dictOf(DictEntry.kTag)).map((x) => x.name),
        isNot(contains('心理学')));
    // 撤销＝按 kind+name 回填
    await repo.dictAdd(DictEntry.kTag, '心理学');
    expect((await repo.dictOf(DictEntry.kTag)).map((x) => x.name),
        contains('心理学'));
  });
}
