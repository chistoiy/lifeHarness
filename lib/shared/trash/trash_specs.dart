import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/database/schema.dart';

import '../../features/habit/data/habit_repository.dart';
import '../../features/habit/presentation/habit_providers.dart';
import '../../features/journal/data/journal_dao.dart';
import '../../features/journal/data/note_dao.dart';
import '../../features/journal/presentation/journal_providers.dart';
import '../../features/items/data/items_repository.dart';
import '../../features/items/domain/item_calc.dart' show daysHeld, poolOf;
import '../../features/items/presentation/items_kit.dart' show itemMoney;
import '../../features/items/presentation/items_providers.dart';
import '../../features/mindmap/data/mindmap_dao.dart';
import '../../features/mindmap/presentation/mindmap_providers.dart';
import '../../features/read/data/read_repository.dart';
import '../../features/read/domain/book.dart';
import '../../features/read/domain/shelf_query.dart' show sessionAggByBook;
import '../../features/read/presentation/read_providers.dart';
import '../../features/todo/data/todo_dao.dart';
import '../../features/todo/domain/todo.dart';
import '../../features/todo/presentation/todo_providers.dart';
import '../../features/todo/presentation/widgets/todo_edit_sheet.dart'
    show dueLabel;
import 'trash_models.dart';

/// V1.61 回收站登记式接口（工单 `交棒话术-20261005-物品档案删除批` §C0）。
///
/// **一类内容进回收站要接的六条线，在一处登记完**：
/// 读源（本类垃圾箱行）· 恢复回调 · 彻底删除回调 · 动作后刷本模块读数 ·
/// 到期清理出口 · 源模块写信号（回收站随之自失效）。
///
/// 为什么抽：原先是「中心化枚举 + 三处按类别分支 + 两处写死清单」，加一类要改六个地方。
/// 物品是第七类，同构再补一遍＝把「加一类」的成本再付一次。
///
/// 代价与补偿（如实记）：Dart 的枚举穷尽 `switch` 本来是**编译期**护栏——加一类漏接线就编译不过。
/// 换成注册表后编译期不再知道，漏登记只能在运行期发现。所以 `test/trash_guard_test.dart`
/// 补了三条硬闸：每个 `TrashKind` 必须在册且仅登记一次、回收站分派处不得再出现按类别分支、
/// 到期清理必须按注册表顺序跑。**摘掉注册表直接写 switch＝守护红**，不是自觉。
typedef TrashRowsFn = Future<List<TrashItem>> Function(Database db);
typedef TrashRestoreFn = Future<void> Function(Ref ref, TrashItem it);

/// 彻底删除单项；返回值＝本次连带清除的在库划线书摘条数（只有书籍非 0）。
typedef TrashPurgeFn = Future<int> Function(Ref ref, TrashItem it);
typedef TrashRefreshFn = void Function(Ref ref);
typedef TrashPurgeExpiredFn = Future<int> Function(Database db, int keepDays);

/// 一个类别的完整登记项。缺任何一条线都编译不过（`required`），
/// 「登记了一半」由守护用例按 `TrashKind` 逐类点名。
class TrashKindSpec {
  TrashKindSpec({
    required this.kind,
    required this.rows,
    required this.restore,
    required this.purge,
    required this.refresh,
    required this.purgeExpired,
    required this.signals,
    required this.refreshGroup,
    this.restoreToastOf,
  });

  final TrashKind kind;

  /// 本类垃圾箱行（含副信息与孤行判定）。
  final TrashRowsFn rows;

  /// 恢复＝回原模块原位（同一条记录，不新建）。
  final TrashRestoreFn restore;

  /// 彻底删除＝真 DELETE（连带口径由本类自己说清）。
  final TrashPurgeFn purge;

  /// 动作后把本模块读数刷回原位（各模块页数字即时补回）。
  final TrashRefreshFn refresh;

  /// 冷启动到期清理出口，返回清除行数。
  final TrashPurgeExpiredFn purgeExpired;

  /// 刷新分组：同组一次动作只刷一遍。阅读线的书·划线·书单共用一路 tick，
  /// 不分组的后果＝一次批量恢复把 readTick 连加三次（旧实现是一条分支只加一次）。
  final Object refreshGroup;

