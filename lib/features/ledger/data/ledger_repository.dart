import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import '../domain/ledger_txn.dart';

/// 单条待导入流水：模板 + 可选「自动新建账户」下标（写入时解析真实 id）。
class ImportRowSpec {
  const ImportRowSpec(this.txn, {this.newAcctIndex});

  final LedgerTxn txn;
  final int? newAcctIndex;
}

/// 记账模块仓储（记账计划 §3/§4/§7 + 九·补1~6）。
///
/// 硬约束：
/// - **流水写入只走一条路径**：[addTxn]/[editTxn]/[delTxn]（导入走 [commitImport]），
///   同事务重算 `balance_cache` 物化列；五处联动（列表/合计/预算/环图/余额）由
///   presentation 层 tick 失效重取实现，禁止任何旁路直写；
/// - 双口径：unpaid 计收支不动余额；nb 从收支/分类/预算出口同时剔除
///   （聚合口径见 domain/ledger_calc.dart 纯函数）；
/// - 多账本：流水/预算按 bk 隔离；账户全局共用（余额=base+Σeff 跨账本合并）；
/// - 配置键一律 `ledger.` 前缀，落 settings 表 KV（ADR D11，同 habit.* 先例）。
class LedgerRepository {
  LedgerRepository(this.db);

  final Database db;

  /// COUNT(*) 助手（本 sqflite 版本无 count 便捷方法；与既有模块 rawQuery 同法）。
  Future<int> _c(DatabaseExecutor e, String table,
      {String? where, List<Object?>? whereArgs}) async {
    final rows = await e.rawQuery(
      'SELECT COUNT(*) c FROM $table${where == null ? '' : ' WHERE $where'}',
      whereArgs,
    );
    return rows.first['c']! as int;
  }

  // ==================== 设置 KV（计划 §7） ====================

  Future<String?> kv(String key) async {
    final rows = await db.query(
      DbSchema.tSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setKv(String key, String value) => db.insert(
        DbSchema.tSettings,
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<bool> hideAmounts() async => await kvBool('ledger.hideAmounts', false);

  Future<void> setHideAmounts(bool v) =>
      setKv('ledger.hideAmounts', v ? 'true' : 'false');

  /// 记一笔保存后行为：'back' 回主页 / 'stay' 留在表单。
  Future<String> afterSave() async => await kv('ledger.afterSave') ?? 'back';

  Future<void> setAfterSave(String v) => setKv('ledger.afterSave', v);

  Future<bool> confirmDel() async => await kvBool('ledger.confirmDel', true);

  Future<void> setConfirmDel(bool v) =>
      setKv('ledger.confirmDel', v ? 'true' : 'false');

  /// 预算月起始日（1 或 15；仅影响日均可用与结转周期显示，不改流水归属）。
  Future<int> monthStart() async => await kvInt('ledger.monthStart', 1);

  Future<void> setMonthStart(int d) => setKv('ledger.monthStart', '$d');

  /// 预算超支提醒开关（提醒注册批2 后段接线；键先行）。
  Future<bool> budgetAlert() async => await kvBool('ledger.budgetAlert', true);

  Future<void> setBudgetAlert(bool v) =>
      setKv('ledger.budgetAlert', v ? 'true' : 'false');

  /// 月度小结推送开关。
  Future<bool> monthlyDigest() async =>
      await kvBool('ledger.monthlyDigest', false);

  Future<void> setMonthlyDigest(bool v) =>
      setKv('ledger.monthlyDigest', v ? 'true' : 'false');

  /// 默认记账账户（未设置/失效回落首个未归档账户；§7 首账户）。
  Future<int?> defAcctId() async {
    final raw = await kv('ledger.defAcct');
    final id = int.tryParse(raw ?? '');
    if (id != null &&
        (await db.query(
          DbSchema.tLedgerAccounts,
          where: 'id = ? AND archived = 0',
          whereArgs: [id],
          limit: 1,
        ))
            .isNotEmpty) {
      return id;
    }
    final first = await db.query(
      DbSchema.tLedgerAccounts,
      where: 'archived = 0',
      orderBy: 'id ASC',
      limit: 1,
    );
    return first.isEmpty ? null : first.first['id'] as int;
  }

  Future<void> setDefAcct(int id) => setKv('ledger.defAcct', '$id');

  /// 当前账本（未设置/失效回落首账本）。
  Future<int> curBookId() async {
    final id = int.tryParse(await kv('ledger.book') ?? '');
    if (id != null &&
        (await db.query(
          DbSchema.tLedgerBooks,
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        ))
            .isNotEmpty) {
      return id;
    }
    final first = await db.query(
      DbSchema.tLedgerBooks,
      orderBy: 'sort ASC, id ASC',
      limit: 1,
    );
    return first.isEmpty ? 1 : first.first['id'] as int;
  }

  Future<void> setCurBook(int id) => setKv('ledger.book', '$id');

  /// 快速记一笔入口（最多 4 个、至少 1 个；默认原型 quick 集 [餐饮,交通,购物,居住]）。
  Future<List<int>> quickCats() async {
    final list = _decodeIntList(await kv('ledger.quick'));
    return list.isEmpty ? const [101, 102, 103, 104] : list;
  }

  Future<void> setQuickCats(List<int> ids) => setKv('ledger.quick', jsonEncode(ids));

  /// 顶部卡大数字位（九·补6：默认本月结余）。
  Future<String> heroBig() async => await kv('ledger.heroBig') ?? 'balMonth';

  Future<void> setHeroBig(String k) => setKv('ledger.heroBig', k);

  /// 顶部卡小槽 2/3/4（默认 本月支出/本月收入/日均支出）。
  Future<List<String>> heroSlots() async {
    final raw = await kv('ledger.hero');
    if (raw == null) return const ['teMonth', 'tiMonth', 'avgTe'];
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      return list.length == 3 ? list : const ['teMonth', 'tiMonth', 'avgTe'];
    } catch (_) {
      return const ['teMonth', 'tiMonth', 'avgTe'];
    }
  }

  Future<void> setHeroSlots(List<String> ks) =>
      setKv('ledger.hero', jsonEncode(ks));

  Future<int> kvInt(String key, int def) async =>
      int.tryParse(await kv(key) ?? '') ?? def;

  Future<bool> kvBool(String key, bool def) async {
    final v = await kv(key);
    return v == null ? def : v == 'true';
  }

  List<int> _decodeIntList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return const [];
    }
  }

  // ==================== 账本（九·补1） ====================

  Future<List<LedgerBook>> books() async {
    final rows =
        await db.query(DbSchema.tLedgerBooks, orderBy: 'sort ASC, id ASC');
    return [for (final r in rows) LedgerBook.fromRow(r)];
  }

