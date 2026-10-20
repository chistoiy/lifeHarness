import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/category.dart';
import 'package:lifeharness/features/calendar/domain/category_ops.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F1-3/C10/B6（时间模块批1 · 冻结口径）分类拖拽换组与删除连带：
/// ① 次级拖入目标一级组 ⇒ parent_id 更新为该组；
/// ② 拖到列表最顶 ⇒ 换入第一个一级组（**禁** `parentId:null` 表达换组）；
/// ③ `CategoryDao.update` 的显式 `setParent(id)` 落库；
/// ④ 删除分类（B6）后其下时间块归入「其他」。
Category _byName(List<Category> cats, String n) =>
    cats.firstWhere((c) => c.name == n);

void main() {
  sqfliteFfiInit();

  late Database db;
  late CategoryDao dao;
  // 落库后回读的真实 id（insert 剥 id 自增，不可钉死）。
  late int idP1, idP2, idS1;
  late Category p1, p2, s1, s2;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = CategoryDao(db);
    idP1 = await dao.insert(const Category(name: '甲组', sort: 1));
    idP2 = await dao.insert(const Category(name: '乙组', sort: 2));
    idS1 = await dao.insert(Category(name: '开会', parentId: idP1, sort: 1));
    await dao.insert(Category(name: '刷题', parentId: idP2, sort: 1));
    final cats = await dao.list();
    p1 = _byName(cats, '甲组');
    p2 = _byName(cats, '乙组');
    s1 = _byName(cats, '开会');
    s2 = _byName(cats, '刷题');
  });
  tearDown(() async => db.close());

  test('次级拖入目标组 ⇒ 计划把 parent_id 解析为该组（C10）', () {
    // 行序：甲组, 开会, 乙组, 刷题 → 把「开会」(行1) 拖到「乙组」后（行3）。
    final rows = [p1, s1, p2, s2];
    final flags = [false, true, false, true];
    final plan = categoryReorderPlan(rows, flags, 1, 3);
    final moved = plan.where((m) => m.cat.name == '开会').single;
    expect(moved.parentId, idP2); // 换入「乙组」组
    expect(moved.parentId, isNotNull); // 禁 null 表换组
  });

  test('次级拖到最顶 ⇒ 换入第一个一级组（旧 null 语义作废）', () {
    final rows = [p1, s1, p2, s2];
    final flags = [false, true, false, true];
    // 把「开会」(行1) 拖到行0（列表最顶）：上方无一级 ⇒ 第一个一级组「甲组」。
    final plan = categoryReorderPlan(rows, flags, 1, 0);
    final moved = plan.where((m) => m.cat.name == '开会').single;
    expect(moved.parentId, idP1);
  });

  test('setParent 显式落库：parent_id 真实改写（ffi 库直测）', () async {
    await dao.update(s1, setParent: idP2, sort: 1);
    final cats = await dao.list();
    expect(_byName(cats, '开会').parentId, idP2);
  });

  test('reorder 计划全量落库后父组/组内 sort 一致（跨组换组）', () async {
    final rows = [p1, s1, p2, s2];
    final flags = [false, true, false, true];
    for (final m in categoryReorderPlan(rows, flags, 1, 3)) {
      if (m.primary) {
        await dao.update(m.cat, clearParent: true, sort: m.sort);
      } else {
        await dao.update(m.cat, setParent: m.parentId, sort: m.sort);
      }
    }
    final cats = await dao.list();
    expect(_byName(cats, '开会').parentId, idP2);
    // 跨组 sort 序正确：标准 ReorderableListView 语义（向下拖 newIndex-1 后插入），
    // 拖到原索引 3 ⇒ 最终落在乙组与刷题之间 ⇒ 开会(sort1)、刷题(sort2)。
    final subs = cats.where((c) => c.parentId == idP2).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    expect(subs.map((c) => c.name).toList(), ['开会', '刷题']);
  });

  test('B6：删除分类后其下时间块归入「其他」（cat_id 清空、名称归其他）', () async {
    final tbDao = TimeBlockDao(db);
    await tbDao.insert(TimeBlock(
        day: DateTime(2026, 9, 19),
        startMin: 600,
        endMin: 660,
        catId: idS1,
        catName: '开会'));
    // 历史行：只有名称没有 cat_id。
    await tbDao.insert(TimeBlock(
        day: DateTime(2026, 9, 19), startMin: 700, endMin: 720, catName: '开会'));
    final n = await tbDao.reassignToOther(catIds: [idS1], catNames: ['开会']);
    expect(n, 2);
    final rows = await tbDao.listByDay(DateTime(2026, 9, 19));
    for (final r in rows) {
      expect(r.catId, isNull);
      expect(r.catName, kCatOther);
    }
  });

  test('B6：删一级连带次级一起归「其他」（ids+names 双条件命中）', () async {
    final tbDao = TimeBlockDao(db);
    await tbDao.insert(TimeBlock(
        day: DateTime(2026, 9, 19),
        startMin: 600,
        endMin: 660,
        catId: idS1,
        catName: '开会'));
    final n = await tbDao.reassignToOther(
        catIds: [idP1, idS1], catNames: ['甲组', '开会']);
    expect(n, 1);
    expect((await tbDao.listByDay(DateTime(2026, 9, 19))).single.catName,
        kCatOther);
  });
}
