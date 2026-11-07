import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/ledger/domain/ledger_search.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';

/// 记账批3b · L12 搜索过滤纯函数用例（原型 fsResults 5341~5350 / fsRun 5351~5353
/// 逐条对译取证）。覆盖：AND 即时组合 / 边界含等号 / bk 隔离（九·补1）/
/// nb 口径（fsRun 不剔 nb）/ 日期区间端点 / kind 白名单（adjust 不进结果）/ 排序。
/// 说明：本文件为纯函数单测，无 widget 依赖，故不 import helpers.dart
/// （避免 unused_import 新增 analyze 警告；helpers 供两个页面 widget 测试使用）。
void main() {
  var seq = 0;
  LedgerTxn tx({
    String kind = LedgerTxn.kExpense,
    double amt = 10,
    int? catId = 101,
    int accountId = 1,
    int? toAccountId,
    String date = '2026-09-10',
    String note = '',
    List<String> tags = const [],
    int bk = 1,
    bool nb = false,
  }) =>
      LedgerTxn(
        id: ++seq,
        kind: kind,
        amt: amt,
        catId: catId,
        accountId: accountId,
        toAccountId: toAccountId,
        date: date,
        note: note,
        tags: tags,
        bk: bk,
        nb: nb,
      );

  const cats = {101: '餐饮', 102: '交通', 201: '工资', 207: '其他'};
  String catName(int? id) => cats[id] ?? '其他';

  List<LedgerTxn> run(
    Iterable<LedgerTxn> ts, {
    int bk = 1,
    String kw = '',
    double? min,
    double? max,
    int? catId,
    int? acctId,
    String? tag,
    String? from,
    String? to,
  }) =>
      ledgerSearch(
        txns: ts,
        bk: bk,
        q: LedgerSearchQuery(
          kw: kw,
          min: min,
          max: max,
          catId: catId,
          acctId: acctId,
          tag: tag,
          from: from,
          to: to,
        ),
        catName: catName,
      );

  group('1 · 关键词（5342：命中备注或分类名）', () {
    test('备注命中 / 分类名命中 / 双落空', () {
      final ts = [
        tx(note: '午餐便当'),
        tx(note: '地铁', catId: 102),
        tx(note: '电影票'),
      ];
      expect(run(ts, kw: '午餐').single.note, '午餐便当');
      // 分类名 '交通' 命中（备注不含关键词）
      expect(run(ts, kw: '交通').single.note, '地铁');
      expect(run(ts, kw: '不存在词'), isEmpty);
    });
  });

  group('2 · AND 即时组合', () {
    test('kw+cat+tag+金额区间 全条件交集', () {
      final ts = [
        tx(note: '午餐', catId: 101, amt: 30, tags: ['报销']),
        tx(note: '午餐储蓄', catId: 101, amt: 300, tags: ['报销']),
        tx(note: '午餐', catId: 101, amt: 30, tags: ['出差']),
        tx(note: '午餐', catId: 102, amt: 30, tags: ['报销']),
      ];
      final r = run(ts, kw: '午餐', catId: 101, tag: '报销', min: 20, max: 50);
      expect(r, hasLength(1));
      expect(r.single.date, '2026-09-10');
      expect(r.single.tags, ['报销']);
    });
  });

  group('3 · bk 隔离（5341 · 九·补1）', () {
    test('他账本流水不进结果，切 bk 只出他账本', () {
      final ts = [tx(note: '本账本'), tx(note: '他账本', bk: 2)];
      expect(run(ts, bk: 1).map((t) => t.note), ['本账本']);
      expect(run(ts, bk: 2).map((t) => t.note), ['他账本']);
    });
  });

  group('4 · 金额边界（5343~5344：含等号；max 仅 expense 生效）', () {
    test('min 含等号：amt==min 保留；低于剔除', () {
      final ts = [tx(amt: 50, note: '等号'), tx(amt: 49.99, note: '低')];
      expect(run(ts, min: 50).map((t) => t.note), ['等号']);
    });
    test('max 含等号：amt==max 保留；超出剔除', () {
      final ts = [tx(amt: 50, note: '等号'), tx(amt: 50.01, note: '高')];
      expect(run(ts, max: 50).map((t) => t.note), ['等号']);
    });
    test('max 不杀收入（isEx 条件）', () {
      final ts = [
        tx(kind: LedgerTxn.kIncome, amt: 8000, note: '工资'),
        tx(amt: 8000, note: '大额支出'),
      ];
      expect(run(ts, max: 100).map((t) => t.note), ['工资']);
    });
    test('min 对非支出取绝对值（5343 Math.abs 口径）', () {
      final ts = [
        tx(kind: LedgerTxn.kTransfer, amt: 50, note: '转账50'),
        tx(kind: LedgerTxn.kTransfer, amt: 60, note: '转账60'),
      ];
      expect(run(ts, min: 60).map((t) => t.note), ['转账60']);
    });
  });

  group('5 · 分类 / 账户 / 标签（5345~5347）', () {
    test('分类等值匹配（不限收支树）', () {
      final ts = [tx(catId: 201, kind: LedgerTxn.kIncome), tx(catId: 101)];
      expect(run(ts, catId: 201).single.kind, LedgerTxn.kIncome);
    });
    test('账户命中转入或转出（转账双向）', () {
      final ts = [
        tx(accountId: 1, note: '出'),
        tx(accountId: 2, toAccountId: 1, kind: LedgerTxn.kTransfer, note: '入'),
        tx(accountId: 3, note: '无关'),
      ];
      expect(run(ts, acctId: 1).map((t) => t.note), ['入', '出']); // 同日 id DESC
    });
    test('标签包含匹配', () {
      final ts = [tx(tags: ['报销', 'AA'], note: '有'), tx(tags: ['出差'], note: '无')];
      expect(run(ts, tag: 'AA').map((t) => t.note), ['有']);
    });
  });

  group('6 · 日期区间（5348~5349：字符串比较含端点）', () {
    final ts = [
      tx(date: '2026-09-01', note: '首日'),
      tx(date: '2026-09-15', note: '中间'),
      tx(date: '2026-09-30', note: '末日'),
      tx(date: '2026-10-05', note: '窗外'),
    ];
    test('from/to 含端点', () {
      expect(run(ts, from: '2026-09-01', to: '2026-09-30').map((t) => t.note),
          containsAll(['首日', '末日']));
      expect(run(ts, from: '2026-09-01', to: '2026-09-30'), hasLength(3));
    });
    test('单边生效（含端点：末日保留、窗外在其后也保留）', () {
      expect(run(ts, to: '2026-09-01').single.note, '首日');
      expect(run(ts, from: '2026-09-30').map((t) => t.note), ['窗外', '末日']);
    });
  });

  group('7 · kind 白名单与 nb 口径（5350 / fsRun 5352）', () {
    test('adjust 不进结果；refund 保留', () {
      final ts = [
        tx(kind: LedgerTxn.kAdjust, note: '调整'),
        tx(kind: LedgerTxn.kRefund, note: '退款'),
      ];
      expect(run(ts).map((t) => t.note), ['退款']);
    });
    test('nb 行进结果、且计入合计（fsRun 无 nb 剔除·取证 5352）', () {
      final ts = [
        tx(amt: 50, nb: true, note: '不计入支出'),
        tx(amt: 50, note: '常规支出'),
        tx(kind: LedgerTxn.kIncome, amt: 80, nb: true, note: '不计入收入'),
      ];
      final tot = ledgerSearchTotals(run(ts));
      expect(tot.n, 3);
      expect(tot.exp, 100); // 含 nb expense
      expect(tot.inc, 80); // 含 nb income
    });
    test('合计仅 expense/income 两类求和（refund/transfer 不进两侧）', () {
      final tot = ledgerSearchTotals(run([
        tx(kind: LedgerTxn.kRefund, amt: 20),
        tx(kind: LedgerTxn.kTransfer, amt: 30),
        tx(amt: 10),
        tx(kind: LedgerTxn.kIncome, amt: 40),
      ]));
      expect((tot.exp, tot.inc), (10.0, 40.0));
      expect(tot.n, 4);
    });
  });

  group('8 · 排序（5350：date DESC，同日 id DESC）', () {
    test('跨日与同日双段', () {
      final a = tx(date: '2026-09-01', note: '早');
      final b = tx(date: '2026-09-10', note: '晚1');
      final c = tx(date: '2026-09-10', note: '晚2');
      expect(run([a, c, b]).map((t) => t.note), ['晚2', '晚1', '早']);
    });
  });
}
