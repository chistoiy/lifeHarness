import 'dart:math' as math;

import 'health_models.dart';

/// 检查报告规格单源（批3.5b · 事实源＝`tools/health/v2_pages.html` `#p-report` ＋
/// `tools/health/v2_sheets.html` `sheetHReportAdd`/`sheetHMetric` ＋
/// `tools/health/v2_js.js` 的 `HK_LIB`/`rpRender`/`rpYear`/`rpToggle`/`rpDel`/`rpa*`/`hmk*`）。
///
/// 屏与两张弹层**都从这里取判据与文案**，不在两处各写一遍。四条口径：
/// · 偏高/偏低**不落状态列**（v37 DDL 注释）：按行内参考范围实时算，
///   `v<lo` 偏低、`v>hi` 偏高，**边界值算正常**（`hkFlagOf` 一处定死，页/弹层/统计共用）；
/// · 归档轴是**月份**（原型 `r.d.slice(0,2)`）而不是年份：chips＝「全部」∪ 出现过的月份，
///   卡片一张报告一份、**默认折叠**（原型 `rpBody` 起手就带 `hidden`）；
/// · 附件读数由 `files` 内容**派生**（原型把 PDF 也计进「图片 ×N」且末次动作覆盖读数，
///   本实现按类型分开数——偏离登记在批3.5 工单 §3）；
/// · 检验项数值滚轮量程**按参考跨度自适应**（`hmkWheels`：跨度小就 0.1 一档，
///   免得肌酐 41~81 也铺出几百格滚不动）。

/// 常用项目库十枚（原型 `HK_LIB` 原序·单位与参考范围一律照原文）。
class HkLibItem {
  const HkLibItem(this.name, this.unit, this.refLo, this.refHi);

  final String name;
  final String unit;
  final double refLo;
  final double refHi;
}

const List<HkLibItem> hkLib = [
  HkLibItem('血红蛋白', 'g/L', 115, 150),
  HkLibItem('白细胞', '×10⁹/L', 3.5, 9.5),
  HkLibItem('血小板', '×10⁹/L', 125, 350),
  HkLibItem('总胆固醇', 'mmol/L', 0, 5.2),
  HkLibItem('低密度脂蛋白', 'mmol/L', 0, 3.4),
  HkLibItem('甘油三酯', 'mmol/L', 0, 1.7),
  HkLibItem('空腹血糖', 'mmol/L', 3.9, 6.1),
  HkLibItem('糖化血红蛋白', '%', 4, 6),
  HkLibItem('尿酸', 'μmol/L', 155, 357),
  HkLibItem('肌酐', 'μmol/L', 41, 81),
];

/// 按名称查项目库（弹层里自定义名不在库内＝null，单位与量程都回落到自定义档）。
HkLibItem? hkFind(String name) {
  for (final m in hkLib) {
    if (m.name == name) return m;
  }
  return null;
}

/// 单位只从项目库取（原型 `HK_LIB.find(...)?.[1] || ''`）：自定义项没有单位就是空串。
String hkUnitOf(String name) => hkFind(name)?.unit ?? '';

// ==================== 判档 ====================

enum HkFlag { low, normal, high, none }

/// 判档（原型 `m[1]<m[3]?'lo':(m[1]>m[4]?'hi':'ok')`）：**边界值算正常**，
/// 无数值或无参考范围出 `none`（不假装判过档）。
HkFlag hkFlagOf(double? value, double? refLo, double? refHi) {
  final v = value;
  final lo = refLo;
  final hi = refHi;
  if (v == null || lo == null || hi == null) return HkFlag.none;
  if (v < lo) return HkFlag.low;
  if (v > hi) return HkFlag.high;
  return HkFlag.normal;
}

/// 参考范围缺任一端就当「没有参考范围」——不拿单边当范围（会把另一端无限判成异常）。
HkFlag hkFlagOfMetric(ReportMetric m) =>
    hkFlagOf(m.value, m.refLo, m.refHi);

String hkFlagTx(HkFlag f) => switch (f) {
      HkFlag.low => '偏低',
      HkFlag.high => '偏高',
      HkFlag.normal => '正常',
      HkFlag.none => '—',
    };

bool hkIsAbnormal(HkFlag f) => f == HkFlag.low || f == HkFlag.high;

/// 一份报告里的异常项数（卡片角标与统计位共用）。
int hkAbnormal(Iterable<ReportMetric> ms) =>
    ms.where((m) => hkIsAbnormal(hkFlagOfMetric(m))).length;

