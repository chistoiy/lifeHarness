import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批2a · L4/L16 计算下沉单测（分桶 / 双维度 Top15 / 环比 / 洞察规则边界 /
/// 年度聚合；口径=剔 nb、refund 冲抵，同 mStat/catStat）。
void main() {
  LedgerTxn t(
    String kind,
    double amt, {
    int? cat = 101,
    String sub = '',
    String date = '2026-09-10',
    bool nb = false,
    String note = '',
  }) =>
      LedgerTxn(
        kind: kind,
        amt: amt,
        catId: cat,
        sub: sub,
        accountId: 1,
        date: date,
        nb: nb,
        note: note,
        bk: 1,
      );

  group('1 · shiftDays / repRange 周期分桶（原型 repRange 行为）', () {
    test('shiftDays 跨月跨年', () {
      expect(shiftDays('2026-09-30', 1), '2026-10-01');
      expect(shiftDays('2026-01-01', -1), '2025-12-31');
      expect(shiftDays('2026-09-23', 0), '2026-09-23');
    });

    test('月视图：按日分桶 · 标签不补零 · 区间起止/天数', () {
      final r = repRange(period: 'month', today: '2026-09-23', month: '2026-02');
      expect(r.s, '2026-02-01');
      expect(r.e, '2026-02-28');
      expect(r.days, 28);
      expect(r.label, '2026年2月');
      expect(r.monthlyAvg, isFalse);
      expect(r.buckets.length, 28);
      expect(r.buckets.first.label, '1');
      expect(r.buckets.first.s, '2026-02-01');
      expect(r.buckets.last.e, '2026-02-28');
    });

    test('月视图闰年 2 月 29 桶', () {
      final r = repRange(period: 'month', today: '2024-02-10', month: '2024-02');
      expect(r.buckets.length, 29);
    });

    test('年视图：12 个月桶 · monthlyAvg · 标签 N月', () {
      final r = repRange(period: 'year', today: '2026-09-23', month: '2026-09');
      expect(r.s, '2026-01-01');
      expect(r.e, '2026-12-31');
      expect(r.label, '2026年');
      expect(r.monthlyAvg, isTrue);
      expect(r.buckets.length, 12);
      expect(r.buckets[0].label, '1月');
      expect(r.buckets[1].s, '2026-02-01');
      expect(r.buckets[1].e, '2026-02-28');
      expect(r.buckets[11].e, '2026-12-31');
    });

    test('周视图：近 7 天止于 today · weekOffset 按 7 天平移', () {
      final r =
          repRange(period: 'week', today: '2026-09-23', month: '2026-09');
      expect(r.label, '近 7 天');
      expect(r.s, '2026-09-17');
      expect(r.e, '2026-09-23');
      expect(r.buckets.length, 7);
      expect(r.buckets.first.label, '17');
      expect(r.buckets.last.label, '23');
      final back = repRange(
          period: 'week', today: '2026-09-23', month: '2026-09', weekOffset: -1);
      expect(back.s, '2026-09-10');
      expect(back.e, '2026-09-16');
      expect(back.label, '09-10 ~ 09-16');
    });

    test('自定义：默认起=月首止=today · 62 桶上限 · 起>止 空桶', () {
      final r = repRange(period: 'custom', today: '2026-09-23', month: '2026-09');
      expect(r.s, '2026-09-01');
      expect(r.e, '2026-09-23');
      expect(r.buckets.length, 23);
      expect(r.label, '09-01 ~ 09-23');
      final long = repRange(
        period: 'custom',
        today: '2026-12-31',
        month: '2026-01',
        from: '2026-01-01',
        to: '2026-12-31',
      );
      expect(long.buckets.length, 62);
      final empty = repRange(
        period: 'custom',
        today: '2026-09-23',
        month: '2026-09',
        from: '2026-10-01',
        to: '2026-09-23',
      );
      expect(empty.buckets, isEmpty);
    });

    test('repPrevWindow：起点前平移整段（月视图=上期）', () {
      final r = repRange(period: 'month', today: '2026-09-23', month: '2026-09');
      final (ps, pe) = repPrevWindow(r);
      expect(pe, '2026-08-31');
      expect(ps, '2026-08-02');
    });

    test('momPct：上期无数据回 0', () {
      expect(momPct(190, 100), 90);
      expect(momPct(10, 0), 0);
    });
  });

  group('2 · 区间聚合 / 双维度排行 / 钻取 / Top', () {
    final list = [
      t(LedgerTxn.kExpense, 100, date: '2026-09-05'),
      t(LedgerTxn.kExpense, 50, cat: 102, date: '2026-09-10'),
      t(LedgerTxn.kRefund, 30, date: '2026-09-12'),
      t(LedgerTxn.kIncome, 999, cat: 201, date: '2026-09-10'),
      t(LedgerTxn.kTransfer, 500, cat: null, date: '2026-09-10'),
      t(LedgerTxn.kExpense, 888, cat: 103, nb: true, date: '2026-09-10'),
    ];

    test('txnsBetween 闭区间过滤', () {
      final got = txnsBetween(list, '2026-09-05', '2026-09-10');
      expect(got.length, 5); // 仅按日期过滤（transfer/nb 也在内，聚合层再剔）
      expect(txnsBetween(list, '2026-09-13', '2026-09-30'), isEmpty);
    });

    test('repTrend：柱/曲线共用 buckets · refund 冲抵 · nb 剔除', () {
      final r = repRange(period: 'month', today: '2026-09-23', month: '2026-09');
      final bs = repTrend(list, r);
      expect(bs.length, 30);
      final d5 = bs.firstWhere((b) => b.label == '5');
      expect(d5.exp, 100);
      final d10 = bs.firstWhere((b) => b.label == '10');
      expect(d10.exp, 50); // nb=888 与 transfer=500 均不计
      expect(d10.inc, 999);
      final d12 = bs.firstWhere((b) => b.label == '12');
      expect(d12.exp, -30);
      expect(bs.fold<double>(0, (a, b) => a + b.exp), 120);
    });

    test('rankAgg 大类：expense 累加 refund 冲抵 · 收入/转账/nb 不进 · v>0 降序', () {
      final rank = rankAgg(list, bySub: false);
      expect(rank, [('101', 70.0), ('102', 50.0)]);
    });

    test('rankAgg 小类：空 sub 归 cat| · 截 Top15（大类维度不截）', () {
      final many = [
        for (var i = 0; i < 16; i++)
          t(LedgerTxn.kExpense, (i + 1) * 10.0, cat: 101, sub: 's$i'),
      ];
      final sub = rankAgg(many, bySub: true);
      expect(sub.length, 15);
      expect(sub.first, ('101|s15', 160.0));
      expect(sub.any((e) => e.$1 == '101|s0'), isFalse); // 最小值被截掉
      final cats = [
        for (var i = 0; i < 20; i++) t(LedgerTxn.kExpense, 10, cat: 100 + i),
      ];
      expect(rankAgg(cats, bySub: false).length, 20);
    });

    test('rankAgg 全退款类目净额 ≤0 被剔除', () {
      final neg = [
        t(LedgerTxn.kExpense, 10, cat: 104),
        t(LedgerTxn.kRefund, 30, cat: 104),
      ];
      expect(rankAgg(neg, bySub: false), isEmpty);
    });

    test('drillTxns：仅 expense/refund · 按当前键 · 日期降序', () {
      final all = txnsBetween(list, '2026-09-01', '2026-09-30');
      final d = drillTxns(all, key: '101', bySub: false);
      expect(d.map((e) => e.date), ['2026-09-12', '2026-09-05']);
      expect(drillTxns(all, key: '201', bySub: false), isEmpty); // 收入不钻
      expect(drillTxns(all, key: '103', bySub: false), isEmpty); // nb 不钻
    });

    test('topNotes：备注聚合 · 空备注回落类目名 · 截 5', () {
      final rows = [
        t(LedgerTxn.kExpense, 10, note: 'a'),
        t(LedgerTxn.kExpense, 20, note: 'b'),
        t(LedgerTxn.kExpense, 30, note: 'a'),
        t(LedgerTxn.kExpense, 35, note: 'c'),
        t(LedgerTxn.kExpense, 50, note: 'd'),
        t(LedgerTxn.kExpense, 60, note: 'e'),
        t(LedgerTxn.kExpense, 70, note: ''), // → 餐饮
        t(LedgerTxn.kRefund, 99, note: 'f'), // refund 不进 Top
        t(LedgerTxn.kExpense, 99, note: 'g', nb: true), // nb 不进
      ];
      final top = topNotes(rows, nameOf: (x) => '餐饮');
      expect(top.length, 5);
      expect(top.first, ('餐饮', 70.0));
      expect(top.map((e) => e.$1), ['餐饮', 'e', 'd', 'a', 'c']);
    });
  });

  group('3 · yearStat（L16 口径）', () {
    final rows = [
      t(LedgerTxn.kExpense, 120, date: '2026-03-05', note: '聚餐'),
      t(LedgerTxn.kExpense, 60, cat: 102, date: '2026-03-06'),
      t(LedgerTxn.kRefund, 20, date: '2026-08-01'),
      t(LedgerTxn.kIncome, 5000, cat: 201, date: '2026-03-06'),
      t(LedgerTxn.kExpense, 999, cat: 103, nb: true, date: '2026-03-06'),
      t(LedgerTxn.kExpense, 700, date: '2025-06-10'), // 别年
    ];

    test('总支出/收入/笔数/记账天数/最大单笔/排行/月桶', () {
      final y = yearStat(rows, '2026');
      expect(y.exp, 160); // 120+60−20（nb 与别年剔除）
      expect(y.inc, 5000);
      expect(y.cnt, 3); // expense×2 + income×1（refund 不计笔数）
      expect(y.actDays, 2); // 03-05 / 03-06
      expect(y.big?.note, '聚餐');
      expect(y.rank, [(101, 100.0), (102, 60.0)]);
      expect(y.months.length, 12);
      expect(y.months[2].exp, 180); // 3 月支出（refund 在 8 月）
      expect(y.months[7].exp, -20);
      expect(y.months[0].exp, 0);
      expect(y.avgDaily, closeTo(160 / 365, 1e-9));
    });

    test('空年份：全 0 且 big=null', () {
      final y = yearStat(rows, '2024');
      expect(y.exp, 0);
      expect(y.cnt, 0);
      expect(y.actDays, 0);
      expect(y.big, isNull);
      expect(y.rank, isEmpty);
    });
  });

  group('4 · 报表消费洞察规则边界（九·补3 接线输入）', () {
    test('环比 ±5% 三档分界', () {
      (String, String) at(double curExp) {
        final r = spendingInsights(
          cur: MStat(exp: curExp, inc: 0),
          prevExp: 100,
          topRank: null,
          totalExp: curExp,
          budgetTotal: 0,
          biggest: null,
        );
        return (r.first.$1, r.first.$3);
      }

      expect(at(105).$1, '注意'); // cmp=+5 → 增加 5%
      expect(at(105).$2, '支出较上期增加 5%');
      expect(at(95).$1, '优秀'); // cmp=−5 → 减少 5%
      expect(at(104).$1, '合理'); // |cmp|<5 持平
      expect(at(104).$2, '支出与上期基本持平');
    });

    test('预算 90% / 超支 / 缺失回落', () {
      final r90 = spendingInsights(
        cur: MStat(exp: 180, inc: 0),
        prevExp: 0,
        topRank: null,
        totalExp: 0,
        budgetTotal: 200,
        biggest: null,
      );
      expect(r90.first, ('注意', 'target', '预算已用 90%', '剩余 ${money(20)}'));
      final over = spendingInsights(
        cur: MStat(exp: 260, inc: 0),
        prevExp: 0,
        topRank: null,
        totalExp: 0,
        budgetTotal: 200,
        biggest: null,
      );
      expect(over.first.$1, '注意');
      expect(over.first.$3, '本期预算已超支 ${money(60)}');
      final none = spendingInsights(
        cur: MStat(exp: 180, inc: 0),
        prevExp: 0,
        topRank: null,
        totalExp: 0,
        budgetTotal: 0, // 预算缺失 → 无预算条
        biggest: null,
      );
      expect(none, isEmpty);
    });

    test('主要支出占比 40% 分界 · topRank 缺失跳过', () {
      final lo = spendingInsights(
        cur: MStat(exp: 200, inc: 0),
        prevExp: 0,
        topRank: ('餐饮', 60),
        totalExp: 200,
        budgetTotal: 0,
        biggest: null,
      );
      expect(lo.first, ('合理', 'pie', '餐饮是主要支出', '占比 30% · 共 ${money(60)}'));
      final hi = spendingInsights(
        cur: MStat(exp: 200, inc: 0),
        prevExp: 0,
        topRank: ('餐饮', 120),
        totalExp: 200,
        budgetTotal: 0,
        biggest: null,
      );
      expect(hi.first.$1, '注意'); // 60% ≥ 40
      expect(hi.first.$3, '餐饮是主要支出');
      final none = spendingInsights(
        cur: MStat(exp: 200, inc: 0),
        prevExp: 0,
        topRank: null,
        totalExp: 200,
        budgetTotal: 0,
        biggest: null,
      );
      expect(none, isEmpty);
    });
  });
}
