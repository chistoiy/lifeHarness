/// 物品价值域模型（需求 V1.42 模块 9 · 专版 index-day_aim__goods.html P7 系）。
///
/// 关键口径：二次付费与回收残值**不落档案列**，一律由 item_events 实算
/// （成本池 = 购入价 + Σextra − Σrecycle）；报废/转出 billing=0 冻结决算；
/// 审计时间轴仅追加不删改（HG-D2）。
library;

/// 计费方式（ieCalcPick 三 chip）。
enum ItemMode {
  day('day', '直线法 · 按天摊薄'),
  times('times', '按次均摊'),
  stop('stop', '预估止损');

  const ItemMode(this.wire, this.label);
  final String wire;
  final String label;
  static ItemMode of(String w) => ItemMode.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => ItemMode.day,
      );
}

/// 生命周期状态（ieStChips 四档 + 回收留用子态）。
const kItemStatusActive = '使用中';
const kItemStatusIdle = '闲置';
const kItemStatusRecycleKeep = '已回收(抵扣留用)';
const kItemStatusRecycleOut = '已回收(转出)';
const kItemStatusScrapped = '已报废';

/// 分类（建档下拉；统计环图分组同源）。
const kItemCats = ['数码', '家电', '家具', '服饰', '交通工具', '其他'];

/// 按次单位下拉。
const kItemUnits = ['次', '公里', '页', '小时'];

/// item_events.kind 值。
const kEvBuy = 'buy';
const kEvExtra = 'extra';
const kEvRecycle = 'recycle';
const kEvScrap = 'scrap';

class ItemEvent {
  const ItemEvent({
    this.id,
    required this.itemId,
    required this.kind,
    required this.label,
    this.amount = 0,
    this.note,
    required this.date,
  });

  final int? id;
  final int itemId;
  final String kind;
  final String label;
  final double amount;
  final String? note;
  final String date; // YYYY-MM-DD

  static ItemEvent fromRow(Map<String, Object?> r) => ItemEvent(
        id: r['id'] as int,
        itemId: r['item_id'] as int,
        kind: r['kind'] as String,
        label: r['label'] as String,
        amount: (r['amount'] as num?)?.toDouble() ?? 0,
        note: r['note'] as String?,
        date: r['event_date'] as String,
      );
}

class ItemUsage {
  const ItemUsage({this.id, required this.itemId, required this.day, this.qty = 1});
  final int? id;
  final int itemId;
  final String day;
  final double qty;

  static ItemUsage fromRow(Map<String, Object?> r) => ItemUsage(
        id: r['id'] as int,
        itemId: r['item_id'] as int,
        day: r['day'] as String,
        qty: (r['qty'] as num).toDouble(),
      );
}

class ItemProfile {
  const ItemProfile({
    this.id,
    required this.name,
    this.iconId = 'box',
    this.category = '数码',
    required this.buyDate,
    required this.price,
    this.expectedYears,
    this.warranty,
    this.status = kItemStatusActive,
    this.billing = true,
    this.mode = ItemMode.day,
    this.planUnits,
    this.unit = '次',
    this.stopPct = 30,
    this.photo,
    this.source = 'manual',
    this.sourceTxnId,
    this.deletedAt,
    this.events = const [],
    this.usages = const [],
  });

  final int? id;
  final String name;
  final String iconId;
  final String category;
  final String buyDate; // YYYY-MM-DD
  final double price;
  final int? expectedYears;
  final String? warranty;
  final String status;

  /// 计费中（报废/转出＝false，决算冻结）。
  final bool billing;
  final ItemMode mode;
  final double? planUnits;
  final String unit;
  final int stopPct;
  final String? photo;

  /// manual 手动建档 · ledger 记账流水升级建档（来源徽标）。
  final String source;
  final int? sourceTxnId;

  /// V1.61 软删时刻（epoch ms）；null＝在册。非空＝在回收站，保留期内可恢复。
  final int? deletedAt;

  final List<ItemEvent> events;
  final List<ItemUsage> usages;

  /// 在册判定唯一口径：回收站里的档案不进列表、不进统计、不计每日成本。
  bool get isDeleted => deletedAt != null;
  bool get recycledOut => status == kItemStatusRecycleOut;
  bool get scrapped => status == kItemStatusScrapped;
  bool get archived => !billing; // 历史（决算）分组口径

  ItemProfile copyWith({
    String? name,
    String? iconId,
    String? category,
    String? buyDate,
    double? price,
    int? expectedYears,
    String? warranty,
    String? status,
    bool? billing,
    ItemMode? mode,
    double? planUnits,
    String? unit,
    int? stopPct,
    String? photo,
    String? source,
    int? sourceTxnId,
    int? deletedAt,
    List<ItemEvent>? events,
    List<ItemUsage>? usages,
  }) =>
      ItemProfile(
        id: id,
        name: name ?? this.name,
        iconId: iconId ?? this.iconId,
        category: category ?? this.category,
        buyDate: buyDate ?? this.buyDate,
        price: price ?? this.price,
        expectedYears: expectedYears ?? this.expectedYears,
        warranty: warranty ?? this.warranty,
        status: status ?? this.status,
        billing: billing ?? this.billing,
        mode: mode ?? this.mode,
        planUnits: planUnits ?? this.planUnits,
        unit: unit ?? this.unit,
        stopPct: stopPct ?? this.stopPct,
        photo: photo ?? this.photo,
        source: source ?? this.source,
        sourceTxnId: sourceTxnId ?? this.sourceTxnId,
        // 漏带 deletedAt 会把回收站里的档案洗成在册态（习惯模块踩过，这里显式带上）；
        // 清空只能走 restoreItem，故沿用 `?? this.` 语义。
        deletedAt: deletedAt ?? this.deletedAt,
        events: events ?? this.events,
        usages: usages ?? this.usages,
      );

  static ItemProfile fromRow(Map<String, Object?> r) => ItemProfile(
        id: r['id'] as int,
        name: r['name'] as String,
        iconId: r['icon'] as String,
        category: r['category'] as String,
        buyDate: r['buy_date'] as String,
        price: (r['price'] as num).toDouble(),
        expectedYears: r['expected_years'] as int?,
        warranty: r['warranty'] as String?,
        status: r['status'] as String,
        billing: (r['billing'] as int? ?? 1) == 1,
        mode: ItemMode.of(r['mode'] as String),
        planUnits: (r['plan_units'] as num?)?.toDouble(),
        unit: r['unit'] as String? ?? '次',
        stopPct: r['stop_pct'] as int? ?? 30,
        photo: r['photo'] as String?,
        source: r['source'] as String,
        sourceTxnId: r['source_txn_id'] as int?,
        deletedAt: r['deleted_at'] as int?,
      );
}

/// 全域快照（列表/详情/统计/决算/提醒中心派生共用）。
class ItemsData {
  const ItemsData({required this.items});
  final List<ItemProfile> items;

  List<ItemProfile> get active =>
      items.where((x) => x.billing).toList(growable: false);
}
