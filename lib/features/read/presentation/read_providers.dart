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

/// 豆瓣元数据缓存条数（防封批 2026-09-26 · 设置页「豆瓣数据缓存」行展示/
/// 清除按钮置灰判断用；readTick 写后自动重取）。
final doubanCacheCountProvider = FutureProvider<int>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).doubanCacheCount();
});

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
final autoAskProvider = FutureProvider<bool>((ref) async {
  final v =
      (await ref.watch(readKvProvider(('read.autoAsk', 'true')).future)) ==
      'true';
  return v;
});

/// 有声倍速折算开关（read.speedFold，默认开）：读取时同步静态桥，
/// 使 domain 层纯 getter billedMinutes 生效（§6 阅读计时组）。
final speedFoldProvider = FutureProvider<bool>((ref) async {
  final v =
      (await ref.watch(readKvProvider(('read.speedFold', 'true')).future)) ==
      'true';
  BookSession.speedFold = v;
  return v;
});

/// 顶部长胶囊是否可见：有在跑会话 && 计时形态为顶部胶囊 && read.floatBar 开。
/// （全屏形态下计时走沉浸页，顶栏不再挂胶囊。）
final readTimerBarVisibleProvider = FutureProvider<bool>((ref) async {
  final run = await ref.watch(runningSessionProvider.future);
  if (run == null) return false;
  if (await ref.watch(timerUIProvider.future) != '顶部胶囊') return false;
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

/// 书架资料全值域引用计数（单类管理页行副行 / 删除守卫批量取）。
final dictCountsProvider = FutureProvider.family<Map<String, int>, String>((
  ref,
  kind,
) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).dictRefCounts(kind);
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
  final now2 = DateTime(now.year, now.month, now.day);
  final weekStart = now2.subtract(Duration(days: now.weekday - 1));
  final monthStart = DateTime(now.year, now.month);
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
    // L7 五路实况（统计页目标卡 · 批D）。
    goalWeekDays: await repo.kvInt('read.goalWeekDays', 5),
    goalMonthQuotes: await repo.kvInt('read.goalMonthQuotes', 20),
    weekDays: days.where((d) => !d.isBefore(weekStart) && !d.isAfter(now2)).length,
    monthQuotes: await repo.quoteCountSince(
      ReadRepository.dayStartMs(monthStart),
    ),
    weekQuotes: await repo.quoteCountSince(
      ReadRepository.dayStartMs(weekStart),
    ),
  );
});

/// 时长格式化（原型 bsFmt：≥60 → 4h32m）。
String bsFmt(int minutes) => minutes < 60
    ? '$minutes′'
    : (minutes % 60 == 0
          ? '${minutes ~/ 60}h'
          : '${minutes ~/ 60}h${minutes % 60}m');

/// 进度口径四态（原型 bsPosLabel 4551）：pos→「x/tot 位置」、
/// min（有声）→「p% · 有声」、chap→「按章节」、else→「rp/pages 页」。
String bsPosLabel(Book b) => switch (b.progressWay) {
  Book.kWayPos =>
    '${(b.readLoc ?? 0).round()} / ${(b.totalLoc ?? 0).round()} 位置',
  Book.kWayMin => '${b.percent}% · 有声',
  Book.kWayChap => '按章节',
  _ => '${b.readPages} / ${b.pages} 页',
};

/// 进度方式中文名（原型 BS_PW 5235：page=页数 pos=位置 chap=章节 pct=百分比 min=分钟）。
String bsWayName(String way) => switch (way) {
  Book.kWayPos => '位置',
  Book.kWayChap => '章节',
  Book.kWayPct => '百分比',
  Book.kWayMin => '分钟',
  _ => '页数',
};

/// 评分显示（整数去尾零 · 原型 `${b.rate}分` 口径；0 分显空串）。
String bsRateLabel(double rating) => rating <= 0
    ? ''
    : rating % 1 == 0
    ? '${rating.toInt()}分'
    : '$rating分';