/// 卡片角标（原型 `rpRender`：有异常出「n 项异常」，否则「全部正常」）。
String rpBadgeTx(int abnormal) => abnormal > 0 ? '$abnormal 项异常' : '全部正常';

// ==================== 报告＋检验项的拼装体 ====================

/// 一张报告卡要吃「元信息＋它的检验项」两路数据，域层拼一起，页面不再各取一次
/// （异常计数、项数、附件数全都从这里出，两处取数会读数错位）。
class ReportBundle {
  const ReportBundle({required this.report, required this.metrics});

  final HealthReport report;
  final List<ReportMetric> metrics;

  int get metricCount => metrics.length;
  int get abnormalCount => hkAbnormal(metrics);
  HkFlag flagOf(ReportMetric m) => hkFlagOfMetric(m);
}

// ==================== 归档轴（月份） ====================

/// 归档月份＝`date` 的 `MM` 两字（原型 `r.d.slice(0,2)`）。
String rpMonth(String date) => date.length >= 7 ? date.substring(5, 7) : date;

/// 「全部」＋按取数序出现过的月份（原型 `['全部'].concat([...new Set(...)])`：
/// 月份顺序跟着列表顺序走，不额外排序）。
List<String> rpMonthChips(List<ReportBundle> bs) {
  final seen = <String>{};
  for (final b in bs) {
    seen.add(rpMonth(b.report.date));
  }
  return ['全部', ...seen];
}

/// 月份筛选（'全部'＝不过滤，原型 `rpYear` 同判据）。
List<ReportBundle> rpByMonth(List<ReportBundle> bs, String month) =>
    month == '全部' ? bs : [for (final b in bs) if (rpMonth(b.report.date) == month) b];

/// chips 文案：'全部' 原样，月份去前导零加「月」（原型 `(+x)+' 月'` → '09'→'9 月'）。
String rpMonthTx(String chip) => chip == '全部' ? chip : '${int.parse(chip)} 月';

/// 流水序＝最新在上（偏离：原型吃数组插入序；本实现与症状流水同口径，
/// 否则新传的报告排在列表底部，用户以为没存上）。
List<ReportBundle> rpDesc(List<ReportBundle> bs) {
  final out = [...bs];
  out.sort((a, b) {
    final d = b.report.date.compareTo(a.report.date);
    return d != 0 ? d : (b.report.id ?? 0).compareTo(a.report.id ?? 0);
  });
  return out;
}

// ==================== 统计三位 ====================

/// 附件计数（原型 `r.pics.length || (r.fmt==='PDF'?1:0)`）：有附件就数附件，
/// 一张都没存下但类型记着 PDF 时按 1 个记。
int rpAttachCount(HealthReport r) =>
    r.files.isNotEmpty ? r.files.length : (r.kind == 'pdf' ? 1 : 0);

/// `kind` 列的取值＝附件内容的派生（只有 PDF、没有图片时才记 'pdf'）：
/// 它不参与读数（`rpFmtTx` 直接看文件表），只作存储侧标注与「附件被清空后」的兜底。
String rpKindOf(List<String> files) => files.isNotEmpty && files.every(_isPdfPath)
    ? 'pdf'
    : 'img';

class RpStat {
  const RpStat({required this.reports, required this.abnormal, required this.attachments});

  /// 报告份数。
  final int reports;

  /// 异常检验项条数。
  final int abnormal;

  /// 图片/PDF 个数。
  final int attachments;
}

/// 页顶三读数（原型 `rpRender` 的 `rpStat`，吃当前档案的**全量**、不受月份筛选影响）。
RpStat rpStatOf(List<ReportBundle> bs) => RpStat(
      reports: bs.length,
      abnormal: bs.fold<int>(0, (a, b) => a + b.abnormalCount),
      attachments: bs.fold<int>(0, (a, b) => a + rpAttachCount(b.report)),
    );

// ==================== 行文案 ====================

/// 卡片副注（原型 `${r.d} · ${r.hosp} · ${r.fmt} · ${r.ms.length} 项`）。
/// 日期这里给全量 `yyyy-MM-dd`（原型种子只有 MM-DD，库里跨年报告只显 MM-DD 会分不清年）。
String rpCardSub(ReportBundle b) {
  final r = b.report;
  return '${r.date} · ${r.hospital ?? '—'} · ${rpFmtTx(r)} · ${b.metricCount} 项';
}

/// 附件读数（'未附' / '图片 ×N' / 'PDF' / 'PDF · 图片 ×N'）。
String rpFmtTx(HealthReport r) {
  final pdfs = r.files.where(_isPdfPath).length;
  final imgs = r.files.length - pdfs;
  if (r.files.isEmpty) return r.kind == 'pdf' ? 'PDF' : '未附';
  if (pdfs == 0) return '图片 ×${r.files.length}';
  return imgs > 0 ? 'PDF · 图片 ×$imgs' : (pdfs == 1 ? 'PDF' : 'PDF ×$pdfs');
}

