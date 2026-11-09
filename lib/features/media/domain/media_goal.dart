import '../domain/media_item.dart';
import '../domain/media_session.dart';

/// 影音游目标屏（批8a · 词典 LH-C22 · 原型 `m-goal`）。
///
/// 固定六行＝计划 §八 L7 六路汇聚逐字；一指标一行存 `media_goals`（DB v40），
/// 「未设＝删行」，屏上虚线入口、行内零百分比（LH-C22 铁口径③④）。
/// 读数**恒吃真实耗时**（账本 §九.1 同一条），不随 `media.speedFold` 折算变。

class MediaGoal {
  const MediaGoal({
    required this.metric,
    required this.unit,
    required this.target,
    this.active = true,
    this.updatedAt,
  });

  final String metric;

  /// 单位原文（min / h / 部 / 天 / 条）。
  final String unit;

  /// 目标值：单位的最小整数刻度（时长＝分钟、小时＝0.1h 即 36＝3.6h、计数原值）。
  final int target;

  final bool active;
  final int? updatedAt;

  static MediaGoal fromRow(Map<String, Object?> r) => MediaGoal(
        metric: '${r['metric']}',
        unit: '${r['unit']}',
        target: (r['target'] as num?)?.toInt() ?? 0,
        active: (r['active'] as num?)?.toInt() == 1,
        updatedAt: (r['updated_at'] as num?)?.toInt(),
      );

  Map<String, Object?> toRow() => {
        'metric': metric,
        'unit': unit,
        'target': target,
        'active': active ? 1 : 0,
        'updated_at': updatedAt,
      };
}

/// 六路定义（顺序＝屏上固定行序＝原型 MGOALS 逐字）。
const List<({String k, String label, String unit, String per})> kMdsGoalDefs = [
  (k: 'movieMin', label: '每日观影', unit: 'min', per: 'day'),
  (k: 'musicH', label: '每周听歌', unit: 'h', per: 'week'),
  (k: 'gameH', label: '每月游玩', unit: 'h', per: 'month'),
  (k: 'doneN', label: '每年看完', unit: '部', per: 'year'),
  (k: 'dayN', label: '每周影音天数', unit: '天', per: 'week'),
  (k: 'sceneN', label: '每月名场面', unit: '条', per: 'month'),
];

const Map<String, String> kMdsPerWord = {
  'day': '今天',
  'week': '本周',
  'month': '本月',
  'year': '今年',
};

/// 完结档＝看完/追完/通关（音乐「循环中」不算看完，原型 M_DONE_STATES 同表）。
const List<String> kMdsDoneStates = ['看完', '追完', '通关'];

/// 滚轮档位（原型 mGoalItems 逐字：观影 10 档、听歌/影音天数/看完 1 档、游玩 0.1h 步长、名场面 1 档）。
List<String> mdsGoalWheelLabels(String metric) => switch (metric) {
      'movieMin' => [for (var v = 10; v <= 300; v += 10) '$v'],
      'musicH' => [for (var v = 1; v <= 48; v++) '$v'],
      'gameH' => [for (var t = 5; t <= 300; t += 5) '$t'],
      'doneN' => [for (var v = 1; v <= 100; v++) '$v'],
      'dayN' => [for (var v = 1; v <= 7; v++) '$v'],
      _ => [for (var v = 1; v <= 100; v++) '$v'],
    };

/// 滚轮选中值 → 存储刻度（游玩 h 档存 0.1h 整数）。
int mdsGoalStoreValue(String metric, int wheelIndex) =>
    int.parse(mdsGoalWheelLabels(metric)[wheelIndex]);

/// 滚轮显示标签（游玩 0.1h 一档＝3.6 这样的小数，其余原值）。
List<String> mdsGoalWheelDisplay(String metric) {
  final raw = mdsGoalWheelLabels(metric);
  if (metric != 'gameH') return raw;
  return [for (final v in raw) (int.parse(v) / 10).toStringAsFixed(1)];
}

/// 读数文案（原型 mGoalNum：小时档一位小数，其余取整）。
String mdsGoalReadText(String metric, num v) {
  final d = switch (metric) {
    'musicH' || 'gameH' => 1,
    _ => 0,
  };
  return v.toDouble().toStringAsFixed(d);
}

/// 目标 chip 文案（游玩存 0.1h 整数 → 3.6 h；其余原值）。
String mdsGoalTargetText(MediaGoal g) {
  final v = g.metric == 'gameH' ? g.target / 10.0 : g.target.toDouble();
  return '${mdsGoalReadText(g.metric, v)} ${g.unit}';
}

/// 六路达成读数（metric → 数值，单位＝该指标 unit）。
///
/// 窗口钉自然日历（铁口径①）：日＝今天零点起、周＝周一起、月/年＝当前自然月/年；
/// 件内**不读时钟**，`now` 由调用侧注入（日期类用例禁时间炸弹）。
/// 时长一律吃 [MediaSession.minutes] 真实列（铁口径②），调用侧给已结算会话。
Map<String, num> mdsComputeGoalReads({
  required List<MediaSession> sessions,
  required List<MediaItem> items,
  required int sceneNotesThisMonth,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: (today.weekday - 1) % 7));
  final monthStart = DateTime(now.year, now.month);
  final yearStart = DateTime(now.year);

  int sumMin(Iterable<MediaSession> xs) =>
      xs.fold(0, (a, s) => a + (s.endedAt != null ? s.minutes : 0));

  /// 会话起点当天零点（比较一律降到日粒度，避开时刻噪音）。
  DateTime sessDay(MediaSession s) {
    final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    return DateTime(d.year, d.month, d.day);
  }

  final movieMin = sumMin(sessions.where((s) =>
      (s.kind == MediaItem.kMovie || s.kind == MediaItem.kSeries) &&
      sessDay(s) == today));
  final musicH = sumMin(sessions.where((s) =>
          s.kind == MediaItem.kMusic &&
          !DateTime.fromMillisecondsSinceEpoch(s.startedAt)
              .isBefore(weekStart))) /
      60.0;
  final gameH = sumMin(sessions.where((s) =>
          s.kind == MediaItem.kGame &&
          !DateTime.fromMillisecondsSinceEpoch(s.startedAt)
              .isBefore(monthStart))) /
      60.0;
  final doneN = items.where((x) =>
          kMdsDoneStates.contains(x.state) &&
          x.endedAt != null &&
          !DateTime.fromMillisecondsSinceEpoch(x.endedAt!).isBefore(yearStart))
      .length;
  final dayN = sessions
      .where((s) =>
          !DateTime.fromMillisecondsSinceEpoch(s.startedAt).isBefore(weekStart))
      .map((s) {
        final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
        return DateTime(d.year, d.month, d.day);
      })
      .toSet()
      .length;

  return {
    'movieMin': movieMin,
    'musicH': musicH,
    'gameH': gameH,
    'doneN': doneN,
    'dayN': dayN,
    'sceneN': sceneNotesThisMonth,
  };
}
