import 'package:sqflite/sqflite.dart';

import '../../features/habit/data/habit_repository.dart';
import '../../features/journal/data/note_dao.dart';
import '../../features/read/data/read_repository.dart';
import '../../features/read/domain/book.dart';
import '../../features/read/domain/shelf_query.dart' show sessionAggByBook;
import '../../features/todo/data/todo_dao.dart';
import '../../features/todo/presentation/widgets/todo_edit_sheet.dart'
    show dueLabel;
import 'trash_models.dart';

/// V1.60 全局回收站的取数出口（跨六模块，R1 惯例＝经 shared 聚合，feature 之间不互连）。
///
/// 只读面在此：六类垃圾箱行 + 到期自动清理；写面（恢复/彻底删除）在
/// [TrashService]（trash_providers.dart），因为待办恢复要连带重排提醒。
class TrashRepository {
  TrashRepository(this.db);

  final Database db;

  /// 六类垃圾箱条目，按删除时间倒序（原型 D.trash 同序口径）。
  Future<List<TrashItem>> items() async {
    final todoDao = TodoDao(db);
    final read = ReadRepository(db);
    final out = <TrashItem>[];

    for (final t in await todoDao.trashed()) {
      out.add(TrashItem(
        kind: TrashKind.todo,
        rawId: t.id!,
        title: t.title,
        deletedAt: t.deletedAt,
        subs: [
          if (t.dueAt != null) '⏰ ${dueLabel(t)}',
          if (t.tag != null) '#${t.tag}',
        ],
        src: t,
      ));
    }

    for (final n in await NoteDao(db).trash()) {
      out.add(TrashItem(
        kind: TrashKind.note,
        rawId: n.id!,
        title: n.title,
        deletedAt: n.deletedAt,
        subs: [if (n.folder != null && n.folder!.isNotEmpty) n.folder!],
        src: n,
      ));
    }

    for (final h in await HabitRepository(db).trashedHabits()) {
      out.add(TrashItem(
        kind: TrashKind.habit,
        rawId: h.id,
        title: h.name,
        deletedAt: trashTimeOf(h.deletedAt),
        subs: const [],
        src: h,
      ));
    }

    // 书行副信息：在库划线数 + 累计阅读分钟 + 进度（原型 gtSub book 分支·「在库」二字同名）。
    final agg = sessionAggByBook(await read.allSessions());
    for (final b in await read.trashedBooks()) {
      final quotes = await read.liveQuoteCountOf(b.id);
      out.add(TrashItem(
        kind: TrashKind.book,
        rawId: b.id,
        title: b.title,
        deletedAt: trashTimeOf(b.deletedAt),
        subs: [
          '含在库划线·笔记 $quotes 条 · '
              '阅读 ${(agg[b.id]?.minutes ?? 0)} 分钟 · '
              '进度 ${b.percent}%'
        ],
        amberSub: true,
        cascadeQuotes: quotes,
        src: b,
      ));
    }

    // 划线/书摘：所属书不在架（已彻底删除或仍在垃圾箱）＝孤行，不可单独恢复。
    final byId = <String, Book>{for (final b in await read.allBooks()) b.id: b};
    for (final q in await read.trashedQuotes()) {
      final parent = byId[q.bookId];
      final orphan = parent == null || parent.isDeleted;
      out.add(TrashItem(
        kind: TrashKind.quote,
        rawId: q.id!,
        // 父书行已没了就取不到书名——这是能力边界，行上直说「所属书已彻底删除」，
        // 不编一个假书名（原型那侧数据自带 link，真库没有）。
        title: q.body.trim().isEmpty ? '（图片书摘）' : q.body.trim(),
        deletedAt: trashTimeOf(q.deletedAt),
        subs: [
          if (parent == null) '所属书已彻底删除',
          if (parent != null && parent.isDeleted) '所属《${parent.title}》· 书还在回收站',
          if (parent != null && !parent.isDeleted) '所属《${parent.title}》',
        ],
        orphan: orphan,
        // 提示语与原型 gtOrph 一字不差（置灰标签的说明＝为什么不能恢复＋下一步怎么走）
        orphanHint: parent == null
            ? '所属书已彻底删除'
            : '所属书还在回收站，先恢复书或整体删除',
        src: q,
      ));
    }

    for (final l in await read.trashedLists()) {
      out.add(TrashItem(
        kind: TrashKind.list,
        rawId: l.id!,
        title: l.name,
        deletedAt: trashTimeOf(l.deletedAt),
        subs: [l.isAuto ? l.badge : '成员 ${await read.listItemCount(l.id!)} 本'],
        src: l,
      ));
    }

    final epoch = DateTime(1970);
    out.sort((a, b) =>
        (b.deletedAt ?? epoch).compareTo(a.deletedAt ?? epoch));
    return out;
  }

  /// 到期自动清理（需求 V1.60：冷启动清理由「仅待办」扩至全部纳入党表）。
  /// [keepDays]<=0＝不清理。按**人话模块名**返回清除行数（书籍含连带摘录），
  /// 供启动日志逐表留痕；键名刻意不用表名，免与 E 批守护的裸表名扫描相撞。
  Future<Map<String, int>> purgeExpiredByTable(int keepDays) async {
    if (keepDays <= 0) return const {};
    final read = ReadRepository(db);
    return {
      '待办': await TodoDao(db).purgeExpired(keepDays),
      '笔记': await NoteDao(db).purgeExpired(keepDays),
      '习惯': await HabitRepository(db).purgeExpiredHabits(keepDays),
      // 先清书行（连带口径），再清摘录/书单，避免刚置孤的孤行本轮即被当作过期清走。
      '书籍': await read.purgeExpiredTrashBooks(keepDays),
      '划线书摘': await read.purgeExpiredTrashQuotes(keepDays),
      '书单': await read.purgeExpiredTrashLists(keepDays),
    };
  }
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
