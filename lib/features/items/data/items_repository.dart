import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../../../core/logging/app_log.dart';
import '../domain/item_calc.dart';
import '../domain/item_models.dart';

/// 物品价值仓储（仿 care/days 范式；审计时间轴仅追加＝本类不暴露 events 改删口）。
///
/// 与记账（L12）联动：建档同步生成支出流水、二次付费=支出、回收=收入——
/// 流水写入统一走 shared/linkage/item_mounts.dart（R1 守护，items 不 import ledger）；
/// 保修汇入提醒中心由 days 侧 syncDerived 直读 item_profiles（name/warranty 列名对齐）。
class ItemsRepository {
  ItemsRepository(this.db);

  final Database db;

  // ==================== 加载 ====================

  Future<ItemsData> loadAll() async {
    // 在册口径＝deleted_at IS NULL：回收站里的档案不进列表/统计/每日成本（V1.61）。
    final rows = await db.query(DbSchema.tItemProfiles,
        where: 'deleted_at IS NULL', orderBy: 'billing DESC, id ASC');
    final evs = await db.query(DbSchema.tItemEvents, orderBy: 'id ASC');
    final uss = await db.query(DbSchema.tItemUsages, orderBy: 'id ASC');
    return ItemsData(
      items: [
        for (final r in rows)
          ItemProfile.fromRow(r).copyWith(
            events: [
              for (final e in evs)
                if (e['item_id'] == r['id']) ItemEvent.fromRow(e)
            ],
            usages: [
              for (final u in uss)
                if (u['item_id'] == r['id']) ItemUsage.fromRow(u)
            ],
          ),
      ],
    );
  }

  Map<String, Object?> _row(ItemProfile it, int ts) => {
        'name': it.name,
        'icon': it.iconId,
        'category': it.category,
        'buy_date': it.buyDate,
        'price': it.price,
        'expected_years': it.expectedYears,
        'warranty': it.warranty,
        'status': it.status,
        'billing': it.billing ? 1 : 0,
        'mode': it.mode.wire,
        'plan_units': it.planUnits,
        'unit': it.unit,
        'stop_pct': it.stopPct,
        'photo': it.photo,
        'source': it.source,
        'source_txn_id': it.sourceTxnId,
        'deleted_at': it.deletedAt,
        'updated_at': ts,
      };

  // ==================== 回收站（V1.61 物品档案删除） ====================

