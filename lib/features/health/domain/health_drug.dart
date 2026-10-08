import 'health_calc.dart';
import 'health_models.dart';

/// 用药规格单源（批5 · 事实源＝`prototype/index-health.html` 的 `p-med`/`sheetHDrug` ＋
/// `hMedPlan`/`hRenderMeds`/`hRenderMedChips`/`hDrugSave`/`hDrugDel`/`tgMedAll`）。
///
/// 工作台用药卡、`/health/med` 卡列表、录入弹层三处**都从这里取读数与文案**，
/// 不在页面与弹层各写一遍判据。五条口径：
/// · **已服与有交代是两条判据**（`slotTaken` / `slotSettled`，都在 `health_calc.dart`）：
///   计划位 `o`、依从率、热力「达标」只认 `taken`；漏服判认「既没服也没跳过」。本期没有 skipped 写点，
///   但判据不许合成一条（工单 §2，变异刀1 就钉这条）；
/// · **归档档案不参与今日计划**：卡列表与 `mdPlan` 都过滤 `archived`，而流水读侧一律不过滤
///   （历史依从率不能被「删了这支药」改写；批6 趋势必须 `drugs(includeArchived: true)` 取档案）；
/// · 近 7 天热力**按单药口径**算（原型 `hRenderMeds` 在每张卡里调全局 `hMedPlan`，
///   结果所有卡的同一行一模一样＝假精确），三档判据带 `t>0` 守卫（无计划日出空档，不出绿）；
/// · 免打扰窗口是**从判据反推**出来的文案（`mdDndTx`），不是写死的 `23:00 – 07:00` 字面量；
/// · 文案不许吹没做的事：排程在批8 才接线，所以提醒开关的提示条只说「已开启 · 排程随提醒中心上线生效」。

// ==================== 屏上一次取数的快照 ====================

/// 用药屏快照＝档案（未归档）＋今日打卡＋近 7 天分层打卡。
///
/// 三份读数在仓储侧**同一次 await 序列**里取齐，所以「今日 2/4 次」与热力格里今天那一格
/// 不会各看各的（同工作台 `HealthToday` 的口径：五张卡各读各的必然出现错位帧）。
typedef MedBundle = ({
  List<DrugPlan> drugs,

  /// 今日：drug_id →（时刻 → 状态）
  Map<int, Map<String, String>> todayLogs,

  /// 近 7 天：日期 →（drug_id →（时刻 → 状态））
  Map<String, Map<int, Map<String, String>>> byDay,

  /// 热力七格要展示的日期（旧→新，与 `byDay` 同窗口）
  List<String> days,
  String date,
});

// ==================== 量程与档位（弹层的可选集合就是这里给的集合） ====================

/// 时刻滚轮步长（原型 `hTimes()`＝24 小时 × 4 刻）。
const int medSlotStepMin = 15;

/// 剂量量程（原型 `hNums(0.5,6,0.5)`）：0.5 一片起步、6 片封顶、半片一档。
const double medDoseLo = 0.5;
const double medDoseStep = 0.5;
const int medDoseCount = 12; // (6-0.5)/0.5 + 1

/// 单位固定「片」（原型 `hDrugSave` 硬编码 `unit:'片'`，弹层没有输入位）。
const String medUnit = '片';

/// 新建档案的默认时刻（原型 `hDrugOpen` 的 `hdTimes=['08:00']`）。
const String medDefaultTime = '08:00';

/// 工作台 chips 最多铺几枚，余下的收进「+n 全部」（原型 `slice(0,5)`）。
const int medChipMax = 5;

/// 单张报告附件上限那种「两处不各写一遍」：弹层的「＋格」显隐与点格守卫同吃这一句。
List<String> medTimeOptions() => [
      for (var h = 0; h < 24; h++)
        for (final m in const [0, 15, 30, 45])
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
    ];

