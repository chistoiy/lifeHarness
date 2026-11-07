/// 记账实体模型（账户/账本/分类/预算/字典；计划 §3 与原型 L 对象对应）。
library;

import 'dart:math' as math;

/// ledger_accounts（全局共用，不带 bk；余额=base+Σeff 跨账本合并）。
class LedgerAccount {
  const LedgerAccount({
    this.id = 0,
    required this.type,
    required this.name,
    this.base = 0,
    this.creditLimit,
    this.billDay,
    this.repayDay,
    this.icon = 'wallet',
    this.color = '#0ea5e9',
    this.archived = false,
    this.balanceCache = 0,
  });

  static const kCash = 'cash';
  static const kDebit = 'debit';
  static const kCredit = 'credit';
  static const kEwallet = 'ewallet';
  static const kInvest = 'invest';
  static const kOther = 'other';

  /// 类型目录（原型 AA_TYPES 同序：键/名/图标）。
  static const types = <(String, String, String)>[
    (kCash, '现金', 'wallet'),
    (kDebit, '储蓄卡', 'card'),
    (kCredit, '信用卡', 'cardplus'),
    (kEwallet, '电子钱包', 'chat'),
    (kInvest, '理财', 'chart'),
    (kOther, '其他', 'dots'),
  ];

  static String typeLabel(String t) =>
      types.firstWhere((e) => e.$1 == t, orElse: () => types.last).$2;

  final int id;
  final String type;
  final String name;
  final double base;
  final double? creditLimit;
  final int? billDay;
  final int? repayDay;
  final String icon;
  final String color;
  final bool archived;

  /// 写路径同事务重算的物化列（仪表盘快读）。
  final double balanceCache;

  bool get isCredit => type == kCredit;

  /// 信用卡可用额度 = limit + 余额（余额为负）。
  double get available => (creditLimit ?? 0) + balanceCache;

  LedgerAccount copyWith({double? balanceCache}) => LedgerAccount(
        id: id,
        type: type,
        name: name,
        base: base,
        creditLimit: creditLimit,
        billDay: billDay,
        repayDay: repayDay,
        icon: icon,
        color: color,
        archived: archived,
        balanceCache: balanceCache ?? this.balanceCache,
      );

  static LedgerAccount fromRow(Map<String, Object?> r) => LedgerAccount(
        id: r['id']! as int,
        type: r['type']! as String,
        name: r['name']! as String,
        base: (r['base']! as num).toDouble(),
        creditLimit: (r['credit_limit'] as num?)?.toDouble(),
        billDay: r['bill_day'] as int?,
        repayDay: r['repay_day'] as int?,
        icon: (r['icon'] as String?) ?? 'wallet',
        color: (r['color'] as String?) ?? '#0ea5e9',
        archived: (r['archived']! as int) != 0,
        balanceCache: (r['balance_cache']! as num).toDouble(),
      );

  Map<String, Object?> toRow() => {
        if (id != 0) 'id': id,
        'type': type,
        'name': name,
        'base': base,
        'credit_limit': creditLimit,
        'bill_day': billDay,
        'repay_day': repayDay,
        'icon': icon,
        'color': color,
        'archived': archived ? 1 : 0,
        'balance_cache': balanceCache,
      };
}

/// ledger_books（九·补1 多账本）。
class LedgerBook {
  const LedgerBook({this.id = 0, required this.name, this.sort = 0});

  final int id;
  final String name;
  final int sort;

  static LedgerBook fromRow(Map<String, Object?> r) => LedgerBook(
        id: r['id']! as int,
        name: r['name']! as String,
        sort: (r['sort']! as int),
      );
}

/// ledger_categories：kind ∈ expense|income；parentId NULL=大类；
/// 子分类行带父 id；流水引用口径为「大类 id + 子分类名」（原型口径）。
class LedgerCat {
  const LedgerCat({
    this.id = 0,
    required this.kind,
    this.parentId,
    required this.name,
    this.icon = 'dots',
    this.color = '#94a3b8',
    this.hidden = false,
    this.sort = 0,
  });

