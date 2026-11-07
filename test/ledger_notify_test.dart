import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/notifications/notification_service.dart';
import 'package:lifeharness/features/ledger/data/ledger_repository.dart';
import 'package:lifeharness/features/ledger/domain/ledger_txn.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_notify.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1.57 B 批 · 记账通知排程（拍板记录 §九）。
/// 测试环境 ready=false → 排程静默降级；本文件断言面＝「排程调用」的
/// 决策与返回文本（档位去重/跨周期重置/小结时点），真实送达属真机验收项。
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

  // 内存库按路径复用：不 close 会带着上个用例的表和数据进下一个。
  tearDown(() => db.close());

  Future<void> addExpense(double amt, String date) => repo.addTxn(LedgerTxn(
      kind: LedgerTxn.kExpense,
      bk: 1,
      amt: amt,
      catId: 101,
      accountId: 1,
      date: date,
      note: 'x'));

  group('budgetStagesToFire 纯函数', () {
    test('80/100 各一次；同档已发剔除；无预算不提醒', () {
      expect(
          budgetStagesToFire(exp: 79, total: 100, already: {}), isEmpty);
      expect(budgetStagesToFire(exp: 85, total: 100, already: {}), [80]);
      expect(budgetStagesToFire(exp: 85, total: 100, already: {80}), isEmpty);
      expect(budgetStagesToFire(exp: 120, total: 100, already: {}), [80, 100]);
      expect(budgetStagesToFire(exp: 120, total: 100, already: {80}), [100]);
      expect(budgetStagesToFire(exp: 500, total: 0, already: {}), isEmpty);
    });

    test('parseFiredStages 容忍空/脏值', () {
      expect(parseFiredStages(null), isEmpty);
      expect(parseFiredStages('80,100'), {80, 100});
      expect(parseFiredStages('80,,x'), {80});
    });
  });

  group('nextDigestAt 小结时点', () {
    test('当月 1 日 09:00 未到用当月，否则次月 1 日', () {
      expect(nextDigestAt(DateTime(2026, 5, 1, 8, 59)),
          DateTime(2026, 5, 1, 9));
      expect(nextDigestAt(DateTime(2026, 5, 1, 9)),
          DateTime(2026, 6, 1, 9));
      expect(nextDigestAt(DateTime(2026, 12, 20)),
          DateTime(2027, 1, 1, 9));
    });
  });

  group('checkBudgetAlert 端到端（去重落 KV）', () {
    final now = DateTime(2026, 9, 15, 12);
    final month = '2026-09';

    test('达 80% 触发一次并落档；再查不重发；跨周期（10 月）重置', () async {
      await repo.setBudgetTotal(1, month, 100);
      await repo.setKv('ledger.monthStart', '1');
      await addExpense(85, '2026-09-10');
      expect(await checkBudgetAlert(repo, now: now), [80]);
      expect(await checkBudgetAlert(repo, now: now), isEmpty);
      // 档位 KV 已记 80
      expect(await repo.kv('ledger.budFired.1.$month'), '80');
      // 越 100% 触发 100 档
      await addExpense(20, '2026-09-12');
      expect(await checkBudgetAlert(repo, now: now), [100]);
      expect(await repo.kv('ledger.budFired.1.$month'), '80,100');
      // 下月重置：同一档位在 10 月可再发
      await repo.setBudgetTotal(1, '2026-10', 100);
      await addExpense(90, '2026-10-02');
      expect(await checkBudgetAlert(repo, now: DateTime(2026, 10, 5)), [80]);
    });

    test('开关关闭 → 不触发也不写档', () async {
      await repo.setBudgetTotal(1, month, 100);
      await repo.setBudgetAlert(false);
      await addExpense(120, '2026-09-10');
      expect(await checkBudgetAlert(repo, now: now), isEmpty);
      expect(await repo.kv('ledger.budFired.1.$month'), isNull);
    });
  });

  group('syncMonthlyDigest', () {
    test('开关开＝排下一枚 1 日 09:00 并返回当月口径文案（ready=false 仅降级送达）', () async {
      await repo.setMonthlyDigest(true);
      await addExpense(66, '2026-09-11');
      await addTxnIncome(repo, 300, '2026-09-05');
      final body = await syncMonthlyDigest(repo, now: DateTime(2026, 9, 15));
      expect(body, isNotNull);
      // 排程时点＝10 月 1 日 → 小结口径月＝2026-09（送达时的「上月」）。
      expect(body, contains('2026-09'));
      expect(body, contains('支出'));
      expect(body, contains('收入'));
    });

    test('开关关＝取消排程返回 null', () async {
      await repo.setMonthlyDigest(false);
      expect(await syncMonthlyDigest(repo, now: DateTime(2026, 9, 15)), isNull);
    });
  });

  test('免打扰顺延：23–7 点窗内一律推到最近 07:00', () {
    expect(NotificationService.inDndWindow(DateTime(2026, 9, 1, 23)), isTrue);
    expect(NotificationService.inDndWindow(DateTime(2026, 9, 1, 6, 59)), isTrue);
    expect(NotificationService.inDndWindow(DateTime(2026, 9, 1, 7)), isFalse);
    expect(NotificationService.deferOutOfDnd(DateTime(2026, 9, 1, 23, 30)),
        DateTime(2026, 9, 2, 7));
    expect(NotificationService.deferOutOfDnd(DateTime(2026, 9, 1, 2, 0)),
        DateTime(2026, 9, 1, 7));
    expect(NotificationService.deferOutOfDnd(DateTime(2026, 9, 1, 9, 0)),
        DateTime(2026, 9, 1, 9, 0));
  });
}

Future<void> addTxnIncome(LedgerRepository repo, double amt, String date) =>
    repo.addTxn(LedgerTxn(
        kind: LedgerTxn.kIncome,
        bk: 1,
        amt: amt,
        catId: 201,
        accountId: 1,
        date: date,
        note: 'w'));