  Future<int> addBook(String name) async => db.insert(DbSchema.tLedgerBooks, {
        'name': name.trim(),
        'sort': (await _c(db, DbSchema.tLedgerBooks)) + 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<void> renameBook(int id, String name) => db.update(
        DbSchema.tLedgerBooks,
        {'name': name.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 账本删除守卫：至少保留一个账本；账本内仍有流水禁删（非空账本禁删）。
  /// 返回 left=删后账本数，txns=0 成功 / >0 有流水 / -1 仅剩一本。
  Future<({int left, int txns})> delBook(int id) async {
    final total = await _c(db, DbSchema.tLedgerBooks);
    if (total <= 1) return (left: total, txns: -1);
    final n =
        await _c(db, DbSchema.tLedgerTxns, where: 'bk = ?', whereArgs: [id]);
    if (n > 0) return (left: total, txns: n);
    await db.delete(DbSchema.tLedgerBooks, where: 'id = ?', whereArgs: [id]);
    final cur = await kv('ledger.book');
    if (cur == '$id') {
      final first = await db.query(DbSchema.tLedgerBooks,
          orderBy: 'sort ASC, id ASC', limit: 1);
      await setCurBook(first.first['id']! as int);
    }
    return (left: total - 1, txns: 0);
  }

  Future<int> bookTxnCount(int id) =>
      _c(db, DbSchema.tLedgerTxns, where: 'bk = ?', whereArgs: [id]);

  /// 各账本流水数（S7 账本列表「N 笔流水」一次取齐）。
  Future<Map<int, int>> bookTxnCounts() async {
    final rows = await db.rawQuery(
      'SELECT bk, COUNT(*) AS n FROM ${DbSchema.tLedgerTxns} GROUP BY bk',
    );
    return {for (final r in rows) r['bk']! as int: r['n']! as int};
  }

  /// L1 到期横幅：当前账本启用中且 next_date ≤ 今天 的周期账单数（批2 前恒 0）。
  Future<int> dueRecurCount(int bk, String today) => _c(
    db,
    DbSchema.tLedgerRecur,
    where: 'bk = ? AND active = 1 AND next_date <= ?',
    whereArgs: [bk, today],
  );

  // ==================== 周期账单（批2d L9 · 九·补1 表带 bk） ====================

  /// 当前账本周期账单列表（原型 L.recur.filter(r=>r.bk===curBook)；插入序=id ASC）。
  Future<List<LedgerRecur>> recurs(int bk) async {
    final rows = await db.query(DbSchema.tLedgerRecur,
        where: 'bk = ?', whereArgs: [bk], orderBy: 'id ASC');
    return [for (final r in rows) LedgerRecur.fromRow(r)];
  }

  /// 到期行（横幅/L9 汇总同一查询）：active 且 next_date ≤ 今天。
  Future<List<LedgerRecur>> dueRecurs(int bk, String today) async {
    final rows = await db.query(
      DbSchema.tLedgerRecur,
      where: 'bk = ? AND active = 1 AND next_date <= ?',
      whereArgs: [bk, today],
      orderBy: 'id ASC',
    );
    return [for (final r in rows) LedgerRecur.fromRow(r)];
  }

  Future<int> addRecur(LedgerRecur r) =>
      db.insert(DbSchema.tLedgerRecur, r.toRow());

  /// 编辑落库（整行按 id 更新；不动流水，下次生成即取新参数——原型无编辑，
  /// 计划 §4 启停/新建外补编辑入口，字段与新建一致）。
  Future<void> updateRecur(int id, LedgerRecur r) => db.update(
        DbSchema.tLedgerRecur,
        r.toRow()..remove('id'),
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 启停开关（原型 row toggle：r.on=!r.on）。
  Future<void> setRecurActive(int id, bool on) =>
      db.update(DbSchema.tLedgerRecur, {'active': on ? 1 : 0},
          where: 'id = ?', whereArgs: [id]);

  /// 删除周期定义（原型 recDel：仅移除行，不动已生成流水）。
  Future<void> delRecur(int id) =>
      db.delete(DbSchema.tLedgerRecur, where: 'id = ?', whereArgs: [id]);

  /// 到期批量生成（原型 recGenDue → 逐条 recGen）：每行经统一 [addTxn] 写路径
  /// 落 expense 流水（source='recurring' + recurring_id，日期=next，备注=名称，
  /// 同事务回算余额），随后 next=recurNext(next, freq) 推进一个周期。
  /// 返回生成笔数；行内逐条原子（多行非单事务：与逐条点击生成语义一致）。
  Future<int> genDueRecur(int bk, String today) async {
    final due = await dueRecurs(bk, today);
    for (final r in due) {
      await addTxn(LedgerTxn(
        kind: LedgerTxn.kExpense,
        amt: r.amt,
        catId: r.catId,
        sub: r.sub,
        accountId: r.accountId,
        date: r.nextDate,
        note: r.name,
        source: LedgerTxn.kSourceRecurring,
        recurringId: r.id,
        bk: r.bk,
      ));
      await db.update(
        DbSchema.tLedgerRecur,
        {'next_date': recurNext(r.nextDate, r.freq)},
        where: 'id = ?',
        whereArgs: [r.id],
      );
    }
    return due.length;
  }

  // ==================== 账户（全局共用，不带 bk） ====================

  Future<List<LedgerAccount>> accounts({bool includeArchived = false}) async {
    final rows = await db.query(
      DbSchema.tLedgerAccounts,
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'id ASC',
    );
    return [for (final r in rows) LedgerAccount.fromRow(r)];
  }

  Future<LedgerAccount?> account(int id) async {
    final rows = await db.query(DbSchema.tLedgerAccounts,
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LedgerAccount.fromRow(rows.first);
  }

  Future<int> addAccount(LedgerAccount a) => db.transaction((txn) async {
        final id =
            await txn.insert(DbSchema.tLedgerAccounts, a.toRow());
        await _recomputeBalances(txn);
        return id;
      });

  Future<void> updateAccount(int id, Map<String, Object?> patch) =>
      db.transaction((txn) async {
        await txn.update(DbSchema.tLedgerAccounts, patch,
            where: 'id = ?', whereArgs: [id]);
        await _recomputeBalances(txn);
      });

  Future<void> setAccountArchived(int id, bool on) =>
      updateAccount(id, {'archived': on ? 1 : 0});

  /// 删除守卫：余额未清零或仍有引用流水不可删（§4 资产口径）。
  Future<bool> delAccount(int id) async {
    final a = await account(id);
    if (a == null) return false;
    if (a.balanceCache != 0) return false;
    final ref = await _c(db, DbSchema.tLedgerTxns,
        where: 'account_id = ? OR to_account_id = ?',
        whereArgs: [id, id]);
    if (ref > 0) return false;
    await db.delete(DbSchema.tLedgerAccounts, where: 'id = ?', whereArgs: [id]);
    return true;
  }

  /// 删除守卫（§4 资产口径 · 原型 delAccount）：仅「余额未清零」拒删，
  /// 清零即硬删账户（其历史流水保留，账户显示侧回落空名·同原型）。
  /// 返回 ok=已删除；bal=拦截时的当前余额（供 toast 文案）。
  Future<({bool ok, double bal})> delAccountGuarded(int id) async {
    final a = await account(id);
    if (a == null) return (ok: false, bal: 0.0);
    if (a.balanceCache != 0) return (ok: false, bal: a.balanceCache);
    await db.delete(DbSchema.tLedgerAccounts, where: 'id = ?', whereArgs: [id]);
    return (ok: true, bal: 0.0);
  }

  /// 近 6 月净资产走势（原型 netAt：全部账户[含归档] base+Σeff(date≤月末)，跨账本）。
  Future<List<({String label, double value})>> netWorthTrend({
    String? endMonth,
  }) async {
    final cur = endMonth ?? monthKey(DateTime.now());
    final accts = await accounts(includeArchived: true);
    final rows = await db.query(DbSchema.tLedgerTxns, orderBy: 'date ASC, id ASC');
    final txns = [for (final r in rows) LedgerTxn.fromRow(r)];
    final out = <({String label, double value})>[];
    for (var i = 5; i >= 0; i--) {
      final mth = monthStep(cur, -i);
      final cutoff = '$mth-${monthDayCount(mth).toString().padLeft(2, '0')}';
      var total = 0.0;
      for (final a in accts) {
        var s = a.base;
        for (final t in txns) {
          if (t.date.compareTo(cutoff) <= 0) s += t.eff(a.id);
        }
        total += s;
      }
      out.add((
        label: '${int.parse(mth.substring(5, 7))}月',
        value: double.parse(total.toStringAsFixed(2)),
      ));
    }
    return out;
  }

  // ==================== 流水统一写路径（finTouch 等价物） ====================

  /// 记一笔/生成流水。返回新行 id。
  Future<int> addTxn(LedgerTxn t) => db.transaction((txn) async {
        final row = t.toRow();
        row['created_at'] = DateTime.now().millisecondsSinceEpoch;
        final id = await txn.insert(DbSchema.tLedgerTxns, row);
        await _recomputeBalances(txn);
        return id;
      });

  /// 编辑流水（patch 为列名→值；调用方组装，同原型 ledgerEdit(id,patch) 口径）。
  Future<void> editTxn(int id, Map<String, Object?> patch) =>
      db.transaction((txn) async {
        await txn.update(DbSchema.tLedgerTxns, patch,
            where: 'id = ?', whereArgs: [id]);
        await _recomputeBalances(txn);
      });

  /// 删除流水：连带删除其全部退款（§4「删原支出连带删其 refund」）。
  Future<void> delTxn(int id) => db.transaction((txn) async {
        await txn.delete(DbSchema.tLedgerTxns,
            where: 'id = ? OR refund_of = ?', whereArgs: [id, id]);
        await _recomputeBalances(txn);
      });

  Future<LedgerTxn?> txnById(int id) async {
    final rows = await db.query(DbSchema.tLedgerTxns,
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LedgerTxn.fromRow(rows.first);
  }

  /// 生成退款冲抵流水：仅 expense 且未被退过，一笔仅退一次（§4 退款口径）。
  /// 返回新流水 id；不可退时返回 null。
  Future<int?> refundTxn(int originalId, {String? date}) async {
    final t = await txnById(originalId);
    if (t == null || t.kind != LedgerTxn.kExpense) return null;
    final already = await _c(db, DbSchema.tLedgerTxns,
        where: 'refund_of = ?', whereArgs: [originalId]);
    if (already > 0) return null;
    return addTxn(LedgerTxn(
      kind: LedgerTxn.kRefund,
      amt: t.amt,
      catId: t.catId,
      sub: t.sub,
      accountId: t.accountId,
      date: date ?? dayKey(DateTime.now()),
      note: '退款 · ${t.note.isEmpty ? (await catName(t.catId)) : t.note}',
      source: LedgerTxn.kSourceManual,
      refundOf: originalId,
      bk: t.bk,
    ));
  }

  /// 「调整余额」：与目标值的差量生成 adjust 流水（§4 资产口径）。
  Future<void> adjustBalance(int accountId, double target, {int? bk}) async {
    final a = await account(accountId);
    if (a == null) return;
    final delta = double.parse((target - a.balanceCache).toStringAsFixed(2));
    if (delta.abs() < 0.005) return;
    await addTxn(LedgerTxn(
      kind: LedgerTxn.kAdjust,
      amt: delta,
      catId: DbSchema.ledgerCatOtherExpense,
      accountId: accountId,
      date: dayKey(DateTime.now()),
      note: '余额调整',
      bk: bk ?? await curBookId(),
    ));
  }

  /// 写路径同事务全量重算 balance_cache（余额=base+Σeff 跨账本合并）。
  Future<void> _recomputeBalances(DatabaseExecutor e) async {
    final accts = await e.query(DbSchema.tLedgerAccounts);
    final txns = await e.query(DbSchema.tLedgerTxns);
    final models = [for (final r in txns) LedgerTxn.fromRow(r)];
    for (final a in accts) {
      final id = a['id']! as int;
      final bal = (a['base']! as num).toDouble() +
          models.fold<double>(0, (s, t) => s + t.eff(id));
      await e.update(
        DbSchema.tLedgerAccounts,
        {'balance_cache': double.parse(bal.toStringAsFixed(2))},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ---- 查询 ----

  /// 当前账本全部流水（指标引擎/近30天 chips 用）。
  Future<List<LedgerTxn>> bookTxns(int bk) async {
    final rows = await db.query(DbSchema.tLedgerTxns,
        where: 'bk = ?', whereArgs: [bk], orderBy: 'date ASC, id ASC');
    return [for (final r in rows) LedgerTxn.fromRow(r)];
  }

  Future<List<LedgerTxn>> monthTxns(int bk, String month) async {
    final rows = await db.query(
      DbSchema.tLedgerTxns,
      where: "bk = ? AND date LIKE ?",
      whereArgs: [bk, '$month-%'],
      orderBy: 'date ASC, id ASC',
    );
    return [for (final r in rows) LedgerTxn.fromRow(r)];
  }

  /// 近 30 天流水（高频 chips 统计窗口；九·补1）。
  Future<List<LedgerTxn>> last30Txns(int bk) async {
    final from = dayKey(DateTime.now().subtract(const Duration(days: 29)));
    final rows = await db.query(
      DbSchema.tLedgerTxns,
      where: 'bk = ? AND date >= ?',
      whereArgs: [bk, from],
      orderBy: 'date ASC, id ASC',
    );
    return [for (final r in rows) LedgerTxn.fromRow(r)];
  }

  /// 单账户流水（L7 账户详情·批2 用）。
  Future<List<LedgerTxn>> acctTxns(int accountId, {int limit = 40}) async {
    final rows = await db.query(
      DbSchema.tLedgerTxns,
      where: 'account_id = ? OR to_account_id = ?',
      whereArgs: [accountId, accountId],
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return [for (final r in rows) LedgerTxn.fromRow(r)];
  }

  /// L15 导出分页查询（批3b·计划书 §5「导出流式落盘」）：按当前账本 bk + 可选
  /// 范围条件（month=该月 · accountId=转入/转出双向 · catId=等值）以
  /// date ASC, id ASC 稳定序 LIMIT/OFFSET 逐页取；写盘侧消费到不足一页为止，
  /// 大流水不整表进内存。
  Future<List<LedgerTxn>> exportTxnsPage(
    int bk, {
    String? month,
    int? accountId,
    int? catId,
    int offset = 0,
    int limit = 200,
    // 余量批3：日期区间（`YYYY-MM-DD` 闭区间；与 timeRange 同口径）。
    // 与 month 参数并存时取交集（面板不会同时给，但调用方安全）。
    String? dateFrom,
    String? dateTo,
  }) async {
    final where = ['bk = ?'];
    final args = <Object?>[bk];
    if (month != null) {
      where.add('date LIKE ?');
      args.add('$month-%');
    }
    if (dateFrom != null) {
      where.add('date >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null) {
      where.add('date <= ?');
      args.add(dateTo);
    }
    if (accountId != null) {
      where.add('(account_id = ? OR to_account_id = ?)');
      args.addAll([accountId, accountId]);
    }
    if (catId != null) {
      where.add('cat_id = ?');
      args.add(catId);
    }
    final rows = await db.query(
      DbSchema.tLedgerTxns,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date ASC, id ASC',
      limit: limit,
      offset: offset,
    );
    return [for (final r in rows) LedgerTxn.fromRow(r)];
  }

  // ==================== 分类（独立两级树 ledger_categories） ====================

  /// 全部分类行（大类+子分类；UI 侧组树）。
  Future<List<LedgerCat>> cats() async {
    final rows = await db.query(DbSchema.tLedgerCategories,
        orderBy: 'parent_id IS NOT NULL, sort ASC, id ASC');
    return [for (final r in rows) LedgerCat.fromRow(r)];
  }

  Future<String> catName(int? id) async {
    if (id == null) return '其他';
    final rows = await db.query(DbSchema.tLedgerCategories,
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? '其他' : rows.first['name']! as String;
  }

  Future<int> addMajorCat(
          String kind, String name, String icon, String color) async =>
      db.insert(DbSchema.tLedgerCategories, {
        'kind': kind,
        'parent_id': null,
        'name': name.trim(),
        'icon': icon,
        'color': color,
        'sort': await _c(db, DbSchema.tLedgerCategories,
                where: 'parent_id IS NULL AND kind = ?',
                whereArgs: [kind]) +
            1,
      });

  /// 新增子分类（id=大类*10+序，与种子编号规则一致；冲突回落自增）。
  Future<int> addSubCat(int parentId, String name) async {
    final parent = await db.query(DbSchema.tLedgerCategories,
        where: 'id = ?', whereArgs: [parentId], limit: 1);
    if (parent.isEmpty) throw ArgumentError('父分类不存在: $parentId');
    final kind = parent.first['kind']! as String;
    final color = (parent.first['color'] as String?) ?? '#94a3b8';
    final icon = (parent.first['icon'] as String?) ?? 'dots';
    final siblings = await _c(db, DbSchema.tLedgerCategories,
        where: 'parent_id = ?', whereArgs: [parentId]);
    final guess = parentId * 10 + siblings + 1;
    final conflict = await db.query(DbSchema.tLedgerCategories,
        where: 'id = ?', whereArgs: [guess], limit: 1);
    final row = {
      'kind': kind,
      'parent_id': parentId,
      'name': name.trim(),
      'icon': icon,
      'color': color,
      'sort': siblings + 1,
    };
    if (conflict.isEmpty) {
      return db.insert(DbSchema.tLedgerCategories, {'id': guess, ...row});
    }
    return db.insert(DbSchema.tLedgerCategories, row);
  }

  Future<void> renameMajorCat(int id, String name) => db.update(
      DbSchema.tLedgerCategories,
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id]);

  /// 子分类改名：同步历史流水 sub 字段与收藏（九·补1/实现提示口径）。
  Future<void> renameSubCat(int catId, String oldName, String newName) =>
      db.transaction((txn) async {
        await txn.rawUpdate(
          'UPDATE ${DbSchema.tLedgerTxns} SET sub = ? '
          'WHERE cat_id = ? AND sub = ?',
          [newName.trim(), catId, oldName],
        );
        await txn.rawUpdate(
          'UPDATE OR IGNORE ${DbSchema.tLedgerFav} SET sub = ? '
          'WHERE cat_id = ? AND sub = ?',
          [newName.trim(), catId, oldName],
        );
      });

  Future<void> setCatStyle(int id, {String? icon, String? color}) => db.update(
        DbSchema.tLedgerCategories,
        {if (icon != null) 'icon': icon, if (color != null) 'color': color}, // ignore: use_null_aware_elements
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 大类删除：其流水整体迁移至对应收支树的「其他」；兜底分类不可删。
  /// migrated：>=0 迁移条数；-1 分类不存在；-2 兜底不可删。
  Future<({int migrated})> delCat(int id) async {
    final rows = await db.query(DbSchema.tLedgerCategories,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return (migrated: -1);
    final kind = rows.first['kind']! as String;
    final fallback = kind == LedgerCat.kIncome
        ? DbSchema.ledgerCatOtherIncome
        : DbSchema.ledgerCatOtherExpense;
    if (id == fallback) return (migrated: -2);
    return db.transaction((txn) async {
      final n = await txn.update(DbSchema.tLedgerTxns,
          {'cat_id': fallback, 'sub': ''},
          where: 'cat_id = ?', whereArgs: [id]);
      await txn.delete(DbSchema.tLedgerCategories,
          where: 'id = ? OR parent_id = ?', whereArgs: [id, id]);
      await txn.delete(DbSchema.tLedgerFav,
          where: 'cat_id = ?', whereArgs: [id]);
      return (migrated: n);
    });
  }

  /// 子分类删除：其流水回落「未细分」（sub 置空）。
  Future<void> delSubCat(int parentId, String subName) =>
      db.transaction((txn) async {
        await txn.update(DbSchema.tLedgerTxns, {'sub': ''},
            where: 'cat_id = ? AND sub = ?',
            whereArgs: [parentId, subName]);
        await txn.delete(DbSchema.tLedgerCategories,
            where: 'parent_id = ? AND name = ?',
            whereArgs: [parentId, subName]);
        await txn.delete(DbSchema.tLedgerFav,
            where: 'cat_id = ? AND sub = ?',
            whereArgs: [parentId, subName]);
      });

  /// 长按拖动/上下移：同树内按给定序回写 sort（九·补2 ③）。
  Future<void> reorderMajors(String kind, List<int> orderedIds) =>
      db.transaction((txn) async {
        for (var i = 0; i < orderedIds.length; i++) {
          await txn.update(DbSchema.tLedgerCategories, {'sort': i + 1},
              where: 'id = ?', whereArgs: [orderedIds[i]]);
        }
      });

  /// 收藏（常用类别 = 星标收藏子分类；原型 L.fav 'cat|sub' 落表）。
  Future<List<(int, String)>> favs() async {
    final rows = await db.query(DbSchema.tLedgerFav,
        columns: ['cat_id', 'sub'], orderBy: 'rowid ASC');
    return [
      for (final r in rows) (r['cat_id']! as int, (r['sub'] as String?) ?? '')
    ];
  }

  Future<bool> toggleFav(int catId, String sub) async {
    final exist = await db.query(DbSchema.tLedgerFav,
        where: 'cat_id = ? AND sub = ?', whereArgs: [catId, sub], limit: 1);
    if (exist.isEmpty) {
      await db.insert(DbSchema.tLedgerFav, {'cat_id': catId, 'sub': sub});
      return true;
    }
    await db.delete(DbSchema.tLedgerFav,
        where: 'cat_id = ? AND sub = ?', whereArgs: [catId, sub]);
    return false;
  }

  // ---- L8 分类管理补充（批2d） ----

  /// 分类引用流水数（删除守卫文案「该分类下有 N 笔流水」按当前账本口径，
  /// 同原型 delCat 的 `t.cat===id && t.bk===curBook`）。
  Future<int> catTxnCount(int catId, int bk) =>
      _c(db, DbSchema.tLedgerTxns,
          where: 'cat_id = ? AND bk = ?', whereArgs: [catId, bk]);

  /// 隐藏/恢复（ledger_categories.hidden；种子恒 0，不影响既有选择器口径）。
  Future<void> setCatHidden(int catId, bool on) => db.update(
        DbSchema.tLedgerCategories,
        {'hidden': on ? 1 : 0},
        where: 'id = ?',
        whereArgs: [catId],
      );

  /// 子分类行改名（批2d L8；大类用既有 [renameMajorCat]。历史流水 sub 与收藏
  /// 同步走既有 [renameSubCat]，两者由页面按序组合调用）。
  Future<void> renameCat(int id, String name) => db.update(
        DbSchema.tLedgerCategories,
        {'name': name.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 子分类同列表重排（九·补2 ③「大类/子分类均长按拖动排序，同列表内重排」；
  /// 大类用既有 [reorderMajors]）。
  Future<void> reorderSubs(int parentId, List<int> orderedIds) =>
      db.transaction((txn) async {
        for (var i = 0; i < orderedIds.length; i++) {
          await txn.update(DbSchema.tLedgerCategories, {'sort': i + 1},
              where: 'id = ? AND parent_id = ?',
              whereArgs: [orderedIds[i], parentId]);
        }
      });

  // ==================== 预算（cat_id=0 行=总预算+结转位；bk 隔离） ====================

  Future<LedgerBudget> budgetOf(int bk, String month) async {
    final rows = await db.query(DbSchema.tLedgerBudgets,
        where: 'bk = ? AND month = ?', whereArgs: [bk, month]);
    var total = 0.0;
    var carry = false;
    final perCat = <int, double>{};
    for (final r in rows) {
      final cid = r['cat_id']! as int;
      final amt = (r['amt']! as num).toDouble();
      if (cid == 0) {
        total = amt;
        carry = (r['carry']! as int) != 0;
      } else if (amt > 0) {
        perCat[cid] = amt;
      }
    }
    return LedgerBudget(total: total, carry: carry, perCat: perCat);
  }

  Future<void> setBudgetTotal(int bk, String month, double total) async {
    final rows = await db.query(DbSchema.tLedgerBudgets,
        where: 'bk = ? AND month = ? AND cat_id = 0',
        whereArgs: [bk, month],
        limit: 1);
    final carry =
        rows.isEmpty ? 0 : (rows.first['carry']! as int);
    await db.insert(DbSchema.tLedgerBudgets,
        {'bk': bk, 'month': month, 'cat_id': 0, 'amt': total, 'carry': carry},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setBudgetCarry(int bk, String month, bool on) async {
    final rows = await db.query(DbSchema.tLedgerBudgets,
        where: 'bk = ? AND month = ? AND cat_id = 0',
        whereArgs: [bk, month],
        limit: 1);
    final amt = rows.isEmpty ? 0.0 : (rows.first['amt']! as num).toDouble();
    await db.insert(
        DbSchema.tLedgerBudgets,
        {
          'bk': bk,
          'month': month,
          'cat_id': 0,
          'amt': amt,
          'carry': on ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setBudgetCat(int bk, String month, int catId, double amt) =>
      amt <= 0
          ? db.delete(DbSchema.tLedgerBudgets,
              where: 'bk = ? AND month = ? AND cat_id = ?',
              whereArgs: [bk, month, catId])
          : db.insert(
              DbSchema.tLedgerBudgets,
              {'bk': bk, 'month': month, 'cat_id': catId, 'amt': amt},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

  // ==================== 角色 / 标签 / 商家（九·补5 两级化） ====================

  Future<List<LedgerWho>> whos() async {
    final rows = await db.query(DbSchema.tLedgerWhos,
        orderBy: 'sort ASC, id ASC');
    return [for (final r in rows) LedgerWho.fromRow(r)];
  }

  Future<String> whoDefName() async {
    final rows = await db
        .query(DbSchema.tLedgerWhos, where: 'is_default = 1', limit: 1);
    if (rows.isNotEmpty) return rows.first['name']! as String;
    final any = await db
        .query(DbSchema.tLedgerWhos, orderBy: 'sort ASC', limit: 1);
    return any.isEmpty ? '自己' : any.first['name']! as String;
  }

  /// 返回 false = 重名拒绝。
  Future<bool> addWho(String name) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (await _c(db, DbSchema.tLedgerWhos,
            where: 'name = ?', whereArgs: [n]) >
        0) {
      return false;
    }
    await db.insert(DbSchema.tLedgerWhos,
        {'name': n, 'is_default': 0, 'sort': (await _c(db, DbSchema.tLedgerWhos)) + 1});
    return true;
  }

  /// 角色改名：同步历史流水 who 字段（同子分类改名口径）。
  Future<void> renameWho(int id, String newName) => db.transaction((txn) async {
        final rows = await txn.query(DbSchema.tLedgerWhos,
            where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) return;
        final old = rows.first['name']! as String;
        await txn.update(DbSchema.tLedgerWhos, {'name': newName.trim()},
            where: 'id = ?', whereArgs: [id]);
        await txn.update(DbSchema.tLedgerTxns, {'who': newName.trim()},
            where: 'who = ?', whereArgs: [old]);
      });

  /// 默认角色不可删；至少保留一个（九·补5 交互口径）。
  Future<bool> delWho(int id) async {
    final rows = await db.query(DbSchema.tLedgerWhos,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return false;
    if ((rows.first['is_default']! as int) != 0) return false;
    if (await _c(db, DbSchema.tLedgerWhos) <= 1) return false;
    await db.delete(DbSchema.tLedgerWhos, where: 'id = ?', whereArgs: [id]);
    return true;
  }

  Future<void> setDefaultWho(int id) => db.transaction((txn) async {
        await txn.update(DbSchema.tLedgerWhos, {'is_default': 0});
        await txn.update(DbSchema.tLedgerWhos, {'is_default': 1},
            where: 'id = ?', whereArgs: [id]);
      });

  Future<void> moveWho(int id, int delta) =>
      _moveBySort(DbSchema.tLedgerWhos, id, delta);

  Future<List<LedgerTagGroup>> tagGroups() async {
    final gs = await db.query(DbSchema.tLedgerTagGroups,
        orderBy: 'sort ASC, id ASC');
    final ts = await db.query(DbSchema.tLedgerTags,
        orderBy: 'sort ASC, id ASC');
    return [
      for (final g in gs)
        LedgerTagGroup(
          id: g['id']! as int,
          name: g['name']! as String,
          sort: g['sort']! as int,
          tags: [
            for (final t in ts)
              if (t['group_id'] == g['id']) t['name']! as String
          ],
        ),
    ];
  }

  Future<bool> addTagGroup(String name) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (await _c(db, DbSchema.tLedgerTagGroups,
            where: 'name = ?', whereArgs: [n]) >
        0) {
      return false;
    }
    await db.insert(
        DbSchema.tLedgerTagGroups, {'name': n, 'sort': (await _c(db, DbSchema.tLedgerTagGroups)) + 1});
    return true;
  }

  Future<void> renameTagGroup(int id, String name) => db.update(
      DbSchema.tLedgerTagGroups,
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id]);

  /// 删组（至少保留一个分组；组内标签一并移除，
  /// 流水残留标签字符串由显示侧按目录过滤静默忽略——九·补5 实现提示）。
  Future<bool> delTagGroup(int id) async {
    if (await _c(db, DbSchema.tLedgerTagGroups) <= 1) return false;
    await db.transaction((txn) async {
      await txn.delete(
          DbSchema.tLedgerTags, where: 'group_id = ?', whereArgs: [id]);
      await txn.delete(
          DbSchema.tLedgerTagGroups, where: 'id = ?', whereArgs: [id]);
    });
    return true;
  }

  Future<void> moveTagGroup(int id, int delta) =>
      _moveBySort(DbSchema.tLedgerTagGroups, id, delta);

  Future<bool> addTag(int groupId, String name) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (await _c(db, DbSchema.tLedgerTags,
            where: 'name = ?', whereArgs: [n]) >
        0) {
      return false;
    }
    await db.insert(DbSchema.tLedgerTags, {
      'group_id': groupId,
      'name': n,
      'sort': (await _c(db, DbSchema.tLedgerTags,
              where: 'group_id = ?', whereArgs: [groupId])) +
          1,
    });
    return true;
  }

  /// 标签改名：全表同步流水 tags JSON（实现提示口径）。
  Future<void> renameTag(String oldName, String newName) async {
    final rows = await db.query(DbSchema.tLedgerTxns,
        columns: ['id', 'tags'],
        where: 'tags LIKE ?',
        whereArgs: ['%$oldName%']);
    for (final r in rows) {
      final tags = LedgerTxn.decodeTags(r['tags'] as String?);
      if (!tags.contains(oldName)) continue;
      await db.update(
        DbSchema.tLedgerTxns,
        {
          'tags': LedgerTxn.encodeTags(
              [for (final t in tags) t == oldName ? newName.trim() : t])
        },
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    await db.update(DbSchema.tLedgerTags, {'name': newName.trim()},
        where: 'name = ?', whereArgs: [oldName]);
  }

  /// 标签删除：流水残留字符串静默忽略（不动流水）。
  Future<void> delTag(String name) => db.delete(
      DbSchema.tLedgerTags,
      where: 'name = ?',
      whereArgs: [name]);

  Future<void> moveTag(int groupId, String tagName, int delta) async {
    final rows = await db.query(DbSchema.tLedgerTags,
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'sort ASC, id ASC');
    final idx = rows.indexWhere((r) => r['name'] == tagName);
    final j = idx + delta;
    if (idx < 0 || j < 0 || j >= rows.length) return;
    await db.transaction((txn) async {
      final a = rows[idx], b = rows[j];
      await txn.update(DbSchema.tLedgerTags, {'sort': b['sort']},
          where: 'id = ?', whereArgs: [a['id']]);
      await txn.update(DbSchema.tLedgerTags, {'sort': a['sort']},
          where: 'id = ?', whereArgs: [b['id']]);
    });
  }

  Future<List<LedgerMerchant>> merchants() async {
    final rows = await db.query(DbSchema.tLedgerMerchants,
        orderBy: 'sort ASC, id ASC');
    return [for (final r in rows) LedgerMerchant.fromRow(r)];
  }

  Future<bool> addMerchant(String name) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (await _c(db, DbSchema.tLedgerMerchants,
            where: 'name = ?', whereArgs: [n]) >
        0) {
      return false;
    }
    await db.insert(DbSchema.tLedgerMerchants,
        {'name': n, 'sort': (await _c(db, DbSchema.tLedgerMerchants)) + 1});
    return true;
  }

  Future<void> renameMerchant(int id, String newName) =>
      db.transaction((txn) async {
        final rows = await txn.query(DbSchema.tLedgerMerchants,
            where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) return;
        final old = rows.first['name']! as String;
        await txn.update(DbSchema.tLedgerMerchants, {'name': newName.trim()},
            where: 'id = ?', whereArgs: [id]);
        await txn.update(DbSchema.tLedgerTxns, {'merchant': newName.trim()},
            where: 'merchant = ?', whereArgs: [old]);
      });

  Future<void> delMerchant(int id) => db.delete(DbSchema.tLedgerMerchants,
      where: 'id = ?', whereArgs: [id]);

  Future<void> moveMerchant(int id, int delta) =>
      _moveBySort(DbSchema.tLedgerMerchants, id, delta);

  // ==================== 心愿单（批3a L10 · 九·补1 表带 bk） ====================

  /// 心愿兑换支出归类「购物」（原型 wishRedeem `cat:'shop'` → 种子大类 id 103）。
  static const int _catShop = 103;

  /// 当前账本心愿列表（原型 L.wishes.filter(bk)；UI 侧按 done 分实现/未实现组）。
  Future<List<LedgerWish>> wishes(int bk) async {
    final rows = await db.query(DbSchema.tLedgerWishes,
        where: 'bk = ?', whereArgs: [bk], orderBy: 'id ASC');
    return [for (final r in rows) LedgerWish.fromRow(r)];
  }

  Future<LedgerWish?> wishById(int id) async {
    final rows = await db.query(DbSchema.tLedgerWishes,
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LedgerWish.fromRow(rows.first);
  }

  /// 新建心愿（原型 wishAdd：saved 恒 0；守卫 target>0 由 UI 侧把关）。
  Future<int> addWish({
    required int bk,
    required String name,
    required double target,
  }) =>
      db.insert(DbSchema.tLedgerWishes, {
        'bk': bk,
        'name': name.trim(),
        'target': target,
        'saved': 0,
        'done': 0,
      });

  /// 编辑心愿名称/目标（原型无编辑入口，本批按交付物补；不动 saved/done）。
  Future<void> updateWish(int id, {required String name, required double target}) =>
      db.update(
        DbSchema.tLedgerWishes,
        {'name': name.trim(), 'target': target},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 存入/取出进度（原型 wishSave/wishTake：仅改 saved，**不落流水** §10 U-2）。
  /// [delta] 正=存入、负=取出；saved 下限 0（原型 `Math.max(0,saved-v)`）。
  Future<void> bumpWishSaved(int id, double delta) async {
    final w = await wishById(id);
    if (w == null) return;
    final next = w.saved + delta;
    await db.update(
      DbSchema.tLedgerWishes,
      {'saved': next < 0 ? 0.0 : next},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除心愿（原型卡片 trash：仅移除行，不动已生成流水）。
  Future<void> delWish(int id) =>
      db.delete(DbSchema.tLedgerWishes, where: 'id = ?', whereArgs: [id]);

  /// 兑换归档（原型 wishRedeem + §4「saved≥target 才可用；选账户生成 expense
  /// 并归档」）：走统一 [addTxn] 写路径落 expense（source='wish'+wish_id、
  /// 归类购物、金额=target、账户=所选），随后回写 done/done_date/done_txn 且
  /// saved 归零（原型 w.saved=0）。守卫未达成直接拒绝、不生成流水。返回 true=已兑换。
  Future<bool> redeemWish(int id, {required int accountId}) async {
    final w = await wishById(id);
    if (w == null || !w.achieved) return false; // saved<target 拒绝（§4 守卫）
    final today = dayKey(DateTime.now());
    final txnId = await addTxn(LedgerTxn(
      kind: LedgerTxn.kExpense,
      amt: w.target,
      catId: _catShop,
      sub: '',
      accountId: accountId,
      date: today,
      note: '心愿兑现 · ${w.name}',
      source: LedgerTxn.kSourceWish,
      wishId: w.id,
      bk: w.bk,
    ));
    await db.update(
      DbSchema.tLedgerWishes,
      {'done': 1, 'done_date': today, 'done_txn': txnId, 'saved': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  // ==================== 借贷（§4 记一笔·借贷 tab 直写 / 批3a L11） ====================

  /// side：'lend' 借出（别人欠我）/ 'borrow' 借入（我欠别人）。
  Future<int> addDebt({
    required int bk,
    required String side,
    required String person,
    required double total,
    String note = '',
  }) =>
      db.insert(DbSchema.tLedgerDebts, {
        'bk': bk,
        'side': side,
        'person': person.trim(),
        'total': total,
        'paid': 0,
        'note': note,
      });

  /// 当前账本借贷列表（原型 L.debts.filter(bk)；UI 侧按 side 分组/筛选）。
  Future<List<LedgerDebt>> debts(int bk) async {
    final rows = await db.query(DbSchema.tLedgerDebts,
        where: 'bk = ?', whereArgs: [bk], orderBy: 'id ASC');
    return [for (final r in rows) LedgerDebt.fromRow(r)];
  }

  Future<LedgerDebt?> debtById(int id) async {
    final rows = await db.query(DbSchema.tLedgerDebts,
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LedgerDebt.fromRow(rows.first);
  }

  /// 删除借贷行（原型卡片「删」：仅移除行，不动已生成流水）。
  Future<void> delDebt(int id) =>
      db.delete(DbSchema.tLedgerDebts, where: 'id = ?', whereArgs: [id]);

  /// 借贷流水归类/方向（原型 debtPay/debtClose）：
  /// - 借出收还款=实际收款 → income，归类「其他收入」(oi→种子 207)；
  /// - 借入还欠款=实际付款 → expense，归类「其他支出」(oe→种子 114)；
  /// [settle] true 生成「结清」备注，false 生成「还款」备注。
  Future<int> _debtFlow(
    LedgerDebt d, {
    required double amt,
    required int accountId,
    required bool settle,
  }) {
    final lend = d.isLend;
    return addTxn(LedgerTxn(
      kind: lend ? LedgerTxn.kIncome : LedgerTxn.kExpense,
      amt: amt,
      catId: lend
          ? DbSchema.ledgerCatOtherIncome
          : DbSchema.ledgerCatOtherExpense,
      sub: '',
      accountId: accountId,
      date: dayKey(DateTime.now()),
      note: settle
          ? (lend ? '${d.person} 结清' : '结清 ${d.person}')
          : (lend ? '${d.person} 还款' : '还 ${d.person}'),
      source: LedgerTxn.kSourceDebt,
      debtId: d.id,
      bk: d.bk,
    ));
  }

  /// 记还款（原型 debtPay：金额滚轮 → 生成实际流水 + paid 回写进度）。
  /// 账户=默认账户（原型 `a:L.set.defAcct`，非选择器）；paid=min(total,paid+v)，
  /// 流水金额=滚轮 v 全额（原型 amt:v，即使超出剩余）。v≤0 拒绝、不落库。返回 true=已记。
  Future<bool> payDebt(int id, double v, {int? accountId}) async {
    if (v <= 0) return false; // 原型 if(!v)return
    final d = await debtById(id);
    if (d == null) return false;
    final acct = accountId ?? await defAcctId();
    if (acct == null) return false;
    final np = d.paid + v;
    await _debtFlow(d, amt: v, accountId: acct, settle: false);
    await db.update(
      DbSchema.tLedgerDebts,
      {'paid': np > d.total ? d.total : np},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  /// 结清（原型 debtClose：选账户；剩余 left>0 才补一笔实际流水，随后 paid=total）。
  /// 账户=所选（openLedgerAcctPick '结清账户'）。返回 true=已结清。
  Future<bool> settleDebt(int id, {required int accountId}) async {
    final d = await debtById(id);
    if (d == null) return false;
    final left = d.left;
    if (left > 0.005) {
      // 原型 if(left>0)：已结清行不再补流水，仅重置 paid=total。
      await _debtFlow(d, amt: left, accountId: accountId, settle: true);
    }
    await db.update(
      DbSchema.tLedgerDebts,
      {'paid': d.total},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  /// 同表相邻交换 sort（管理态 ↑↓ 钮通用实现）。
  Future<void> _moveBySort(String table, int id, int delta) =>
      db.transaction((txn) async {
        final rows = await txn.query(table, orderBy: 'sort ASC, id ASC');
        final idx = rows.indexWhere((r) => r['id'] == id);
        final j = idx + delta;
        if (idx < 0 || j < 0 || j >= rows.length) return;
        final a = rows[idx], b = rows[j];
        await txn.update(table, {'sort': b['sort']},
            where: 'id = ?', whereArgs: [a['id']]);
        await txn.update(table, {'sort': a['sort']},
            where: 'id = ?', whereArgs: [b['id']]);
      });

  // ==================== 账单导入（九·补4 · 五步向导落库层） ====================

  /// bill_hash：交易单号优先；缺失时「时间|金额|对方」组合键
  /// （同 read 模块 dedup_hash 明文先例，UNIQUE 索引兜底）。
  static String billHashOf({
    String? tradeNo,
    String? date,
    String? time,
    double? amt,
    String? counterparty,
  }) {
    final no = tradeNo?.trim();
    if (no != null && no.isNotEmpty) return no;
    return '${date ?? ''} ${time ?? ''}|${(amt ?? 0).toStringAsFixed(2)}|${counterparty ?? ''}';
  }

  /// 该哈希是否已存在（预览步「重复命中」判定）。
  Future<bool> billHashExists(String hash) async =>
      await _c(db, DbSchema.tLedgerTxns,
          where: 'bill_hash = ?', whereArgs: [hash]) >
      0;

  /// 确认导入：同事务建所选新账户 + 按勾选写 src='bill' 流水 + 登记批次。
  /// 强制导入的重复行在哈希后拼 `#fN` 变体，绕开 UNIQUE 且保留原键可追溯。
  Future<({int batchId, int written})> commitImport({
    required int bk,
    required String platform,
    String? fileName,
    List<LedgerAccount> newAccounts = const [],
    required List<ImportRowSpec> rows,
  }) =>
      db.transaction((txn) async {
        final acctIds = <int?>[];
        for (final a in newAccounts) {
          acctIds.add(await txn.insert(DbSchema.tLedgerAccounts, a.toRow()));
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final batchId = await txn.insert(DbSchema.tLedgerImportBatches, {
          'bk': bk,
          'platform': platform,
          'file_name': fileName,
          'written': 0,
          'new_account_ids': jsonEncode(acctIds),
          'created_at': now,
        });
        var written = 0;
        for (final r in rows) {
          final row = r.txn.toRow();
          if (r.newAcctIndex != null) {
            row['account_id'] = acctIds[r.newAcctIndex!];
          }
          row['bk'] = bk;
          row['imp_batch'] = batchId;
          row['created_at'] = now;
          final hash = row['bill_hash'] as String?;
          if (hash != null && hash.isNotEmpty) {
            var h = hash;
            var k = 0;
            while ((await txn.query(DbSchema.tLedgerTxns,
                        where: 'bill_hash = ?', whereArgs: [h], limit: 1))
                    .isNotEmpty) {
              h = '$hash#f${++k}';
            }
            row['bill_hash'] = h;
          }
          await txn.insert(DbSchema.tLedgerTxns, row);
          written++;
        }
        await txn.update(DbSchema.tLedgerImportBatches, {'written': written},
            where: 'id = ?', whereArgs: [batchId]);
        await _recomputeBalances(txn);
        return (batchId: batchId, written: written);
      });

  /// 批次列表（撤销入口在导入完成页与设置页；批3 全量接线）。
  Future<List<Map<String, Object?>>> importBatches() =>
      db.query(DbSchema.tLedgerImportBatches, orderBy: 'created_at DESC');

  /// 整批撤销：删本批全部流水；可选回收本批新建且已无引用、余额为 0 的账户。
  Future<int> undoImportBatch(int batchId, {bool reclaimAccounts = false}) =>
      db.transaction((txn) async {
        final n = await txn.delete(DbSchema.tLedgerTxns,
            where: 'imp_batch = ?', whereArgs: [batchId]);
        if (reclaimAccounts) {
          final batch = await txn.query(DbSchema.tLedgerImportBatches,
              where: 'id = ?', whereArgs: [batchId], limit: 1);
          if (batch.isNotEmpty) {
            final ids = _decodeIntList(batch.first['new_account_ids'] as String?);
            for (final id in ids) {
              final refs = await txn.query(DbSchema.tLedgerTxns,
                  columns: ['id'],
                  where: 'account_id = ? OR to_account_id = ?',
                  whereArgs: [id, id],
                  limit: 1);
              final a = await txn.query(DbSchema.tLedgerAccounts,
                  where: 'id = ?', whereArgs: [id], limit: 1);
              if (refs.isEmpty &&
                  a.isNotEmpty &&
                  (a.first['base']! as num) == 0) {
                await txn.delete(
                    DbSchema.tLedgerAccounts, where: 'id = ?', whereArgs: [id]);
              }
            }
          }
        }
        await txn.delete(DbSchema.tLedgerImportBatches,
            where: 'id = ?', whereArgs: [batchId]);
        await _recomputeBalances(txn);
        return n;
      });
}
