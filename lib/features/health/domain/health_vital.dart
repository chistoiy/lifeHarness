/// 健康 · 体征五类（批2.5 · 原型 `tools/health/v2_js.js` 的 `VT` 表 + `vt*` 行为）。
///
/// 这一份是**规格与展示派生**的唯一出处，三条口径写在这里：
/// · **参考区间不在本文件**——唯一出处＝`health_calc.dart` 的 `vitalRef`（§11.3.1），本表只带单位/时段/
///   滚轮字段与步长，避免两处区间漂移；`vitalRef` 的上限 999 是「无上限」哨兵（血氧只按下限判），
///   所以柱高另记一枚 `barBase`，展示文案走 `refLabel`（不印 999）；
/// · **异常只作提示不作诊断**（§11.3.1）：`flag` 只出「低/高」色标与文案，不给结论；
/// · **没有基线就不编「较基线」**（`deltaText` 回落参考区间），与「无记录＝空槽」同一条诚实口径。
library;

import 'health_calc.dart';
import 'health_models.dart';

/// 录入滚轮的一列数值：`col`＝表列名（sys/dia/hr/val），`lo/hi/step`＝档位范围与步长。
class VitalField {
  const VitalField(this.col, this.label, this.lo, this.hi, [this.step = 1]);

  final String col;
  final String label;
  final double lo;
  final double hi;
  final double step;

  /// 滚轮档位（含端点）；档数是整数，所以用 `round()` 而不是 `floor()`——
  /// `(22-2.8)/0.1` 在浮点里是 191.99999…，floor 会把末档 22.0 直接吞掉。
  List<double> get values {
    final n = ((hi - lo) / step).round() + 1;
    return [for (var i = 0; i < n; i++) double.parse((lo + i * step).toStringAsFixed(2))];
  }
}

/// 一类体征的展示与输入规格（原型 `VT[k]` 的转写）。
class VitalSpec {
  const VitalSpec({
    required this.kind,
    required this.name,
    required this.unit,
    required this.fields,
    required this.slots,
    required this.barBase,
    this.slotLabel = '测量时段',
  });

  final String kind;
  final String name;
  final String unit;
  final List<VitalField> fields;
  final List<String> slots;

  /// 迷你柱的基准（原型 `ref[1]`）：血氧的参考上限在 `vitalRef` 里是 999 哨兵，不能拿来算柱高。
  final double barBase;

  /// 血糖那行原型多带一句饮食指引（`vtSlots` 按类型换题注）。
  final String slotLabel;

  /// 小数位只由**主值步长**决定（0.1 步长＝一位小数），别按指标名硬编码。
  int get decimals => fields.first.step < 1 ? 1 : 0;

  (double, double)? get ref => vitalRef[kind];

  /// 参考区间文案；999 上限＝「无上限」，只写「参考 ≥95」。
  String get refLabel {
    final r = ref;
    if (r == null) return '暂无参考区间';
    if (r.$2 >= 999) return '参考 ≥${trimNum(r.$1)} $unit';
    return '参考 ${trimNum(r.$1)} ~ ${trimNum(r.$2)} $unit';
  }

  String fmt(double? v) => v == null ? '—' : decimals == 1 ? v.toStringAsFixed(1) : trimNum(v);

  static String trimNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// 五类顺序＝原型 `VT_K`（瓦片、chips、工作台体征条都吃这一序，别各处自排导致错位）。
const List<String> vitalOrder = ['bp', 'hr', 'spo2', 'glu', 'temp'];

const Map<String, VitalSpec> vitalSpecs = {
  'bp': VitalSpec(kind: 'bp', name: '血压', unit: 'mmHg', barBase: 139, slots: [
    '晨起空腹', '上午', '午后', '晚间', '睡前', '运动后'
  ], fields: [
    VitalField('sys', '收缩压', 70, 200),
    VitalField('dia', '舒张压', 40, 130),
    VitalField('hr', '心率', 40, 160),
  ]),
  'hr': VitalSpec(kind: 'hr', name: '心率', unit: '次/分', barBase: 95, slots: [
    '晨起静息', '日间', '晚间', '运动后'
  ], fields: [
    VitalField('val', '静息心率', 35, 180),
  ]),
  'spo2': VitalSpec(kind: 'spo2', name: '血氧', unit: '%', barBase: 100, slots: [
    '晨起', '日间', '晚间'
  ], fields: [
    VitalField('val', '血氧饱和度', 80, 100),
  ]),
  'glu': VitalSpec(kind: 'glu', name: '血糖', unit: 'mmol/L', barBase: 6.1,
      slotLabel: '血糖时段 · 饮食情况见备注', slots: [
    '空腹', '餐后2h', '随机', '夜间'
  ], fields: [
    VitalField('val', '血糖', 2.8, 22, 0.1),
  ]),
  'temp': VitalSpec(kind: 'temp', name: '体温', unit: '℃', barBase: 37.2, slots: [
    '晨起', '日间', '晚间', '复测'
  ], fields: [
    VitalField('val', '体温', 35, 42, 0.1),
  ]),
};

/// 一条体征读数（`health_vital` 表 · 一行一次测量）。
class HealthVital {
  const HealthVital({
    this.id,
    required this.profileId,
    required this.date,
    required this.time,
    required this.kind,
    this.sys,
    this.dia,
    this.hr,
    this.val,
    this.slot,
    this.dietNote,
    this.note,
  });

