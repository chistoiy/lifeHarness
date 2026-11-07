import 'book.dart';

/// 记进度四方式纯函数（计划 §3.4 openProgress / AC 第九章）。
///
/// 入参 [value] 按方式解释：page=页码、pos=位置(loc)、pct=百分比 0~100、
/// chap=选中章节（配 [chapterTitle]/[chapterStartPage]）。
/// 返回 books 行增量 map（read_pages/read_loc/chapter），边界：
/// total_loc 或 pages 为 0 时不做折算、pos>total 钳到 100%。
Map<String, Object?> progressPatch(
  Book b,
  String way,
  double? value, {
  String? chapterTitle,
  int? chapterStartPage,
}) {
  final patch = <String, Object?>{};
  void setPct(double p) {
    p = p.clamp(0, 100);
    if (b.pages > 0) patch['read_pages'] = (p / 100 * b.pages).round();
    if ((b.totalLoc ?? 0) > 0) patch['read_loc'] = p / 100 * b.totalLoc!;
  }

  switch (way) {
    case Book.kWayPage:
      final v = value?.round() ?? 0;
      patch['read_pages'] = b.pages > 0 ? v.clamp(0, b.pages) : v;
      if ((b.totalLoc ?? 0) > 0 && b.pages > 0) {
        patch['read_loc'] =
            (patch['read_pages'] as int) / b.pages * b.totalLoc!;
      }
    case Book.kWayPos:
      final tot = b.totalLoc ?? 0;
      final v = (value ?? 0).clamp(0, tot > 0 ? tot : double.infinity);
      patch['read_loc'] = v;
      if (tot > 0 && b.pages > 0) {
        patch['read_pages'] = (v / tot * b.pages).round();
      }
    case Book.kWayPct:
      setPct(value ?? 0);
    case Book.kWayChap:
      patch['chapter'] = chapterTitle;
      if (chapterStartPage != null) {
        patch['read_pages'] = b.pages > 0
            ? chapterStartPage.clamp(0, b.pages)
            : chapterStartPage;
      }
    case Book.kWayMin:
      patch['read_loc'] = value; // 有声：位置列承载分钟数
  }
  return patch;
}

/// 位置 ↔ 页 折算（AC 边界：总位置 0 或总页数 0 返回 null 不崩）。
int? pageFromLoc(Book b, double loc) => (b.totalLoc ?? 0) > 0 && b.pages > 0
    ? (loc / b.totalLoc! * b.pages).round()
    : null;

double? locFromPage(Book b, int page) =>
    (b.totalLoc ?? 0) > 0 && b.pages > 0 ? page / b.pages * b.totalLoc! : null;

/// 均速 / 预计剩余 / 预计读完日（原型 openProgress 三行；页口径）。
class ProgressForecast {
  const ProgressForecast({
    required this.pagesPerDay,
    required this.remainPages,
    this.etaDays,
    this.finishAt,
  });

  final double pagesPerDay;
  final int remainPages;
  final int? etaDays;
  final DateTime? finishAt;

  static ProgressForecast of(Book b, {int? firstActivityMs, DateTime? now}) {
    final nowTs = now ?? DateTime.now();
    if (b.pages <= 0 || b.readPages <= 0) {
      return ProgressForecast(
        pagesPerDay: 0,
        remainPages: b.pages - b.readPages,
      );
    }
    final fromMs = [
      b.startedAt,
      firstActivityMs,
      b.createdAt,
    ].whereType<int>().reduce((a, c) => a < c ? a : c);
    final from = DateTime.fromMillisecondsSinceEpoch(fromMs);
    final days = nowTs.difference(from).inDays + 1; // 首日即按 1 天
    final ppd = b.readPages / days;
    final remain = (b.pages - b.readPages).clamp(0, b.pages);
    if (ppd <= 0 || remain <= 0) {
      return ProgressForecast(
        pagesPerDay: ppd,
        remainPages: remain,
        etaDays: remain <= 0 ? 0 : null,
      );
    }
    final eta = (remain / ppd).ceil();
    return ProgressForecast(
      pagesPerDay: ppd,
      remainPages: remain,
      etaDays: eta,
      finishAt: DateTime(nowTs.year, nowTs.month, nowTs.day + eta),
    );
  }
}

/// 剩余/读完日文案（无教学语，仅状态短语）。
String forecastLabel(ProgressForecast f) {
  if (f.remainPages <= 0 && f.pagesPerDay > 0) return '已读完';
  if (f.etaDays == null || f.finishAt == null) return '暂无均速数据';
  final d = f.finishAt!;
  return '预计 ${d.month}/${d.day} 读完 · 剩 ${f.etaDays} 天';
}
