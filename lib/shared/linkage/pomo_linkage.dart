import '../../core/database/app_database.dart';
import '../../features/calendar/data/category_dao.dart';
import '../../features/calendar/data/time_block_dao.dart';

/// 番茄 → 时间模块联动（V1.20 · L4 入账）。
/// 待办模块不直接 import 日历 feature（架构守护 R1），统一走本聚合层服务。
Future<void> writePomoBlock({
  required int startMin,
  required int endMin,
  int? catId,
  String catName = '工作',
  String? note,
}) {
  final now = DateTime.now();
  final day0 = DateTime(now.year, now.month, now.day);
  return TimeBlockDao(AppDatabase.instance.db).markRange(
    day0,
    startMin.clamp(0, 1439),
    endMin.clamp(1, 1440),
    catId: catId,
    catName: catName,
    note: note,
  );
}

/// 按分类 id 取名称（次级/一级通用；供番茄入账写 category 列）。
Future<String?> catNameById(int? id) async {
  if (id == null) return null;
  final cats = await CategoryDao(AppDatabase.instance.db).list();
  for (final c in cats) {
    if (c.id == id) return c.name;
  }
  return null;
}
