import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enough_convert/gbk.dart';
import 'package:lifeharness/features/ledger/data/bill_parser.dart';

/// V1.51 文件式导入：parseBillFile 按字节解析（csv GBK/UTF-8）+ Excel 日期序列号归一。
void main() {
  const alipayCsv = '''交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
2026-08-03 12:01:59,餐饮美食,全家便利店,***,早餐,支出,18.50,余额宝,交易成功,T001,M1,
2026-08-05 09:00:00,收入,***,,工资,收入,8000.00,支付宝账户余额,交易成功,T002,,
''';

  test('parseBillFile 解 GBK 字节（支付宝真实导出编码）', () {
    final r = parseBillFile(gbk.encode(alipayCsv));
    expect(r?.platform, '支付宝');
    expect(r?.rows.length, 2);
    expect(r?.rows.first.counterparty, '全家便利店');
    expect(r?.rows.first.payMethod, '余额宝');
    expect(r?.rows.first.date, '2026-08-03');
    expect(r?.rows.first.time, '12:01');
  });

  test('parseBillFile 解 UTF-8 字节（不被误当 GBK 乱码）', () {
    final r = parseBillFile(utf8.encode(alipayCsv));
    expect(r?.platform, '支付宝');
    expect(r?.rows.length, 2);
    expect(r?.rows.first.counterparty, '全家便利店');
  });

  test('parseBillFile 解 UTF-8 BOM 字节', () {
    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(alipayCsv)];
    expect(parseBillFile(bytes)?.rows.length, 2);
  });

  test('excelSerialToDateTime 还原微信日期序列号', () {
    final dt = excelSerialToDateTime(46290.48952546297);
    expect(dt.year, 2026);
    expect(dt.month, 9);
    expect(dt.day, 25);
    expect(dt.hour, 11);
    expect(dt.minute, 44);
  });

  test('无法识别的字节返回 null', () {
    expect(parseBillFile([1, 2, 3, 4, 5, 6, 7]), isNull);
  });
}
