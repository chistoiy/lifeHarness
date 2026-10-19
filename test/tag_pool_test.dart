import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/data/tag_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/domain/tag.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 批2b 标签池（`tags` / `tag_links`）· DAO 层常驻守护。
///
/// 钉的是工单 §4g 的四条产品口径与五条拍板：
/// ① 池全局唯一（只有一个写口）② scopes 多值、新建默认三勾 ③ 按模块过滤
/// ④ 搜索/改名/合并/删除；拍板①合并取并集、②改名连带、③删除不进回收站、
/// ④计数按全仓引用总数、⑤搜索归管理页。
void main() {
  sqfliteFfiInit();

  late Database db;
  late TagDao dao;
  late JournalRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TagDao(db);
    repo = JournalRepository(JournalDao(db));
  });

  tearDown(() async => db.close());

  Future<JournalEntry> newEntry(String content, {List<String> tags = const []}) =>
      repo.save(JournalEntry(
        day: DateTime(2026, 10, 19),
        content: content,
        tags: tags,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

  group('T1 新建（口径②：默认三模块全勾）', () {
    test('不传 scopes = diary,note,time 全含；isPublic 派生为真', () async {
      final r = await dao.create('复盘');
      expect(r.ok, isTrue);
      final t = (await dao.list()).single;
      expect(t.scopes, {'diary', 'note', 'time'});
      expect(t.isPublic, isTrue);
    });

    test('显式传 scopes 只留合法值；空名/超长/重名都给可读拒绝', () async {
      final r1 = await dao.create('  #加班  ', scopes: {'diary', 'bad'});
      expect(r1.ok, isTrue);
      final t = (await dao.list()).single;
      expect(t.name, '加班', reason: '前导 # 与空白要剥掉，池内名字一律不带 #');
      expect(t.scopes, {'diary'});
      expect(t.isPublic, isFalse);

      expect((await dao.create('')).ok, isFalse);
      expect((await dao.create('一二三四五六七八九十一二三')).ok, isFalse,
          reason: '上限 12 字（原型 maxlength）');
      final dup = await dao.create('加班');
      expect(dup.ok, isFalse);
      expect(dup.msg, contains('已存在'), reason: '重名必须给理由，不能静默失败');
      expect(await dao.list(), hasLength(1));
    });
  });

  group('T2 计数 = 全仓引用总数（拍板④）', () {
    test('日记 + 笔记 + 时间三模块引用相加，不按模块各算一份', () async {
      final t = (await dao.create('重要')).tag!;
      await dao.setItemTags('diary', 1, ['重要']);
      await dao.setItemTags('note', 7, ['重要']);
      await dao.setItemTags('time', 9, ['重要']);
      final row = (await dao.list()).single;
      expect(row.useCount, 3);
      expect(t.useCount, 0, reason: 'create 返回的是新建时的快照，不参与计数断言');
    });

    test('同一模块内多条内容各自计一条；删关联即减', () async {
      await dao.create('生活');
      await dao.setItemTags('diary', 1, ['生活']);
      await dao.setItemTags('diary', 2, ['生活']);
      expect((await dao.list()).single.useCount, 2);
      await dao.removeItem('diary', 1);
      expect((await dao.list()).single.useCount, 1);
    });
  });

  group('T3 合并（拍板①：关联搬移 + scopes 取并集）', () {
    test('源引用并入目标、源消失、模块并集；同篇双挂不撞主键', () async {
      final a = (await dao.create('晨跑', scopes: {'diary'})).tag!;
      final b = (await dao.create('运动', scopes: {'note'})).tag!;
      await dao.setItemTags('diary', 1, ['晨跑']);
      await dao.setItemTags('diary', 2, ['晨跑']);
      await dao.setItemTags('diary', 1, ['晨跑', '运动']); // 1 号篇同时挂两个

      final r = await dao.merge(a.id, b.id);
      expect(r.ok, isTrue);
      final pool = await dao.list();
      expect(pool.map((t) => t.name), ['运动']);
      final target = pool.single;
      expect(target.scopes, {'diary', 'note'},
          reason: '并集：取交集会让合并后日记里选不到该标签');
      expect(target.useCount, 2, reason: '1 号篇双挂只算一条（主键去重）');
      expect(await dao.namesOf('diary', 2), ['运动']);
    });
  });

  group('T4 删除（拍板③：解绑不删内容、不进回收站）', () {
    test('三模块解绑、篇目仍在、行内快照同步清空（不会复活）', () async {
      await dao.create('加班');
      final e = await newEntry('#加班 写周报');
      expect(e.tags, ['加班']);
      final t = (await dao.list()).single;

      await dao.deleteTag(t.id);
      expect(await dao.list(), isEmpty);
      final re = await repo.open(e.id!);
      expect(re, isNotNull, reason: '内容本身不删');
      expect(re!.tags, isEmpty, reason: '快照必须同步，否则 seed 会把删掉的标签复活');
      expect(await dao.seedFromJournalTags(), 0, reason: '删光后 seed 不得重新导入');
      expect(await dao.list(), isEmpty);
    });
  });

  group('T5 改名（拍板②：所有引用一起改）', () {
    test('只改池行名；关联按 id 不变，读回即是新名；快照同步', () async {
      await dao.create('复盘');
      final e = await newEntry('#复盘 今天复盘了');
      final t = (await dao.list()).single;
      final r = await dao.rename(t.id, '#日复盘');
      expect(r.ok, isTrue);
      expect((await dao.list()).single.name, '日复盘');
      expect(await dao.namesOf('diary', e.id!), ['日复盘']);
      expect((await repo.open(e.id!))!.tags, ['日复盘']);
      // 撞名拒绝
      await dao.create('另一个');
      final dup = await dao.rename(t.id, '另一个');
      expect(dup.ok, isFalse);
    });
  });

  group('T6 历史标签懒导入（seed）', () {
    test('老库快照 → 池 + 关联；幂等；快照为空不跑', () async {
      // 模拟 v49 老库：行里有 JSON 快照，关联表为空
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await db.insert(DbSchema.tJournal, {
        'entry_date': DateTime(2026, 10, 1).millisecondsSinceEpoch,
        'content': '正文',
        'tags': '["生活","复盘","生活"]',
        'created_at': now,
        'updated_at': now,
      });
      final n = await dao.seedFromJournalTags();
      expect(n, 2, reason: '同名去重（同名只建一条关联）');
      expect((await dao.list()).map((t) => t.name), ['生活', '复盘']);
      expect(await dao.namesOf('diary', id), ['生活', '复盘']);
      expect(await dao.seedFromJournalTags(), 0, reason: '关联表非空即不再跑');
      expect((await dao.list()), hasLength(2));
    });
  });

  group('T7 按模块过滤（口径③）', () {
    test('只属笔记的标签不出现在日记侧', () async {
      await dao.create('读书笔记', scopes: {'note'});
      await dao.create('晨间页', scopes: {'diary'});
      expect((await dao.listFor('diary')).map((t) => t.name), ['晨间页']);
      expect((await dao.listFor('note')).map((t) => t.name), ['读书笔记']);
      expect(await dao.listFor('time'), isEmpty);
    });
  });

  group('T8 跨模块搜索（拍板⑤：归管理页）', () {
    test('命中标签 + 日记正文 + 笔记标题；忽略作用域', () async {
      await dao.create('电影', scopes: {'note'});
      await newEntry('今天看了一部好电影');
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(DbSchema.tNotes, {
        'title': '电影清单',
        'content': '片单正文',
        'created_at': now,
        'updated_at': now,
      });

      final r = await dao.search('电影');
      expect(r.tags.map((t) => t.name), ['电影'],
          reason: '标签命中忽略作用域（只属笔记也要搜到）');
      expect(r.rows.map((x) => x.module), containsAll(['diary', 'note']));
      expect((await dao.search('')).rows, isEmpty);
    });
  });
}
