import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/domain/book_session.dart';

/// 书架查询/排序纯函数（计划 §3.4 触发条 ⇅ 面板；UI 与测试共用一套口径）。
///
/// 排序键（原型 SH_SORTS）：recent 最近阅读 / prog 按进度 / rate 按评分 /
/// added 入架顺序 / name 书名 / pages 总页数。
/// 维度键（原型 SH_DIMS）：none/st/tag/rate/author/pub/src/grp。
class ShelfQuery {
  const ShelfQuery({
    this.state,
    this.kw = '',
    this.dim = 'none',
    this.dimVal = '',
    this.sort = 'recent',
    this.quoteIds = const {},
  });

  final String? state; // 分区筛选；null=全部
  final String kw; // 书名/作者/标签/来源/分组/出版社/摘录原文 模糊（原型 4549）
  final String dim;
  final String dimVal;
  final String sort;

  /// 摘录命中的 book_id 集合（repo.quoteBookIdsMatching 求得；kw 匹配范围之一）。
  final Set<String> quoteIds;

  static int lastReadOf(Book b) =>
      b.lastReadAt ?? b.endedAt ?? b.startedAt ?? b.updatedAt;

  /// 原型 shFiltered 的匹配串：书名+作者+标签+来源+分组+出版社+该书摘录原文。
  bool matchesKw(Book b) {
    if (kw.isEmpty) return true;
    final k = kw.toLowerCase();
    if (b.title.toLowerCase().contains(k) ||
        b.author.toLowerCase().contains(k) ||
        (b.source ?? '').toLowerCase().contains(k) ||
        (b.grp ?? '').toLowerCase().contains(k) ||
        (b.publisher ?? '').toLowerCase().contains(k) ||
        b.tags.any((t) => t.toLowerCase().contains(k)) ||
        quoteIds.contains(b.id)) {
      return true;
    }
    return false;
  }

  List<Book> apply(List<Book> all) {
    var out = all.where((b) => !b.isDeleted).toList();
    if (state != null) out = out.where((b) => b.state == state).toList();
    if (kw.isNotEmpty) out = out.where(matchesKw).toList();
    if (dim != 'none' && dimVal.isNotEmpty) {
      out = out.where((b) => dimValuesOf(b).contains(dimVal)).toList();
    }
    out.sort(
      (a, b) => switch (sort) {
        'prog' => b.percent.compareTo(a.percent),
        'rate' => b.rating.compareTo(a.rating),
        'added' => a.createdAt.compareTo(b.createdAt),
        // 原型 localeCompare(y.n,'zh')＝拼音序；Dart 无内置 zh collation，
        // 工程现有依赖（intl 0.20.2）也不提供 Collator → 需引拼音库才能兑现，暂按码位序。
        'name' => a.title.compareTo(b.title),
        'pages' => b.pages.compareTo(a.pages),
        _ => lastReadOf(b).compareTo(lastReadOf(a)),
      },
    );
    return out;
  }

  /// 单本书在某维度下的归属值（tag 可多值；rate 归入整数星档）。
  List<String> dimValuesOf(Book b) => switch (dim) {
    'st' => [b.state],
    'tag' => b.tags,
    'rate' => b.rating > 0 ? ['${b.rating.floor()} 星'] : const [],
    'author' => [b.author],
    'pub' => [if (b.publisher?.isNotEmpty ?? false) b.publisher!],
    'src' => [if (b.source?.isNotEmpty ?? false) b.source!],
    'grp' => [if (b.grp?.isNotEmpty ?? false) b.grp!],
    _ => const [],
  };

  /// 维度可选值列表（书架二级面板用；rate 降序，其余按书目聚合保序去重）。
  static List<String> dimValues(String dim, List<Book> all) {
    final q = ShelfQuery(dim: dim);
    final set = <String>{};
    for (final b in all.where((b) => !b.isDeleted)) {
      set.addAll(q.dimValuesOf(b));
    }
    final out = set.toList();
    if (dim == 'rate') out.sort((a, b) => b.compareTo(a));
    return out;
  }

  /// 维度值 → 引用该书数（原型 bsBindBtns 5391 值 chips 的 `bmCount` 计数徽标）。
  static Map<String, int> dimValueCounts(String dim, List<Book> all) {
    final q = ShelfQuery(dim: dim);
    final m = <String, int>{};
    for (final b in all.where((b) => !b.isDeleted)) {
      for (final v in q.dimValuesOf(b)) {
        m[v] = (m[v] ?? 0) + 1;
      }
    }
    return m;
  }

  /// 分区计数（chips 带数）。
  static Map<String, int> countsByState(List<Book> all) {
    final m = {for (final s in Book.states) s: 0};
    for (final b in all.where((b) => !b.isDeleted)) {
      m[b.state] = (m[b.state] ?? 0) + 1;
    }
    return m;
  }
}

/// 计时起停语义（单活会话）：全局同时至多一条 running 会话，
/// 对另一本开始会自动结束上一本（与顶部胶囊「当前任务」口径一致）。
/// 结束入账：endedAt < startedAt 直接丢弃（时钟回拨防护 · 计划 §2.4）；
/// [minSecs]＝短会话门槛（轮5.2② read.brMinSecs，默认 30）：不足门槛同样丢弃，
/// 时长与会话都不入账；有实际时长不足 1 分钟按 1 分钟计。
BookSession? closeRunning(BookSession s, int nowMs, {int minSecs = 0}) {
  if (nowMs < s.startedAt) return null; // 回拨：丢弃，由调用方删行
  final elapsed = nowMs - s.startedAt;
  if (minSecs > 0 && elapsed < minSecs * 1000) return null; // 太短：不入账
  return s.copyWith(
    endedAt: nowMs,
    minutes: elapsed <= 0 ? 0 : (elapsed / 60000).ceil(),
  );
}

/// 摘录/会话/状态变更的统一「最后活动」时间（last_read_at 聚合口径 §3.2）。
int maxActivity(Book b, {int? extra}) {
  var v = ShelfQuery.lastReadOf(b);
  if (extra != null && extra > v) v = extra;
  return v;
}

/// 摘录去重键（计划 §5 三级之摘录级）：sha1 依赖 cryptography 包暂不引，
/// 批3 导入前以「bookId|chapter|page|规范化正文」串作等价键（同规则可复算）。
String quoteDedupKey(String bookId, String? chapter, int? page, String body) =>
    '$bookId|${chapter ?? ''}|${page ?? ''}|'
    '${body.replaceAll(RegExp(r'\s+'), '').toLowerCase()}';

/// BookQuote 列表 → book_id 聚合（笔记库三统计/封面卡 q 数）。
Map<String, int> quoteCountByBook(List<BookQuote> qs) {
  final m = <String, int>{};
  for (final q in qs.where((q) => q.deletedAt == null)) {
    m[q.bookId] = (m[q.bookId] ?? 0) + 1;
  }
  return m;
}

/// 会话列表 → 每本累计入账分钟与次数（books.min/times 派生口径）。
Map<String, ({int minutes, int times})> sessionAggByBook(List<BookSession> ss) {
  final m = <String, ({int minutes, int times})>{};
  for (final s in ss) {
    if (s.endedAt == null || s.endedAt! < s.startedAt) continue; // 回拨行不入账
    final cur = m[s.bookId];
    m[s.bookId] = (
      minutes: (cur?.minutes ?? 0) + s.billedMinutes,
      times: (cur?.times ?? 0) + 1,
    );
  }
  return m;
}
