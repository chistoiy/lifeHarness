import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/db_overview.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/shared/linkage/export_units.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// NFC 卡片批1 · **备份三处登记**守护（工单 §2 末段 · 冻结档 C8-V3 / §6.1 · 变异刀3 靶点）。
///
/// 三处缺一即视为「卡片没进备份包」，而 C8 的全部意义正是
/// 「换机后同一张物理标签仍可用」——漏任何一处，这条价值直接归零：
/// ① 不加 `excludeTables`：全量实表差集自然收；
/// ② **`export_units.dart` 登记 NFC 单元**：不登记则**子集备份不导出该表**
///    （子集走 `exportTablesForModules` 差集法，未登记＝归属不明＝不收），
///    而子集备份是 V1.66 批2 刚拍板的主推路径；
/// ③ **`db_overview.dart` 补中文标签**：不登记则概览屏不显示、恢复报告无中文名。
void main() {
  group('NFC 备份三处登记（C8-V3）', () {
    test('① nfc_cards 不在任何恒排除名单内（全量备份自然收）', () {
      expect(kRegenerableExcluded, isNot(contains(DbSchema.tNfcCards)),
          reason: '把用户自己建的卡片当「可再生派生表」排除 ⇒ 备份丢卡片数据');
    });

    test('② export_units 登记 NFC 单元且含 nfc_cards（子集备份靠这条）', () {
      final unit = exportUnitById('nfc');
      expect(unit, isNotNull, reason: 'NFC 单元未登记 ⇒ 子集备份走差集法时不收本表');
      expect(unit!.label, 'NFC 卡片');
      expect(unit.tables, contains(DbSchema.tNfcCards));
    });

    test('② 子集导出确实收 nfc_cards（差集法的实际读数，不只看注册表）', () {
      final tables = exportTablesForModules(<String>['nfc']);
      expect(tables, contains(DbSchema.tNfcCards),
          reason: 'exportTablesForModules(["nfc"]) 收不到本表 ⇒ '
              '用户在导出面板只勾 NFC 时包内无卡片，换机后标签失效');
    });

    test('② 与其他单元无表重叠（一张表只属一个单元，否则子集语义分叉）', () {
      final ids = kExportUnits.map((u) => u.id).toList();
      expect(ids.toSet().length, ids.length, reason: '单元 id 有重复');
      final seen = <String, String>{};
      for (final u in kExportUnits) {
        for (final t in u.tables) {
          final prev = seen[t];
          expect(prev, isNull,
              reason: '表 $t 同时属 $prev 与 ${u.id} ⇒ 子集差集口径会互相吞表');
          seen[t] = u.id;
        }
      }
    });

    test('③ db_overview 有该表中文标签（恢复报告不出现裸英文表名）', () {
      final meta = dbTableLabels[DbSchema.tNfcCards];
      expect(meta, isNotNull, reason: '概览屏不显示该表、恢复报告无中文标签');
      expect(meta!.label, 'NFC 卡片');
      expect(meta.module, 'NFC');
    });

    test('② NFC 单元无时间筛语义（面板须明说「不生效」而非静默忽略）', () {
      final unit = exportUnitById('nfc')!;
      expect(unit.timeFilterable, isFalse,
          reason: '卡片表不是流水；若误设 timeRoots，导出面板会显示一个语义不明的筛选项');
    });

    test('③ 批1b 三列随本表进备份包（desc_text/color/target_sub 缺一＝换机后卡片变样）',
        () async {
      // 备份的 db 腿是整表读（`SELECT *` 口径），故新列是否入包＝表里有没有这三列。
      // 这条断言钉的是「加列批必须同步到备份面」：漏了列，换机恢复后卡片没有
      // 描述/颜色/二级参数，打卡卡与呵护宝宝卡会当场变「未选条目」。
      TestWidgetsFlutterBinding.ensureInitialized();
      databaseFactory = databaseFactoryFfiNoIsolate;
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      await db.insert(DbSchema.tNfcCards, {
        'id': 'backup000001',
        'name': '玄关卡',
        'target_kind': 'nav',
        'target_ref': 'care',
        'target_sub': '1/nurse',
        'created_at': 1,
        'use_count': 0,
        'desc_text': '出门喂奶',
        'color': 2,
      });
      final row = (await db.query(DbSchema.tNfcCards)).first;
      expect(row.keys, containsAll(<String>['desc_text', 'color', 'target_sub']));
      expect(row['desc_text'], '出门喂奶');
      expect(row['color'], 2);
      expect(row['target_sub'], '1/nurse');
      await db.close();
    });
  });
}