  final int? id;
  final int profileId;
  final String date;

  /// `HH:mm`：测量时刻（同日多条靠它排序，不参与归属日判定）。
  final String time;
  final String kind;
  final int? sys;
  final int? dia;

  /// 血压那行的伴生心率（`hr` 列只有血压在用；心率指标自身的值在 `val`）。
  final int? hr;
  final double? val;
  final String? slot;

  /// 血糖饮食标注列：原型 `sheetHVital` 只有备注一个输入框，本批不接此列（留待产品裁定）。
  final String? dietNote;
  final String? note;

  VitalSpec get spec => vitalSpecs[kind]!;

  double? field(String col) => switch (col) {
        'sys' => sys?.toDouble(),
        'dia' => dia?.toDouble(),
        'hr' => hr?.toDouble(),
        _ => val,
      };

  /// 主值＝该类的第一个字段（血压取收缩压），判级与统计都只看它（原型 `vtPrimary`）。
  double? get primary => field(spec.fields.first.col);

  /// 'low'/'normal'/'high'；主值缺失＝null（UI 出「未记录」，不判成正常）。
  String? get flag => vitalLevel(kind, primary);

  /// 读数文本：血压＝`120/80` 两值，其余按步长定小数（原型 `hpFmt`）。
  String get valueText => kind == 'bp'
      ? (sys == null || dia == null ? '—' : '$sys/$dia')
      : spec.fmt(val);

  /// 瓦片迷你柱高度（0~1，原型 `primary/(ref[1]*1.15)` 后夹在 12%~100%）。
  double barFrac() {
    final p = primary;
    if (p == null || spec.barBase <= 0) return 0;
    return (p / (spec.barBase * 1.15) * 100).clamp(12, 100) / 100;
  }

  /// 副注（原型 `vtDelta`）：血压比基线两值、心率比静息值，其余比参考区间。
  /// 基线三值在「本人」种子里全空，且本批没有写基线的屏（`sheetHBaseline` 延后，见工单 §2）——
  /// 读不到基线就回落到「参考 a ~ b」，不拿 118/72 这类演示值兜底。
  String deltaText(HealthProfile? p) {
    if (p != null && kind == 'bp' && sys != null && dia != null && p.restSys != null && p.restDia != null) {
      return '较基线 ${_sign(sys! - p.restSys!)} / ${_sign(dia! - p.restDia!)}';
    }
    if (p != null && kind == 'hr' && val != null && p.restHr != null) {
      return '较静息 ${_sign(val!.round() - p.restHr!)}';
    }
    return spec.refLabel;
  }

  factory HealthVital.fromRow(Map<String, Object?> r) => HealthVital(
        id: r['id'] as int?,
        profileId: r['profile_id'] as int,
        date: r['date'] as String,
        time: r['time'] as String,
        kind: r['kind'] as String,
        sys: (r['sys'] as num?)?.toInt(),
        dia: (r['dia'] as num?)?.toInt(),
        hr: (r['hr'] as num?)?.toInt(),
        val: (r['val'] as num?)?.toDouble(),
        slot: r['slot'] as String?,
        dietNote: r['diet_note'] as String?,
        note: r['note'] as String?,
      );

  Map<String, Object?> toRow() => {
        'profile_id': profileId,
        'date': date,
        'time': time,
        'kind': kind,
        'sys': sys,
        'dia': dia,
        'hr': hr,
        'val': val,
        'slot': slot,
        'diet_note': dietNote,
        'note': note,
      };
}

String _sign(int d) => d >= 0 ? '+$d' : '$d';

/// 一组读数的均值（按该类小数位取整）；空表返回 null（UI 显「—」）。
double? vitalMean(List<HealthVital> vs, int decimals) {
  final vals = vs.map((v) => v.primary).whereType<double>().toList();
  if (vals.isEmpty) return null;
  final m = vals.reduce((a, b) => a + b) / vals.length;
  return decimals == 1 ? double.parse(m.toStringAsFixed(1)) : m.roundToDouble();
}

/// 窗口内的异常条数（主值落在参考区间外；主值缺失＝未记录，不计入也不判成正常）。
int vitalAbnormalCount(Iterable<HealthVital> vs) =>
    vs.where((v) => v.flag != null && v.flag != 'normal').length;