/// 折叠箭头的两态文案（原型 `rpToggle` 在 '›' 与 '⌄' 之间换）。
String rpArrow(bool open) => open ? '⌄' : '›';

/// 医生建议行（原型 `医生建议：${r.doc||'—'}`）。
String rpAdviceTx(String? advice) => '医生建议：${advice == null || advice.isEmpty ? '—' : advice}';

/// 空态（原型 `rpRender` 尾句原话）。
const String rpEmptyTx = '该档案暂无报告 · 点下方上传';

/// 检验项空列表（原型 `hmkList` 的「尚未录入检验项」）。
const String rpNoMetricTx = '尚未录入检验项';

/// 弹层底部预览条（原型 `rpaPrev` 原话，含「建档后逐条录入」这条口径本身）。
String rpDraftTx(int files) =>
    '附件 $files 个 · 检验项需建档后逐条录入（参考范围决定偏高/偏低标记）';

/// 报告保存提示（原型 `rpaSave`：`已归档 名称 · N 项` / 无项时 `· 待录入检验项`）。
String rpSavedTx(String name, int metrics) =>
    '已归档 $name${metrics > 0 ? ' · $metrics 项' : ' · 待录入检验项'}';

/// 名称必填（原型 `rpaSave` 缺名就 toast 且**不落库**）。
const String rpNeedNameTx = '请填写报告名称';

/// 检验项名称必填（原型 `hmkAdd` 原话）。
const String rpNeedMetricNameTx = '请先选或填写项目名称';

/// 检验项加入提示（原型 `hmkAdd`：`已加入 名称 · 报告标记重算`）。
String rpMetricAddedTx(String name) => '已加入 $name · 报告标记重算';

/// 删除确认文案（原型 `rpDel` 的 `confirmRow('删除 ' + name + ' 报告')`）。
String rpDelTx(String name) => '删除 $name 报告';

/// 删除后的提示（原型「已删除 · 图片随报告移除」——文件由 R5c 附件清理服务收）。
const String rpDeletedTx = '已删除 · 图片随报告移除';

/// 检验项行（原型 `hmkList`/`rpRender` 共用判据：名称 / 数值＋单位 / 参考范围 / 旗）。
String rpMetricValueTx(ReportMetric m) =>
    m.value == null ? '—' : '${hkNumTx(m.value!)} ${m.unit ?? ''}'.trim();

String rpMetricRefTx(ReportMetric m) => m.refLo == null || m.refHi == null
    ? '—'
    : '${hkNumTx(m.refLo!)} ~ ${hkNumTx(m.refHi!)}';

bool _isPdfPath(String path) => path.toLowerCase().endsWith('.pdf');

/// 附件缩略位上限（原型 `rpaPics`：`el.children.length < 6` 才铺「＋」——
/// 报告不限量，但页面上第 7 格起不再给入口）。
const int rpAttachMax = 6;

/// 还能不能加一格（弹层「＋」显隐与点格守卫同吃这一句）。
bool rpCanAddAttach(int have) => have < rpAttachMax;

/// 检验项弹层副注（原型 `hmkSub`：`名称 · 日期 · 已录 N 项`）。
String rpMetricSub(HealthReport r, int count) => '${r.name} · ${r.date} · 已录 $count 项';

/// 数值还没配齐时的提示（原型 `hmkTip` 缺项分支原话）。
const String rpTipHintTx = '选项目 · 填数值与参考范围后自动标记偏高偏低';

/// 判档预览（原型 `hmkTip` 齐项分支：`名称 数值 单位 · 参考 lo ~ hi 旗`）。
String rpTipTx(
        {required String name,
        required double value,
        required double lo,
        required double hi}) =>
    '$name ${hkNumTx(value)} ${hkUnitOf(name)} · 参考 ${hkNumTx(lo)} ~ ${hkNumTx(hi)} '
    '${hkFlagTx(hkFlagOf(value, lo, hi))}'.trim();

