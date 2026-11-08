/// C05 · 可读目录「逐模块 CSV 投影」纯序列化层（零依赖、零网络）。
///
/// 口径（竞品补全清单 C05）：
/// - 「可读目录」在 notes/md 与 `data/<表>.json` 之外，为 **物品 / 目标 / 习惯 /
///   阅读 / 影音游 / 时间** 六模块逐表产出 CSV——表格类数据用 CSV 才真可读；
/// - 与 `.lhbak` 可恢复包**同源同谓词**：行集由调用方用 `exportTimeFilters`
///   的同一份谓词读出（本层只做序列化，不查库、不另造时间口径）；
/// - 零 import：表清单 / 列序 / 行数据全部由调用方注入（同 `readable_format.dart`
///   的「不自建第二份定义」理由），故可脱离 DB 直接单测。
///
/// 落盘出口在 `shared/linkage/backup_read_export.dart`（走既有 SAF/文件出口）。
library;

/// C05 扩容模块 id（与 `kExportUnits` 的 id 同口径）。
///
/// `time` 无对应导出单元（`time_blocks` 属未归属表，全量包经差集法整表带入），
/// 其 id 沿用标签作用域 `kTagScopes` 与 `dbTableLabels` 的「时间」口径（`time`），
/// 不另造命名。
const List<String> kReadableCsvModuleIds = <String>[
  'items',
  'goals',
  'habit',
  'read',
  'media',
  'time',
];

/// 时间模块的人话标签（与 `dbTableLabels` 的 module 值一致）。
const String kReadableTimeModuleLabel = '时间';

/// 时间模块的表清单：`events` 已一次性并入 `time_blocks` 并退役（恒空壳），
/// 只投影时间块，避免给用户一份永远空的「日程」表。
const List<String> kReadableTimeTables = <String>['time_blocks'];

/// 该模块是否走 CSV 投影（[moduleIds] 空＝全部数据＝全选，与导出面板同口径）。
bool readableCsvWanted(String moduleId, Set<String> moduleIds) =>
    moduleIds.isEmpty || moduleIds.contains(moduleId);

/// CSV 单元格：含逗号 / 双引号 / 换行才加引号（RFC 4180），内部 `"` 双写。
/// null 写空串（与 JSON 投影的 null 语义区分：CSV 无 null 类型）。
String csvCell(Object? v) {
  final s = v == null ? '' : '$v';
  final needsQuote = s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r');
  if (!needsQuote) return s;
  final escaped = s.replaceAll('"', '""');
  return '"$escaped"';
}

/// 列序：给定 [columns] 优先（保证**空表也出表头**）；否则按行键首次出现
/// 顺序取并集（`SELECT *` 的行键即真实列，不猜列序）。
List<String> csvColumns(
  List<Map<String, Object?>> rows, {
  List<String>? columns,
}) {
  if (columns != null && columns.isNotEmpty) return List<String>.of(columns);
  final seen = <String>{};
  final out = <String>[];
  for (final r in rows) {
    for (final k in r.keys) {
      if (seen.add(k)) out.add(k);
    }
  }
  return out;
}

/// 行 → CSV 文本（表头恒在；空行集＝只有表头＝「导了但没数据」的实话形态，
/// 与 `data/<表>.json` 写 `[]` 同一条口径）。
String rowsToCsv(
  List<Map<String, Object?>> rows, {
  List<String>? columns,
}) {
  final cols = csvColumns(rows, columns: columns);
  final sb = StringBuffer();
  sb.writeln(cols.map(csvCell).join(','));
  for (final r in rows) {
    sb.writeln(cols.map((c) => csvCell(r[c])).join(','));
  }
  return sb.toString();
}
