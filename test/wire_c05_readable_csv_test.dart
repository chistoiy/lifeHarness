/// C05 · 可读目录逐模块 CSV 投影守护（纯函数级，零 DB）。
///
/// 每条断言同例给正档（该成立的成立）与负档（不该成立的确实不成立），
/// 防「只写正向、实现恒真」的假绿。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/export/readable_format.dart';
import 'package:lifeharness/core/export/readable_tables.dart';

void main() {
  test('① csvCell：含逗号/引号/换行才加引号；普通值原样（负档不滥用引号）', () {
    expect(csvCell('a,b'), '"a,b"', reason: '正档：逗号单元格加引号');
    expect(csvCell('he said "hi"'), '"he said ""hi"""',
        reason: '正档：内部双引号双写');
    expect(csvCell('line1\nline2'), '"line1\nline2"',
        reason: '正档：换行单元格加引号');
    expect(csvCell('plain'), 'plain', reason: '负档：无需转义时保持原样');
    expect(csvCell(null), '', reason: '负档：null 不写成字面 null');
  });

  test('② rowsToCsv：表头＋行序稳定；空行集只出表头（无假数据行）', () {
    final csv = rowsToCsv(<Map<String, Object?>>[
      {'id': 1, 'name': '早,起', 'note': 'x'},
      {'id': 2, 'name': '阅读', 'note': null},
    ], columns: const <String>['id', 'name', 'note']);
    final lines = csv.trim().split('\n');
    expect(lines.first, 'id,name,note', reason: '正档：列序＝注入的 DDL 列序');
    expect(lines.length, 3, reason: '正档：表头＋两行数据');
    expect(csv, contains('1,"早,起",x'), reason: '正档：逗号值被转义');
    expect(csv, contains('2,阅读,'), reason: '正档：null 落空串');
    expect(csv, isNot(contains('null')), reason: '负档：不写字面 null');

    final empty = rowsToCsv(const <Map<String, Object?>>[],
        columns: const <String>['id', 'name']);
    expect(empty.trim(), 'id,name', reason: '正档：空表也出表头（实话形态）');
    expect(empty.trim().split('\n').length, 1,
        reason: '负档：空表不伪造数据行');
  });

  test('③ csvColumns：无注入列时按行键首次出现并集；注入列优先', () {
    expect(csvColumns(<Map<String, Object?>>[
      {'b': 1},
      {'a': 2, 'b': 3},
    ]), <String>['b', 'a'], reason: '正档：首次出现序并集');
    expect(
        csvColumns(<Map<String, Object?>>[
          {'b': 1},
        ], columns: const <String>['id', 'b']),
        <String>['id', 'b'],
        reason: '正档：注入列序优先（空表也能定表头）');
    expect(
        csvColumns(const <Map<String, Object?>>[]), isEmpty,
        reason: '负档：无行无注入列＝不凭空造列');
  });

  test('④ readableCsvWanted：空选择＝全选；子集只认本模块（负档不误扩）', () {
    expect(readableCsvWanted('items', const <String>{}), isTrue,
        reason: '正档：全部数据含物品');
    expect(readableCsvWanted('time', const <String>{'time'}), isTrue,
        reason: '正档：显式选中时间');
    expect(readableCsvWanted('items', const <String>{'goals'}), isFalse,
        reason: '负档：未选物品不产物品 CSV');
    expect(kReadableCsvModuleIds, containsAll(<String>['items', 'goals', 'habit', 'read', 'media', 'time']),
        reason: '正档：C05 六模块齐备');
    expect(kReadableCsvModuleIds, isNot(contains('ledger')),
        reason: '负档：记账仍走专属领域导出器，不重复登记');
  });

  test('⑤ parseAlterAddColumn / parseAllDdlColumns：v53 纯加列并入逐表字段', () {
    final adds = <({String table, String column})?>[
      for (final s in DbSchema.itemsV53AddColumns) parseAlterAddColumn(s),
    ];
    expect(adds.every((a) => a != null), isTrue,
        reason: '正档：v53 八条 ALTER 全部可解析');
    expect(adds.map((a) => a!.column),
        containsAll(<String>['photos', 'attachments']),
        reason: '正档：多图/凭证两列在册');
    expect(parseAlterAddColumn('CREATE INDEX idx ON t(c)'), isNull,
        reason: '负档：非 ALTER 语句不误判');

    final all = parseAllDdlColumns(DbSchema.createStatements);
    expect(all[DbSchema.tItemProfiles],
        containsAll(<String>['name', 'photos', 'attachments']),
        reason: '正档：建表列＋追加列合并');
    expect(all[DbSchema.tNotes] ?? const <String>[], isNot(contains('photos')),
        reason: '负档：追加列不串到别的表');
  });

  test('⑥ buildReadableTableDocs：同源谓词挂表；未给谓词＝恒全量不编造', () {
    final docs = buildReadableTableDocs(
      tables: const <String>['ledger_txns', 'ledger_books'],
      ddlColumns: const <String, List<String>>{
        'ledger_txns': <String>['id', 'date', 'amt'],
      },
      timeColumns: const <String, String>{'ledger_txns': 'date'},
      timePredicates: const <String, String>{
        'ledger_txns': '"date" BETWEEN ? AND ?',
      },
    );
    expect(docs.first.columns, <String>['id', 'date', 'amt'],
        reason: '正档：列取自注入 DDL');
    expect(docs.first.timeFiltered, isTrue, reason: '正档：流水表带时间谓词');
    expect(docs.first.timeColumn, 'date', reason: '正档：业务时间列在册');
    expect(docs[1].timeFiltered, isFalse, reason: '负档：未给谓词＝恒全量');
    expect(docs[1].columns, isEmpty, reason: '负档：未解析不编造列');
  });
}
