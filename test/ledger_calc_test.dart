import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批1a · 口径纯函数（计划 §8：四则求值含 12+3×4、除零、连续算子；
/// mStat/catStat 双口径；24 指标抽样；chips 回落）。
void main() {
  group('1 · 四则键盘求值（先乘除后加减）', () {
    test('12+3×4=24', () => expect(exprVal('12+3×4'), 24));
    test('连加连减 1.5+2−0.5=3', () => expect(exprVal('1.5+2−0.5'), 3));
    test('先乘后加再除 100÷4+5×2=35',
        () => expect(exprVal('100÷4+5×2'), 35));
    test('除零回退左值 8÷0=8', () => expect(exprVal('8÷0'), 8));
    test('小数点截断 0.1+0.2=0.3', () => expect(exprVal('0.1+0.2'), 0.3));
    test('负结果夹到 0：3−10=0', () => expect(exprVal('3−10'), 0));
    test('纯数字 12.34', () => expect(exprVal('12.34'), 12.34));
    test('空串=0', () => expect(exprVal(''), 0));
    test('末位运算子防御：5×=0（右缺省按 0）', () => expect(exprVal('5×'), 0));
    test('小数点每段唯一 / 单段最长 9 位', () {
      expect(exprDigitAllowed('1.2', '.'), isFalse);
      expect(exprDigitAllowed('12', '.'), isTrue);
      expect(exprDigitAllowed('123456789', '9'), isFalse);
      expect(exprDigitAllowed('1+123456789', '9'), isFalse);
      expect(exprDigitAllowed('1+2345678', '9'), isTrue);
    });
  });

  group('2 · 聚合口径（unpaid/nb/refund/transfer/adjust）', () {
    LedgerTxn t(
      String kind, {
      double amt = 10,
      int? cat = 101,
      bool nb = false,
      bool unpaid = false,
      String date = '2026-09-10',
      int? to,
    }) =>
        LedgerTxn(
          kind: kind,
          amt: amt,
          catId: cat,
          accountId: 1,
          toAccountId: to,
          date: date,
          nb: nb,
          unpaid: unpaid,
          bk: 1,
        );

    test('mStat：支出含 unpaid、剔除 nb；退款冲抵为负支出', () {
      final s = mStat([
        t(LedgerTxn.kExpense, amt: 100),
        t(LedgerTxn.kExpense, amt: 30, unpaid: true),
        t(LedgerTxn.kExpense, amt: 70, nb: true),
        t(LedgerTxn.kIncome, amt: 500, cat: 201),
        t(LedgerTxn.kRefund, amt: 40, cat: 101),
        t(LedgerTxn.kTransfer, amt: 999, cat: null, to: 2),
        t(LedgerTxn.kAdjust, amt: -50, cat: null),
      ]);
      expect(s.exp, 90); // 100+30−40；nb/transfer/adjust 不计
      expect(s.inc, 500);
      expect(s.net, 410);
    });

    test('catStat：>0 过滤、降序；withNb 可含不计入行', () {
      final c = catStat([
        t(LedgerTxn.kExpense, amt: 50, cat: 101),
        t(LedgerTxn.kExpense, amt: 80, cat: 102),
        t(LedgerTxn.kRefund, amt: 80, cat: 102),
        t(LedgerTxn.kExpense, amt: 20, cat: 103, nb: true),
      ]);
      expect(c.map((e) => e.$1), [101]);
      final c2 = catStat(
          [
            t(LedgerTxn.kExpense, amt: 20, cat: 103, nb: true),
            t(LedgerTxn.kExpense, amt: 5, cat: 101),
          ],
          withNb: true);
      expect(c2.first.$1, 103);
    });

    test('dayMap：日支出含分类集；退款冲抵', () {
      final d = dayMap([
        t(LedgerTxn.kExpense, amt: 12, cat: 101, date: '2026-09-10'),
        t(LedgerTxn.kExpense, amt: 8, cat: 102, date: '2026-09-10'),
        t(LedgerTxn.kRefund, amt: 5, cat: 101, date: '2026-09-10'),
        t(LedgerTxn.kIncome, amt: 3, cat: 201, date: '2026-09-11'),
      ]);
      expect(d[10]!.exp, 15);
      expect(d[10]!.cats, {101, 102});
      expect(d[11]!.inc, 3);
    });

    test('eff：unpaid 不动余额；transfer 双向；adjust 原样', () {
      expect(t(LedgerTxn.kExpense, amt: 10, unpaid: true).eff(1), 0);
      expect(t(LedgerTxn.kExpense, amt: 10).eff(1), -10);
      expect(t(LedgerTxn.kExpense, amt: 10).eff(2), 0);
      final tr = t(LedgerTxn.kTransfer, amt: 40, cat: null, to: 2);
      expect(tr.eff(1), -40);
      expect(tr.eff(2), 40);
      expect(t(LedgerTxn.kAdjust, amt: -50, cat: null).eff(1), -50);
      expect(t(LedgerTxn.kRefund, amt: 40).eff(1), 40);
      expect(t(LedgerTxn.kRefund, amt: 40, unpaid: true).eff(1), 0);
    });
  });

  group('3 · chips（收藏 ∪ 近30天高频 · 截12 · 按收支树过滤）', () {
    test('收入树内不出现支出分类；高频去重排序', () {
      final last30 = [
        for (var i = 0; i < 3; i++)
          LedgerTxn(kind: LedgerTxn.kExpense, amt: 10, catId: 101, sub: '午餐', accountId: 1, date: '2026-09-10', bk: 1),
        LedgerTxn(kind: LedgerTxn.kExpense, amt: 10, catId: 101, sub: '晚餐', accountId: 1, date: '2026-09-10', bk: 1),
        LedgerTxn(kind: LedgerTxn.kExpense, amt: 10, catId: 103, sub: '数码', accountId: 1, date: '2026-09-10', bk: 1),
        LedgerTxn(kind: LedgerTxn.kIncome, amt: 10, catId: 201, sub: '月薪', accountId: 1, date: '2026-09-10', bk: 1),
      ];
      final expenseTree = {101, 102, 103};
      final chips = recentFavChips(
        last30: last30,
        favs: [(102, '打车')],
        treeCatIds: expenseTree,
      );
      expect(chips.first, (102, '打车')); // 收藏恒前
      expect(chips[1], (101, '午餐')); // 高频次之
      expect(chips.every((c) => expenseTree.contains(c.$1)), isTrue);
      expect(chips, isNot(contains((201, '月薪'))));
    });
  });

  group('4 · 月份/日期工具', () {
    test('monthStep 跨年', () {
      expect(monthStep('2026-01', -1), '2025-12');
      expect(monthStep('2026-12', 1), '2027-01');
      expect(monthStep('2026-09', -8), '2026-01');
    });
    test('monthDayCount 含闰年', () {
      expect(monthDayCount('2024-02'), 29);
      expect(monthDayCount('2026-02'), 28);
      expect(monthDayCount('2026-09'), 30);
    });
    test('wdOf 与 money 格式', () {
      expect(wdOf('2026-09-23'), '三'); // 周三
      expect(money(1234567.5), '¥1,234,567.50');
      expect(amtText(-2.5), '¥2.50'); // money 取绝对值，符号由 signedAmt
      expect(signedAmt(-2.5), '-¥2.50');
      expect(amtText(9, hide: true), '¥•••••');
    });
  });

  group('5 · 24 指标抽样（九·补5 口径）', () {
    LedgerTxn t(String kind, double amt, String date, {int? cat, bool nb = false}) =>
        LedgerTxn(
            kind: kind,
            amt: amt,
            catId: cat,
            accountId: 1,
            date: date,
            nb: nb,
            bk: 1);

    final ctx = FinMetricCtx.build(
      bookTxns: [
        t(LedgerTxn.kExpense, 100, '2026-09-23', cat: 101), // 今日
        t(LedgerTxn.kIncome, 300, '2026-09-23', cat: 201),
        t(LedgerTxn.kExpense, 50, '2026-09-01', cat: 102),
        t(LedgerTxn.kExpense, 77, '2026-08-31', cat: 102), // 出月
        t(LedgerTxn.kExpense, 999, '2026-09-10', cat: 103, nb: true), // 不计入
      ],
      today: '2026-09-23',
      month: '2026-09',
      budgetTotal: 1200,
      balances: [500, -200],
    );

    test('今日/本月窗口与 nb 剔除', () {
      expect(finMetricVal('teToday', ctx), 100);
      expect(finMetricVal('balToday', ctx), 200);
      expect(finMetricVal('teMonth', ctx), 150); // 999 不计入
      expect(finMetricVal('balMonth', ctx), 150); // 300−150
      expect(finMetricVal('teAll', ctx), 227); // 含 8 月
    });
    test('预算三指标：今日预算=月/天数；剩余日预算≥0', () {
      expect(finMetricVal('budToday', ctx), 1200 / 30);
      expect(finMetricVal('budLeft', ctx), 1200 - 150);
      expect(finMetricVal('budDayLeft', ctx), (1200 - 150) / 8);
    });
    test('日均按已过天数', () {
      expect(finMetricVal('avgTe', ctx), 150 / 23);
    });
    test('资产跨账本合并：净资产/总资产/总负债', () {
      expect(finMetricVal('netWorth', ctx), 300);
      expect(finMetricVal('assets', ctx), 500);
      expect(finMetricVal('liab', ctx), 200);
    });
    test('周窗口=周一起始：9-23（周三）所在周含 9-21~9-27', () {
      expect(finMetricVal('teWeek', ctx), 100); // 9-01/8-31 不出周窗
    });
    test('目录齐 24 项且命名对齐原型', () {
      expect(finMetrics, hasLength(24));
      expect(finMetricName('balMonth'), '本月结余');
      expect(finMetricName('budDayLeft'), '剩余日预算');
    });
  });

  group('6 · 消费洞察四规则（无 AI · 三档标签）', () {
    test('占比≥40% 注意 / 环比 ±5% 三档 / 预算 90% 与超支 / 最大单笔', () {
      final ins = spendingInsights(
        cur: const MStat(exp: 1200, inc: 800),
        prevExp: 1000, // +20% → 注意
        topRank: ('餐饮', 600), // 50% → 注意
        totalExp: 1200,
        budgetTotal: 1250, // 96% → 注意
        biggest: ('山姆采购', 899),
      );
      expect(ins, hasLength(4));
      expect(ins.map((e) => e.$1), ['注意', '注意', '注意', '合理']);
      expect(ins.map((e) => e.$3),
          containsAll(['餐饮是主要支出', '支出较上期增加 20%', '预算已用 96%']));
      final ok = spendingInsights(
        cur: const MStat(exp: 500, inc: 800),
        prevExp: 500,
        topRank: ('餐饮', 100),
        totalExp: 500,
        budgetTotal: 1000,
        biggest: null,
      );
      expect(ok.map((e) => e.$1), ['合理', '合理', '合理']);
    });
  });
}
