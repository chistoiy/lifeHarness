import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/media.dart' as md;

/// 影音游批1 · v37→v38 建表闸（解禁批：先证明表与去重索引真能用，再谈屏）。
/// 独立文件：全 app 点火类用例混跑会 isolate 污染。
void main() {
  sqfliteFfiInit();

  late Database db;
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.migrations[37]!) {
      await db.execute(sql);
    }
  });
  tearDown(() => db.close());

  Future<Set<String>> tables() async => (await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
      .map((r) => r['name'] as String)
      .toSet();

  test('版本号 42，37→38 建七表＋39→40 建目标表，八表齐', () async {
    expect(DbSchema.version, 42,
        reason: 'V1.64 批2 本地导入升 42（41→42 段＝note_folders 挂载三列＋notes.src_hash，'
            '纯加列零搬）；批8a 目标屏建 media_goals（39→40 段）与批5 复习三列（38→39 段）不动');
    expect(DbSchema.migrations.containsKey(37), isTrue,
        reason: '缺这段＝老库升级不建影音游表（新装有、老库没有）');
    final t = await tables();
    for (final name in md.mediaTables) {
      expect(t, contains(name), reason: '$name 未随 v38 建出');
    }
    expect(md.mediaTables, hasLength(8), reason: '批8a 起含 media_goals＝八表');
    expect(md.mediaKinds, ['movie', 'series', 'music', 'game']);
    expect(DbSchema.migrations.containsKey(39), isTrue,
        reason: '批8a v39→v40 段在场＝建 media_goals（老库升级通道）');
    expect((DbSchema.migrations[39] ?? const []).join(' '), contains(md.tMediaGoals),
        reason: '39→40 段必须真建目标表，不是空段');
  });

  test('条目 id 是 TEXT 主键；重复插入不静默吞（导入去重第一道）', () async {
    Future<void> put(String id, {String kind = 'movie', String state = '未看'}) =>
        db.insert(md.tMediaItems, {
          'id': id,
          'kind': kind,
          'title': '测试条目',
          'state': state,
          'progress_way': 'pct',
          'created_at': 1,
          'updated_at': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await put('m1');
    await put('m1');
    expect(await db.query(md.tMediaItems), hasLength(1));
    final row = (await db.query(md.tMediaItems)).single;
    expect(row['creator'], '未知', reason: '创作者缺省＝未知，不留空串');
    expect(row['deleted_at'], isNull);
  });

  test('外部 id 部分唯一索引：同 imdb_id 第二条被拒，不同源互不干扰，空值不参与约束', () async {
    Future<void> ext(String id, String ids) => db.insert(md.tMediaItems, {
          'id': id,
          'kind': 'movie',
          'title': id,
          'state': '未看',
          'progress_way': 'pct',
          'external_ids': ids,
          'created_at': 1,
          'updated_at': 1,
        });
    await ext('a', '{"imdb_id":"tt0111161","douban_id":"1292052"}');
    // 同一 IMDb 号换条记录再插＝必须撞唯一索引（三级去重第一级生效）
    await expectLater(ext('b', '{"imdb_id":"tt0111161"}'), throwsA(anything));
    // 只有豆瓣号的另一条（换了号）：不撞
    await ext('c', '{"douban_id":"29747581"}');
    // 无 external_ids / 空对象：两条都要能并存（NULL 不参与唯一约束）
    await ext('d', '{}');
    await ext('e', '{}');
    expect(await db.query(md.tMediaItems), hasLength(4));
  });

  test('笔记 dedup_hash 唯一（同一时间点同一句话不双落），无 hash 的手写笔记不受限', () async {
    Future<void> note(int? hash) => db.insert(md.tMediaNotes, {
          'item_id': 'a',
          'kind': 'movie',
          'note_type': 'line',
          'body': '发得正来',
          'created_at': 1,
          'updated_at': 1,
          'dedup_hash': hash == null ? null : 'h$hash',
        });
    await note(1);
    await expectLater(note(1), throwsA(anything));
    await note(2);
    await note(null);
    await note(null);
    expect(await db.query(md.tMediaNotes), hasLength(4));
  });

  test('字典 source 预置 14 家且幂等；同 kind 同名撞唯一索引', () async {
    final rows = await db.query(md.tMediaDict, where: "kind='source'");
    expect(rows, hasLength(14));
    // 再跑一遍建表段（IF NOT EXISTS + INSERT OR IGNORE）不该翻倍
    for (final sql in DbSchema.migrations[37]!) {
      await db.execute(sql);
    }
    expect(await db.query(md.tMediaDict, where: "kind='source'"), hasLength(14));
    await expectLater(
        db.insert(md.tMediaDict, {'kind': 'source', 'name': '豆瓣'}),
        throwsA(anything),
        reason: '字典改名走 UPDATE，不靠插重名');
  });

  test('影音单成员表复合主键：同单同条目不双落，换单可再入', () async {
    await db.insert(md.tMediaLists, {'name': '2026 片单', 'created_at': 1});
    final listId = (await db.query(md.tMediaLists)).single['id'] as int;
    Future<void> member(int lid, String item) => db.insert(
        md.tMediaListItems, {'list_id': lid, 'item_id': item, 'pos': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await member(listId, 'a');
    await member(listId, 'a');
    await member(listId, 'b');
    expect(await db.query(md.tMediaListItems), hasLength(2));
  });
}
