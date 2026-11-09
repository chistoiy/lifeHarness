import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';
import 'package:lifeharness/features/ledger/domain/ledger_export.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_export_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// 记账批3b · L15 数据导出页 widget 用例（原型 renderExport 5382~5401 全渲染：
/// 范围四 chip / acct·cat 二级下拉 / 格式 seg / 预览两行 / 「导出 N 条」钮）。
/// 执行导出走真实落盘：dirOverride 注入临时目录（禁 path_provider 平台通道），
/// toast 前缀逐字断言 + 文件读回内容/行数断言 + bk 隔离。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('lexp_page');
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
  });
  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  final today = dayKey(DateTime.now());

  /// bk1：两笔餐饮（备注含逗号/引号，验证 CSV 转义）+ 今日工资；bk2：奶粉。
  Future<void> seed() async {
    Future<void> add(LedgerTxn Function() f) => repo.addTxn(f());
    await add(() => LedgerTxn(
        kind: 'expense', amt: 30, catId: 101, accountId: 1,
        date: '2026-09-10', note: '午餐, 和老板', bk: 1));
    await add(() => LedgerTxn(
        kind: 'expense', amt: 45, catId: 101, accountId: 1,
        date: '2026-09-11', note: '他说"好"', bk: 1));
    await add(() => LedgerTxn(
        kind: 'income', amt: 8000, catId: 201, accountId: 1,
        date: today, note: '工资', tags: ['必要'], bk: 1));
    final b2 = await repo.addBook('宝宝账本');
    await add(() => LedgerTxn(
        kind: 'expense', amt: 200, catId: 101, accountId: 1,
        date: '2026-09-09', note: '奶粉', bk: b2));
  }

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: LedgerExportPage(dirOverride: () async => dir.path),
        ),
      ),
    );
    await settle5(tester);
  }

  /// toast 断言：SnackBar 文案含动态路径，轮询 contains。导出经 sqflite ffi +
  /// 真实文件 IO（runAsync 放行真实事件循环·journal waitFinder 先例），再 pump 排帧。
  Future<void> pollContains(WidgetTester tester, String needle) async {
    for (var i = 0; i < 40; i++) {
      if (find.textContaining(needle).evaluate().isNotEmpty) return;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    fail('toast 未出现: $needle');
  }

  Future<void> export(
      WidgetTester tester, String button, String toastNeedle) async {
    await tester.tap(find.text(button));
    await pollContains(tester, toastNeedle);
    await clearToasts(tester);
  }

  group('1 · 骨架（原型 5388~5400 逐字）', () {
    testWidgets('标题/范围四 chip/格式 seg/预览两行/导出钮计数', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      expect(find.text('数据导出'), findsOneWidget);
      expect(find.text('CSV · JSON'), findsOneWidget);
      expect(find.text('导出范围'), findsOneWidget);
      for (final n in ['全部', '按月', '按账户', '按分类']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('CSV · Excel 兼容'), findsOneWidget);
      expect(find.text('JSON · 完整字段'), findsOneWidget);
      expect(find.text('预览'), findsOneWidget);
      expect(
        find.text('3 条流水 · 字段：日期,类型,分类,子分类,金额,账户,备注,标签,来源\n'
            '不含账户完整卡号，仅本机构建摘要'),
        findsOneWidget,
      );
      expect(find.text('导出 3 条'), findsOneWidget); // bk2 奶粉不进计数
    });
  });

  group('2 · CSV 导出落盘（toast 逐字前缀 + 文件内容 + 转义 + bk 隔离）', () {
    testWidgets('全量导出 → 表头+3 行；逗号/引号备注转义；不含他账本', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await export(tester, '导出 3 条', '已导出 全量 流水 · lifeharness_ledger.csv（');
      final f = File('${dir.path}${Platform.pathSeparator}lifeharness_ledger.csv');
      expect(f.existsSync(), isTrue);
      final lines = f.readAsLinesSync();
      expect(lines.first, ledgerCsvHeader);
      expect(lines.where((l) => l.startsWith('2026-')).length, 3);
      expect(lines, contains('2026-09-10,支出,餐饮,,30.00,现金,"午餐, 和老板",,manual'));
      expect(lines, contains('2026-09-11,支出,餐饮,,45.00,现金,"他说""好""",,manual'));
      expect(lines.any((l) => l.contains('奶粉')), isFalse);
      expect(lines.any((l) => l.contains('"必要"')), isFalse); // 单标签无逗号不加引号
    });
  });

  group('3 · JSON 导出', () {
    testWidgets('切格式 seg → 预览字段行逐字；导出文件可解析 3 条', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await tester.tap(find.text('JSON · 完整字段'));
      await settle5(tester);
      expect(
        find.text('3 条流水 · 字段：id, kind, cat, sub, amt, account, date, note, tags, source\n'
            '不含账户完整卡号，仅本机构建摘要'),
        findsOneWidget,
      );
      await export(tester, '导出 3 条', '已导出 全量 流水 · lifeharness_ledger.json（');
      final list = jsonDecode(
              File('${dir.path}${Platform.pathSeparator}lifeharness_ledger.json')
                  .readAsStringSync())
          as List;
      expect(list, hasLength(3));
      expect((list.first as Map).keys.first, 'id');
      expect(list.any((e) => (e as Map)['note'] == '奶粉'), isFalse);
    });
  });

  group('4 · 范围切换', () {
    testWidgets('按分类（默认首个支出大类 餐饮）→ 2 条并落盘', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await tester.tap(find.text('按分类'));
      await settle5(tester);
      expect(find.text('餐饮'), findsOneWidget); // 二级下拉当前值
      expect(find.text('导出 2 条'), findsOneWidget);
      await export(tester, '导出 2 条', '已导出 全量 流水 · lifeharness_ledger.csv（');
      final lines =
          File('${dir.path}${Platform.pathSeparator}lifeharness_ledger.csv')
              .readAsLinesSync();
      expect(lines.where((l) => l.startsWith('2026-')).length, 2);
    });

    testWidgets('按月（查看月=当月）→ 当月流水条数；toast 带月份', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await tester.tap(find.text('按月'));
      await settle5(tester);
      // 期望=种子三笔中 date 前缀命中查看月者（2026-09 种子 + 今日工资）。
      final mm = monthKey(DateTime.now());
      final n = ['2026-09-10', '2026-09-11', today]
          .where((d) => d.startsWith('$mm-'))
          .length;
      expect(find.text('导出 $n 条'), findsOneWidget);
      await export(tester, '导出 $n 条', '已导出 $mm 流水 · lifeharness_ledger.csv（');
    });

    testWidgets('按账户（默认账户=现金）→ 3 条', (tester) async {
      await useSurface(tester);
      await seed();
      await pump(tester);
      await tester.tap(find.text('按账户'));
      await settle5(tester);
      expect(find.text('现金'), findsOneWidget); // 二级下拉当前值
      expect(find.text('导出 3 条'), findsOneWidget);
    });
  });
}
