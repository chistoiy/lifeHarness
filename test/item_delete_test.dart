import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/items/data/items_repository.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/shared/trash/trash_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1.61 物品档案删除 · 数据层与回收站第七类（工单 `交棒话术-20261005-物品档案删除批` §E.2）。
///
/// 四条拍板逐条落到断言：① 软删进回收站可恢复 ② **记账流水保留**（删物品不动账）
/// ③ 任意状态可删 ④ 在册口径一处定义（列表/统计/每日成本同源排除）。
/// 独立文件＝全 app 测试拆文件防 isolate 污染（AGENTS 门禁条）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late ItemsRepository items;
  late TrashRepository trash;

  Future<int> addProfile({
    String name = '测试相机',
    double price = 199,
    String status = kItemStatusActive,
    bool billing = true,
    int? sourceTxnId,
  }) =>
      items.addItem(ItemProfile(
        name: name,
        buyDate: '2026-01-01',
        price: price,
        status: status,
        billing: billing,
        source: sourceTxnId == null ? 'manual' : 'ledger',
        sourceTxnId: sourceTxnId,
      ));

  Future<int> addTxn({double amt = 199, String source = 'item', String? linkId}) =>
      db.insert(DbSchema.tLedgerTxns, {
        'kind': 'expense',
        'amt': amt,
        'account_id': 1,
        'date': '2026-01-01',
        'bk': 0,
        'created_at': 1,
        'note': '物品建档：测试相机',
        'source': source,
        'link_id': linkId,
      });

  Future<int> countOf(String table, {String where = '', List<Object?>? args}) async {
    final sql = 'SELECT COUNT(*) AS c FROM $table'
        '${where.isEmpty ? '' : ' WHERE $where'}';
    final r = await db.rawQuery(sql, args);
    return (r.first['c'] as int?) ?? 0;
  }

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    items = ItemsRepository(db);
    trash = TrashRepository(db);
  });
  tearDown(() => db.close());

  test('软删＝出在册、进回收站，副信息与连带读数同源', () async {
    final id = await addProfile();
    expect((await items.loadAll()).items.map((e) => e.name), contains('测试相机'));

    await items.softDeleteItem(id);

    // 在册面：列表/统计/每日成本共用 loadAll，一条谓词全带走。
    final data = await items.loadAll();
    expect(data.items, isEmpty, reason: '软删档案仍在在册读数里＝删了还在计费');
    expect(data.active, isEmpty);

    // 回收站面：行在、标题兜底、副信息带分类/成本池/持有与流水保留，玫红后果有读数。
    final rows = await trash.items();
    final row = rows.singleWhere((r) => r.kind.name == 'item');
    expect(row.rawId, id);
    expect(row.subs.first, contains('成本池'));
    expect(row.subs.first, contains('数码'));
    expect(row.subs.last, '关联流水 0 条保留');
    expect(row.cascadeNotes, contains('连带清 成本时间轴 1 条'),
        reason: '建档自带一条「购入」审计，连带读数不能写 0');
    expect(row.deletedAt, isNotNull);
  });

  test('回收站行的「成本池」＝净值（含二次付费），不是购入价（真机 6071 纠偏）', () async {
    // 真机抓到的缺陷：行上读的是 item_profiles.price，做过 ¥50 二次付费的档案
    // 明明成本池 ¥249，回收站却写「成本池 ¥199」。修＝trashedItems 挂回时间轴
    // 子记录，行上改吃 poolOf（与列表/详情同一个公式，在册口径一处定义）。
    final id = await addProfile(price: 199);
    await items.addExtraPay(id, 50, '维修/配件');
    await items.softDeleteItem(id);

    final row = (await trash.items()).singleWhere((r) => r.kind.name == 'item');
    expect(row.subs.first, contains('成本池 ¥249'),
        reason: '回收站行只读购入价＝把二次付费抹掉了（真机 6071 现象）');
    expect(row.subs.first, isNot(contains('成本池 ¥199')));
    // 后果读数同源：时间轴两条（购入＋二次付费）。
    expect(row.cascadeNotes, contains('成本时间轴 2 条'));
  });

  test('恢复＝清软删标记，状态与计费口径原样回来（不新建条目）', () async {
    final id = await addProfile(status: kItemStatusScrapped, billing: false);
    await items.softDeleteItem(id);
    expect(await items.trashedItems(), hasLength(1));

    await items.restoreItem(id);

    final back = (await items.loadAll()).items.single;
    expect(back.id, id);
    expect(back.deletedAt, isNull);
    // 删除前后是同一份档案：已报废/停计费的，恢复后仍是已报废/停计费。
    expect(back.status, kItemStatusScrapped);
    expect(back.billing, isFalse);
    expect(await items.trashedItems(), isEmpty);
  });

  test('任意状态可删：已报废与已回收转出的档案同样能进回收站（拍板③）', () async {
    final scrapped = await addProfile(name: '旧显示器', status: kItemStatusScrapped, billing: false);
    final recycled = await addProfile(name: '转出的平板', status: kItemStatusRecycleOut, billing: false);

    await items.softDeleteItem(scrapped);
    await items.softDeleteItem(recycled);

    expect((await items.trashedItems()).map((e) => e.id),
        containsAll([scrapped, recycled]));
    expect(await items.loadAll(), isNotNull);
    expect((await items.loadAll()).items, isEmpty);
  });

  test('彻底删除＝清档案与两张子表，**记账流水一行不碰**（拍板②）', () async {
    final txn = await addTxn(linkId: '占位');
    final id = await addProfile(sourceTxnId: txn);
    await db.update(DbSchema.tLedgerTxns, {'link_id': '$id'},
        where: 'id = ?', whereArgs: [txn]);
    await db.insert(DbSchema.tItemUsages,
        {'item_id': id, 'day': '2026-02-01', 'qty': 1.0, 'created_at': 0});
    await items.softDeleteItem(id);

    final txnsBefore = await countOf(DbSchema.tLedgerTxns);
    await items.purgeItem(id);

    expect(await countOf(DbSchema.tItemProfiles, where: 'id = ?', args: [id]), 0);
    expect(await countOf(DbSchema.tItemEvents, where: 'item_id = ?', args: [id]), 0,
        reason: '时间轴随档案清（否则留下指向空档案的孤行）');
    expect(await countOf(DbSchema.tItemUsages, where: 'item_id = ?', args: [id]), 0);
    expect(await countOf(DbSchema.tLedgerTxns), txnsBefore,
        reason: '记账是独立账本：删物品不反向删账（那笔支出仍在账上）');
  });

  test('到期清理按保留期连子表一起清，未到期与在册一律不动', () async {
    final due = await addProfile(name: '到期件');
    final keep = await addProfile(name: '期内件');
    final alive = await addProfile(name: '在册件');
    await items.softDeleteItem(due);
    await items.softDeleteItem(keep);
    final old = DateTime.now()
        .subtract(const Duration(days: 40))
        .millisecondsSinceEpoch;
    await db.update(DbSchema.tItemProfiles, {'deleted_at': old},
        where: 'id = ?', whereArgs: [due]);

    final n = await items.purgeExpiredItems(30);

    expect(n, 1, reason: '只清超过保留期的软删档案（keepDays=30·40 天前那条）');
    expect(await countOf(DbSchema.tItemProfiles, where: 'id = ?', args: [due]), 0);
    expect(await countOf(DbSchema.tItemEvents, where: 'item_id = ?', args: [due]), 0);
    expect(await countOf(DbSchema.tItemProfiles, where: 'id = ?', args: [keep]), 1);
    expect(await countOf(DbSchema.tItemProfiles, where: 'id = ?', args: [alive]), 1);
    // keepDays<=0＝「不清理」档，一律不动。
    expect(await items.purgeExpiredItems(0), 0);
  });

  test('回收站到期清理出口含物品（注册表遍历自动扩到七类）', () async {
    final id = await addProfile();
    await items.softDeleteItem(id);
    await db.update(DbSchema.tItemProfiles, {
      'deleted_at': DateTime.now()
          .subtract(const Duration(days: 90))
          .millisecondsSinceEpoch
    }, where: 'id = ?', whereArgs: [id]);

    final byKind = await trash.purgeExpiredByTable(30);

    expect(byKind.keys, contains('物品'),
        reason: '启动清理按注册表逐类跑，新类登记后不必再改这里');
    expect(byKind['物品'], 1);
  });

  test('copyWith 不得把回收站里的档案洗回在册（习惯模块踩过）', () async {
    const p = ItemProfile(
        name: 'x', buyDate: '2026-01-01', price: 1, deletedAt: 123456);
    expect(p.copyWith(name: 'y').deletedAt, 123456);
    expect(p.isDeleted, isTrue);
  });

  test('迁移 35→36：老库（无列）跑 ALTER 后列与索引都在', () async {
    // 内存库在同进程内是同一份（setUp 已按新 schema 建过表），先拆掉再按老形状造。
    final legacy = db;
    await legacy.execute('DROP TABLE IF EXISTS item_profiles');
    await legacy.execute(
        'CREATE TABLE item_profiles (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
    for (final sql in DbSchema.migrations[35]!) {
      await legacy.execute(sql);
    }
    final cols = (await legacy.rawQuery('PRAGMA table_info(item_profiles)'))
        .map((r) => r['name'] as String)
        .toList();
    expect(cols, contains('deleted_at'));
    final idx = (await legacy.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='item_profiles'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(idx, contains('idx_item_profiles_deleted'));
    // 断言的是「版本已抬过本段目标 35」，不钉死具体号（36 起后续批次还会继续抬，
    // 写死 36 的那条在健康批与影音游批抬到 37/38 时必然假红）。
    expect(DbSchema.version, greaterThan(35),
        reason: '加了迁移段必须抬目标版本，否则老库不会执行');
  });

  test('档案在回收站期间，其来源流水仍不可再次升级建档（防一水流两档）', () async {
    final txn = await addTxn(source: 'manual', amt: 8888);
    final id = await addProfile(sourceTxnId: txn);
    await items.softDeleteItem(id);

    final candidates = await items.upgradeCandidates(limit: 50);

    expect(candidates.map((c) => c.txnId), isNot(contains(txn)),
        reason: '「已产过档」这个事实不因删档而消失；按在册过滤会让同一笔流水再建一份档');
  });
}
