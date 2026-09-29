/// R15-1 / V1.56 记账导入「整批撤销」补口钉桩。
/// 工单：`docs/交棒话术-20260929-R15-1整批撤销.md` · 拍板：`docs/拍板记录-20260930-缺口盘点批.md` §一
/// 三项口径全部钉住：① 入口两处（导入完成页钮 + 导入记录列表）② 账户回收默认不勾
/// ③ 可撤销范围＝仅最近一批（旧批只读、不给钮）。
/// 另钉「撤销必须落 key 行日志且来源归到记账」（L3 口径）与数据层两档语义不被 UI 改动。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_import_batches_sheet.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

bool _loggedKey(String contains) =>
    AppLog.lines.any((l) => l.text.contains(contains) && l.key);

/// 造一批导入（[n] 条流水 + 1 个本批新建账户），返回批次 id。
Future<int> _commit(
  LedgerRepository repo, {
  required String platform,
  required String file,
  required int n,
}) async {
  final res = await repo.commitImport(
    bk: 1,
    platform: platform,
    fileName: file,
    newAccounts: [
      LedgerAccount(type: LedgerAccount.kEwallet, name: '$platform·$file'),
    ],
    rows: [
      for (var i = 0; i < n; i++)
        ImportRowSpec(
          LedgerTxn(
            kind: LedgerTxn.kExpense,
            amt: 10.0 + i,
            catId: 101,
            accountId: 0, // 占位：commitImport 按 newAcctIndex 覆写
            date: '2026-09-0${i + 1}',
            source: LedgerTxn.kSourceBill,
            billHash: '$platform-$file-$i',
            bk: 1,
          ),
          newAcctIndex: 0,
        ),
    ],
  );
  return res.batchId;
}

