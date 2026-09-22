import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/read_repository.dart';
import '../domain/book.dart';
import '../domain/book_dict.dart';
import '../domain/book_list.dart';
import '../domain/book_quote.dart';
import '../domain/book_session.dart';
import '../domain/book_toc.dart';
import '../domain/shelf_query.dart' show sessionAggByBook;

/// 阅读模块 providers（M1批3）。
///
/// 写库后统一 `readTickProvider.state++` 触发全部数据重取（与 todosProvider 同法）。

final readRepositoryProvider = Provider<ReadRepository>(
  (ref) => ReadRepository(AppDatabase.instance.db),
);

final readTickProvider = StateProvider<int>((ref) => 0);

final booksProvider = FutureProvider<List<Book>>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).allBooks();
});

final runningSessionProvider = FutureProvider<BookSession?>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).runningSession();
});

/// settings 表 read.* 键通用取值（带默认值即时反映，写后 readTick 失效）。
final readKvProvider = FutureProvider.family<String, (String key, String def)>((
  ref,
  arg,
) async {
  ref.watch(readTickProvider);
  final raw = await ref.watch(readRepositoryProvider).kv(arg.$1);
  return raw ?? arg.$2;
});

/// 计时形态（计划 §6 read.timerUI：全屏 / 顶部胶囊，默认全屏）。
final timerUIProvider = FutureProvider<String>(
  (ref) => ref.watch(readKvProvider(('read.timerUI', '全屏')).future),
);

/// 悬浮计时条开关（read.floatBar，默认开）。
final floatBarProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(readKvProvider(('read.floatBar', 'true')).future)) ==
      'true',
);

/// 结束计时即弹记进度（read.autoAsk，默认开）。
final autoAskProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(readKvProvider(('read.autoAsk', 'true')).future)) ==
      'true',
);

/// 顶部长胶囊是否可见：有在跑会话 && read.floatBar 开（§3.3 两种形态都常驻）。
final readTimerBarVisibleProvider = FutureProvider<bool>((ref) async {
  final run = await ref.watch(runningSessionProvider.future);
  if (run == null) return false;
  return ref.watch(floatBarProvider).valueOrNull ?? true;
});

/// 单书会话明细（计时明细弹层 / 轨迹）。
final sessionsOfProvider = FutureProvider.family<List<BookSession>, String>((
  ref,
  bookId,
) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).sessionsOf(bookId);
});

/// 单书两级目录。
final tocProvider = FutureProvider.family<List<TocNode>, String>((ref, bookId) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).tocOf(bookId);
});

/// 书架资料字典（按 kind）。
final dictProvider = FutureProvider.family<List<DictEntry>, String>((
  ref,
  kind,
) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).dictOf(kind);
});

final allQuotesProvider = FutureProvider<List<BookQuote>>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).allQuotes();
});

/// 书单列表（批4）。
final bookListsProvider = FutureProvider<List<BookList>>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).allLists();
});

/// 书单成员（年度单动态求）。
final listMembersProvider = FutureProvider.family<List<Book>, int>((
  ref,
  listId,
) async {
  ref.watch(readTickProvider);
  final l = await ref.watch(readRepositoryProvider).listById(listId);
  if (l == null) return const [];
  final yearSort = await ref
      .watch(readRepositoryProvider)
      .kv('read.yearSort');
  return ref
      .watch(readRepositoryProvider)
      .listMembers(l, desc: yearSort == '降序');
});

/// 工作台聚合数据（今日卡 + 轨道 + 最近摘录一次取齐）。
class WorkbenchData {
  const WorkbenchData({
    required this.books,
    required this.minutesToday,
    required this.minutesWeek,
    required this.streak,
    required this.goalDay,
    required this.goalWeek,
    required this.goalBooks,
    required this.quotes,
    required this.quotesTotal,
    required this.dueReviews,
    required this.running,
    required this.agg,
    this.goalWeekDays = 5,
    this.goalMonthQuotes = 20,
    this.weekDays = 0,
    this.monthQuotes = 0,
    this.weekQuotes = 0,
  });

  final List<Book> books;
  final int minutesToday;
  final int minutesWeek;
  final int streak;
  final int goalDay;
  final int goalWeek;
  final int goalBooks;
  final List<BookQuote> quotes;

  /// 摘录总数 / 今日到期复习数（复习卡副标题 · §3.4）。
  final int quotesTotal;
  final int dueReviews;
  final BookSession? running;

  /// book_id → (累计分钟, 次数)
  final Map<String, ({int minutes, int times})> agg;

  /// L7 五路与本周/本月实况（统计页目标卡 · 计划批4）。
  final int goalWeekDays;
  final int goalMonthQuotes;
  final int weekDays;
  final int monthQuotes;
  final int weekQuotes;

  List<Book> get reading => ShelfSort.byLastRead(
    books.where((b) => b.state == Book.kStateReading && !b.isDeleted).toList(),
  );

  /// 全部藏书按最近阅读倒序（封面轨道数据源 §3.3）。
  List<Book> get rail =>
      ShelfSort.byLastRead(books.where((b) => !b.isDeleted).toList());

  int get doneThisYear {
    final y = DateTime.now().year;
    return books
        .where(
          (b) =>
              !b.isDeleted &&
              b.state == Book.kStateDone &&
              b.endedAt != null &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == y,
        )
        .length;
  }

  /// 今日卡计时目标书：在读排序第一本（最近阅读那本 · §3.4）。
  Book? get timerTarget => reading.isEmpty ? null : reading.first;

  /// 连续阅读天数（今天没读则从昨天往回数）。
  static int streakOf(List<DateTime> days) {
    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    final set = days.map((d) => DateTime(d.year, d.month, d.day)).toSet();
    if (!set.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!set.contains(cursor)) return 0;
    }
    var n = 0;
    while (set.contains(cursor)) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }
}

/// 最近阅读倒序（last_read_at 聚合列口径 §3.2）。
class ShelfSort {
  static List<Book> byLastRead(List<Book> inList) => [...inList]
    ..sort(
      (a, b) =>
          (b.lastReadAt ?? b.updatedAt).compareTo(a.lastReadAt ?? a.updatedAt),
    );
}

final workbenchProvider = FutureProvider<WorkbenchData>((ref) async {
  ref.watch(readTickProvider);
  final repo = ref.watch(readRepositoryProvider);
  final books = await repo.allBooks();
  final now = DateTime.now();
  final day = await repo.minutesOnDay(now);
  final week = await repo.minutesThisWeek();
  final days = await repo.readingDays();
  final quotes = await repo.recentQuotes(3);
  final running = await repo.runningSession();
  return WorkbenchData(
    books: books,
    minutesToday: day,
    minutesWeek: week,
    streak: WorkbenchData.streakOf(days),
    goalDay: await repo.kvInt('read.goalDayMin', 30),
    goalWeek: await repo.kvInt('read.goalWeekMin', 210),
    goalBooks: await repo.kvInt('read.goalBooks', 50),
    quotes: quotes,
    quotesTotal: await repo.quoteCount(),
    dueReviews: await repo.dueReviewCount(),
    running: running,
    agg: sessionAggByBook(await repo.allSessions()),
  );
});

/// 时长格式化（原型 bsFmt：≥60 → 4h32m）。
String bsFmt(int minutes) => minutes < 60
    ? '$minutes′'
    : (minutes % 60 == 0
          ? '${minutes ~/ 60}h'
          : '${minutes ~/ 60}h${minutes % 60}m');
