/// 目标 OKR 域模型（需求 V1.42 模块 7 · 专版 index-day_aim__goods.html P10 系）。
///
/// 周期口径：period 串 '2026 Q1'..'2026 Q4' 或 '年度目标'（归属年另取 periodYear）；
/// 归档只读/预建/复制清零；KR 数据源自动汇聚（载入时实算，来源明细可回溯）；
/// KPT 复盘每季一份（撰写中可编辑、归档只读），Try 一键生成下季草稿。
library;

/// KR 数据源（GE_SRC 六项；manual 之外均自动汇聚）。
enum KrSource {
  manual('manual', '手动'),
  todo('todo', '待办完成数'),
  read('read', '阅读本数'),
  journal('journal', '日记篇数'),
  habit('habit', '习惯打卡'),
  ledger('ledger', '记账结余');

  const KrSource(this.wire, this.label);
  final String wire;
  final String label;
  static KrSource of(String w) => KrSource.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => KrSource.manual,
      );
}

/// KR 单位选项（renderGe select 同集）。
const kKrUnits = ['%', '次/周', '天/月', '本', '篇', '项', '次'];

/// 单周期 O 上限（超限创建入口提醒收敛）。
const kMaxOkrPerPeriod = 5;

class KrUpdate {
  const KrUpdate(
      {this.id, required this.krId, required this.cur, required this.kind, this.note, required this.at});
  final int? id;
  final int krId;
  final double cur;

  /// manual 手动回填 · auto 汇聚变更留痕。
  final String kind;
  final String? note;
  final int at;

  static KrUpdate fromRow(Map<String, Object?> r) => KrUpdate(
        id: r['id'] as int,
        krId: r['kr_id'] as int,
        cur: (r['cur'] as num).toDouble(),
        kind: r['kind'] as String,
        note: r['note'] as String?,
        at: r['created_at'] as int,
      );
}

class GoalKr {
  const GoalKr({
    this.id,
    required this.goalId,
    required this.label,
    required this.target,
    this.unit = '项',
    this.source = KrSource.manual,
    this.cur = 0,
    this.updates = const [],
  });

  final int? id;
  final int goalId;
  final String label;
  final double target;
  final String unit;
  final KrSource source;
  final double cur;

  /// 来源明细留痕（回填历史，仅追加）。
  final List<KrUpdate> updates;

  /// 进度%：cur/target 实算，封顶 100（原型 v 列改由引擎算，HG-E1）。
  int get progressPct =>
      target <= 0 ? 0 : (cur / target * 100).round().clamp(0, 100);
  bool get achieved => progressPct >= 100;

  /// 展示当前值：整数去尾（3.0→'3'）。
  String get curText =>
      cur == cur.roundToDouble() ? cur.toInt().toString() : cur.toString();
  String get tgtText =>
      target == target.roundToDouble() ? target.toInt().toString() : '$target';

  static GoalKr fromRow(Map<String, Object?> r) => GoalKr(
        id: r['id'] as int,
        goalId: r['goal_id'] as int,
        label: r['label'] as String,
        target: (r['target'] as num).toDouble(),
        unit: r['unit'] as String,
        source: KrSource.of(r['src'] as String),
        cur: (r['cur'] as num).toDouble(),
      );
}

class Goal {
  const Goal({
    this.id,
    required this.title,
    required this.period,
    this.sort = 0,
    this.krs = const [],
  });

  final int? id;
  final String title;
  final String period;
  final int sort;
  final List<GoalKr> krs;

  /// 周期达成度：KR 进度均值（原型 goalPct 实算）。
  int get pct => krs.isEmpty
      ? 0
      : (krs.fold<int>(0, (s, k) => s + k.progressPct) / krs.length).round();

  Goal copyWith({String? title, String? period, int? sort, List<GoalKr>? krs}) =>
      Goal(
        id: id,
        title: title ?? this.title,
        period: period ?? this.period,
        sort: sort ?? this.sort,
        krs: krs ?? this.krs,
      );

  static Goal fromRow(Map<String, Object?> r) => Goal(
        id: r['id'] as int,
        title: r['title'] as String,
        period: r['period'] as String,
        sort: (r['sort'] as int?) ?? 0,
      );
}

/// KPT 季度复盘（period 唯一；archived=只读归档）。
class GoalReview {
  const GoalReview({
    this.id,
    required this.period,
    this.keep = '',
    this.problem = '',
    this.trial = '',
    this.archived = false,
  });

  final int? id;
  final String period;
  final String keep;
  final String problem;
  final String trial;
  final bool archived;

  static GoalReview fromRow(Map<String, Object?> r) => GoalReview(
        id: r['id'] as int,
        period: r['period'] as String,
        keep: r['keep'] as String,
        problem: r['problem'] as String,
        trial: r['trial'] as String,
        archived: (r['archived'] as int? ?? 0) == 1,
      );
}

/// 全域快照。
class GoalsData {
  const GoalsData({
    required this.goals,
    required this.reviews,
    required this.archivedPeriods,
  });

  final List<Goal> goals;
  final List<GoalReview> reviews;
  final Set<String> archivedPeriods;

  List<Goal> inPeriod(String p) =>
      goals.where((g) => g.period == p).toList(growable: false);

  bool isArchived(String p) => archivedPeriods.contains(p);

  GoalReview? reviewFor(String p) =>
      reviews.where((r) => r.period == p).firstOrNull;
}
