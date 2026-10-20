import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_dict.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';

/// 影音游批3续 · 影音资料字典数据面（原型 `m-mgr` 五类实体的写读口径）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late MediaRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<String> add({
    String kind = MediaItem.kMovie,
    required String title,
    String creator = '未知',
    String? publisher,
    String? source,
    String? grp,
    List<String> tags = const [],
  }) async {
    final id = await repo.addItem(
      MediaItem(
      kind: kind,
      title: title,
      state: MediaItem.initialState(kind),
      progressWay: MediaItem.defaultWay(kind),
      creator: creator,
      publisher: publisher,
      source: source,
      grp: grp,
      tags: tags,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    // 与录入弹层同一动作序列：落库后登记名册
    await repo.registerItemNames(
      (await repo.itemById(id))!,
    );
    return id;
  }

  test('新条目保存＝创作者/发行/来源/标签自动进名册，空值与「未知」不进', () async {
    await add(
      title: '沙丘 2',
      creator: '维伦纽瓦',
      publisher: '华纳',
      source: '豆瓣',
      tags: ['科幻', '二刷'],
    );
    for (final (tab, name) in [
      ('creator', '维伦纽瓦'),
      ('pub', '华纳'),
      ('tags', '科幻'),
    ]) {
      final rows = await repo.dictRows(MediaDictRepo.dictKinds[tab]!);
      expect(
        rows.map((r) => r.name),
        contains(name),
        reason: '$tab 名册应自动登记 $name',
      );
    }
    // 「未知」占位主创不进名册（否则管理器全是噪声行）
    await add(title: '无名片');
    expect(
      (await repo.dictRows('creator')).map((r) => r.name),
      isNot(contains('未知')),
    );
  });

  test('ensureDict 幂等＝同一名字登记两次只一条（撞 (kind,name) 唯一索引）', () async {
    final first = await repo.ensureDict('creator', '诺兰');
    final second = await repo.ensureDict('creator', '诺兰');
    expect(first, isTrue);
    expect(second, isFalse);
    final rows = await db.query(md.tMediaDict, where: "kind='creator' AND name='诺兰'");
    expect(rows, hasLength(1));
  });

  test('清单＝名册 ∪ 条目实际值；引用数只数在册（软删不算仍在用）', () async {
    final keep = await add(title: '在用片', creator: '是枝裕和', source: 'IMDb');
    final gone = await add(title: '删掉的片', creator: '是枝裕和');
    await repo.ensureDict('creator', '没被用过的名字');
    await repo.softDelete([gone]);
    final rows = await repo.dictRows('creator');
    final byName = {for (final r in rows) r.name: r.refCount};
    expect(byName['是枝裕和'], 1, reason: '两条同名但一条已软删＝引用数 1');
    expect(byName.keys, contains('没被用过的名字'));
    expect(byName['没被用过的名字'], 0);
    // 名册外的实际值也看得见（source 预置 14 家＋条目实际用的 IMDb）
    expect((await repo.dictRows('source')).map((r) => r.name), contains('IMDb'));
    final ids = await repo.itemIdsOf('creator', '是枝裕和');
    expect(ids, [keep]);
  });

  test('改名联动条目列；目标名已在册＝合并成一条字典行（不炸唯一索引）', () async {
    final a = await add(title: '甲', creator: '王家卫');
    final b = await add(title: '乙', creator: '王家衛');
    await repo.ensureDict('creator', '王家衛'); // 目标名先在册 → 变合并
    final n = await repo.renameDict('creator', '王家卫', '王家衛');
    expect(n, 2, reason: '两条条目都跟到新名字');
    expect((await repo.itemById(a))!.creator, '王家衛');
    expect((await repo.itemById(b))!.creator, '王家衛');
    final rows = await db.query(
      md.tMediaDict,
      where: "kind='creator' AND name='王家衛'",
    );
    expect(rows, hasLength(1), reason: '合并后名册只留一条');
    expect(
      await db.query(md.tMediaDict, where: "kind='creator' AND name='王家卫'"),
      isEmpty,
    );
  });

  test('标签改名＝逗号列逐条重写，撞已有同名标签时去重不重复', () async {
    final x = await add(title: '标签片', tags: ['悬疑', '推理']);
    final y = await add(title: '另一片', tags: ['悬疑']);
    final n = await repo.renameDict('tag', '推理', '悬疑');
    expect(n, 2, reason: '两片都算在用「悬疑」');
    expect((await repo.itemById(x))!.tags, ['悬疑'], reason: '撞名去重，不留下两条同名');
    expect((await repo.itemById(y))!.tags, ['悬疑']);
    expect(repo.refCountOf('tag', '推理'), completion(0));
  });

  test('删除引用守卫＝有在用条目不许删；清空后可删且只摘名册行', () async {
    await repo.ensureDict('group', '周末档');
    final id = await add(title: '被占用', grp: '周末档');
    expect(await repo.deleteDict('group', '周末档'), isFalse, reason: '刀4：摘掉守卫这行即红');
    final rows = await db.query(md.tMediaDict, where: "kind='group'");
    expect(rows.map((r) => r['name']), contains('周末档'), reason: '被拦时名册不许被动过');
    await repo.softDelete([id]);
    expect(await repo.deleteDict('group', '周末档'), isTrue);
    expect(
      await db.query(md.tMediaDict, where: "kind='group' AND name='周末档'"),
      isEmpty,
    );
  });
}
