/// C05 · 通用可读数据出口「格式说明」纯函数层（零依赖、纯 Dart、零网络）。
///
/// 口径（竞品补全清单 C05）：把可读目录投影从 notes/md 扩到更多模块，附
/// 「schema 版本 ＋ 逐表字段」格式说明；与 `.lhbak` 可恢复包**同源同谓词**。
///
/// 本层刻意零 import（连 core/database 都不碰）：表清单、DDL 语句、时间谓词
/// 全部由调用方注入——时间筛选计划从 `shared/linkage/export_units.dart` 的
/// `exportTimeFilters` 取，逐表字段从 `DbSchema.createStatements` 经
/// [parseDdlColumns] 解析，二者都不在 core 层自建第二份定义（避免 core→shared
/// 反向依赖，R2 同族顾虑；交叉一致性由守护用例负责）。
///
/// 写进可读目录树的 UI 出口在 `shared/linkage/backup_read_export.dart`
/// （本轮禁改路径），故本层提供 [readableProjectionMembers] 成员 map，
/// 待该出口接线时并入其投影成员表即可（「UI 出口待接线」）。
library;

import 'dart:convert';

/// 格式说明自身的 schema 版本（FORMAT.md / schema.json 的形状版本）。
const int kReadableFormatSchema = 1;

/// 一个可读目录导出单元的投影说明。
class ReadableUnitDoc {
  const ReadableUnitDoc({
    required this.id,
    required this.label,
    required this.tables,
    required this.projection,
  });

  final String id;
  final String label;
  final List<String> tables;

  /// 该模块在可读目录树里的输出（如 `data/<表>.json` / `ledger/*.csv`）。
  final String projection;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'tables': tables,
        'projection': projection,
      };
}

/// 一张表的逐表字段说明（columns 由 [parseDdlColumns] 从真实 DDL 解析）。
class ReadableTableDoc {
  const ReadableTableDoc({
    required this.table,
    required this.columns,
    this.timeColumn,
    this.timePredicate,
  });

  final String table;
  final List<String> columns;

  /// 业务时间列（来自 export_units.timeRoots）；null＝恒全量表。
  final String? timeColumn;

  /// 与 `.lhbak` 包同源的筛选谓词 SQL（来自 exportTimeFilters）；null＝恒全量。
  final String? timePredicate;

  bool get timeFiltered => timePredicate != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'table': table,
        'columns': columns,
        if (timeColumn != null) 'timeColumn': timeColumn,
        if (timePredicate != null) 'timePredicate': timePredicate,
        'timeFiltered': timeFiltered,
      };
}

/// 从一条 `CREATE TABLE ... (...)` DDL 解析「表名 ＋ 逐列名」（纯函数、容错）。
///
/// 约束行（PRIMARY / UNIQUE / CHECK / FOREIGN / CONSTRAINT …）与 CREATE INDEX /
/// INSERT 等非建表语句一律跳过；列名带引号或反引号也归一。返回 null＝非建表语句。
({String table, List<String> columns})? parseDdlColumns(String ddl) {
  final m = RegExp(
    r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(([\s\S]*)\)',
    caseSensitive: false,
  ).firstMatch(ddl);
  if (m == null) return null;
  final table = m.group(1)!;
  final body = m.group(2)!;
  const skipHeads = <String>{
    'PRIMARY', 'UNIQUE', 'CHECK', 'FOREIGN', 'CONSTRAINT', 'KEY', 'INDEX',
    'EXCLUDE', 'ON', 'WITHOUT',
  };
  final cols = <String>[];
  for (final raw in body.split(',')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final first = line
        .split(RegExp(r'\s+'))
        .first
        .replaceAll(RegExp(r'["`\[\]]'), '');
    if (skipHeads.contains(first.toUpperCase())) continue;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(first)) continue;
    if (!cols.contains(first)) cols.add(first);
  }
  return (table: table, columns: cols);
}

/// 批量把 DDL 语句清单解析成「表 → 列」映射（供 [buildFormatMarkdown] 用）。
Map<String, List<String>> parseAllDdlColumns(Iterable<String> statements) {
  final out = <String, List<String>>{};
  for (final s in statements) {
    final parsed = parseDdlColumns(s);
    if (parsed != null) out[parsed.table] = parsed.columns;
  }
  return out;
}