Future<List<int>> _acctIds(LedgerRepository r) async =>
    (await r.accounts()).map((a) => a.id).toList();

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late LedgerRepository repo;

  setUp(() async {
    AppLog.reset();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = LedgerRepository(db);
  });
  tearDown(() async {
    AppLog.reset();
    await db.close();
  });

  group('1 · 数据层两档语义（UI 只接线，不改行为）', () {
    test('撤最新批 → 另一批流水与批次行完全不受影响', () async {
      final b1 = await _commit(repo, platform: '支付宝', file: 'a.csv', n: 3);
      final b2 = await _commit(repo, platform: '微信', file: 'b.csv', n: 2);
      expect(await repo.bookTxns(1), hasLength(5));

      expect(await repo.undoImportBatch(b2), 2);
      final left = await repo.bookTxns(1);
      expect(left, hasLength(3), reason: '只该删掉批次 $b2 的 2 条');
      expect(left.every((t) => t.impBatch == b1), isTrue);
      expect((await repo.importBatches()).map((r) => r['id']), [
        b1,
      ], reason: '批次表只出列被撤的那一行');
    });

    test('默认档不回收账户；回收档也不动仍有引用的账户', () async {
      final keep = await _commit(repo, platform: '支付宝', file: 'keep.csv', n: 1);
      final kept = (await repo.accounts())
          .firstWhere((a) => a.name == '支付宝·keep.csv')
          .id;

      await repo.undoImportBatch(keep);
      expect(
        await _acctIds(repo),
        contains(kept),
        reason: 'reclaimAccounts 默认 false → 账户不得被静默删除',
      );

      final b2 = await _commit(repo, platform: '微信', file: 'ref.csv', n: 1);
      final a2 = (await repo.accounts())
          .firstWhere((a) => a.name == '微信·ref.csv')
          .id;
      await repo.addTxn(
        LedgerTxn(
          kind: LedgerTxn.kExpense,
          amt: 1,
          catId: 101,
          accountId: a2,
          date: '2026-09-09',
          bk: 1,
        ),
      );
      await repo.undoImportBatch(b2, reclaimAccounts: true);
      expect(await _acctIds(repo), contains(a2), reason: '仍有流水引用的账户不得被回收');
    });

    test('回收档 · 无引用且余额 0 的本批新建账户会被移除', () async {
      final b = await _commit(repo, platform: '通用', file: 'free.csv', n: 1);
      final id = (await repo.accounts())
          .firstWhere((a) => a.name == '通用·free.csv')
          .id;
      await repo.undoImportBatch(b, reclaimAccounts: true);
      expect(await _acctIds(repo), isNot(contains(id)));
    });
  });

  group('2 · 导入记录弹层（三项拍板口径）', () {
    Future<void> pumpSheet(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [ledgerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => showLedgerImportBatches(c),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await settle5(tester);
      await tester.tap(find.text('open'));
      await settle5(tester);
    }

    testWidgets('列表倒序·仅最近一批挂撤销钮·旧批只读', (tester) async {
      final older = await _commit(repo, platform: '支付宝', file: 'old.csv', n: 2);
      final newer = await _commit(repo, platform: '微信', file: 'new.csv', n: 1);
      await pumpSheet(tester);

      expect(find.byKey(const ValueKey('sheetLedgerBatches')), findsOneWidget);
      expect(find.byKey(ValueKey('lib-row-$newer')), findsOneWidget);
      expect(
        find.byKey(ValueKey('lib-undo-$newer')),
        findsOneWidget,
        reason: '最近一批要有撤销钮',
      );
      expect(
        find.byKey(ValueKey('lib-undo-$older')),
        findsNothing,
        reason: '可撤销范围＝仅最近一批，旧批不给钮也不写解释句',
      );
    });

    testWidgets('确认弹层写明删除条数·回收默认不勾', (tester) async {
      await _commit(repo, platform: '微信', file: 'one.csv', n: 4);
      await pumpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('lib-undo-1')));
      await settle5(tester);

      expect(find.byKey(const ValueKey('sheetLedgerUndo')), findsOneWidget);
      expect(find.textContaining('将删除 4 条流水'), findsOneWidget);
      expect(find.textContaining('报表、分类占比与资产页同步重算'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const ValueKey('lib-reclaim')))
            .value,
        isFalse,
        reason: '账户回收默认不勾（2026-09-30 拍板）',
      );
    });

    testWidgets('确认撤销 → 状态行 + key 行日志 + 撤销钮下移到旧批', (tester) async {
      final older = await _commit(repo, platform: '支付宝', file: 'old.csv', n: 2);
      await _commit(repo, platform: '微信', file: 'new.csv', n: 3);
      await pumpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('lib-undo-2')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('lib-yes')));
      await settle5(tester);
      await drainLogTimer(tester);

      expect(
        find.byKey(const ValueKey('lib-status')),
        findsOneWidget,
        reason: '撤完要就地给状态提示（不能只靠页面 SnackBar）',
      );
      expect(find.textContaining('已撤销批次 2 · 删除 3 条流水'), findsOneWidget);
      expect(
        _loggedKey('账单整批撤销：批次 2 · 删流水 3 条'),
        isTrue,
        reason: 'L3 口径：撤销要落 key 行',
      );
      srcIsLedger();
      // 撤掉最新批后，旧批成为新的最近一批 → 撤销钮下移。
      expect(find.byKey(ValueKey('lib-undo-$older')), findsOneWidget);
      expect(find.byKey(const ValueKey('lib-undo-2')), findsNothing);
      expect(await repo.bookTxns(1), hasLength(2));
    });
  });

  group('3 · 源码级防回归（承诺与入口必须同时在场）', () {
    test('三处「整批撤销」承诺都有真实入口', () {
      final page = File(
        'lib/features/ledger/presentation/ledger_import_page.dart',
      ).readAsStringSync();
      final sheet = File(
        'lib/features/ledger/presentation/ledger_import_batches_sheet.dart',
      ).readAsStringSync();
      expect(page, contains('LedgerImportUndoButton'), reason: '完成页要挂撤销钮');
      expect(
        page,
        contains('LedgerImportRecordsRow'),
        reason: '向导首页与完成页都要有导入记录入口',
      );
      expect(
        page,
        contains('_batchId = res.batchId'),
        reason: '完成页要知道自己刚落的批次号',
      );
      expect(
        sheet,
        contains('undoImportBatch('),
        reason: 'repo 既有 API 必须有调用方（R15-1 立案根因）',
      );
      expect(sheet, contains('importBatches()'), reason: '批次列表必须真读库，不造假数据');
      expect(sheet, contains('账单整批撤销：批次'), reason: '撤销要落 key 行');
    });
  });
}

/// 撤销日志的来源归类必须是「记账」（日志页筛选口径）。
void srcIsLedger() {
  final hit = AppLog.lines.where((l) => l.text.contains('账单整批撤销')).toList();
  expect(hit, isNotEmpty);
  expect(hit.first.src, '记账', reason: '来源归类错：${hit.first.src}');
}
