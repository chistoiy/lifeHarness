import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/category.dart';

/// 分类数据访问（V1.19.1 · 两级树 · 拖拽换父组/排序写回）。
class CategoryDao {
  const CategoryDao(this.db);
  final Database db;

  Future<List<Category>> list() async {
    final rows = await db.query(DbSchema.tCategories, orderBy: 'parent_id IS NOT NULL, sort ASC, id ASC');
    return rows.map(Category.fromRow).toList();
  }

  Future<int> insert(Category c) => db.insert(DbSchema.tCategories, c.toRow()..remove('id'));

  /// 编辑保存。C10（时间模块批1 · 冻结口径）：**换组一律走显式 `setParent(id)`**
  /// ——禁用「传 null 当换组」：`parentId==null` 在旧实现里对 `parent_id` 不写库，
  /// 「拖到最顶换组」因此静默失效（P0-3）。`clearParent` 仅用于一级行归位。
  Future<int> update(Category c,
          {int? parentId, bool clearParent = false, int? sort, int? setParent}) =>
      db.update(
          DbSchema.tCategories,
          {
            ...c.toRow(),
            if (clearParent) 'parent_id': null,
            if (setParent != null)
              'parent_id': setParent
            else if (!clearParent && parentId != null) 'parent_id': parentId,
            'sort': ?sort,
          },
          where: 'id = ?',
          whereArgs: [c.id]);

  /// 删除一级分类时其次级一并删除（原型行为：组随成员走）。
  Future<int> deleteWithChildren(Category c) => c.isPrimary
      ? db.delete(DbSchema.tCategories,
          where: 'id = ? OR parent_id = ?', whereArgs: [c.id, c.id])
      : db.delete(DbSchema.tCategories, where: 'id = ?', whereArgs: [c.id]);
}