/// 数值显示：整数不带小数点，其余最多两位并去尾零（原型直接打印 JS 数字，
/// Dart 的 `6.0` 会显成「6.0」——检验单上的 108 不该写成 108.0）。
String hkNumTx(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

// ==================== 检验项滚轮量程 ====================

/// 一根滚轮：档位值＋选中档（档位集合就是可选集合，不假装能选中间值）。
class HkWheel {
  const HkWheel({required this.values, required this.index});

  final List<double> values;
  final int index;

  int get count => values.length;
  List<String> get labels => [for (final v in values) hkNumTx(v)];
  double get value => values[index];

  /// 一档多大（'0.1' / '1'），给读数下面那行小字用。
  String get stepTx => hkNumTx(values.length > 1 ? (values[1] - values[0]).abs() : 1);
}

/// 三根滚轮（数值／参考下限／参考上限）。
class HkWheels {
  const HkWheels({required this.val, required this.lo, required this.hi});

  final HkWheel val;
  final HkWheel lo;
  final HkWheel hi;

  double get value => val.value;
  double get refLo => lo.value;
  double get refHi => hi.value;
}

/// 自定义/未选中项目时的量程兜底（原型 `hmkWheels(0,400,1)` 的那对 0/400）。
const double hkOpenLo = 0;
const double hkOpenHi = 400;

/// 滚轮档位表（原型 `hNums(from,to,step)`：从 `from` 起、每 `step` 一档、滑到 `to` 为止）。
/// 参考柱恒从 0 起（原型 `hNums(0, …)`），所以「下限填 0」永远滚得到；数值柱按跨度自适应
/// （见 `hkValueRange`），项目库选中时铺的是 `(lo-1, hi+1)` 这一窄段，不是全量程。
List<double> hkNums(double from, double to, double step) {
  final st = step <= 0 ? 1.0 : step;
  final lo = math.min(from, to);
  final hi = math.max(from, to);
  final n = ((hi - lo) / st).floor() + 1;
  // 用 `lo + i*st` 而不是累加 `v += st`：累加会把浮点误差摊进每一档（0.1 步进滚到 100 就偏成 100.0000000004）。
  return [for (var i = 0; i < n; i++) _round1(lo + i * st)];
}

double _round1(double v) => (v * 10).roundToDouble() / 10;

/// 数值柱跨度自适应（原型 `hmkWheels`：`span=max(4,hi-lo)` → 两侧各放 45% 跨度，
/// 总宽 >80 就 1 一档、否则 0.1 一档——肌酐 41~81 只铺 0.1 档，不生出几百格滚不动）。
List<double> hkValueRange(double lo, double hi) {
  final span = math.max(4.0, hi - lo);
  final from = math.max(0.0, _round1(lo - span * .45));
  final to = _round1(hi + span * .45);
  return hkNums(from, to, (to - from) > 80 ? 1 : 0.1);
}

/// 参考上下限柱的量程（原型 `hNums(0, Math.max(20, round(hi*1.6)), 1)`）。
double hkRefMax(double? refHi) =>
    math.max(20, ((refHi ?? hkOpenHi) * 1.6).round()).toDouble();

/// 三柱装配：
/// · 选中项目库项＝数值柱收到 `(lo-1, hi+1)`、0.1 一档、默认档取参考范围中点
///   （原型 `hmkLib` 里那段「找最接近 (lo+hi)/2 的档」）；
/// · 自定义名／刚开弹层＝数值柱按自适应跨度铺 0 起、默认档取正中，
///   参考柱按 `hi*1.6` 铺量程、默认档落 `round(lo)`／`round(hi)`。
HkWheels hkWheelsFor({double? refLo, double? refHi}) {
  final known = refLo != null && refHi != null;
  final lo = refLo ?? hkOpenLo;
  final hi = refHi ?? hkOpenHi;
  final refVals = hkNums(0, hkRefMax(known ? refHi : null), 1);
  final valVals = known ? hkNums(math.max(0, lo - 1), hi + 1, 0.1) : hkValueRange(hkOpenLo, hkOpenHi);
  return HkWheels(
    val: HkWheel(
        values: valVals,
        index: known
            ? _nearestIdx(valVals, (lo + hi) / 2)
            : (valVals.length / 2).round().clamp(0, valVals.length - 1)),
    lo: HkWheel(values: refVals, index: _refIdx(refVals, lo)),
    hi: HkWheel(values: refVals, index: _refIdx(refVals, hi)),
  );
}

/// 参考柱的默认档＝`round(值)` 夹紧到量程内（原型直接把四舍五入后的数当 index 用，
/// 量程一变（选了项目库）旧 index 可能越界，这里统一夹紧）。
int _refIdx(List<double> vals, double v) => v.round().clamp(0, vals.length - 1);

int _nearestIdx(List<double> vals, double target) {
  var best = 0;
  for (var i = 0; i < vals.length; i++) {
    if ((vals[i] - target).abs() < (vals[best] - target).abs()) best = i;
  }
  return best;
}
