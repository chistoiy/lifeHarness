import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/ledger/domain/ledger_export.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批3b · L15 导出纯函数与流式落盘用例。覆盖：CSV 转义（逗号/引号/换行）/
/// kind 显示名 / 范围过滤（原型 renderExport 5384~5387 对译）/ 分页流式写文件
/// （临时目录真实写后读回断言行数与内容；写盘函数注入 dir，不触 path_provider）。
/// 纯函数单测不 import helpers.dart（无 widget 依赖，避免 unused_import）。
void main() {
  String catName(int? id) => id == 102 ? '交通' : '餐饮';
  String acctName(int? id) => id == 2 ? '储蓄卡' : '现金';

  LedgerTxn tx({
    int id = 1,
    String kind = LedgerTxn.kExpense,
    double amt = 30,
    int? catId = 101,
    String sub = '',
    int accountId = 1,
    int? toAccountId,
    String date = '2026-09-10',
    String note = '午餐',
    List<String> tags = const [],
    String source = 'manual',
  }) =>
      LedgerTxn(
        id: id,
        kind: kind,
        amt: amt,
        catId: catId,
        sub: sub,
        accountId: accountId,
        toAccountId: toAccountId,
        date: date,
        note: note,
        tags: tags,
        source: source,
        bk: 1,
      );

  group('1 · CSV 单元格转义（RFC4180）', () {
    test('逗号/引号/换行加引号，内部引号翻倍；普通值原样', () {
      expect(ledgerCsvCell('简单'), '简单');
      expect(ledgerCsvCell('a,b'), '"a,b"');
      expect(ledgerCsvCell('他说"好"'), '"他说""好"""');
      expect(ledgerCsvCell('第一行\n第二行'), '"第一行\n第二行"');
      expect(ledgerCsvCell('混合, "引号"\n换行'), '"混合, ""引号""\n换行"');
    });
  });

  group('2 · kind 显示名', () {
    test('五类逐字 + 未知回落原键', () {
      expect(ledgerKindLabel('expense'), '支出');
      expect(ledgerKindLabel('income'), '收入');
      expect(ledgerKindLabel('transfer'), '转账');
      expect(ledgerKindLabel('refund'), '退款');
      expect(ledgerKindLabel('adjust'), '余额调整');
      expect(ledgerKindLabel('weird'), 'weird');
    });
  });

  group('3 · CSV 行生成', () {
    test('支出全列：日期,类型,分类,子分类,金额(两位小数),账户,备注,标签,来源', () {
      final line = ledgerTxnCsvLine(
        tx(sub: '', tags: ['必要', '报销'], source: 'recurring'),
        catName: catName,
        acctName: acctName,
      );
      expect(line, '2026-09-10,支出,餐饮,,30.00,现金,午餐,"必要,报销",recurring');
    });
    test('转账账户列「出 → 入」；备注含逗号被引号包裹', () {
      final line = ledgerTxnCsvLine(
        tx(
            kind: LedgerTxn.kTransfer,
            amt: 500,
            accountId: 1,
            toAccountId: 2,
            note: '工资, 上交'),
        catName: catName,
        acctName: acctName,
      );
      expect(line.split(',')[0], '2026-09-10');
      expect(line, contains('转账'));
      expect(line, contains('现金 → 储蓄卡'));
      expect(line, contains('"工资, 上交"'));
    });
    test('金额列含等值精度：12.345 → 12.35（toStringAsFixed(2)）', () {
      expect(ledgerTxnCsvLine(tx(amt: 12.345), catName: catName, acctName: acctName),
          contains(',12.35,'));
    });
  });

  group('4 · JSON 对象（10 键序同预览文案）', () {
    test('键序 id,kind,cat,sub,amt,account,date,note,tags,source', () {
      final e = ledgerTxnJsonEntry(tx(tags: ['必要']),
          catName: catName, acctName: acctName);
      expect(e.keys.toList(), [
        'id', 'kind', 'cat', 'sub', 'amt',
        'account', 'date', 'note', 'tags', 'source'
      ]);
      expect(e['cat'], '餐饮');
      expect(e['account'], '现金');
      expect(e['tags'], ['必要']);
    });
  });

  group('5 · 范围过滤（原型 5384~5387）', () {
    final ts = [
      tx(id: 1, date: '2026-09-10', note: '九月'),
      tx(id: 2, date: '2026-08-10', note: '八月'),
      tx(id: 3, kind: LedgerTxn.kTransfer, accountId: 1, toAccountId: 2, note: '转账'),
      tx(id: 4, catId: 102, note: '交通'),
    ];
    test('all 不过滤', () {
      expect(ledgerExportScope(txns: ts, scope: 'all'), hasLength(4));
    });
    test('month 前 7 位匹配', () {
      expect(
          ledgerExportScope(txns: ts, scope: 'month', month: '2026-09')
              .map((t) => t.note),
          ['九月', '转账', '交通']);
    });
    test('acct 转入/转出双向命中', () {
      expect(ledgerExportScope(txns: ts, scope: 'acct', acctId: 2).map((t) => t.note),
          ['转账']);
    });
    test('cat 等值', () {
      expect(ledgerExportScope(txns: ts, scope: 'cat', catId: 102).map((t) => t.note),
          ['交通']);
    });
  });

  group('6 · 流式落盘（临时目录真实写后读回）', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('lexp'));
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    List<LedgerTxn> rows(int n) => [
      for (var i = 1; i <= n; i++)
        tx(id: i, amt: i * 10.0, note: '行$i', catId: i.isEven ? 102 : 101)
    ];
    LedgerExportPageFetcher pages(List<LedgerTxn> all) =>
        (offset, limit) async => all.skip(offset).take(limit).toList();

    test('CSV：pageSize=2 跨页写出，表头+行数逐字读回', () async {
      final r = await writeLedgerExportFile(
        dir: dir.path,
        fmt: 'csv',
        fetchPage: pages(rows(5)),
        catName: catName,
        acctName: acctName,
        pageSize: 2,
      );
      expect(r.count, 5);
      expect(r.path, '${dir.path}${Platform.pathSeparator}lifeharness_ledger.csv');
      final body = File(r.path).readAsLinesSync();
      expect(body.first, ledgerCsvHeader);
      expect(body.where((l) => l.startsWith('2026-')).length, 5);
      expect(body, contains('2026-09-10,支出,交通,,20.00,现金,行2,,manual'));
    });

    test('JSON：合法数组、元素序与金额数值型', () async {
      final r = await writeLedgerExportFile(
        dir: dir.path,
        fmt: 'json',
        fetchPage: pages(rows(5)),
        catName: catName,
        acctName: acctName,
        pageSize: 2,
      );
      final list = jsonDecode(File(r.path).readAsStringSync()) as List;
      expect(list, hasLength(5));
      expect((list.first as Map)['amt'], 10.0);
      expect((list.last as Map)['note'], '行5');
    });

    test('空集：CSV 仅表头；JSON 为空数组', () async {
      final c = await writeLedgerExportFile(
        dir: dir.path,
        fmt: 'csv',
        fetchPage: pages(const []),
        catName: catName,
        acctName: acctName,
      );
      expect(c.count, 0);
      expect(File(c.path).readAsLinesSync(), [ledgerCsvHeader]);
      final j = await writeLedgerExportFile(
        dir: dir.path,
        fmt: 'json',
        fetchPage: pages(const []),
        catName: catName,
        acctName: acctName,
      );
      expect(jsonDecode(File(j.path).readAsStringSync()), isEmpty);
    });

    test('恰好整页边界：4 行 pageSize=2 不重复不丢行', () async {
      final r = await writeLedgerExportFile(
        dir: dir.path,
        fmt: 'csv',
        fetchPage: pages(rows(4)),
        catName: catName,
        acctName: acctName,
        pageSize: 2,
      );
      expect(r.count, 4);
      expect(File(r.path).readAsLinesSync().where((l) => l.startsWith('2026-')).length,
          4);
    });
  });

  group('7 · 预览字段文案（原型 5399 逐字）', () {
    test('CSV / JSON 两式', () {
      expect(ledgerFieldNote('csv'), '字段：日期,类型,分类,子分类,金额,账户,备注,标签,来源');
      expect(ledgerFieldNote('json'),
          '字段：id, kind, cat, sub, amt, account, date, note, tags, source');
      expect(ledgerCsvHeader, '日期,类型,分类,子分类,金额,账户,备注,标签,来源');
    });
  });
}
