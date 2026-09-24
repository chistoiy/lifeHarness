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
        {if (icon != null) 'icon': icon, if (color != null) 'color': color},
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