  /// 软删＝只打 `deleted_at`，档案与子记录原地保留，回收站可恢复。
  /// **不往成本时间轴写事件**——时间轴记的是资产变动（仅追加口径），
  /// 自删动作的留痕走应用日志（`shared/trash` 统一记）。
  Future<void> softDeleteItem(int id) => db.update(
        DbSchema.tItemProfiles,
        {
          'deleted_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      ).then((_) => AppLog.addKey('物品删除：#$id 已移入回收站 · 保留期内可恢复'));

  /// 回收站列表（按删除时间倒序，与其余各类同序）。
  ///
  /// 与 [loadAll] 一样把成本时间轴与用量**挂回档案**：行上的「成本池」是净值
  /// （购入＋二次付费−回收残值），只读 `item_profiles` 一行会把做过二次付费的
  /// 档案写成购入价（真机 6071 抓到：¥249 的档案行上显示「成本池 ¥199」）。
  Future<List<ItemProfile>> trashedItems() async {
    final rows = await db.query(DbSchema.tItemProfiles,
        where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC, id DESC');
    final evs = await db.query(DbSchema.tItemEvents, orderBy: 'id ASC');
    final uss = await db.query(DbSchema.tItemUsages, orderBy: 'id ASC');
    return [
      for (final r in rows)
        ItemProfile.fromRow(r).copyWith(
          events: [
            for (final e in evs)
              if (e['item_id'] == r['id']) ItemEvent.fromRow(e)
          ],
          usages: [
            for (final u in uss)
              if (u['item_id'] == r['id']) ItemUsage.fromRow(u)
          ],
        ),
    ];
  }

  /// 恢复＝清 `deleted_at`。`status`/`billing`/`mode` 一律不动——
  /// 删除前后是同一份档案，计费按删除前状态继续（需求 V1.61 拍板①）。
  Future<void> restoreItem(int id) => db.update(
        DbSchema.tItemProfiles,
        {
          'deleted_at': null,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 彻底删除＝真删三表该档案的行（档案＋成本时间轴＋按次用量）。
  /// **记账流水一行不碰**（拍板②：记账是独立账本，物品不反向删账）。
  Future<void> purgeItem(int id) => db.transaction((txn) async {
        await txn.delete(DbSchema.tItemEvents,
            where: 'item_id = ?', whereArgs: [id]);
        await txn.delete(DbSchema.tItemUsages,
            where: 'item_id = ?', whereArgs: [id]);
        await txn.delete(DbSchema.tItemProfiles,
            where: 'id = ?', whereArgs: [id]);
      });

  /// 到期清理（与待办同款 cutoff 语义：`deleted_at < now-keepDays`）。
  /// 先按 id 清单连子表一起真删，不做「无父即孤儿」式全表扫——那会顺手清掉
  /// 别处尚未落定的行，语义太大。
  /// 回收站行与彻底删除确认的**同源读数**：成本时间轴条数 · 按次用量条数 ·
  /// 关联记账流水条数（`source='item' AND link_id=本档案`，含建档/二次付费/回收收入）。
  /// 流水只数不改——拍板②要求「保留」，读数也得看得见才敢承诺。
  Future<({int events, int usages, int txns})> trashReadout(int id) async {
    Future<int> cnt(String table, String where, List<Object?> args) async {
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM $table WHERE $where', args);
      return (r.first['c'] as int?) ?? 0;
    }

    return (
      events: await cnt(DbSchema.tItemEvents, 'item_id = ?', [id]),
      usages: await cnt(DbSchema.tItemUsages, 'item_id = ?', [id]),
      txns: await cnt(DbSchema.tLedgerTxns, "source = 'item' AND link_id = ?",
          ['$id']),
    );
  }

  Future<int> purgeExpiredItems(int keepDays) async {
    if (keepDays <= 0) return 0;
    final cutoff =
        DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final due = await txn.query(DbSchema.tItemProfiles,
          columns: ['id'],
          where: 'deleted_at IS NOT NULL AND deleted_at < ?',
          whereArgs: [cutoff]);
      if (due.isEmpty) return 0;
      final ids = [for (final r in due) r['id'] as int];
      final ph = List.generate(ids.length, (_) => '?').join(',');
      await txn.delete(DbSchema.tItemEvents,
          where: 'item_id IN ($ph)', whereArgs: ids);
      await txn.delete(DbSchema.tItemUsages,
          where: 'item_id IN ($ph)', whereArgs: ids);
      return txn.delete(DbSchema.tItemProfiles,
          where: 'id IN ($ph)', whereArgs: ids);
    });
  }

  // ==================== 建档 / 编辑 ====================

  /// 新建（同事务追加「购入」首条审计）。返回新 id。
  Future<int> addItem(ItemProfile it) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final id = await db.transaction((txn) async {
      final id = await txn.insert(
          DbSchema.tItemProfiles, {..._row(it, ts), 'created_at': ts});
      await txn.insert(DbSchema.tItemEvents, {
        'item_id': id,
        'kind': kEvBuy,
        'label': '购入',
        'amount': it.price,
        'note': it.source == 'ledger'
            ? '来源：记账流水升级建档（联动 L12）· 不可删除'
            : '手动建档 · 同步生成记账流水（联动 L12）',
        'event_date': it.buyDate,
        'created_at': ts,
      });
      return id;
    });
    AppLog.addKey('物品建档：#$id ${it.name} · 价 ${it.price} · '
        '${it.buyDate} · 计费=${it.billing} · 来源 ${it.source}');
    return id;
  }

  /// 编辑档案（不动 billing 冻结口径由调用方传入；events 不在此改）。
  Future<void> updateItem(ItemProfile it) => db.update(DbSchema.tItemProfiles,
      _row(it, DateTime.now().millisecondsSinceEpoch),
      where: 'id = ?', whereArgs: [it.id]);

  // ==================== 生命周期三操作（全部仅追加 + 实时重算在引擎侧） ====

  Future<void> _appendEvent(int itemId, ItemEvent e) =>
      db.insert(DbSchema.tItemEvents, {
        'item_id': itemId,
        'kind': e.kind,
        'label': e.label,
        'amount': e.amount,
        'note': e.note,
        'event_date': e.date,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  /// 二次付费：计入成本池，摊回全周期（日均回升由引擎实算）。
  Future<void> addExtraPay(int itemId, double amount, String desc,
          {String? note, String? date}) async {
    final d = date ?? fmtYmd(DateTime.now());
    await _appendEvent(
        itemId,
        ItemEvent(
            itemId: itemId,
            kind: kEvExtra,
            label: '二次付费：$desc',
            amount: amount,
            note: note,
            date: d));
    AppLog.addKey('物品二次付费：#$itemId +$amount · $desc · $d（摊回全周期）');
  }

  /// 回收/出售：残值扣减。keep=true 抵扣留用（继续计费）；
  /// false 转出（停计费 + 冻结决算）。
  Future<void> recycle(int itemId, double amount,
      {required bool keep, String? date}) async {
    final d = date ?? fmtYmd(DateTime.now());
    await db.transaction((txn) async {
      await txn.insert(DbSchema.tItemEvents, {
        'item_id': itemId,
        'kind': kEvRecycle,
        'label': keep ? '回收残值抵扣 · 继续留用' : '回收/出售 · 转出',
        'amount': amount,
        'note': '生成收入记账流水（联动 L12）· 以新净值${keep ? '继续每日摊薄' : '停止计费 · 决算已生成'}',
        'event_date': d,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await txn.update(DbSchema.tItemProfiles, {
        'status': keep ? kItemStatusRecycleKeep : kItemStatusRecycleOut,
        'billing': keep ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, where: 'id = ?', whereArgs: [itemId]);
    });
    AppLog.addKey('物品回收：#$itemId 残值 $amount · '
        '${keep ? '抵扣留用·继续计费' : '转出·停计费并冻结决算'} · $d');
  }

  /// 报废：停止计费、冻结决算、转历史库（原因入审计行；二次确认在 UI 层）。
  Future<void> scrap(int itemId, String reason, {String? date}) async {
    final d = date ?? fmtYmd(DateTime.now());
    await db.transaction((txn) async {
      await txn.insert(DbSchema.tItemEvents, {
        'item_id': itemId,
        'kind': kEvScrap,
        'label': '报废',
        'amount': 0,
        'note': '原因：$reason · 停止计费 · 决算已冻结 · 审计记录已保留',
        'event_date': d,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await txn.update(
          DbSchema.tItemProfiles,
          {
            'status': kItemStatusScrapped,
            'billing': 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [itemId]);
    });
    AppLog.addKey('物品报废：#$itemId · 原因「$reason」 · $d · '
        '停计费并冻结决算');
  }

  // ==================== 按次用量 ====================

  Future<void> addUsage(int itemId, String day, double qty) => db.insert(
      DbSchema.tItemUsages,
      {
        'item_id': itemId,
        'day': day,
        'qty': qty,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  // ==================== 记账流水升级建档（来源徽标） ====================

  /// 可升级的大额支出流水（购物类 top N，未升级过的；供录入弹层「从记账流水升级」tab）。
  Future<List<LedgerCandidate>> upgradeCandidates({int limit = 20}) async {
    final rows = await db.rawQuery(
        '''
        SELECT t.id, t.note, t.amt, t.date, c.name AS cat
        FROM ${DbSchema.tLedgerTxns} t
        LEFT JOIN ${DbSchema.tLedgerCategories} c ON c.id = t.cat_id
        WHERE t.kind = 'expense' AND t.source IN ('manual','bill','recurring')
          AND t.amt >= 50
          AND t.id NOT IN (
            SELECT source_txn_id FROM ${DbSchema.tItemProfiles}
            WHERE source_txn_id IS NOT NULL)
        ORDER BY t.amt DESC LIMIT ?
        ''',
        [limit]);
    return rows
        .map((r) => LedgerCandidate(
              txnId: r['id'] as int,
              title: (r['note'] as String?)?.trim().isNotEmpty == true
                  ? r['note'] as String
                  : (r['cat'] as String? ?? '支出'),
              amount: (r['amt'] as num).toDouble(),
              date: r['date'] as String,
              catName: r['cat'] as String?,
            ))
        .toList();
  }

  /// 升级建档后回写：流水挂来源徽标（source='item' + link_id=新物品 id）。
  /// 流水金额不改，统一写路径由联动门面先行保证。
  Future<void> stampTxnUpgrade(int txnId, int itemId) => db.update(
      DbSchema.tLedgerTxns,
      {'source': 'item', 'link_id': '$itemId'},
      where: 'id = ?',
      whereArgs: [txnId]);
}

/// 升级建档候选流水投影。
class LedgerCandidate {
  const LedgerCandidate({
    required this.txnId,
    required this.title,
    required this.amount,
    required this.date,
    this.catName,
  });
  final int txnId;
  final String title;
  final double amount;
  final String date;
  final String? catName;
}
