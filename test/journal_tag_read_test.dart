import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/data/tag_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/domain/tag.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 批2b · 日记读路径的标签真源（`tag_links`）与快照回落（`journal_entries.tags`）。
///
/// 这两条是同一枚硬币的两面，缺一条就会出「列表有标签、回收站没有」或
/// 「删掉的标签在冷启动后又回来了」这类偏。
void main() {
  sqfliteFfiInit();

  late Database db;
  late TagDao tagDao;
  late JournalDao jdao;
  late JournalRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    tagDao = TagDao(db);
    jdao = JournalDao(db);
    repo = JournalRepository(jdao);
  });

  tearDown(() async => db.close());

  Future<int> rawInsert(String content, String? tagsJson) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert(DbSchema.tJournal, {
      'entry_date': DateTime(2026, 10, 19).millisecondsSinceEpoch,
      'content': content,
      'tags': tagsJson,
      'created_at': now,
      'updated_at': now,
    });
  }

  test('R1 关联表优先于行内快照（改池名后读到的就是新名）', () async {
    final id = await rawInsert('正文', jsonEncode(['旧名']));
    await tagDao.setItemTags('diary', id, ['旧名']);
    // 直接改池行名（模拟改名路径已写库后的状态）
    await tagDao.rename((await tagDao.list()).single.id, '新名');
    final e = await jdao.byId(id);
    expect(e!.tags, ['新名']);
    // 行内快照也被 resync 重写（回落源不会残留旧名）
    final row = (await db.query(DbSchema.tJournal, columns: ['tags'], where: 'id = ?', whereArgs: [id])).single;
    expect(row['tags'] as String, contains('新名'));
  });

  test('R2 关联表无该篇行时回落行内快照（老库尚未 seed）', () async {
    final id = await rawInsert('正文', jsonEncode(['生活', '复盘']));
    final e = await jdao.byId(id);
    expect(e!.tags, ['生活', '复盘'], reason: '关联为空＝还没导入，不能把老标签读没');
  });

  test('R3 保存双写：关联表 + 快照；显式标签与正文 #词合并去重', () async {
    final e = await repo.save(JournalEntry(
      day: DateTime(2026, 10, 19),
      content: '#复盘 今天复盘了 #生活',
      tags: const ['复盘', '晨跑'],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    expect(e.tags, containsAll(['复盘', '晨跑', '生活']));
    expect(await tagDao.namesOf('diary', e.id!), containsAll(['复盘', '晨跑', '生活']));
    final row = (await db.query(DbSchema.tJournal,
            columns: ['tags'], where: 'id = ?', whereArgs: [e.id]))
        .single;
    expect(jsonDecode(row['tags'] as String), containsAll(['复盘', '晨跑', '生活']));

    // 再保存一次只留「复盘」：另外两枚从关联表消失（显式移除＝真删）
    final e2 = await repo.save(e.copyWith(content: '#复盘 只留一个', tags: const ['复盘']));
    expect(e2.tags, ['复盘']);
    expect(await tagDao.namesOf('diary', e.id!), ['复盘']);
  });

  test('R4 软删保留关联（回收站恢复后标签跟着回来），彻底删除才清', () async {
    final e = await repo.save(JournalEntry(
      day: DateTime(2026, 10, 19),
      content: '带标签的篇',
      tags: const ['生活'],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await repo.remove(e.id!);
    expect(await tagDao.namesOf('diary', e.id!), ['生活'], reason: '软删不清关联');
    await repo.restoreJournal(e.id!);
    expect((await jdao.byId(e.id!))!.tags, ['生活']);
    await repo.purgeJournal(e.id!);
    expect(await tagDao.namesOf('diary', e.id!), isEmpty);
  });

  test('R5 列表/区间/搜索三条读路径都带标签（不只 list）', () async {
    final e = await repo.save(JournalEntry(
      day: DateTime(2026, 10, 19),
      content: '关键词 甲乙丙',
      tags: const ['晨间页'],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    expect((await jdao.list()).single.tags, ['晨间页']);
    expect((await jdao.range(DateTime(2026, 10, 1), DateTime(2026, 11, 1))).single.tags,
        ['晨间页']);
    expect((await jdao.search('甲乙丙')).single.tags, ['晨间页']);
    expect((await jdao.listByDay(e.day)).single.tags, ['晨间页']);
  });

  test('R6 标签表随建库就位（v50 DDL 与迁移同源）', () async {
    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN (?, ?)",
            [DbSchema.tTags, DbSchema.tTagLinks]))
        .map((r) => r['name'] as String)
        .toSet();
    expect(tables, {DbSchema.tTags, DbSchema.tTagLinks});
    expect(DbSchema.version, 50);
    expect(kTagScopes, ['diary', 'note', 'time']);
  });
}
