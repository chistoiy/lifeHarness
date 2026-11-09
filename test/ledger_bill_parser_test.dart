import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/ledger/data/bill_parser.dart';

/// 记账批1d · 账单 CSV 解析层单测（纯函数）。

const alipayCsv = '''
支付宝业务流水明细,导出对象:本人
账号,chist***@example.com
起始时间,2026-08-01 00:00:00
终止时间,2026-08-31 23:59:59
导出时间,2026-09-01 10:00:00
----------------------支付宝账单----------------------
交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
2026-08-03 12:01:59,餐饮美食,全家便利店,***,"早餐,咖啡",支出,"¥18.50",余额宝,交易成功,T001,M1,
2026-08-05 09:00:00,收入,***,,工资,收入,"¥8,000.00",支付宝账户余额,交易成功,T002,,
2026-08-06 10:00:00,文化休闲,美团外卖,*,退款订单,不计收支,¥30.00,花呗,退款成功,T003,,
2026-08-07 11:00:00,转账红包,自己,*,零钱通转入,不计收支,"¥1,000.00",余额宝,交易成功,T004,,
''';

const wxCsv = '''
微信支付账单明细,导出对象:本人
微信昵称,chist
起始时间,2026-08-01 00:00:00
终止时间,2026-08-31 23:59:59
----------------------微信支付账单明细列表----------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-08-01 08:00:00,商户付款,T3出行,打车费用,支出,¥23.50,零钱,交易成功,W001,M9,
2026-08-02 20:00:00,二维码收款,老王,/,收入,500.00,/,已存入零钱,W002,,
''';

void main() {
  group('splitCsvLine', () {
    test('引号包裹 + "" 转义 + 逗号内嵌', () {
      expect(splitCsvLine('a,"b,c","d""e"'), ['a', 'b,c', 'd"e']);
    });
  });

  group('parseBillText 支付宝', () {
    final res = parseBillText(alipayCsv)!;
    test('表头前缀行被跳过 · 平台识别', () {
      expect(res.platform, '支付宝');
    });
    test('可导入 3 条（支出/收入/退款）· 不计收支被跳过', () {
      expect(res.rows.length, 3);
      expect(res.skipped, 1);
    });
    test('引号内逗号不打断字段', () {
      final r = res.rows[0];
      expect(r.counterparty, '全家便利店');
      expect(r.product, '早餐,咖啡');
      expect(r.amt, 18.5);
      expect(r.date, '2026-08-03');
      expect(r.time, '12:01');
      expect(r.payMethod, '余额宝');
    });
    test('收入行', () {
      final r = res.rows[1];
      expect(r.isIncome, true);
      expect(r.amt, 8000);
    });
    test('退款行：状态含退款即使不计收支也入表', () {
      final r = res.rows[2];
      expect(r.isRefund, true);
      expect(r.payMethod, '花呗');
    });
    test('skipNonSpend=false 时转账红包仍因「不计收支」过滤', () {
      final r2 = parseBillText(alipayCsv, skipNonSpend: false)!;
      expect(r2.rows.length, 3);
      expect(r2.skipped, 1);
    });
  });

  group('parseBillText 微信', () {
    final res = parseBillText(wxCsv)!;
    test('平台与列名映射', () {
      expect(res.platform, '微信支付');
      expect(res.rows.length, 2);
      expect(res.rows[0].amt, 23.5);
      expect(res.rows[0].payMethod, '零钱');
      expect(res.rows[1].isIncome, true);
    });
  });

  test('无法识别的文本返回 null', () {
    expect(parseBillText('hello,world\n1,2'), isNull);
    expect(parseBillText('交易时间,无关列\n2026-08-01,3'), isNull);
  });

  test('guessAcctType 建型口径', () {
    expect(guessAcctType('花呗'), 'credit');
    expect(guessAcctType('储蓄卡(招商 1234)'), 'debit');
    expect(guessAcctType('余额宝'), 'invest');
    expect(guessAcctType('零钱通'), 'invest');
    expect(guessAcctType('支付宝账户余额'), 'ewallet');
    expect(guessAcctType('零钱'), 'ewallet');
    expect(guessAcctType('现金'), 'cash');
  });

  test('aggBillAccounts 按笔数降序', () {
    final res = parseBillText(alipayCsv)!;
    final agg = aggBillAccounts(res.rows);
    expect(agg.map((a) => a.$1).toList(),
        containsAll(['余额宝', '支付宝账户余额', '花呗']));
  });

  test('mapBillCat 命中与回落', () {
    BillRow r(String cat, String p) => BillRow(
      date: '2026-08-01',
      time: '10:00',
      counterparty: 'x',
      product: p,
      amt: 10,
      isIncome: false,
      isRefund: false,
      payMethod: '零钱',
      tradeNo: '',
      rawCat: cat,
      status: '交易成功',
    );
    expect(mapBillCat(r('餐饮美食', '')), 101);
    expect(mapBillCat(r('交通出行', '打车')), 102);
    expect(mapBillCat(r('数码电器', '')), 103);
    expect(mapBillCat(r('未知分类xyz', '奶茶')), 101); // 商品关键词兜底
    expect(mapBillCat(r('未知分类xyz', '不明事务')), 114);
  });
}
