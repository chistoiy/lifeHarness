# tools/attic/xr_red_clear.py — 存量四红清零：计数漂移/月份时间炸弹/补卡跨月×2
import io

CRLF = chr(13) + chr(10)


def patch(p, pairs):
    s = io.open(p, encoding='utf-8', newline='').read()
    crlf = CRLF in s

    def n(x):
        return x.replace(chr(10), CRLF) if crlf else x

    for a, b in pairs:
        a, b = n(a), n(b)
        assert s.count(a) == 1, (p, a[:50].encode('unicode_escape'), s.count(a))
        s = s.replace(a, b)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


# 1) ai_core_test：0ca64ad 加 read.explain 后提示词包 11→12，断言没跟
patch('test/ai_core_test.dart', [
    ("test('资产可解析：11 个能力点、DeepSeek 默认端点', () {",
     "test('资产可解析：12 个能力点、DeepSeek 默认端点', () {"),
    ("      expect(pack.tasks.length, 11);",
     "      expect(pack.tasks.length, 12);"),
])

# 2) read_data_test 5-5：「本月句」种子写死 2026-09 → 跨月必炸，改当月相对
patch('test/read_data_test.dart', [
    ("""    test('5-5 本月摘录数（L7 第五路）', () async {
      final b = await repo.addBook(Book(title: '甲', createdAt: t0, updatedAt: t0));
      await repo.addQuote(BookQuote(bookId: b.id, kind: '划线', body: '本月句', createdAt: t0, updatedAt: t0));
      await repo.addQuote(BookQuote(bookId: b.id, kind: '划线', body: '去年句', createdAt: DateTime(2025, 5, 5).millisecondsSinceEpoch, updatedAt: t0));""",
     """    test('5-5 本月摘录数（L7 第五路）', () async {
      // 时间炸弹修复（2026-10-01 跨月首现红）：种子必须相对「今天所在月」，
      // 原写死 2026-09/2025-05 每逢月初必炸（日期测试禁时间炸弹口径）。
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, min(now.day, 28));
      final lastYear = DateTime(now.year - 1, 5, 5);
      final b = await repo.addBook(Book(title: '甲', createdAt: t0, updatedAt: t0));
      await repo.addQuote(BookQuote(bookId: b.id, kind: '划线', body: '本月句', createdAt: thisMonth.millisecondsSinceEpoch, updatedAt: t0));
      await repo.addQuote(BookQuote(bookId: b.id, kind: '划线', body: '去年句', createdAt: lastYear.millisecondsSinceEpoch, updatedAt: t0));"""),
])

# 3) habit_backfill_page_test：月初开窗时「昨天」在上个月，日历按月锚定——先翻月再点日
patch('test/habit_backfill_page_test.dart', [
    ("""  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));""",
     """  String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

  /// 补卡日历按月渲染（锚＝今天所在月；可 `btn-hbf-prev` 翻月）。
  /// 月初窗口里「昨天/前天」属上月——存在性检查式翻月，跨月/月内两种日历都成立。
  Future<void> tapDay(WidgetTester tester, String day) async {
    if (find.byKey(ValueKey('hbf-day-$day')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('btn-hbf-prev')));
      await settle5(tester);
    }
    await tester.tap(find.byKey(ValueKey('hbf-day-$day')));
    await settle5(tester);
  }"""),
    ("""    // 选两个过去日 → 确认补卡
    await tester.tap(find.byKey(ValueKey('hbf-day-${key(2)}')));
    await settle5(tester);
    await tester.tap(find.byKey(ValueKey('hbf-day-${key(1)}')));
    await settle5(tester);""",
     """    // 选两个过去日 → 确认补卡（月初时先翻回上月）
    await tapDay(tester, key(2));
    await tapDay(tester, key(1));"""),
    ("""    await tester.tap(find.byKey(ValueKey('hbf-day-${key(1)}')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('btn-hbf-save')));""",
     """    await tapDay(tester, key(1));
    await tester.tap(find.byKey(const ValueKey('btn-hbf-save')));"""),
])
print('red clear ok')
