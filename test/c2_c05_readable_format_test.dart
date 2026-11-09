import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/export/readable_format.dart';
import 'package:lifeharness/shared/linkage/export_units.dart';

/// C05 通用可读数据出口守护：格式说明（schema 版本＋逐表字段）＋同源同谓词。
/// 交叉核对 `export_units.dart`（可恢复包同源）与 `DbSchema.createStatements`
/// （逐表字段真实来源）；纯函数级、正负两档同例都断。
void main() {
  const ddl = 'CREATE TABLE IF NOT EXISTS notes ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'title TEXT NOT NULL, '
      'body TEXT, '
      'created_at INTEGER NOT NULL, '
      'UNIQUE(title))';

  test('① parseDdlColumns：正档解析逐列 / 负档跳过约束行与非建表语句', () {
    final r = parseDdlColumns(ddl);
    expect(r, isNotNull, reason: '正档：建表语句可解析');
    expect(r!.table, 'notes');
    expect(r.columns, <String>['id', 'title', 'body', 'created_at'],
        reason: '正档：逐表字段齐全');
    expect(r.columns.contains('UNIQUE'), isFalse,
        reason: '负档：约束行不是列');
    expect(parseDdlColumns('CREATE INDEX idx ON notes(title)'), isNull,
        reason: '负档：CREATE INDEX 不是建表');
    expect(parseDdlColumns("INSERT INTO notes VALUES (1,'x')"), isNull,
        reason: '负档：INSERT 不是建表');
  });

  test('② 逐表字段取自真实 DDL（DbSchema），非虚构', () {
    final all = parseAllDdlColumns(DbSchema.createStatements);
    expect(all, isNotEmpty, reason: '正档：真实 DDL 能解出多张表');
    expect(all.values.any((c) => c.contains('id')), isTrue,
        reason: '正档：至少一张表含 id 列');
    expect(all.containsKey('__no_such_table__'), isFalse,
        reason: '负档：不凭空造表');
  });

  test('③ 同源同谓词：FORMAT.md 逐表谓词与 exportTimeFilters 一致', () {
    final filters = exportTimeFilters(<String>['ledger'],
        from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
    final txn = filters[DbSchema.tLedgerTxns];
    expect(txn, isNotNull, reason: '正档：流水表有时间谓词');

    final tables = <ReadableTableDoc>[
      for (final u in kExportUnits.where((x) => x.id == 'ledger'))
        for (final t in u.tables)
          ReadableTableDoc(
            table: t,
            columns: const <String>['id', 'date', 'amt'],
            timeColumn: filters[t] != null ? 'date' : null,
            timePredicate: filters[t]?.whereSql,
          ),
    ];
    final units = <ReadableUnitDoc>[
      for (final u in kExportUnits)
        ReadableUnitDoc(
          id: u.id,
          label: u.label,
          tables: u.tables,
          projection: 'data/<表>.json',
        ),
    ];
    final md = buildFormatMarkdown(
        dbSchemaVersion: DbSchema.version, units: units, tables: tables);

    expect(md, contains(txn!.whereSql),
        reason: '正档：流水表谓词 SQL 与可恢复包同源');
    expect(md, contains(DbSchema.tLedgerTxns), reason: '正档：逐表列出流水表');
    expect(md, contains('恒全量'),
        reason: '正档：维度表标恒全量（不在 filters 里）');
    expect(md, contains('schema 版本'), reason: '正档：含 schema 版本字样');
    expect(md, contains('${DbSchema.version}'),
        reason: '正档：DB schema 版本＝活库版本');
    for (final u in kExportUnits) {
      expect(md, contains(u.label), reason: '正档：投影覆盖模块 ${u.id}');
    }
  });

  test('④ schema.json 机器可读且与 FORMAT.md 同源', () {
    final tables = <ReadableTableDoc>[
      ReadableTableDoc(table: 'notes', columns: const <String>['id', 'title']),
    ];
    final units = <ReadableUnitDoc>[
      ReadableUnitDoc(
          id: 'journal', label: '日记', tables: const <String>['notes'],
          projection: 'data/notes.json'),
    ];
    final json = buildSchemaJson(
        dbSchemaVersion: DbSchema.version, units: units, tables: tables);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['db_schema'], DbSchema.version, reason: '正档：版本一致');
    expect(decoded['format_schema'], kReadableFormatSchema);
    expect((decoded['tables'] as List).length, 1, reason: '正档：逐表入 json');
    expect((decoded['units'] as List).length, 1, reason: '正档：逐模块入 json');
    expect(decoded['tables'][0]['timeFiltered'], isFalse,
        reason: '负档：未给谓词＝恒全量表');
  });

  test('⑤ readableProjectionMembers：两成员齐备（UI 出口待接线）', () {
    final members = readableProjectionMembers(
      dbSchemaVersion: DbSchema.version,
      units: <ReadableUnitDoc>[
        for (final u in kExportUnits)
          ReadableUnitDoc(
              id: u.id,
              label: u.label,
              tables: u.tables,
              projection: 'data/<表>.json'),
      ],
      tables: <ReadableTableDoc>[
        ReadableTableDoc(table: 'notes', columns: const <String>['id']),
      ],
    );
    expect(members.containsKey('FORMAT.md'), isTrue, reason: '正档：格式说明成员');
    expect(members.containsKey('schema.json'), isTrue, reason: '正档：schema 成员');
    expect(members['FORMAT.md']!, contains('逐表字段'),
        reason: '正档：FORMAT.md 含逐表字段段');
    expect(members.containsKey('notes.md'), isFalse,
        reason: '负档：本层只产格式说明，不伪造 md 投影');
  });
}
