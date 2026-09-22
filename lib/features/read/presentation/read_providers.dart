import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/read_repository.dart';
import '../domain/book.dart';
import '../domain/book_quote.dart';
import '../domain/book_session.dart';
import '../domain/shelf_query.dart' show sessionAggByBook;

/// 阅读模块 providers（M1批3）。
///
/// 写库后统一 `readTickProvider.state++` 触发全部数据重取（与 todosProvider 同法）。

final readRepositoryProvider =
    Provider<ReadRepository>((ref) => ReadRepository(AppDatabase.instance.db));

final readTickProvider = StateProvider<int>((ref) => 0);

final booksProvider = FutureProvider<List<Book>>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).allBooks();
});

final runningSessionProvider = FutureProvider<BookSession?>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).runningSession();
});

final allQuotesProvider = FutureProvider<List<BookQuote>>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).allQuotes();
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
    required this.running,
    required this.agg,
  });

  final List<Book> books;
  final int minutesToday;
  final int minutesWeek;
  final int streak;
  final int goalDay;
  final int goalWeek;
  final int goalBooks;
  final List<BookQuote> quotes;
  final BookSession? running;

  /// book_id → (累计分钟, 次数)
  final Map<String, ({int minutes, int times})> agg;

  List<Book> get reading => ShelfSort.byLastRead(
      books.where((b) => b.state == Book.kStateReading && !b.isDeleted).toList());

  /// 全部藏书按最近阅读倒序（封面轨道数据源 §3.3）。
  List<Book> get rail =>
      ShelfSort.byLastRead(books.where((b) => !b.isDeleted).toList());

  int get doneThisYear {
    final y = DateTime.now().year;
    return books.where((b) =>
        !b.isDeleted &&
        b.state == Book.kStateDone &&
        b.endedAt != null &&
        DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == y).length;
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
    ..sort((a, b) => (b.lastReadAt ?? b.updatedAt)
        .compareTo(a.lastReadAt ?? a.updatedAt));
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
