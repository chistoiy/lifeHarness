import './selection_controller.dart'; // V1.53.2 性能批 1
// V1.53.4：para_box_cache（性能批 2 方案 B）已摘除——放大镜批停用命中后为死代码，
// 跨页扩选改走「边界自动翻页」方案（reader_sel_ops._edgeFlipSel），无需坐标缓存。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../data/epub_cache.dart';
import '../data/epub_doc.dart';
import '../data/epub_import.dart';
import '../data/read_repository.dart';
import '../data/xray/xray_backup.dart';
import '../data/xray/xray_dao.dart';
import '../data/xray/xray_scheduler.dart';
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

/// 本地 EPUB 导入服务（V1.50 批1）。widget 测试 override 注入 pickHook/私有目录，
/// 不碰真实系统选择器与磁盘（FakeAsync 真 IO 挂死既有教训）。
final epubImportServiceProvider = Provider<EpubImportService>(
  (ref) => EpubImportService(
    ref.watch(readRepositoryProvider),
    // 批A-3 MD5 接线：导入提交时给私有副本算指纹落 books.md5（经 XrayDao 唯一出口）。
    xray: ref.watch(xrayDaoProvider),
  ),
);

/// EPUB 文件加载器（阅读主屏批2/删除批4 复用；测试 override 免真 IO）。
/// 批3.5：生产走懒归档 openFile——图片不再整包进内存；
/// 真机修（2026-09-28）：改后台 isolate 解析（openFileDetached），大书不再卡 UI。
final epubDocLoaderProvider
    = Provider<Future<EpubDoc> Function(String path)>((ref) => (path) async {
  return EpubDoc.openFileDetached(path);
});

/// 整本预载服务（批3.5）：导入后后台解析+全书分页落盘；封面进度数据源。
/// widget 测试 override 注入 parseOverride/pump/docsPath，不碰真实磁盘。
final epubPreloadProvider = ChangeNotifierProvider<EpubPreloadService>(
  (ref) {
    final svc = EpubPreloadService(ref.watch(readRepositoryProvider));
    svc.onBookSettled = (_) =>
        ref.read(readTickProvider.notifier).state++;
    // 生产：docs 目录解析完成后启用分页表落盘；测试 override 注入固定目录。
    unawaited(
      () async {
        try {
          svc.docsPath ??= (await getApplicationDocumentsDirectory()).path;
        } catch (_) {}
      }(),
    );
    return svc;
  },
);

/// 单书清缓存与三态恢复服务（批3.5）。
final epubCacheServiceProvider = Provider<EpubCacheService>(
  (ref) => EpubCacheService(ref.watch(readRepositoryProvider)),
);

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

/// 轮5.4：当前是否有阅读页在前台（阅读页自带顶栏计时胶囊，
/// 全局读书计时条在其上属重复信息 → 进页挂起、退页恢复）。
final readerOpenProvider = StateProvider<int>((_) => 0);

/// 顶部长胶囊是否可见：有在跑会话 && 计时形态为顶部胶囊 && read.floatBar 开
/// && 不在阅读页内（轮5.4 UI 统一）。
/// （全屏形态下计时走沉浸页，顶栏不再挂胶囊。）
final readTimerBarVisibleProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(readerOpenProvider) > 0) return false;
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

/// V1.53.2 性能批 1：选区控制器（方案 A）
final selectionProvider = StateNotifierProvider<SelectionController, ({int ci, int p0, int p1, int o0, int o1})?>((ref) => SelectionController());

/// V1.53.2 性能批 1：高亮色板展开状态
final highlightPopupProvider = StateProvider<bool>((ref) => false);

// ---------- V1.54 X-Ray 全书索引 · 批A（面板与跳转） ----------

/// X-Ray 四表唯一出口的装配位（守护红线：别处拿到的是这个 provider，不是 db）。
final xrayDaoProvider = Provider<XrayDao>(
  (ref) => XrayDao(ref.watch(readRepositoryProvider).db),
);

/// 解析终态修订号（完成/失败/重置）——词条数据重取只看它，逐章进度不惊动列表。
final xrayRevisionProvider = StateProvider<int>((ref) => 0);

/// 解析调度器（全局单飞·面板头与书架角标共用其 live 状态）。
/// widget 测试 override 注入 loadDoc/workerFactory/md5Hook，禁真 isolate 与真 IO。
final xraySchedulerProvider = ChangeNotifierProvider<XrayScheduler>((ref) {
  final svc = ref.watch(epubPreloadProvider);
  final s = XrayScheduler(
    dao: ref.watch(xrayDaoProvider),
    loadDoc: (b) async {
      final ep = b.epub;
      if (ep == null || ep.path.isEmpty) return null;
      var d = svc.docs.get(b.id);
      if (d == null) {
        await svc.warming(b.id);
        d = svc.docs.get(b.id);
      }
      d ??= await svc.snap(b);
      d ??= await EpubDoc.openFileDetached(ep.path);
      return d;
    },
    // 全局单飞优先级：开书（预热）在跑时 X-Ray 让路（§8）。
    busyProbe: (bookId) => svc.warming(bookId) != null,
  );
  s.onRevised = () => ref.read(xrayRevisionProvider.notifier).state = s.revision;
  // 冷启动收尸一次：上个进程留下的 running 行不转 pause，面板/角标会一直谎报状态。
  unawaited(s.reconcileStale());
  return s;
});

/// 单书索引备份服务（F10 · .xraybak 导出/导入；测试 override 注钩子）。
final xrayBackupServiceProvider = Provider<XrayBackupService>(
  (ref) => XrayBackupService(ref.watch(xrayDaoProvider)),
);

/// 某架位的内容指纹（懒补算不在这里做——被动渲染只读库，起解析动作才 ensureMd5）。
final bookMd5Provider = FutureProvider.family.autoDispose<String?, String>((
  ref,
  bookId,
) {
  ref.watch(readTickProvider);
  return ref.watch(xrayDaoProvider).bookMd5(bookId);
});

/// 面板整包数据（任务态+词条+锚点），按 md5 归属、随页面存活。
final xraySnapProvider = FutureProvider.family.autoDispose<XrayPanelData, String>((
  ref,
  md5,
) {
  ref.watch(xrayRevisionProvider);
  return ref.watch(xrayDaoProvider).panelData(md5);
});

/// 书架角标（F7）：一张 join 查询取回所有有任务态的架位；readTick/终态修订失效。
final xrayTaskBadgeProvider = FutureProvider<Map<String, XrayTaskRow>>((ref) {
  ref.watch(readTickProvider);
  ref.watch(xrayRevisionProvider);
  return ref.watch(xrayDaoProvider).taskByBookIds();
});

/// 书架长按「生成/管理全书索引」→ 阅读页落地自动开 X-Ray 段的一次性接力旗。
final readerXrOpenTabProvider = StateProvider<String?>((ref) => null);

/// 选区迷你卡「查看全部位置」→ 面板直达该词条详情（批B F6）。
final readerXrFocusWordProvider = StateProvider<String?>((ref) => null);

/// 选区「X-Ray」未命中 → 面板自动开「加为词条」弹层并预填（批B F8①）。
final readerXrAddWordProvider = StateProvider<String?>((ref) => null);