  static const kExpense = 'expense';
  static const kIncome = 'income';

  final int id;
  final String kind;
  final int? parentId;
  final String name;
  final String icon;
  final String color;
  final bool hidden;
  final int sort;

  bool get isMajor => parentId == null;

  static LedgerCat fromRow(Map<String, Object?> r) => LedgerCat(
        id: r['id']! as int,
        kind: r['kind']! as String,
        parentId: r['parent_id'] as int?,
        name: r['name']! as String,
        icon: (r['icon'] as String?) ?? 'dots',
        color: (r['color'] as String?) ?? '#94a3b8',
        hidden: (r['hidden']! as int) != 0,
        sort: (r['sort']! as int),
      );
}

/// 月预算（ledger_budgets：cat_id=0 行为总预算+结转位；>0 为分类预算）。
class LedgerBudget {
  LedgerBudget({this.total = 0, this.carry = false, Map<int, double>? perCat})
      : perCat = perCat ?? {};

  final double total;
  final bool carry;
  final Map<int, double> perCat;
}

/// ledger_whos（角色）。
class LedgerWho {
  const LedgerWho({this.id = 0, required this.name, this.isDefault = false, this.sort = 0});

  final int id;
  final String name;
  final bool isDefault;
  final int sort;

  static LedgerWho fromRow(Map<String, Object?> r) => LedgerWho(
        id: r['id']! as int,
        name: r['name']! as String,
        isDefault: (r['is_default']! as int) != 0,
        sort: (r['sort']! as int),
      );
}

/// ledger_tags + ledger_tag_groups（两级；流水存标签名字符串数组）。
class LedgerTagGroup {
  const LedgerTagGroup({this.id = 0, required this.name, this.sort = 0, this.tags = const []});

  final int id;
  final String name;
  final int sort;
  final List<String> tags;

  LedgerTagGroup copyWith({List<String>? tags}) =>
      LedgerTagGroup(id: id, name: name, sort: sort, tags: tags ?? this.tags);
}

/// ledger_merchants（商家）。
class LedgerMerchant {
  const LedgerMerchant({this.id = 0, required this.name, this.sort = 0});

  final int id;
  final String name;
  final int sort;

  static LedgerMerchant fromRow(Map<String, Object?> r) => LedgerMerchant(
        id: r['id']! as int,
        name: r['name']! as String,
        sort: (r['sort']! as int),
      );
}

/// ledger_recur（批2d L9 周期账单；九·补1 表带 bk）。
/// freq：day/week/month/year（domain/ledger_calc.dart recurFreqs）；
/// nextDate 'YYYY-MM-DD' 下次扣款日；active=原型 r.on 启停。
class LedgerRecur {
  const LedgerRecur({
    this.id = 0,
    required this.bk,
    required this.name,
    required this.amt,
    this.catId,
    this.sub = '',
    required this.accountId,
    required this.freq,
    required this.nextDate,
    this.active = true,
    this.note,
  });

  final int id;
  final int bk;
  final String name;
  final double amt;
  final int? catId;
  final String sub;
  final int accountId;
  final String freq;
  final String nextDate;
  final bool active;
  final String? note;

  static LedgerRecur fromRow(Map<String, Object?> r) => LedgerRecur(
        id: r['id']! as int,
        bk: r['bk']! as int,
        name: r['name']! as String,
        amt: (r['amt']! as num).toDouble(),
        catId: r['cat_id'] as int?,
        sub: (r['sub'] as String?) ?? '',
        accountId: r['account_id']! as int,
        freq: r['freq']! as String,
        nextDate: r['next_date']! as String,
        active: (r['active']! as int) != 0,
        note: r['note'] as String?,
      );

  Map<String, Object?> toRow() => {
        if (id != 0) 'id': id,
        'bk': bk,
        'name': name,
        'amt': amt,
        'cat_id': catId,
        'sub': sub,
        'account_id': accountId,
        'freq': freq,
        'next_date': nextDate,
        'active': active ? 1 : 0,
        'note': note,
      };
}

