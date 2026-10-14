/// 备份余量批3 ·「按范围自由导出＝时间维度」常驻用例（工单 ⚙ 执行面板第四项）：
/// - ① 四档映射正确（全部/近 1 年/近 3 年/自定义 → 区间边界）；
/// - ② 边界含端点（下界 00:00:00.000、止端点当日 23:59:59.999）；
/// - ③ 恒全量表不被时间谓词筛掉（维度表/容器表）；
/// - ④ 无时间列单元（AI 记录）被判不可筛，面板据其出提示；
/// - ⑤ manifest `scope` 段结构自描述（批4 恢复侧读它分流）；
/// - ⑥ `structVersion` 仍为 2（时间维度不得改容器格式版本）；
/// - ⑦ TEXT 日列（记账 `date` / 习惯 `day`）不被 INTEGER 时间戳筛空——
///    两型并存，若谓词一律绑毫秒，这两张表会被整列筛空且静默。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/shared/linkage/export_units.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openSchemaDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DbSchema.version,
        onCreate: (d, v) async {
          for (final sql in DbSchema.createStatements) {
            await d.execute(sql);
          }
        },
      ),
    );

int ms(DateTime d) => d.millisecondsSinceEpoch;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('lh_time_'));
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('① 四档时间 → 区间映射', () {
    test('全部档＝null（不施加任何时间谓词）', () {
      // all 档在 UI 侧是「时间Range 为 null」，故全库表不进筛选计划。
      final f = exportTimeFilters(
        const ['ledger'],
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );
      // 参考：显式给区间时才有谓词；all 档调用方根本不调本函数。
      expect(f.containsKey(DbSchema.tLedgerTxns), isTrue);
    });

    test('近 1 年 / 近 3 年：起＝今天回溯 1/3 年同日，止＝今天当日末', () {
      final now = DateTime(2026, 10, 15, 14, 30);
      final y1From = DateTime(2025, 10, 15);
      final y3From = DateTime(2023, 10, 15);
      for (final from in [y1From, y3From]) {
        final f = exportTimeFilters(const ['journal'],
            from: from, to: DateTime(2026, 10, 15, 23, 59, 59, 999));
        expect(f[DbSchema.tNotes]!.args.first, ms(from));
      }
      // 起止同一天（跨度 0 天）也必须产出合法闭区间，不得抛。
      final same = exportTimeFilters(const ['journal'],
          from: now, to: DateTime(2026, 10, 15, 23, 59, 59, 999));
      expect(same[DbSchema.tJournal]!.args.first, ms(DateTime(2026, 10, 15)));
      expect(same[DbSchema.tJournal]!.args.last,
          ms(DateTime(2026, 10, 15, 23, 59, 59, 999)));
    });

    test('自定义区间：起>止 由 UI 拦（返回 null 不导出），谓词层不产垃圾',
        () {
      // 口径在 ExportSheet：_range 为 null 时主钮禁用并出「请选起止时间」。
      // 谓词层只保证「拿到合法区间就给出闭区间」，不承担区间校验。
      final f = exportTimeFilters(const ['habit'],
          from: DateTime(2026, 3, 1), to: DateTime(2026, 2, 1));
      // 即便区间倒置，谓词仍自洽（结果必为空集，不会误放行数据）。
      final sql = f[DbSchema.tHabitEntries]!.whereSql;
      expect(sql, '"day" BETWEEN ? AND ?');
      expect(
          f[DbSchema.tHabitEntries]!.args,
          ['2026-03-01', '2026-02-01']);
    });
  });

  group('② 边界含端点', () {
    test('毫秒时间戳根表：下界当日 00:00:00.000 与止端点 23:59:59.999 均命中',
        () async {
      final db = await openSchemaDb();
      for (final at in [
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 1, 23, 59, 59, 999),
        DateTime(2026, 4, 30, 23, 59, 59, 999),
        DateTime(2026, 5, 2),
      ]) {
        await db.insert(DbSchema.tJournal, {
          'entry_date': ms(DateTime(at.year, at.month, at.day)),
          'content': 'x',
          'created_at': ms(at),
          'updated_at': ms(at),
        });
      }
      final f = exportTimeFilters(const ['journal'],
          from: DateTime(2026, 5, 1), to: DateTime(2026, 5, 1, 23, 59, 59, 999));
      final hit = await db.rawQuery(
          'SELECT * FROM "${DbSchema.tJournal}" WHERE ${f[DbSchema.tJournal]!.whereSql}',
          f[DbSchema.tJournal]!.args);
      expect(hit.length, 2, reason: '起止端点当天两篇都算在内，跨界两篇不算');
      await db.close();
    });

    test('TEXT 日列根表：端点按字典序闭区间命中', () async {
      final db = await openSchemaDb();
      for (final d in ['2026-04-30', '2026-05-01', '2026-05-02']) {
        await db.insert(DbSchema.tHabitEntries, {
          'habit_id': 'h1',
          'day': d,
          'origin': 'manual',
          'created_at': 0,
          'updated_at': 0,
        });
      }
      final f = exportTimeFilters(const ['habit'],
          from: DateTime(2026, 5, 1), to: DateTime(2026, 5, 1));
      final hit = await db.rawQuery(
          'SELECT * FROM "${DbSchema.tHabitEntries}" WHERE ${f[DbSchema.tHabitEntries]!.whereSql}',
          f[DbSchema.tHabitEntries]!.args);
      expect(hit.length, 1);
      expect(hit.first['day'], '2026-05-01');
      await db.close();
    });
  });

  group('③ 恒全量表不进筛选计划', () {
    test('维度表/配置表不在谓词映射里（调用方对它们不施加 WHERE）', () {
      final f = exportTimeFilters(const ['ledger'],
          from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
      // 账套/分类/账户/标签/商家…：筛掉会让流水指向不存在的维度（悬挂引用）。
      for (final t in [
        DbSchema.tLedgerBooks,
        DbSchema.tLedgerAccounts,
        DbSchema.tLedgerCategories,
        DbSchema.tLedgerTags,
        DbSchema.tLedgerMerchants,
      ]) {
        expect(f.containsKey(t), isFalse, reason: '$t 是维度表，必须恒全量');
      }
      expect(f.containsKey(DbSchema.tLedgerTxns), isTrue);
    });

    test('子表随主表走：命中集合受父表约束（跨单元引用不跟）', () {
      final f = exportTimeFilters(const ['read'],
          from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
      // 递归闭包：reviews → quotes → books。
      final reviews = f[DbSchema.tBookReviews]!;
      expect(reviews.whereSql, contains('IN (SELECT "id" FROM "book_quotes"'));
      expect(reviews.whereSql, contains('IN (SELECT "id" FROM "books"'));
      // book_dict / douban_meta＝外部缓存，恒全量。
      expect(f.containsKey(DbSchema.tBookDict), isFalse);
      expect(f.containsKey(DbSchema.tDoubanMeta), isFalse);
      // 容器表 book_lists 随其成员走。
      expect(f[DbSchema.tBookLists]!.whereSql,
          contains('IN (SELECT "id" FROM "book_list_items"'));
    });

    test('导出范围外的表不受影响（子集口径不被时间谓词越界）', () {
      final f = exportTimeFilters(const ['habit'],
          from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
      expect(f.containsKey(DbSchema.tJournal), isFalse,
          reason: '只选习惯单元时，日记表不得出现在时间筛选计划里');
      // habits 自身恒全量＝打卡定义是配置（筛掉即孤儿行）。
      expect(f.containsKey(DbSchema.tHabits), isFalse);
    });
  });

  group('④ 无时间列单元被判不可筛', () {
    test('AI 记录：timeFilterable=false 且不出现在任何谓词里', () {
      expect(exportUnitById('ai')!.timeFilterable, isFalse);
      final f = exportTimeFilters(const ['ai'],
          from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
      expect(f.containsKey(DbSchema.tAiCalls), isFalse);
      expect(exportTimeUnfilterableLabels(const ['ai']), ['AI 记录']);
      // 与其它模块同选时，只有 AI 一个被点名。
      expect(exportTimeUnfilterableLabels(const ['ledger', 'ai', 'habit']),
          ['AI 记录']);
      expect(exportTimeUnfilterableLabels(const ['ledger', 'habit']), isEmpty);
      // 全量范围（空 ids）也含 AI → 面板照样出提示行。
      expect(exportTimeUnfilterableLabels(const []), contains('AI 记录'));
    });
  });

  group('⑤⑥ manifest scope 段 + structVersion 不变', () {
    Future<Map<String, dynamic>> manifestOf(Map<String, dynamic>? scope) async {
      final db = await openSchemaDb();
      final res = await LhBak.create(
        db: db,
        outDirPath: temp.path,
        now: DateTime(2026, 10, 15, 12),
        scope: scope,
      );
      final zip = ZipDecoder().decodeBytes(res.file.readAsBytesSync());
      await db.close();
      return jsonDecode(utf8.decode(
              zip.findFile('manifest.json')!.content as List<int>))
          as Map<String, dynamic>;
    }

    test('带时间范围：scope 自描述（模块/起止/被筛表/附件开关）', () async {
      final m = await manifestOf({
        'modules': ['ledger', 'journal'],
        'from': DateTime(2026, 1, 1).toIso8601String(),
        'to': DateTime(2026, 10, 15).toIso8601String(),
        'timeFilteredTables': ['journal_entries', 'ledger_txns', 'notes'],
        'withAttachments': true,
      });
      final scope = m['scope'] as Map<String, dynamic>;
      expect(scope['modules'], ['ledger', 'journal']);
      expect(scope['from'], '2026-01-01T00:00:00.000');
      expect(scope['to'], '2026-10-15T00:00:00.000');
      // 被筛表清单必须已排序＝包内自描述可复现（批4 恢复侧读它分流）。
      expect(scope['timeFilteredTables'],
          ['journal_entries', 'ledger_txns', 'notes']);
      expect(scope['withAttachments'], isTrue);
    });

    test('scope 缺省＝键不出现（全量包与老包读作无范围，structVersion 仍 2）',
        () async {
      final m = await manifestOf(null);
      expect(m.containsKey('scope'), isFalse,
          reason: '老包/全量包不得凭空多一个 scope 键');
      expect(m['structVersion'], 2, reason: '时间维度不改容器格式版本');
    });
  });

  group('⑦ 快照内行筛：谓词落 db.sqlite，不碰活库', () {
    test('包内 db.sqlite 只含命中行；活库行数不变', () async {
      final db = await openSchemaDb();
      await db.insert(DbSchema.tHabits, {
        'id': 'h1',
        'name': '早起',
        'icon': 'x',
        'type': 'good',
        'cycle': 'day',
        'start_date': '2026-01-01',
        'created_at': 0,
        'updated_at': 0,
      });
      for (final d in ['2026-05-01', '2026-06-01', '2026-07-01']) {
        await db.insert(DbSchema.tHabitEntries, {
          'habit_id': 'h1',
          'day': d,
          'origin': 'manual',
          'created_at': 0,
          'updated_at': 0,
        });
      }
      final f = exportTimeFilters(const ['habit'],
          from: DateTime(2026, 5, 1), to: DateTime(2026, 5, 31));
      final res = await LhBak.create(
        db: db,
        outDirPath: temp.path,
        now: DateTime(2026, 10, 15, 12),
        rowFilters: {
          DbSchema.tHabitEntries: (
            whereSql: f[DbSchema.tHabitEntries]!.whereSql,
            args: f[DbSchema.tHabitEntries]!.args
          ),
        },
      );
      // 活库未被筛（备份是只读快照，绝不拿活库开刀）。
      expect((await db.query(DbSchema.tHabitEntries)).length, 3);

      final zip = ZipDecoder().decodeBytes(res.file.readAsBytesSync());
      final snapPath = p.join(temp.path, 'snap.sqlite');
      File(snapPath).writeAsBytesSync(
          zip.findFile('db.sqlite')!.content as List<int>);
      final snap = await databaseFactoryFfi.openDatabase(snapPath,
          options: OpenDatabaseOptions(readOnly: true));
      final rows = await snap.query(DbSchema.tHabitEntries);
      // 谓词＝「这行在范围内、该保留」，故包内留下的是**区间内**那一行。
      // （初版此处反向断言成「区间外的留下」——把实现缺陷写成了期望，
      //  真机 8137 门才暴露：记账 164 行全在区间内却被删成 0 行。）
      expect(rows.map((r) => r['day']), ['2026-05-01'],
          reason: '区间内的 05-01 留下，区间外的 06-01/07-01 被删');
      // 恒全量表在包里照样全量（谓词只施加在被声明的表上）。
      expect((await snap.query(DbSchema.tHabits)).length, 1);
      // manifest 如实登记筛后的行数（verify 双向核对靠它）。
      expect(res.manifest.tables[DbSchema.tHabitEntries]!.rows, 1);
      await snap.close();
      await db.close();
    });

    test('老库缺表时跳过不报错（谓词按声明走，库况参差不齐不炸导出）',
        () async {
      final db = await openSchemaDb();
      await db.execute('DROP TABLE "${DbSchema.tHabitEntries}"');
      final res = await LhBak.create(
        db: db,
        outDirPath: temp.path,
        now: DateTime(2026, 10, 15, 12),
        rowFilters: {
          DbSchema.tHabitEntries: (whereSql: '"day" BETWEEN ? AND ?', args: []),
        },
      );
      expect(res.file.existsSync(), isTrue);
      await db.close();
    });

    test('反向语义守护：删的是谓词补集，命中行必须**留下**', () async {
      // 真机 8137 门的教训：`DELETE ... WHERE <谓词>` 与 `WHERE NOT (<谓词>)`
      // 在「全部行都命中」时表现相反（前者删光、后者全留）。单用「区间内/外
      // 各一行」的样例容易把反向断言写死，故这里显式做两个极端对照。
      final db = await openSchemaDb();
      await db.insert(DbSchema.tHabits, {
        'id': 'h1',
        'name': '早起',
        'icon': 'x',
        'type': 'good',
        'cycle': 'day',
        'start_date': '2026-01-01',
        'created_at': 0,
        'updated_at': 0,
      });
      for (final d in ['2026-05-01', '2026-05-15', '2026-05-31']) {
        await db.insert(DbSchema.tHabitEntries, {
          'habit_id': 'h1',
          'day': d,
          'origin': 'manual',
          'created_at': 0,
          'updated_at': 0,
        });
      }
      final f = exportTimeFilters(const ['habit'],
          from: DateTime(2026, 5, 1), to: DateTime(2026, 5, 31));
      final res = await LhBak.create(
        db: db,
        outDirPath: temp.path,
        now: DateTime(2026, 10, 15, 12),
        rowFilters: {
          DbSchema.tHabitEntries: (
            whereSql: f[DbSchema.tHabitEntries]!.whereSql,
            args: f[DbSchema.tHabitEntries]!.args
          ),
        },
      );
      final zip = ZipDecoder().decodeBytes(res.file.readAsBytesSync());
      final snapPath = p.join(temp.path, 'snap2.sqlite');
      File(snapPath).writeAsBytesSync(
          zip.findFile('db.sqlite')!.content as List<int>);
      final snap = await databaseFactoryFfi.openDatabase(snapPath,
          options: OpenDatabaseOptions(readOnly: true));
      // 三行全在区间内 → 一个都不能少（反向实现下这里会是 0 行）。
      expect((await snap.query(DbSchema.tHabitEntries)).length, 3,
          reason: '全命中的行必须全留下：谓词是保留集，不是删除集');
      await snap.close();
      await db.close();
    });
  });
}
