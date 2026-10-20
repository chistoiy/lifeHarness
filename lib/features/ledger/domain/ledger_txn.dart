/// 记账流水模型（记账计划 §3 ledger_txns；原型 L.txns 字段一一对应）。
///
/// kind 六类语义（硬约束，§3 余额口径）：
/// - expense/income：常规收支，动余额（unpaid=1 时计收支**不动余额**）；
/// - refund：负支出冲抵（amt 恒正，展示/统计按 −支出参与），余额 +amt；
/// - transfer：只移动余额、不计收支；
/// - adjust：余额调整差量（允许负值），只动余额；
/// - nb=1（不计入）：从 mStat/catStat/预算/环图四出口同时剔除。
class LedgerTxn {
  const LedgerTxn({
    this.id = 0,
    required this.kind,
    required this.amt,
    this.catId,
    this.sub = '',
    required this.accountId,
    this.toAccountId,
    required this.date,
    this.time,
    this.note = '',
    this.tags = const [],
    this.source = kSourceManual,
    this.linkId,
    this.refundOf,
    this.recurringId,
    this.wishId,
    this.debtId,
    this.billHash,
    this.impBatch,
    required this.bk,
    this.unpaid = false,
    this.nb = false,
    this.merchant,
    this.who,
    this.createdAt = 0,
  });

  static const kExpense = 'expense';
  static const kIncome = 'income';
  static const kTransfer = 'transfer';
  static const kRefund = 'refund';
  static const kAdjust = 'adjust';

  static const kSourceManual = 'manual';
  static const kSourceBill = 'bill';
  static const kSourceRecurring = 'recurring';
  static const kSourceWish = 'wish';
  static const kSourceDebt = 'debt';
  static const kSourceItem = 'item';
  static const kSourceRead = 'read';

  final int id;
  final String kind;

  /// refund/adjust 之外恒正；adjust 允许负值（差量）。
  final double amt;

  /// 大类 id（ledger_categories）；sub=子分类名（原型口径，非外键）。
  final int? catId;
  final String sub;
  final int accountId;
  final int? toAccountId;

  /// 归属自然日 'YYYY-MM-DD'；time='HH:MM' 可空。
  final String date;
  final String? time;
  final String note;
  final List<String> tags;
  final String source;
  final String? linkId;
  final int? refundOf;
  final int? recurringId;
  final int? wishId;
  final int? debtId;

  /// 账单导入去重键（交易单号优先，缺失时「时间|金额|对方」组合键）。
  final String? billHash;

  /// 归属导入批次（ledger_import_batches.id；整批撤销用）。
  final int? impBatch;
  final int bk;
  final bool unpaid;
  final bool nb;
  final String? merchant;
  final String? who;
  final int createdAt;

  bool get isExpense => kind == kExpense;
  bool get isIncome => kind == kIncome;

  /// 对账户 [aid] 的余额变动量（§3 口径；V1.33 九·补1：unpaid 不动余额）。
  double eff(int aid) {
    switch (kind) {
      case kExpense:
        return accountId == aid && !unpaid ? -amt : 0;
      case kIncome:
      case kRefund:
        return accountId == aid && !unpaid ? amt : 0;
      case kTransfer:
        if (unpaid) return 0;
        if (accountId == aid) return -amt;
        if (toAccountId == aid) return amt;
        return 0;
      case kAdjust:
        return accountId == aid ? amt : 0;
      default:
        return 0;
    }
  }

  LedgerTxn copyWith({
    int? id,
    String? kind,
    double? amt,
    int? catId,
    String? sub,
    int? accountId,
    int? toAccountId,
    String? date,
    String? time,
    String? note,
    List<String>? tags,
    String? source,
    String? linkId,
    int? refundOf,
    int? recurringId,
    int? wishId,
    int? debtId,
    String? billHash,
    int? impBatch,
    int? bk,
    bool? unpaid,
    bool? nb,
    String? merchant,
    String? who,
    int? createdAt,
  }) =>
      LedgerTxn(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        amt: amt ?? this.amt,
        catId: catId ?? this.catId,
        sub: sub ?? this.sub,
        accountId: accountId ?? this.accountId,
        toAccountId: toAccountId ?? this.toAccountId,
        date: date ?? this.date,
        time: time ?? this.time,
        note: note ?? this.note,
        tags: tags ?? this.tags,
        source: source ?? this.source,
        linkId: linkId ?? this.linkId,
        refundOf: refundOf ?? this.refundOf,
        recurringId: recurringId ?? this.recurringId,
        wishId: wishId ?? this.wishId,
        debtId: debtId ?? this.debtId,
        billHash: billHash ?? this.billHash,
        impBatch: impBatch ?? this.impBatch,
        bk: bk ?? this.bk,
        unpaid: unpaid ?? this.unpaid,
        nb: nb ?? this.nb,
        merchant: merchant ?? this.merchant,
        who: who ?? this.who,
        createdAt: createdAt ?? this.createdAt,
      );

  static LedgerTxn fromRow(Map<String, Object?> r) => LedgerTxn(
        id: r['id']! as int,
        kind: r['kind']! as String,
        amt: (r['amt']! as num).toDouble(),
        catId: r['cat_id'] as int?,
        sub: (r['sub'] as String?) ?? '',
        accountId: r['account_id']! as int,
        toAccountId: r['to_account_id'] as int?,
        date: r['date']! as String,
        time: r['time'] as String?,
        note: (r['note'] as String?) ?? '',
        tags: decodeTags(r['tags'] as String?),
        source: (r['source'] as String?) ?? kSourceManual,
        linkId: r['link_id'] as String?,
        refundOf: r['refund_of'] as int?,
        recurringId: r['recurring_id'] as int?,
        wishId: r['wish_id'] as int?,
        debtId: r['debt_id'] as int?,
        billHash: r['bill_hash'] as String?,
        impBatch: r['imp_batch'] as int?,
        bk: (r['bk']! as int),
        unpaid: (r['unpaid']! as int) != 0,
        nb: (r['nb']! as int) != 0,
        merchant: r['merchant'] as String?,
        who: r['who'] as String?,
        createdAt: (r['created_at']! as int),
      );

  Map<String, Object?> toRow() => {
        if (id != 0) 'id': id,
        'kind': kind,
        'amt': amt,
        'cat_id': catId,
        'sub': sub,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'date': date,
        'time': time,
        'note': note,
        'tags': encodeTags(tags),
        'source': source,
        'link_id': linkId,
        'refund_of': refundOf,
        'recurring_id': recurringId,
        'wish_id': wishId,
        'debt_id': debtId,
        'bill_hash': billHash,
        'imp_batch': impBatch,
        'bk': bk,
        'unpaid': unpaid ? 1 : 0,
        'nb': nb ? 1 : 0,
        'merchant': merchant,
        'who': who,
        'created_at': createdAt,
      };

  static List<String> decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    // 存储口径与原型一致：JSON 字符串数组（轻量手写解析，避免额外依赖）。
    final s = raw.trim();
    if (!s.startsWith('[')) return const [];
    return s
        .substring(1, s.length - 1)
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => e.replaceAll(RegExp(r'^"|"$'), ''))
        .toList();
  }

  static String encodeTags(List<String> tags) =>
      '[${tags.map((t) => '"$t"').join(',')}]';
}
