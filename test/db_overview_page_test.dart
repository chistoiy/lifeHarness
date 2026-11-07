/// B-4 概览屏 widget 验收（工单 §7-7）：fake scanner 注入（禁真实 I/O），
/// 断言四段渲染、垃圾箱>0 出异常卡且文案含数字、技术明细默认收起。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/db_overview.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/db_overview_page.dart';
import 'package:lifeharness/shared/trash/trash_models.dart';
import 'package:lifeharness/shared/trash/trash_providers.dart';

import 'helpers.dart';

class _FakeScanner implements DbOverviewScanner {
  _FakeScanner(this.result);

  DbOverview result;
  int scans = 0;

  @override
  Future<DbOverview> scan() async {
    scans++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('DbOverviewScanner.${invocation.memberName}');
}

/// 真机审计实数画像（603235 行 · 97% 可再生 · books 24 含 18 在垃圾箱）。
DbOverview _overview() => DbOverview(
      rows: const [
        DbOverviewRow(
            table: 'xray_mention',
            label: '全书索引 · 可再生',
            module: '阅读',
            rows: 586959),
        DbOverviewRow(
            table: 'ledger_txns',
            label: '账单流水',
            module: '记账',
            rows: 160),
        DbOverviewRow(
            table: 'notes',
            label: '笔记',
            module: '笔记',
            rows: 31),
        DbOverviewRow(
            table: 'books',
            label: '书籍在册',
            module: '阅读',
            rows: 24),
      ],
      totalRows: 603235,
      regenerableRows: 586959,
      byModule: const [
        (module: '阅读', rows: 586983, tables: 2),
        (module: '记账', rows: 160, tables: 1),
        (module: '笔记', rows: 31, tables: 1),
      ],
      emptyTableCount: 12,
    );

List<TrashItem> _trashBooks(int n) => [
      for (var i = 0; i < n; i++)
        TrashItem(kind: TrashKind.book, rawId: 'b$i', title: '书$i'),
    ];

Widget _app(DbOverviewScanner scanner,
        {int? backupBytes = 16112543, List<TrashItem> trash = const []}) =>
    ProviderScope(
      overrides: [
        dbOverviewScannerProvider.overrideWithValue(scanner),
        trashItemsProvider.overrideWith((ref) async => trash),
      ],
      child: MaterialApp(
        home: DbOverviewPage(
          backupSizeReader: () async => backupBytes,
        ),
      ),
    );

void main() {
  testWidgets('四段渲染：总览三数 + 模块行 + 折叠明细（默认收起）', (tester) async {
    final fake = _FakeScanner(_overview());
    await tester.pumpWidget(_app(fake, trash: _trashBooks(18)));
    await settle5(tester);

    expect(find.byKey(const ValueKey('dbo-overview')), findsOneWidget);
    expect(find.text('60.3万'), findsOneWidget);
    // 16,112,543 字节 → 15.4 MB（formatBytes）。
    expect(find.text('15.4 MB'), findsOneWidget);
    expect(find.text('97%'), findsOneWidget); // 总览格（异常卡文案在下一条用例）

    // 模块行按聚合渲染；阅读行挂可再生定性标注。
    expect(find.byKey(const ValueKey('dbo-mod-阅读')), findsOneWidget);
    expect(find.byKey(const ValueKey('dbo-mod-记账')), findsOneWidget);
    expect(find.text('全书索引 58.7万 · 可再生'), findsOneWidget);

    // 刷新钮重扫（趁列表还在顶部先点，展开明细会滚动列表）。
    final before = fake.scans;
    await tester.tap(find.byKey(const ValueKey('dbo-refresh')));
    await settle5(tester);
    expect(fake.scans, before + 1);

    // 技术明细默认收起：逐表明细不可见。
    expect(find.text('xray_mention · 全书索引 · 可再生'), findsNothing);
    final detailsTitle = find.text('技术明细（逐表行数）');
    await tester.ensureVisible(detailsTitle);
    await tester.pump();
    await tester.tap(detailsTitle);
    await settle5(tester);
    expect(find.text('xray_mention · 全书索引 · 可再生'), findsOneWidget);
    expect(find.text('… 其余 12 张空表'), findsOneWidget);
  });

  testWidgets('垃圾箱有书 → 异常卡出现、文案含数字、去回收站钮在位',
      (tester) async {
    await tester.pumpWidget(_app(_FakeScanner(_overview()),
        trash: _trashBooks(18)));
    await settle5(tester);
    expect(find.byKey(const ValueKey('dbo-warn')), findsOneWidget);
    expect(find.text('垃圾箱里有 18 本书未彻底删除'), findsOneWidget);
    expect(find.textContaining('约占数据库 97%'), findsOneWidget);
    expect(find.text('去回收站 ›'), findsOneWidget);
  });

  testWidgets('垃圾箱为空 → 异常卡整卡不渲染', (tester) async {
    await tester.pumpWidget(_app(_FakeScanner(_overview())));
    await settle5(tester);
    expect(find.byKey(const ValueKey('dbo-warn')), findsNothing);
  });

  testWidgets('备份包体积取不到 → 隐藏该格（不编造数字）', (tester) async {
    await tester
        .pumpWidget(_app(_FakeScanner(_overview()), backupBytes: null));
    await settle5(tester);
    expect(find.byKey(const ValueKey('dbo-size')), findsNothing);
    expect(find.byKey(const ValueKey('dbo-total')), findsOneWidget);
  });

  testWidgets('词表外模块无路由 → 行仍显示（不造假热区即无箭头）',
      (tester) async {
    final o = _overview();
    final withOther = DbOverview(
      rows: o.rows,
      totalRows: o.totalRows,
      regenerableRows: o.regenerableRows,
      byModule: [
        ...o.byModule,
        const (module: '其他', rows: 7, tables: 1),
      ],
      emptyTableCount: o.emptyTableCount,
    );
    await tester.pumpWidget(_app(_FakeScanner(withOther)));
    await settle5(tester);
    expect(find.byKey(const ValueKey('dbo-mod-其他')), findsOneWidget);
  });
}
