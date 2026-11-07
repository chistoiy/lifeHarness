import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/domain/diary_filter_kit.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';

/// 日记改版批2d · 筛选「时间段」纯逻辑（对齐原型 `DIARY_RANGES` / `dwInRange` / `dfRangeName`）。
///
/// 这一批此前**整段缺失**：实现侧筛选只有「标记」「标签」两维，原型里 8 档预设
/// 与自定义起止的能力压根没落。补的时候最容易错的不是 UI，是三条边界：
/// ① 相对天数窗是**闭区间**且以「今天 0 点」为基准（`7d` ⇒ 0..6，不是 0..7）；
/// ② `month` 是**上一个自然月**（不是本自然月），一月要回退到去年十二月；
/// ③ `custom` 一端留空＝开区间，`from > to` 才是非法。
/// 全部用**注入 now** 钉住——不注入的话这些用例会随「今天是几号」漂移。
void main() {
  // 固定基准日：2026-10-19 00:00（本地时区，与生产一致）。
  final now = DateTime(2026, 10, 19);

  JournalEntry at(int daysAgo) {
    final d = now.subtract(Duration(days: daysAgo));
    return JournalEntry(
      day: d,
      content: '测试',
      createdAt: d,
      updatedAt: d,
    );
  }

  group('R1~R5 相对天数窗（闭区间·含今天·不含未来）', () {
    // 档位 → 最大允许天数差。逐档验「边界那篇进、边界 +1 那篇不进」。
    const windows = [
      ('7d', 6),
      ('30d', 29),
      ('90d', 89),
      ('1y', 364),
      ('2y', 729),
    ];
    for (final (k, max) in windows) {
      test('$k 含第 $max 天、不含第 ${max + 1} 天', () {
        expect(diaryInRange(at(max), range: k, now: now), isTrue,
            reason: '$k 的窗口是 0..$max（闭区间）');
        expect(diaryInRange(at(max + 1), range: k, now: now), isFalse,
            reason: '$k 不该把 ${max + 1} 天前算进来');
      });
    }

    test('全部档位都含今天、都不含明天', () {
      for (final (k, _) in windows) {
        expect(diaryInRange(at(0), range: k, now: now), isTrue,
            reason: '$k 必须含今天');
        expect(diaryInRange(at(-1), range: k, now: now), isFalse,
            reason: '$k 不能把明天算进来（日记是已发生的事）');
      }
    });

    test('all 恒真（不设限，未来也放行——它是「关闭筛选」而不是「近 N 天」）', () {
      expect(diaryInRange(at(9999), range: 'all', now: now), isTrue);
      expect(diaryInRange(at(-30), range: 'all', now: now), isTrue);
    });
  });

  group('R6~R7 自然年 / 上月', () {
    test('year 只认当年', () {
      expect(diaryInRange(at(0), range: 'year', now: now), isTrue);
      expect(
        diaryInRange(JournalEntry(
            day: DateTime(2025, 12, 31),
            content: '',
            createdAt: now,
            updatedAt: now), range: 'year', now: now),
        isFalse,
      );
      expect(
        diaryInRange(JournalEntry(
            day: DateTime(2026, 1, 1),
            content: '',
            createdAt: now,
            updatedAt: now), range: 'year', now: now),
        isTrue,
      );
    });

    test('month 是上一个自然月（10 月看 9 月，不是 10 月）', () {
      expect(
        diaryInRange(JournalEntry(
            day: DateTime(2026, 9, 1),
            content: '',
            createdAt: now,
            updatedAt: now), range: 'month', now: now),
        isTrue,
      );
      expect(
        diaryInRange(JournalEntry(
            day: DateTime(2026, 9, 30),
            content: '',
            createdAt: now,
            updatedAt: now), range: 'month', now: now),
        isTrue,
      );
      // 本自然月不算「上月」
      expect(diaryInRange(at(0), range: 'month', now: now), isFalse);
      // 上上个月也不算
      expect(
        diaryInRange(JournalEntry(
            day: DateTime(2026, 8, 31),
            content: '',
            createdAt: now,
            updatedAt: now), range: 'month', now: now),
        isFalse,
      );
    });

    test('month 一月要回退到去年十二月（跨年边界）', () {
      final jan = DateTime(2026, 1, 15);
      expect(
        diaryInRange(JournalEntry(
            day: DateTime(2025, 12, 20),
            content: '',
            createdAt: jan,
            updatedAt: jan), range: 'month', now: jan),
        isTrue,
        reason: '一月时「上月」＝去年十二月，用 now.year 比会把整年的人筛成空',
      );
      expect(
        diaryInRange(JournalEntry(
            day: DateTime(2026, 1, 5),
            content: '',
            createdAt: jan,
            updatedAt: jan), range: 'month', now: jan),
        isFalse,
      );
    });
  });

  group('R8~R10 自定义区间', () {
    JournalEntry on(int y, int m, int d) => JournalEntry(
          day: DateTime(y, m, d),
          content: '',
          createdAt: now,
          updatedAt: now,
        );

    test('两端齐：闭区间，两端各进、越界各出', () {
      bool hit(int y, int m, int d) => diaryInRange(on(y, m, d),
          range: kDiaryRangeCustom,
          from: '2026-01-01',
          to: '2026-06-30',
          now: now);
      expect(hit(2026, 1, 1), isTrue, reason: '起始日当天算在区间内');
      expect(hit(2026, 6, 30), isTrue, reason: '结束日当天算在区间内');
      expect(hit(2026, 3, 15), isTrue);
      expect(hit(2025, 12, 31), isFalse);
      expect(hit(2026, 7, 1), isFalse);
    });

    test('只填起始＝「某日之后」开区间', () {
      bool hit(int y, int m, int d) => diaryInRange(on(y, m, d),
          range: kDiaryRangeCustom, from: '2026-06-01', to: '', now: now);
      expect(hit(2026, 6, 1), isTrue);
      expect(hit(2026, 12, 31), isTrue, reason: '没有上界，多晚都算');
      expect(hit(2026, 5, 31), isFalse);
    });

    test('只填结束＝「某日之前」开区间', () {
      bool hit(int y, int m, int d) => diaryInRange(on(y, m, d),
          range: kDiaryRangeCustom, from: '', to: '2026-06-30', now: now);
      expect(hit(2026, 6, 30), isTrue);
      expect(hit(2020, 1, 1), isTrue, reason: '没有下界，多早都算');
      expect(hit(2026, 7, 1), isFalse);
    });

    test('两端都空＝不设限（等价全部，不是空集）', () {
      expect(
        diaryInRange(on(2020, 1, 1), range: kDiaryRangeCustom, now: now),
        isTrue,
      );
    });

    test('日期串比大小而不是比时间差：月份/日期补零后字典序即时间序', () {
      // 若哪天有人把 dfIsoDate 换成 toIso8601String（带时刻），'2026-1-5' 与
      // '2026-01-05' 的字典序会错位，这条会红。
      expect(dfIsoDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dfIsoDate(DateTime(2026, 12, 31)), '2026-12-31');
      expect(
        diaryInRange(on(2026, 1, 9),
            range: kDiaryRangeCustom,
            from: '2026-01-10',
            to: '',
            now: now),
        isFalse,
      );
    });
  });

  group('R11 脏档位不设限（宁可多显示，不把日记藏没）', () {
    test('未知键返回 true', () {
      expect(diaryInRange(at(0), range: 'bogus', now: now), isTrue);
    });
  });

  group('R12 显示名兜底（原型 dfRangeName）', () {
    test('预设档走表名', () {
      expect(dfRangeName('7d'), '近 7 天');
      expect(dfRangeName('month'), '上月');
      expect(dfRangeName('2y'), '近两年');
      expect(dfRangeName('all'), '全部');
    });

    test('custom 四种兜名', () {
      expect(
          dfRangeName(kDiaryRangeCustom, from: '2026-01-01', to: '2026-06-30'),
          '2026-01-01 至 2026-06-30');
      expect(dfRangeName(kDiaryRangeCustom, from: '2026-01-01'), '2026-01-01 起');
      expect(dfRangeName(kDiaryRangeCustom, to: '2026-06-30'), '2026-06-30 前');
      expect(dfRangeName(kDiaryRangeCustom), '自定义');
    });

    test('脏键回落「全部」', () {
      expect(dfRangeName('bogus'), '全部');
    });
  });

  group('R13 应用按钮可点判据（一端可空＝开区间，from>to 非法）', () {
    test('两端都空：不给点（还没选）', () {
      expect(dfRangeValid(), isFalse);
    });

    test('一端非空：可点（开区间）', () {
      expect(dfRangeValid(from: '2026-01-01'), isTrue);
      expect(dfRangeValid(to: '2026-01-01'), isTrue);
    });

    test('from > to：不给点', () {
      expect(dfRangeValid(from: '2026-06-30', to: '2026-01-01'), isFalse);
    });

    test('from == to：可点（单日区间）', () {
      expect(dfRangeValid(from: '2026-01-01', to: '2026-01-01'), isTrue);
    });
  });

  group('R14 底部计数文案（原型 renderDfCount）', () {
    test('无条件：共 N 篇日记', () {
      expect(dfCountLabel(n: 3), '共 3 篇日记');
    });

    test('只选标记：当前筛选：待办，共 N 篇', () {
      expect(dfCountLabel(n: 3, mark: 'todo'), '当前筛选：待办，共 3 篇');
    });

    test('选的是标签：输出 #名字（不能显示成「全部」）', () {
      // 这一步踩过：`dfMarkLabel` 对未知键回「全部」，
      // 直接把键丢进去会出现「当前筛选：全部」——筛选明明生效了却显示没筛。
      expect(dfCountLabel(n: 1, mark: '复盘'), '当前筛选：#复盘，共 1 篇');
    });

    test('标记 + 时间段：用 · 连接', () {
      expect(dfCountLabel(n: 2, mark: 'todo', range: '7d'),
          '当前筛选：待办 · 近 7 天，共 2 篇');
    });

    test('时间段 custom：说出区间', () {
      expect(
        dfCountLabel(
            n: 5, range: kDiaryRangeCustom, from: '2026-01-01', to: '2026-06-30'),
        '当前筛选：2026-01-01 至 2026-06-30，共 5 篇',
      );
    });
  });

  group('R15 档位表形状（顺序＝原型字面序，别按跨度重排）', () {
    test('8 档，all 在最前，其余按原型次序', () {
      expect(kDiaryRanges.length, 8);
      expect(kDiaryRanges.first.k, 'all');
      expect(kDiaryRanges.map((r) => r.k).toList(),
          ['all', '7d', '30d', '90d', 'year', 'month', '1y', '2y']);
    });

    test('custom 不在预设表里，但属于合法落盘键', () {
      expect(kDiaryRanges.any((r) => r.k == kDiaryRangeCustom), isFalse,
          reason: 'custom 是「应用后」的态，不是一枚预设胶囊');
      expect(kDiaryRangeKeys.contains(kDiaryRangeCustom), isTrue);
      expect(kDiaryRangeKeys.length, 9);
    });
  });
}
