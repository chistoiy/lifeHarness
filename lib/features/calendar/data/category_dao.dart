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

  Future<int> update(Category c, {int? parentId, bool clearParent = false, int? sort}) =>
      db.update(
          DbSchema.tCategories,
          {
            ...c.toRow(),
            if (clearParent) 'parent_id': null,
            if (!clearParent && parentId != null) 'parent_id': parentId,
            'sort': ?sort,
          },
          where: 'id = ?',
          whereArgs: [c.id]);

  /// 删除一级分类时其次级一并删除（原型行为：组随成员走）。
  Future<int> deleteWithChildren(Category c) => c.isPrimary
      ? db.delete(DbSchema.tCategories,
          where: 'id = ? OR parent_id = ?', whereArgs: [c.id, c.id])
      : db.delete(DbSchema.tCategories, where: 'id = ?', whereArgs: [c.id]);

  /// 次级换父组（长按拖入其他父级）。
  Future<void> reparent(int categoryId, int newParentId, int sort) => db.update(
      DbSchema.tCategories, {'parent_id': newParentId, 'sort': sort},
      where: 'id = ?', whereArgs: [categoryId]);

  /// 一级重排（拖拽排序写回）。
  Future<void> reorderPrimary(List<int> ids) async {
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update(DbSchema.tCategories, {'sort': i + 1}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit();
  }
}
