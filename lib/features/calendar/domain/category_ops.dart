import 'category.dart';

/// C10（时间模块批1 · 冻结口径）分类拖拽重排的**纯解析层**（无 DB/Widget 依赖）。
///
/// 硬约束：**次级必属某一级组**——
/// · 拖到目标一级组块内 ⇒ 换入该组（前邻一级即新父组，旧口径保留）；
/// · 拖到列表**最顶**（第一个一级组之上）⇒ 换入**第一个一级组**；
/// · **禁**用 `parentId:null` 表达「换组」（旧实现 null 对 `parent_id` 不写库 ⇒ 换组失效）。
class CategoryMove {
  const CategoryMove(this.cat, {required this.primary, this.parentId, required this.sort});
  final Category cat;

  /// true=一级行（走 clearParent 归位重排）；false=次级行（带显式 parentId）。
  final bool primary;
  final int? parentId;
  final int sort;
}

/// 行序 [rows]/[isSub] 在拖拽 [oldIndex]→[newIndex] 后的写回计划。
List<CategoryMove> categoryReorderPlan(
    List<Category> rows, List<bool> isSub, int oldIndex, int newIndex) {
  final list = [...rows];
  final flags = [...isSub];
  final item = list.removeAt(oldIndex);
  final flag = flags.removeAt(oldIndex);
  final target = (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(0, list.length);
  list.insert(target, item);
  flags.insert(target, flag);

  final firstPrimaryId = () {
    for (var i = 0; i < list.length; i++) {
      if (!flags[i]) return list[i].id;
    }
    return null;
  }();
  final moves = <CategoryMove>[];
  var sortP = 0, sortS = 0;
  for (var i = 0; i < list.length; i++) {
    final c = list[i];
    if (!flags[i]) {
      sortP++;
      sortS = 0;
      moves.add(CategoryMove(c, primary: true, sort: sortP));
    } else {
      // 前邻一级即新父组；上方无一级（最顶）⇒ 换入第一个一级组（C10）。
      var j = i - 1;
      while (j >= 0 && flags[j]) {
        j--;
      }
      final parent = j >= 0 ? list[j].id : firstPrimaryId;
      sortS++;
      moves.add(CategoryMove(c, primary: false, parentId: parent, sort: sortS));
    }
  }
  return moves;
}
