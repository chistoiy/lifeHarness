import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_import_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';

/// V1.51 账单导入四屏（文件式）UI 与导航用例。落库/解析正确性由
/// ledger_bill_file_test + 真机端到端覆盖；此处不驱动系统文件选择器。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/ledger/import',
            routes: [
              GoRoute(
                path: '/ledger/import',
                builder: (_, _) => const LedgerImportPage(),
              ),
              GoRoute(
                path: '/ledger',
                builder: (_, _) => const Scaffold(body: Text('L1-STUB')),
              ),
            ],
          ),
        ),
      ),
    );
    await settle5(tester);
  }

  Future<void> tapText(WidgetTester tester, String t) async {
    await tester.tap(find.text(t).last);
    await settle5(tester);
  }

  testWidgets('步骤1 主页：来源4项 + 导入至 + 只导入支出收入 + 隐私承诺', (tester) async {
    await useSurface(tester);
    await pump(tester);
    expect(find.text('账单导入与导出'), findsOneWidget); // AppBar 标题
    expect(find.text('选择账单来源'), findsOneWidget);
    for (final s in ['微信支付', '支付宝', '其他记账产品', '通用模板']) {
      expect(find.text(s), findsWidgets);
    }
    expect(find.text('导入至'), findsOneWidget);
    expect(find.text('只导入支出和收入类型'), findsOneWidget);
    expect(find.textContaining('不上传不联网'), findsWidgets);
    expect(find.text('当前账本'), findsOneWidget);
  });

  testWidgets('步骤1→2：切来源 + 进入选择文件屏', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapText(tester, '支付宝');
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    expect(find.text('选择导入文件'), findsOneWidget); // AppBar
    expect(find.text('支付宝 · 选择导出文件'), findsOneWidget);
    expect(find.text('点击选择账单文件（.xlsx / .csv）'), findsOneWidget);
    expect(find.textContaining('跳过「帮人代付'), findsOneWidget);
    expect(find.text('退款冲抵记为负支出'), findsOneWidget);
  });

  testWidgets('步骤2 未选文件点下一步 → 提示', (tester) async {
    await useSurface(tester);
    await pump(tester);
    await tapText(tester, '微信支付');
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    await tester.tap(find.text('下一步'));
    await settle5(tester);
    expect(find.text('请先选择账单文件'), findsOneWidget);
    await clearToasts(tester);
  });
}