/// 时刻 → 滚轮档位下标；存量时刻不在 15 分钟档上时**就近归档**（滚轮档位就是可选集合，
/// 不假装能选中间值），读不到则回落默认档（`08:00`）。
///
/// 档位表是「00:00 起、每 15 分钟一格」的等差数列，所以直接除法取下标：
/// 走「换算成字符串再 indexOf」会在跨零点那档踩坑（`minToHhmm(0)` 给 `0:00`，表里是 `00:00`，
/// 匹配不到就静默回落 08:00——23:59 那条会被归到早上）。
int medTimeIdx(String? t) {
  final m = hhmmToMin(t);
  if (m == null) return medTimeOptions().indexOf(medDefaultTime);
  return ((m / medSlotStepMin).round() % (24 * 4)).toInt();
}

List<String> medDoseLabels() => [
      for (var i = 0; i < medDoseCount; i++) mdDoseTx(medDoseLo + i * medDoseStep),
    ];

double medDoseAt(int idx) => (medDoseLo + idx * medDoseStep).clamp(medDoseLo, 6.0).toDouble();

/// 存量剂量 → 最近档（不在档上一律吸附，同 `medTimeIdx` 口径）。
int medDoseIdx(double? v) {
  if (v == null) return 1; // 新增默认 1 片（原型 index 1）
  return (((v - medDoseLo) / medDoseStep).round()).clamp(0, medDoseCount - 1);
}

/// 漏服宽限四档（原型 `hWheelPick(...,[15,30,60,120])`）。
const List<int> medGraceOptions = [15, 30, 60, 120];

String medGraceTx(int v) => '超 $v 分钟';