/// ledger_wishes（批3a L10 心愿单；九·补1 表带 bk）。
/// 进度口径（原型 renderWish）：saved/target 达成即 p≥100 可兑换；
/// 存入/取出仅改 saved 不落流水（§10 U-2），兑换由 repo 生成 expense 并归档。
class LedgerWish {
  const LedgerWish({
    this.id = 0,
    required this.bk,
    required this.name,
    required this.target,
    this.saved = 0,
    this.done = false,
    this.doneDate,
    this.doneTxn,
  });

  final int id;
  final int bk;
  final String name;

  /// 目标金额（新建守卫 >0；兑换流水额=target，同原型 wishRedeem）。
  final double target;

  /// 已存金额（存入 +v / 取出 −v 且下限 0）。
  final double saved;

  /// 已实现（兑换归档）。
  final bool done;
  final String? doneDate;

  /// 兑换生成的流水 id（done_txn 回写）。
  final int? doneTxn;

  /// 进度百分比（原型 `Math.min(100,saved/target*100)`；target≤0 归 0）。
  double get progressPct =>
      target > 0 ? math.min(100.0, saved / target * 100) : 0.0;

  /// 达成（saved≥target 且目标有效）→ 可兑换。
  bool get achieved => target > 0 && saved >= target;

  static LedgerWish fromRow(Map<String, Object?> r) => LedgerWish(
        id: r['id']! as int,
        bk: r['bk']! as int,
        name: r['name']! as String,
        target: (r['target']! as num).toDouble(),
        saved: (r['saved']! as num).toDouble(),
        done: (r['done']! as int) != 0,
        doneDate: r['done_date'] as String?,
        doneTxn: r['done_txn'] as int?,
      );

  Map<String, Object?> toRow() => {
        if (id != 0) 'id': id,
        'bk': bk,
        'name': name,
        'target': target,
        'saved': saved,
        'done': done ? 1 : 0,
        'done_date': doneDate,
        'done_txn': doneTxn,
      };
}

/// ledger_debts（批3a L11 借出/借入；九·补1 表带 bk）。
/// side：'lend' 借出（别人欠我）/ 'borrow' 借入（我欠别人）。
/// 记还款/结清生成实际流水（source=debt）并回写 paid（进度条），本金不落
/// 流水、不计入净资产（§10 U-3）；L2 记一笔借贷 tab 与本表同表互认（addDebt）。
class LedgerDebt {
  const LedgerDebt({
    this.id = 0,
    required this.bk,
    required this.side,
    required this.person,
    required this.total,
    this.paid = 0,
    this.note = '',
  });

  static const kLend = 'lend';
  static const kBorrow = 'borrow';

  final int id;
  final int bk;
  final String side;
  final String person;
  final double total;

  /// 已还/已收金额（还款 = min(total, paid+v)）。
  final double paid;
  final String note;

  bool get isLend => side == kLend;

  /// 剩余未收/未还（原型 `left=total-paid`）。
  double get left => total - paid;

  /// 进度百分比（原型 `total?Math.min(100,paid/total*100):0`）。
  double get progressPct =>
      total > 0 ? math.min(100.0, paid / total * 100) : 0.0;

  /// 已结清（left≤0；结清按钮禁用条件）。
  bool get settled => left <= 0.005;

  static LedgerDebt fromRow(Map<String, Object?> r) => LedgerDebt(
        id: r['id']! as int,
        bk: r['bk']! as int,
        side: r['side']! as String,
        person: r['person']! as String,
        total: (r['total']! as num).toDouble(),
        paid: (r['paid']! as num).toDouble(),
        note: (r['note'] as String?) ?? '',
      );

  Map<String, Object?> toRow() => {
        if (id != 0) 'id': id,
        'bk': bk,
        'side': side,
        'person': person,
        'total': total,
        'paid': paid,
        'note': note,
      };
}
