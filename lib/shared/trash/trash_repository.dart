import 'package:sqflite/sqflite.dart';

import 'trash_models.dart';
import 'trash_specs.dart';

/// V1.60 全局回收站的取数出口（跨模块，R1 惯例＝经 shared 聚合，feature 之间不互连）。
///
/// V1.61 起本文件只做**编排**：每类怎么读行、怎么到期清理，全部登记在
/// [trashKindSpecs]（`trash_specs.dart`）。加一类＝登记一条，不在此处再加分支
/// ——守护 `trash_guard_test` 会盯着这里不许出现按类别分支。
class TrashRepository {
  TrashRepository(this.db);

  final Database db;

  /// 各类垃圾箱条目合并，按删除时间倒序（原型 D.trash 同序口径）。
  Future<List<TrashItem>> items() async {
    final out = <TrashItem>[];
    for (final s in trashKindSpecs) {
      out.addAll(await s.rows(db));
    }
    final epoch = DateTime(1970);
    out.sort((a, b) => (b.deletedAt ?? epoch).compareTo(a.deletedAt ?? epoch));
    return out;
  }

  /// 到期自动清理（需求 V1.60：冷启动清理由「仅待办」扩至全部纳入党表）。
  /// [keepDays]<=0＝不清理。按**人话模块名**返回清除行数，供启动日志逐表留痕。
  /// 顺序＝注册表顺序（书籍先于摘录/书单，见 `trash_specs.dart` 注释）。
  Future<Map<String, int>> purgeExpiredByTable(int keepDays) => keepDays <= 0
      ? Future<Map<String, int>>.value(const {})
      : trashPurgeExpired(db, keepDays);
}

/// 恢复/彻底删除的分派结果（屏层据此出回执）。
class TrashOpResult {
  const TrashOpResult({
    required this.count,
    this.purgedBookQuotes = 0,
    this.hadBook = false,
  });
  final int count;

  /// 彻底删除书籍连带清除的在库摘录条数合计。
  final int purgedBookQuotes;

  /// 本次是否含书籍（回执要说明孤行不可再单独恢复）。
  final bool hadBook;
}