  /// 源模块的写信号：任一有变，回收站条目列表自失效（真机 6059 抓过的坑）。
  final List<ProviderListenable<Object?>> signals;

  /// 本类恢复回执；不给则走 [TrashKind.restoreToast]。
  final String Function(TrashItem it)? restoreToastOf;
}

/// **有序**登记表：到期清理按此序跑——先清书行（连带清在库摘录），再清摘录/书单，
/// 否则刚被置孤的行会在同一轮被当作过期清走。改成无序 Map＝守护红。
final List<TrashKindSpec> trashKindSpecs = [
  // ==================== 待办 ====================
  TrashKindSpec(
    kind: TrashKind.todo,
    refreshGroup: 'todo',
    signals: [todosProvider],
    rows: (db) async {
      final out = <TrashItem>[];
      for (final t in await TodoDao(db).trashed()) {
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
      return out;
    },
    restore: (ref, it) =>
        ref.read(todoRepositoryProvider).restore(it.src! as Todo),
    purge: (ref, it) async {
      await ref.read(todoRepositoryProvider).purge([it.rawId as int]);
      return 0;
    },
    refresh: (ref) {
      ref.invalidate(todosProvider);
      ref.invalidate(overdueCountProvider);
    },
    purgeExpired: (db, keepDays) => TodoDao(db).purgeExpired(keepDays),
    restoreToastOf: (it) => '已恢复到「${(it.src! as Todo).quadrant.label}」',
  ),

  // ==================== 笔记 ====================
  TrashKindSpec(
    kind: TrashKind.note,
    refreshGroup: 'note',
    signals: [notesProvider],
    rows: (db) async {
      final out = <TrashItem>[];
      for (final n in await NoteDao(db).trash()) {
        out.add(TrashItem(
          kind: TrashKind.note,
          rawId: n.id!,
          // 真机走查 6059：空标题笔记在行上会剩一个空白标题——与笔记列表同兜底。
          title: n.title.trim().isEmpty ? '未命名笔记' : n.title,
          deletedAt: n.deletedAt,
          subs: [if (n.folder != null && n.folder!.isNotEmpty) n.folder!],
          src: n,
        ));
      }
      return out;
    },
    restore: (ref, it) => ref.read(noteDaoProvider).restore(it.rawId as int),
    purge: (ref, it) async {
      await ref.read(noteDaoProvider).purge(it.rawId as int);
      return 0;
    },
    refresh: (ref) {
      ref.invalidate(notesProvider);
      ref.invalidate(noteTreeProvider);
    },
    purgeExpired: (db, keepDays) => NoteDao(db).purgeExpired(keepDays),
  ),

  // ==================== 习惯 ====================
  TrashKindSpec(
    kind: TrashKind.habit,
    refreshGroup: 'habit',
    signals: [habitTickProvider],
    rows: (db) async {
      final out = <TrashItem>[];
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
      return out;
    },
    restore: (ref, it) =>
        ref.read(habitRepositoryProvider).restoreHabit(it.rawId as String),
    purge: (ref, it) async {
      await ref.read(habitRepositoryProvider).purgeHabit(it.rawId as String);
      return 0;
    },
    refresh: (ref) => ref.read(habitTickProvider.notifier).state++,
    purgeExpired: (db, keepDays) =>
        HabitRepository(db).purgeExpiredHabits(keepDays),
  ),

  // ==================== 书籍（彻底删除含连带清除） ====================
  TrashKindSpec(
    kind: TrashKind.book,
    refreshGroup: 'read',
    signals: [readTickProvider],
    rows: (db) async {
      final read = ReadRepository(db);
      // 书行副信息：在库划线数 + 累计阅读分钟 + 进度（原型 gtSub book 分支·「在库」二字同名）。
      final agg = sessionAggByBook(await read.allSessions());
      final out = <TrashItem>[];
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
      return out;
    },
    restore: (ref, it) =>
        ref.read(readRepositoryProvider).restoreBook(it.rawId as String),
    // 书籍的彻底删除＝连带清（在库摘录/计时/目录/进度），返回连带条数供回执。
    purge: (ref, it) =>
        ref.read(readRepositoryProvider).purgeBook(it.rawId as String),
    refresh: (ref) => ref.read(readTickProvider.notifier).state++,
    purgeExpired: (db, keepDays) =>
        ReadRepository(db).purgeExpiredTrashBooks(keepDays),
  ),

  // ==================== 划线书摘（孤行不可单独恢复） ====================
  TrashKindSpec(
    kind: TrashKind.quote,
    refreshGroup: 'read',
    signals: [readTickProvider],
    rows: (db) async {
      final read = ReadRepository(db);
      // 划线/书摘：所属书不在架（已彻底删除或仍在垃圾箱）＝孤行，不可单独恢复。
      final byId = <String, Book>{for (final b in await read.allBooks()) b.id: b};
      final out = <TrashItem>[];
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
      return out;
    },
    restore: (ref, it) =>
        ref.read(readRepositoryProvider).restoreQuote(it.rawId as int),
    purge: (ref, it) async {
      await ref.read(readRepositoryProvider).purgeQuote(it.rawId as int);
      return 0;
    },
    refresh: (ref) => ref.read(readTickProvider.notifier).state++,
    purgeExpired: (db, keepDays) =>
        ReadRepository(db).purgeExpiredTrashQuotes(keepDays),
    restoreToastOf: (it) => it.subs.isEmpty
        ? '已恢复到原书'
        : '已恢复到${it.subs.first.replaceFirst('所属', '')}',
  ),

  // ==================== 书单 ====================
  TrashKindSpec(
    kind: TrashKind.list,
    refreshGroup: 'read',
    signals: [readTickProvider],
    rows: (db) async {
      final read = ReadRepository(db);
      final out = <TrashItem>[];
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
      return out;
    },
    restore: (ref, it) =>
        ref.read(readRepositoryProvider).restoreList(it.rawId as int),
    purge: (ref, it) async {
      await ref.read(readRepositoryProvider).purgeList(it.rawId as int);
      return 0;
    },
    refresh: (ref) => ref.read(readTickProvider.notifier).state++,
    purgeExpired: (db, keepDays) =>
        ReadRepository(db).purgeExpiredTrashLists(keepDays),
  ),

  // ==================== 物品（V1.61 第七类·加一类＝在此登记一条） ====================
  TrashKindSpec(
    kind: TrashKind.item,
    refreshGroup: 'item',
    signals: [itemsTickProvider],
    rows: (db) async {
      final repo = ItemsRepository(db);
      final out = <TrashItem>[];
      for (final it in await repo.trashedItems()) {
        // 副信息与原型 gtSub 物品分支同序：分类 · 成本池 · 持有天数 · 流水保留。
        final ro = await repo.trashReadout(it.id!);
        out.add(TrashItem(
          kind: TrashKind.item,
          rawId: it.id!,
          title: it.name.trim().isEmpty ? '未命名物品' : it.name,
          deletedAt: trashTimeOf(it.deletedAt),
          subs: [
            // 成本池＝净值（购入＋二次付费−回收残值），不是购入价（真机 6071 纠偏）。
            '${it.category} · 成本池 ${itemMoney(poolOf(it))} · 持有 ${daysHeld(it.buyDate, DateTime.now())} 天',
            '关联流水 ${ro.txns} 条保留',
          ],
          cascadeNotes: '连带清 成本时间轴 ${ro.events} 条 · 按次用量 ${ro.usages} 次 · 关联流水保留',
          src: it,
        ));
      }
      return out;
    },
    restore: (ref, it) => ref.read(itemsRepositoryProvider).restoreItem(it.rawId as int),
    purge: (ref, it) async {
      await ref.read(itemsRepositoryProvider).purgeItem(it.rawId as int);
      return 0; // 物品不产生「在库摘录」那类连带读数；子记录条数由确认弹层自己算
    },
    refresh: (ref) => ref.read(itemsTickProvider.notifier).state++,
    purgeExpired: (db, keepDays) => ItemsRepository(db).purgeExpiredItems(keepDays),
  ),

  // ==================== 日记（语义断链批 2026-10-12 · 第八类） ====================
  TrashKindSpec(
    kind: TrashKind.journal,
    refreshGroup: 'journal',
    signals: [journalsProvider],
    rows: (db) async {
      final out = <TrashItem>[];
      for (final e in await JournalDao(db).trash()) {
        // 副信息＝日期（同日多篇由篇数副行区辨）；标题＝正文预览（篇目无标题列）。
        final preview = e.plainBody.trim();
        String two(int v) => v.toString().padLeft(2, '0');
        final clipped =
            preview.length <= 24 ? preview : '${preview.substring(0, 24)}…';
        out.add(TrashItem(
          kind: TrashKind.journal,
          rawId: e.id!,
          title: clipped.isEmpty ? '只打了心情卡' : clipped.replaceAll('\n', ' '),
          deletedAt: e.deletedAt,
          subs: [
            '${e.day.year}-${two(e.day.month)}-${two(e.day.day)}'
                '${e.templateId != null ? ' · 结构化' : ''}',
          ],
          cascadeNotes: '连带清 分节行（恢复可回；图片文件保留）',
          src: e,
        ));
      }
      return out;
    },
    restore: (ref, it) =>
        ref.read(journalRepositoryProvider).restoreJournal(it.rawId as int),
    purge: (ref, it) =>
        ref.read(journalRepositoryProvider).purgeJournal(it.rawId as int),
    refresh: (ref) => ref.invalidate(journalsProvider),
    purgeExpired: (db, keepDays) => JournalDao(db).purgeExpired(keepDays),
  ),

  // ==================== 导图（思维导图批1 2026-10-12 · 第九类） ====================
  // 删图＝图行软删，节点行不动（恢复＝只清标记即「带全节点回原位」）；
  // 彻底删除才级联 DELETE 全部 mindmap_nodes（登记式接口无自动级联、自写，
  // 先例＝book→quote、journal→分节；trash_guard_test 按 TrashKind 逐类点名）。
  TrashKindSpec(
    kind: TrashKind.mindmap,
    refreshGroup: 'mindmap',
    signals: [mindmapTickProvider],
    rows: (db) async {
      final out = <TrashItem>[];
      for (final m in await MindmapDao(db).trashed()) {
        final nodeCount = Sqflite.firstIntValue(await db.rawQuery(
                'SELECT COUNT(*) FROM ${DbSchema.tMindmapNodes} WHERE map_id = ?',
                [m.id])) ??
            0;
        out.add(TrashItem(
          kind: TrashKind.mindmap,
          rawId: m.id!,
          title: m.title.trim().isEmpty ? '未命名导图' : m.title,
          deletedAt: trashTimeOf(m.deletedAt),
          subs: ['$nodeCount 个节点'],
          cascadeNotes: '连带清 全部节点行 $nodeCount 条（恢复图即整图可回）',
          src: m,
        ));
      }
      return out;
    },
    restore: (ref, it) async =>
        MindmapDao(AppDatabase.instance.db).restoreMap(it.rawId as int),
    purge: (ref, it) async {
      await MindmapDao(AppDatabase.instance.db).purgeMap(it.rawId as int);
      return 0;
    },
    refresh: (ref) => ref.read(mindmapTickProvider.notifier).state++,
    purgeExpired: (db, keepDays) => MindmapDao(db).purgeExpired(keepDays),
  ),
];

/// 按类别取登记项。漏登记＝运行期抛错，但守护用例会在 CI 阶段先红（`trashSpecOf` 逐类点名）。
TrashKindSpec trashSpecOf(TrashKind kind) {
  for (final s in trashKindSpecs) {
    if (s.kind == kind) return s;
  }
  throw StateError('回收站类别未登记：${kind.name} 缺 TrashKindSpec（请在 trash_specs.dart 补一条）');
}

/// 回收站自失效要听的源模块信号（去重：阅读线三类共用一路 tick）。
final List<ProviderListenable<Object?>> trashSourceSignals = {
  for (final s in trashKindSpecs) ...s.signals
}.toList();

/// 到期清理：按注册表顺序逐类跑，键＝人话模块名（刻意不用表名，免与 E 批守护的裸表名扫描相撞）。
Future<Map<String, int>> trashPurgeExpired(Database db, int keepDays) async {
  final out = <String, int>{};
  for (final s in trashKindSpecs) {
    out[s.kind.label] = await s.purgeExpired(db, keepDays);
  }
  return out;
}