/// 生成 `FORMAT.md`：schema 版本 ＋ 目录结构 ＋ 逐表字段 ＋ 逐模块投影 ＋
/// 时间谓词（同源同谓词）＋ 恢复权威性声明。纯字符串序列化，产物可直接落盘。
String buildFormatMarkdown({
  required int dbSchemaVersion,
  required List<ReadableUnitDoc> units,
  required List<ReadableTableDoc> tables,
}) {
  final sb = StringBuffer();
  sb.writeln('# LifeHarness 可读目录 · 格式说明');
  sb.writeln();
  sb.writeln('- 格式 schema 版本：$kReadableFormatSchema');
  sb.writeln('- 数据库 schema 版本：$dbSchemaVersion');
  sb.writeln('- 只读数据出口：**不是恢复源**；恢复一律以 .lhbak 包内 db.sqlite 为权威。');
  sb.writeln('- 时间筛选谓词与 .lhbak 可恢复包**同源同谓词**（exportTimeFilters）；');
  sb.writeln('  未列时间谓词的表＝恒全量，不施加任何 WHERE。');
  sb.writeln('- 全程纯本地生成，零网络、零凭据、不上传全库。');
  sb.writeln();
  sb.writeln('## 目录结构');
  sb.writeln();
  sb.writeln('- `config/settings.json`：口径设置（零凭据），与包内同源。');
  sb.writeln('- `notes/*.md`：笔记 / 日记 / 书摘 / 导图 md 只读投影。');
  sb.writeln('- `ledger/`、`health/`：既有领域导出器收编（csv + json）。');
  sb.writeln('- `data/<模块>/<表>.json`：通用投影，`SELECT *`，行键＝数据库列；');
  sb.writeln('  空表也写空数组（`[]`）＝实话形态，不静默缺文件。');
  sb.writeln('- `attachments/`：附件拷贝（开关）。');
  sb.writeln('- `FORMAT.md` / `schema.json`：本格式说明（schema 版本＋逐表字段）。');
  sb.writeln();
  sb.writeln('## 逐表字段（DB schema v$dbSchemaVersion）');
  sb.writeln();
  sb.writeln('| 表 | 字段 | 时间列 | 时间谓词（同源） |');
  sb.writeln('|---|---|---|---|');
  for (final t in tables) {
    final fields = t.columns.isEmpty ? '（未解析）' : t.columns.join(' / ');
    final tc = t.timeColumn ?? '—';
    final tp = t.timePredicate ?? '恒全量';
    sb.writeln('| ${t.table} | $fields | $tc | $tp |');
  }
  sb.writeln();
  sb.writeln('## 逐模块投影');
  sb.writeln();
  for (final u in units) {
    sb.writeln('- **${u.label}**（`${u.id}`）：${u.projection}；表 ${u.tables.length} 张');
  }
  sb.writeln();
  return sb.toString();
}

/// 生成 `schema.json`（机器可读的同份说明）。
String buildSchemaJson({
  required int dbSchemaVersion,
  required List<ReadableUnitDoc> units,
  required List<ReadableTableDoc> tables,
}) =>
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format_schema': kReadableFormatSchema,
      'db_schema': dbSchemaVersion,
      'recovery_authority': 'db.sqlite',
      'tables': <Object?>[for (final t in tables) t.toJson()],
      'units': <Object?>[for (final u in units) u.toJson()],
    });

/// 可读目录投影成员（成员名 → 文本）：把格式说明并进既有投影成员表即可。
/// ⚠ UI 出口（`backup_read_export.dart`）本轮禁改，故标注「UI 出口待接线」。
Map<String, String> readableProjectionMembers({
  required int dbSchemaVersion,
  required List<ReadableUnitDoc> units,
  required List<ReadableTableDoc> tables,
}) =>
    <String, String>{
      'FORMAT.md': buildFormatMarkdown(
          dbSchemaVersion: dbSchemaVersion, units: units, tables: tables),
      'schema.json': buildSchemaJson(
          dbSchemaVersion: dbSchemaVersion, units: units, tables: tables),
    };
