import 'dart:convert';
import 'dart:io';

import 'ledger_txn.dart';

/// L15 数据导出（原型 renderExport 5382~5401 行 + 计划书 §5 批3「导出流式落盘」）。
///
/// 分层：本文件全部纯函数/纯 IO（目录路径由调用方注入，不触 path_provider，
/// 测试可直接喂临时目录 + 内存分页）；「流式」实现 = 分页拉取 [pageSize] 行、
/// 经 [IOSink] 边拉边写，大流水不整表进内存。

/// 原型导出范围状态（5381 行 `exp={scope:'all',fmt:'csv',...}`）。
const kLedgerExportScopes = <(String, String)>[
  ('all', '全部'),
  ('month', '按月'),
  ('acct', '按账户'),
  ('cat', '按分类'),
];

/// CSV 表头（原型预览行 5399 逐字：字段：日期,类型,分类,子分类,金额,账户,备注,标签,来源）。
const ledgerCsvHeader = '日期,类型,分类,子分类,金额,账户,备注,标签,来源';

/// JSON 字段说明（原型预览行 5399 逐字：字段：id, kind, cat, sub, amt, account, date, note, tags, source）。
const ledgerJsonFieldNote =
    '字段：id, kind, cat, sub, amt, account, date, note, tags, source';

/// 预览字段行（按格式取上二者并加「字段：」前缀，5399 同式）。
String ledgerFieldNote(String fmt) =>
    fmt == 'json' ? ledgerJsonFieldNote : '字段：$ledgerCsvHeader';

/// kind → 类型显示名（CSV「类型」列；transfer/refund/adjust 取 LTxRow 同源词，
/// expense/income 取记一笔 segmented 词「支出/收入」）。
String ledgerKindLabel(String kind) => switch (kind) {
  LedgerTxn.kExpense => '支出',
  LedgerTxn.kIncome => '收入',
  LedgerTxn.kTransfer => '转账',
  LedgerTxn.kRefund => '退款',
  LedgerTxn.kAdjust => '余额调整',
  _ => kind,
};

/// RFC4180 单元格转义：含逗号/引号/换行才加引号，内部引号翻倍。
String ledgerCsvCell(String v) =>
    v.contains(RegExp(r'[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// 单条流水 → CSV 行。列序同 [ledgerCsvHeader]；
/// 金额列取两位小数裸值（Excel 兼容）；标签列逗号连接（自动整体加引号）；
/// 转账账户列「出 → 入」双账户（同 txRow 4733 展示口径）。
String ledgerTxnCsvLine(
  LedgerTxn t, {
  required String Function(int? catId) catName,
  required String Function(int? accountId) acctName,
}) {
  final acct = t.kind == LedgerTxn.kTransfer && t.toAccountId != null
      ? '${acctName(t.accountId)} → ${acctName(t.toAccountId)}'
      : acctName(t.accountId);
  return [
    t.date,
    ledgerKindLabel(t.kind),
    catName(t.catId),
    t.sub,
    t.amt.toStringAsFixed(2),
    acct,
    t.note,
    t.tags.join(','),
    t.source,
  ].map(ledgerCsvCell).join(',');
}

/// 单条流水 → JSON 对象（键序与 [ledgerJsonFieldNote] 一致；cat/account 输出
/// 名称，等价原型原始键值——原型 L.txns 的 cat:'food'、a:'debit' 即目录键名）。
Map<String, Object?> ledgerTxnJsonEntry(
  LedgerTxn t, {
  required String Function(int? catId) catName,
  required String Function(int? accountId) acctName,
}) => {
  'id': t.id,
  'kind': t.kind,
  'cat': catName(t.catId),
  'sub': t.sub,
  'amt': t.amt,
  'account': acctName(t.accountId),
  'date': t.date,
  'note': t.note,
  'tags': t.tags,
  'source': t.source,
};

/// 范围过滤（原型 renderExport 5384~5387 逐条对译；预览计数与流式导出共用）：
/// month=t.d 前 7 位、acct=a/to 双向、cat 等值；all 不过滤。
/// bk 隔离在数据源侧（当前账本查询），九·补1 口径——原型此处漏滤 bk，
/// 全 app 均为分账本视图，本实现按当前账本执行（登记偏差）。
List<LedgerTxn> ledgerExportScope({
  required Iterable<LedgerTxn> txns,
  required String scope,
  String? month,
  int? acctId,
  int? catId,
}) => [
  for (final t in txns)
    if (switch (scope) {
      'month' => t.date.startsWith('$month-'),
      'acct' => t.accountId == acctId || t.toAccountId == acctId,
      'cat' => t.catId == catId,
      _ => true,
    })
      t,
];

/// 分页取数回调（repo.exportTxnsPage 的抽象；测试可喂内存切片）。
typedef LedgerExportPageFetcher = Future<List<LedgerTxn>> Function(
  int offset,
  int limit,
);

/// 流式落盘：逐页 fetch → 逐行 sink.write，返回文件路径与写出行数。
/// [dir] 注入（生产=getApplicationDocumentsDirectory，测试=临时目录）；
/// 文件名 lifeharness_ledger.csv/.json（原型 toast 5400 逐字同名）。
Future<({String path, int count})> writeLedgerExportFile({
  required String dir,
  required String fmt,
  required LedgerExportPageFetcher fetchPage,
  required String Function(int? catId) catName,
  required String Function(int? accountId) acctName,
  int pageSize = 200,
}) async {
  final path = '$dir${Platform.pathSeparator}lifeharness_ledger.$fmt';
  final sink = File(path).openWrite();
  var count = 0;
  try {
    if (fmt == 'json') {
      sink.write('[\n');
    } else {
      sink.write('$ledgerCsvHeader\n');
    }
    var offset = 0;
    while (true) {
      final page = await fetchPage(offset, pageSize);
      if (page.isEmpty) break;
      for (final t in page) {
        if (fmt == 'json') {
          if (count > 0) sink.write(',\n');
          sink.write(
            jsonEncode(ledgerTxnJsonEntry(t, catName: catName, acctName: acctName)),
          );
        } else {
          sink.write('${ledgerTxnCsvLine(t, catName: catName, acctName: acctName)}\n');
        }
        count++;
      }
      offset += page.length;
      if (page.length < pageSize) break; // 末页：不足一页即拉完
    }
    if (fmt == 'json') sink.write(count == 0 ? ']' : '\n]');
  } finally {
    await sink.close();
  }
  return (path: path, count: count);
}
