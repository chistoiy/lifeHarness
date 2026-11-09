import 'dart:convert';
import 'dart:io';

import 'health_calc.dart' show dayKey;

/// 健康流水导出（批6b · 需求 176 行 ＋ 原型 `p-hSet` 的「导出健康流水 CSV / JSON」）。
///
/// 四条口径写在最近处：
/// · **导出含用药与身体数据（敏感）**：预览行与完成提示都带 [healthExportSensitiveNote] 一句实话，
///   不许只说「已生成」；文件名不放中文（跨端文件名与 SAF 兼容面），实话落在提示与预览；
/// · **文件恒公制**：屏上 kg/斤、km/mile 只影响展示与录入（§五.10），导出跟着换会让同一列出现两种单位；
/// · **范围×格式两维**照原型 `hExport` 的四档范围（本机全部/近 30 天/近 90 天/按月份），
///   「按月份」选中后才出月份滚轮——不设「点一下才知要选月」的两段式；
/// · 本文件纯函数/纯 IO（`dir` 与 `now` 由调用侧注入，测试喂临时目录与固定日期），形状照 `ledger_export.dart`。

/// 范围档（原型 `hExport` 的第 3 参逐字：本机全部 · 近 30 天 · 近 90 天 · 按月份）。
const List<(String, String)> kHealthExportScopes = [
  ('all', '本机全部'),
  ('d30', '近 30 天'),
  ('d90', '近 90 天'),
  ('month', '按月份'),
];

/// 格式两档（需求 176 行「导出 CSV/JSON」）。
const List<(String, String)> kHealthExportFormats = [('csv', 'CSV'), ('json', 'JSON')];

/// 敏感实话（工单 §3 明令要带的那一句）。
const String healthExportSensitiveNote = '含敏感记录（用药与身体数据）';

/// 脚注与需求 180 行「数据仅存本机」同句（周报/设置两屏共用一份，别各处手抄）。
const String healthLocalOnlyFootnote = '数据仅存本机 · 无网络上传';

const String healthCsvHeader = '日期,类型,读数,详情,备注';
const String healthJsonFieldNote = '字段：date, kind, value, detail, note';

/// 同一天的类型内序（导出文件按此排，别每次换序——文件要拿去对账）。
const List<String> exportKindOrder = ['喝水', '睡眠', '运动', '身体', '用药'];

/// 预览字段行（按格式取表头或 JSON 键序，与弹层「字段：…」一行同源）。
String healthFieldNote(String fmt) =>
    fmt == 'json' ? healthJsonFieldNote : '字段：$healthCsvHeader';

/// 一条流水（五类压成同一形状：日期/类型/读数/详情/备注）。
///
/// 侧信息（睡眠分期、运动距离与配速、身体围度）落 `detail`，
/// 拆成每类一套列会让 CSV 表头随类型变长，且 Excel 打开后大片空列。
typedef HealthExportRow = ({
  String date,
  String kind,
  String value,
  String detail,
  String note,
});

List<String> healthScopeLabels() => [for (final (_, l) in kHealthExportScopes) l];

String healthScopeKey(int index) => kHealthExportScopes[index].$1;

String healthScopeLabel(String key) =>
    kHealthExportScopes.firstWhere((s) => s.$1 == key,
        orElse: () => kHealthExportScopes.first)
        .$2;

int healthFormatIndex(String fmt) =>
    kHealthExportFormats.indexWhere((f) => f.$1 == fmt);

String healthFormatLabel(String fmt) =>
    kHealthExportFormats.firstWhere((f) => f.$1 == fmt,
        orElse: () => kHealthExportFormats.first)
        .$2;