/// 剂量读数：整数不带小数点，半片留一位（原型 `${dg.dose}` 是 JS 数字直出）。
String mdDoseTx(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

// ==================== 今日计划 / 已服 / 漏服 / 依从 ====================

/// 参与今日计划的档案＝未归档的那些（卡列表同源，两处共用这一句）。
List<DrugPlan> mdActive(List<DrugPlan> drugs) => [for (final d in drugs) if (!d.archived) d];

/// 今日计划次数与已服次数（原型 `hMedPlan`）：`t=Σ times.length`，`o` **只认 taken**。
({int t, int o}) mdPlan(List<DrugPlan> drugs, Map<int, Map<String, String>> logsByDrug) {
  var t = 0, o = 0;
  for (final d in mdActive(drugs)) {
    final lg = logsByDrug[d.id] ?? const <String, String>{};
    for (final x in d.times) {
      t++;
      if (slotTaken(lg, x)) o++;
    }
  }
  return (t: t, o: o);
}

/// 单档案某日计划（热力行按这个算，见文件头第三条口径）。
({int t, int o}) mdDrugDay(DrugPlan d, Map<String, String> logs) {
  var t = 0, o = 0;
  for (final x in d.times) {
    t++;
    if (slotTaken(logs, x)) o++;
  }
  return (t: t, o: o);
}

/// 打卡行读数（原型 `${medDone}/${medTotal} 次 · 今日`）。
String mdPlanTx(({int t, int o}) p) => '${p.o}/${p.t} 次 · 今日';

/// 读数那一行给谁看：一支档案都没建时**出「—」不出「0/0」**——
/// 「0 次没吃」与「根本没计划」是两回事（工作台卡与管理屏同一句都走这里，两处不许各判各的）。
String mdPlanRead(({int t, int o}) p) => p.t == 0 ? '—' : mdPlanTx(p);

/// 热力三档。`t>0` 守卫是判据的一部分：当日没有任何计划时不能画成「全部服用」。
MdHeat mdHeatDay({required int t, required int o}) =>
    (t > 0 && o >= t) ? MdHeat.full : (o > 0 ? MdHeat.part : MdHeat.none);

enum MdHeat { full, part, none }

extension MdHeatTx on MdHeat {
  String get label => switch (this) {
        MdHeat.full => '全部服用',
        MdHeat.part => '部分服用',
        MdHeat.none => '未服用',
      };
}

/// 达标档＝实心绿，部分档＝琥珀，无档由页面吃 `scheme` 中性底（暗色不能靠固定浅灰）。
const int mdHeatFullHex = 0xFF10B981;
const int mdHeatPartHex = 0xFFFCD34D;

/// 某档的单日读数（热力格 tooltip 与测试断言同吃这一份）。
typedef MedDay = ({String day, int t, int o, MdHeat heat});

/// 近 7 天热力行（**旧→新**，原型 `Array.from({length:7},(_,i)=>htDay(6-i))`）。
/// `byDay`＝日期 →（drug_id →（时刻 → 状态）），一次取数喂七格，不按天开七路查询。
List<MedDay> mdHeatRow({
  required DrugPlan drug,
  required List<String> days,
  required Map<String, Map<int, Map<String, String>>> byDay,
}) {
  return [
    for (final day in days)
      () {
        final p = mdDrugDay(drug, byDay[day]?[drug.id] ?? const {});
        return (day: day, t: p.t, o: p.o, heat: mdHeatDay(t: p.t, o: p.o));
      }(),
  ];
}

/// 从 `now` 往前推 `n` 天（含今天），旧→新（日期口径一律 `dayKey`，写死日期属测试时间炸弹）。
List<String> mdDaysBack(DateTime now, int n) => [
      for (var i = n - 1; i >= 0; i--) dayKey(now.subtract(Duration(days: i))),
    ];

/// 当前分钟数（漏服判定用，`now` 由 `healthClockProvider` 注入）。
int mdNowMin(DateTime now) => now.hour * 60 + now.minute;

/// 单档案今日漏服数（宽限由调用侧从设置读，见 `missedSlots`）。
int mdMissedOf(
  DrugPlan d,
  Map<String, String> logs,
  int nowMin, {
  required int graceMin,
}) =>
    missedSlots(times: d.times, loggedAt: logs, nowMin: nowMin, missedGraceMin: graceMin);

/// 今日漏服合计（跨档案求和，卡头徽标与屏顶读数同一判据）。
int mdMissedTotal(
  List<DrugPlan> drugs,
  Map<int, Map<String, String>> logsByDrug,
  int nowMin, {
  required int graceMin,
}) =>
    mdActive(drugs)
        .fold(0, (a, d) => a + mdMissedOf(d, logsByDrug[d.id] ?? const {}, nowMin, graceMin: graceMin));

/// 漏服徽标（n=0 整枚不出现，不是摆一个「今日漏服 0 次」）。
String? mdMissedBadgeTx(int n) => n <= 0 ? null : '今日漏服 $n 次';

/// 依从率文案：计划为 0 → 「—」（0% 会被读成「一次都没吃」，与「没计划」是两回事）。
String mdRateTx(double? rate) => rate == null ? '—' : '${rate.toStringAsFixed(0)}%';

/// 依从率读数（`compliance` 的档案侧包装，计划位仍只吃未归档档案）。
double? mdCompliance(List<DrugPlan> drugs, Map<int, Map<String, String>> logsByDrug) {
  final p = mdPlan(drugs, logsByDrug);
  return p.t == 0 ? null : double.parse((p.o / p.t * 100).toStringAsFixed(0));
}

// ==================== 卡面与 chips 文案 ====================

/// 规格显示：库里存 null（空串在写侧就折成 null），这里补「—」——
/// 原型的 `'—'` 字符串进的是 `spec` 列，本实现不占数据面（工单 §2 偏离⑥）。
String mdSpecTx(String? spec) {
  final v = (spec ?? '').trim();
  return v.isEmpty ? '—' : v;
}

/// 卡副信息（原型 `${dg.spec} · 每次 ${dg.dose} ${dg.unit}${dg.end?' · 疗程至 …':''}`）。
String mdCardSub(DrugPlan d) {
  final end = d.endDate;
  return '${mdSpecTx(d.spec)} · 每次 ${mdDoseTx(d.dose)} ${d.unit}'
      '${(end == null || end.isEmpty) ? '' : ' · 疗程至 $end'}';
}

/// 剂量单位行（弹层 `hdDoseU` 原话）。
String mdDoseUnitTx(String unit) => '$unit · 每次';

/// 打卡槽位一枚（工作台 chips 与卡内时刻行同源，两处不各拼一遍）。
typedef MedSlot = ({int drugId, String time, String name, bool taken});

/// 全部待办槽位（顺序＝档案序 × 档案内时刻序，原型 `hRenderMedChips` 的 push 序）。
List<MedSlot> mdSlots(List<DrugPlan> drugs, Map<int, Map<String, String>> logsByDrug) => [
      for (final d in mdActive(drugs))
        for (final t in d.times)
          (
            drugId: d.id ?? 0,
            time: t,
            name: d.name,
            taken: slotTaken(logsByDrug[d.id] ?? const {}, t),
          ),
    ];

List<MedSlot> mdChipsShown(List<MedSlot> all) => all.take(medChipMax).toList();

/// 「+n 全部」（超出 5 枚才出；整枚文案里 n＝余下的枚数，不是总数）。
String? mdChipsMoreTx(int total) =>
    total <= medChipMax ? null : '+${total - medChipMax} 全部';

String mdSlotTx(MedSlot s) => '${s.time} ${s.name} · ${s.taken ? '已服' : '待服'}';

/// 卡内时刻行副文案（原型 `ok?'已服用 · 可撤销':'待服用'`）。
String mdSlotStateTx(bool taken) => taken ? '已服用 · 可撤销' : '待服用';

/// 卡内时刻行的按钮文字（原型 `${ok?'撤销':'打卡'}`）。
String mdSlotBtnTx(bool taken) => taken ? '撤销' : '打卡';

/// 总开关的当前态＝**在册档案全都开了提醒**才算开（无档案＝关）。
/// 这一枚开关写的是「全量覆写」，读的是「是否已全开」，两条都跟着档案列表走，
/// 不是把某个全局偏好存起来（原型 `tgMedAll` 就没有独立状态位）。
bool mdRemindAllOn(List<DrugPlan> drugs) {
  final xs = mdActive(drugs);
  if (xs.isEmpty) return false;
  return xs.every((d) => d.remind);
}

/// 屏顶「与用药相关症状」汇总（需求 184 行；只做档案级汇总，不进单张卡——
/// 每张卡挂同一个数＝假精确，工单 §2 偏离⑦）。
String mdSymLinkTx(int n) => n == 0 ? '暂无用药相关症状' : '与用药相关症状 $n 条';

// ==================== 免打扰窗口（从判据反推，不写死字面量） ====================

/// 免打扰时段文案（起止由注入的 `inDnd` 判据反推）。
///
/// 判据来自 `NotificationService.inDndWindow`（固定 23:00–07:00），页面把它当函数传进来，
/// 域层不依赖 core，测试可以在 22:59／23:00／06:59／07:00 四点探边界——
/// 窗口改了而这里没跟着改，标签就会和实际行为不一致（这条就是防它）。
/// 无窗返回 null（页面出「未开启」），全天返「全天」。
String? mdDndTx(bool Function(DateTime t) inDnd, DateTime day) {
  final on = <int>{
    for (var h = 0; h < 24; h++) //
        if (inDnd(DateTime(day.year, day.month, day.day, h))) h
  };
  if (on.isEmpty) return null;
  if (on.length == 24) return '全天';
  final start = on.firstWhere((h) => !on.contains((h + 23) % 24));
  final last = on.firstWhere((h) => !on.contains((h + 1) % 24));
  final end = (last + 1) % 24;
  return '${h2(start)}:00 – ${h2(end)}:00';
}

String h2(int v) => v.toString().padLeft(2, '0');

// ==================== 文案常量（一处定义，屏／弹层／测试同一份） ====================

/// 建档名称必填（原型 `hDrugSave` 原话）。
const String medNameRequiredTx = '请填写药品名称';

/// 时刻重复（原型 `hdAddT` 原话）。
const String medDupTimeTx = '该时刻已存在';

String medAddedTx(String t) => '已加入 $t';

/// 档案删除确认（原型 `hDrugDel` 的 `confirmRow` 原话）。
String medDelConfirmTx(String name) => '删除「$name」档案';

/// 归档后提示（原型原话；实现真做到「流水保留」，见 `archiveDrug`）。
const String medDeletedTx = '已删除档案 · 历史打卡保留在流水';

/// 单药提醒（原型「已排程到提醒中心」在批8 之前是假承诺，见工单 §2）。
const String medRemOnTx = '提醒已开启 · 排程随提醒中心上线生效';
const String medRemOffTx = '该药提醒已关闭';
const String medAllOnTx = '已全部开启提醒 · 排程随提醒中心上线生效';
const String medAllOffTx = '已全部关闭用药提醒';

/// 没有在册档案时点总开关（不给一个点了没反应的开关，也不谎报「已全部开启」）。
const String medNoDrugTx = '还没有药品档案 · 先建档再开提醒';

/// 建档成功（原型 `toast('已建档 · 提醒已排程到通知中心')`；排程未接线，改成只说开关状态）。
String medSavedTx(String name, bool rem) =>
    '已建档 $name · ${rem ? '提醒已开启 · 排程随提醒中心上线生效' : '未开启提醒'}';

/// 打卡／撤销（原型 `hMedTap` 原话）。
String medTapTx(String time, String name, bool taken) =>
    '$time · $name ${taken ? '打卡成功' : '已撤销打卡'}';

/// 屏脚注（原型原话，需求 176 行隐私/医嘱口径的落点）。
const String medFootnoteTx = '处方药请遵医嘱 · 本模块只做记录与提醒，不提供用药建议';

/// 卡列表空态（原型 `hRenderMeds` 空分支）。
const String medEmptyTx = '还没有药品档案 · 点下方「＋ 新增药品」';

/// 工作台 chips 空态（原型 `hRenderMedChips` 空分支）。
const String medChipEmptyTx = '暂无用药计划 · 去「用药」建档';

/// 疗程日校验（原型 `<input type=date>` 浏览器自带上限校验；本 App 是文本＋就地滚轮，
/// 得自己卡：非 `yyyy-MM-dd`、月/日越界、真实日历不存在（2 月 30 日）都当场拒收，
/// 不让 `DateTime.tryParse` 把越界值归一成另一天）。
String? medEndDateErr(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  if (m == null) return '疗程日期格式 yyyy-MM-dd';
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12) return '疗程日期月份不合法';
  final probe = DateTime.utc(y, mo, d);
  if (probe.day != d || probe.month != mo || probe.year != y) return '疗程日期不存在';
  return null;
}

/// 时刻去重＋升序（原型 `hdAddT` 拦重复、`push` 后 `sort()`），并且**归一成零填充的 `HH:mm`**：
/// 库里混进 `9:00` 这种写法时，打卡行的 key 与漏服判定都对不上 `09:00`（`Map['09:00']` 取不到 `9:00`），
/// 排序也会「9:00」排在「10:00」后面——所以写侧先归一，读侧只吃一种写法。
List<String> mdCleanTimes(List<String> raw) {
  final out = <String>[];
  for (final t in raw) {
    final m = hhmmToMin(t);
    if (m == null) continue; // 非法时刻不进档案（写了会永远判不出漏服）
    final label = '${h2(m ~/ 60)}:${h2(m % 60)}';
    if (!out.contains(label)) out.add(label);
  }
  out.sort();
  return out;
}