/// 范围过滤（含当日）：`d30`＝今天往回 29 天、`d90`＝89 天、`month`＝`YYYY-MM` 前缀；
/// 日期比较用 `YYYY-MM-DD` 字典序（等长零填充，与 `dayKey` 同式）。
List<HealthExportRow> healthExportScope({
  required List<HealthExportRow> rows,
  required String scope,
  DateTime? now,
  String? month,
}) {
  final today = now ?? DateTime.now();
  switch (scope) {
    case 'd30':
      final from = dayKey(today.subtract(const Duration(days: 29)));
      return [for (final r in rows) if (r.date.compareTo(from) >= 0) r];
    case 'd90':
      final from = dayKey(today.subtract(const Duration(days: 89)));
      return [for (final r in rows) if (r.date.compareTo(from) >= 0) r];
    case 'month':
      if (month == null || month.isEmpty) return const [];
      return [for (final r in rows) if (r.date.startsWith('$month-')) r];
    default:
      return rows;
  }
}

/// RFC4180 单元格转义（含逗号/引号/换行才加引号，内部引号翻倍）——同 `ledgerCsvCell` 口径。
String healthCsvCell(String v) =>
    v.contains(RegExp(r'[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

String healthCsvLine(HealthExportRow r) =>
    [r.date, r.kind, r.value, r.detail, r.note].map(healthCsvCell).join(',');

/// JSON 对象（键序与 [healthJsonFieldNote] 一致）。
Map<String, Object?> healthJsonEntry(HealthExportRow r) =>
    {'date': r.date, 'kind': r.kind, 'value': r.value, 'detail': r.detail, 'note': r.note};

/// 文件名 `health_YYYYMMDD_HHmmss.csv/.json`（原型 toast 的 `health_*.csv` 同形，
/// 带时间戳＝同日二次导出不互相覆盖，落点靠名字就能对上时刻）。
String healthExportFileName({required String fmt, required DateTime now}) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'health_${now.year}${two(now.month)}${two(now.day)}'
      '_${two(now.hour)}${two(now.minute)}${two(now.second)}.$fmt';
}

/// 月份滚轮档位（旧→新，含当月；「按月份」选中后才出这枚滚轮）。
/// 按「绝对月序回退」实算（year*12+month-1-i 再拆回年月）——
/// 直接对 month 做减法再取模会在跨年处翻车（10 月往回 11 档＝去年 11 月，不是今年 12 月）。
List<String> healthMonthLabels(DateTime now, {int count = 12}) {
  final base = now.year * 12 + now.month - 1;
  return [
    for (var i = count - 1; i >= 0; i--)
      '${(base - i) ~/ 12}-${((base - i) % 12 + 1).toString().padLeft(2, '0')}',
  ];
}

/// 落盘：CSV 首行表头、JSON 顶层数组；返回路径与写出行数。
///
/// 行数取**过滤后**的条数——弹层预览与完成提示必须与文件里的条数一致，
/// 否则「本机全部 0 条」也能写出一个只有表头的文件却报「128 条」。
Future<({String path, int count})> writeHealthExportFile({
  required String dir,
  required String fmt,
  required List<HealthExportRow> rows,
  required DateTime now,
}) async {
  final path = '$dir${Platform.pathSeparator}${healthExportFileName(fmt: fmt, now: now)}';
  final sink = File(path).openWrite();
  var count = 0;
  try {
    if (fmt == 'json') {
      sink.write('[\n');
    } else {
      sink.write('$healthCsvHeader\n');
    }
    for (final r in rows) {
      if (fmt == 'json') {
        if (count > 0) sink.write(',\n');
        sink.write(jsonEncode(healthJsonEntry(r)));
      } else {
        sink.write('${healthCsvLine(r)}\n');
      }
      count++;
    }
    if (fmt == 'json') sink.write(count == 0 ? ']' : '\n]');
  } finally {
    await sink.close();
  }
  return (path: path, count: count);
}

/// 完成提示（原型 `hExport` 那句是 `落点见「数据与同步」`——本仓的备份文件屏只扫
/// `backup/` 与 `exports/`，导出件落 documents 根（与记账导出同一既有通道），
/// 那句话在这台机上不成立，改成**真路径**；工单 §4.5 登记为偏离）。
String healthExportToast({
  required String path,
  required int count,
  required String scope,
}) =>
    '已生成 ${baseNameOf(path)} · ${healthScopeLabel(scope)} $count 条 · '
    '$healthExportSensitiveNote · 落点 $path';

String baseNameOf(String path) => path.split(RegExp(r'[\\/]')).last;
