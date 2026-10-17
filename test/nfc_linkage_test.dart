import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/nfc.dart' show NfcTargetKind;
import 'package:lifeharness/features/nfc/domain/nfc_card.dart';
import 'package:lifeharness/shared/linkage/nfc_mounts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// NFC 卡片批1／批1b · 跨模块出口守护（工单 §2 F1-4 · §3 批1b 四口 · 冻结档 §6.1 守 R1）。
///
/// `features/nfc/**` **禁止 import** `features/calendar|read|habit|care/**`；
/// 目标选择器的数据**一律经** `shared/linkage/nfc_mounts.dart`。
/// 反向也禁（守护 R1 的反向条文由 `architecture_test` 覆盖，本文件补语义侧）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('nfc_mounts 读取转发口（批1 两个；两个 toggle 口属批2）', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // 只建本测试要读的两张表：分类（core 域）＋ 书目（read 域）。
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbSchema.tCategories} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          parent_id INTEGER,
          name TEXT NOT NULL,
          color TEXT,
          tag TEXT,
          sort INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbSchema.tBooks} (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          author TEXT NOT NULL DEFAULT '佚名',
          deleted_at INTEGER
        )
      ''');
    });

    tearDown(() async => db.close());

    test('nfcCategoryOptions 返回分类且带父级路径（B23：显示「工作 › 开会」）',
        () async {
      await db.insert(DbSchema.tCategories,
          {'name': '工作', 'sort': 0});
      await db.insert(DbSchema.tCategories,
          {'name': '开会', 'parent_id': 1, 'sort': 0});
      await db.insert(DbSchema.tCategories,
          {'name': '学习', 'sort': 1});

      final cats = await nfcCategoryOptions(db);
      expect(cats.length, 3);
      final primary = cats.firstWhere((c) => c.name == '工作');
      expect(primary.parentId, isNull);
      expect(primary.path, '工作', reason: '一级分类无父级前缀');

      final child = cats.firstWhere((c) => c.name == '开会');
      expect(child.parentId, 1);
      expect(child.path, '工作 › 开会', reason: '多级分类须显父级路径，否则同名分类无法分辨');
    });

    test('同名分类按 id 区分（B23：卡片只存 catId 不存名）', () async {
      await db.insert(DbSchema.tCategories, {'name': '运动', 'sort': 0});
      await db.insert(DbSchema.tCategories, {'name': '运动', 'sort': 1});
      final cats = await nfcCategoryOptions(db);
      final sameName = cats.where((c) => c.name == '运动').toList();
      expect(sameName.length, 2);
      expect(sameName[0].id, isNot(sameName[1].id),
          reason: '同名分类必须靠 id 区分，否则两张卡会绑到同一处');
    });

    test('nfcBookOptions 只返回在册书（B24：移出书架视图但仍在库＝有效）', () async {
      await db.insert(DbSchema.tBooks, {'id': 'bk1', 'title': '活着', 'author': '余华'});
      await db.insert(DbSchema.tBooks,
          {'id': 'bk2', 'title': '已删', 'author': 'x', 'deleted_at': 1700000000000});

      final books = await nfcBookOptions(db);
      expect(books.length, 1);
      expect(books.first.id, 'bk1');
      expect(books.first.title, '活着');
      expect(await nfcBookExists('bk1', db), isTrue);
      expect(await nfcBookExists('bk2', db), isFalse, reason: '真删的书＝目标已失效');
    });

    test('书目标题为空回落「未命名」（不留空白 chip）', () async {
      await db.insert(DbSchema.tBooks, {'id': 'bk3', 'title': '   ', 'author': ''});
      final books = await nfcBookOptions(db);
      expect(books.first.title, '未命名');
    });

    test('分类已删即失效（C24/B9：贴卡时给「已经不在了」而不是崩）', () async {
      await db.insert(DbSchema.tCategories, {'name': '临时', 'sort': 0});
      expect(await nfcCategoryExists(1, db), isTrue);
      await db.delete(DbSchema.tCategories, where: 'id = ?', whereArgs: [1]);
      expect(await nfcCategoryExists(1, db), isFalse);
    });
  });

  group('批1b 出口：分类两级结构（§3-1）', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // 全量 DDL：分类带种子（工作=1／学习=2…，子级 11/12 挂 1、13 挂 8）。
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
    });

    tearDown(() async => db.close());

    test('一级在前、子级挂在父级下（父 id / 是否子级 / 同级顺序都可辨）', () async {
      final tree = await nfcCategoryTree(db);
      final work = tree.firstWhere((g) => g.id == 1);
      expect(work.name, '工作');
      expect(work.children.map((c) => c.name), containsAll(<String>['开会', '不在工位']),
          reason: '子级必须挂在父级下，否则两级选择器点了一级没有联动');
      // 子级不出现在一级列表里（否则同一项会出现两次、选区语义分叉）。
      expect(tree.any((g) => g.id == 11), isFalse);
      for (final g in tree) {
        for (final c in g.children) {
          expect(c.parentId, g.id);
        }
      }
    });

    test('父级不存在的脏数据按一级收（不许从选择器里凭空消失）', () async {
      await db.insert(DbSchema.tCategories,
          {'name': '孤儿', 'parent_id': 99999, 'sort': 0});
      final tree = await nfcCategoryTree(db);
      expect(tree.any((g) => g.name == '孤儿'), isTrue);
    });
  });

  group('批1b 出口：习惯条目（§3-2 · 走 habit_mounts，不直连习惯表）', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      Future<void> add(String id, String name, {int? deletedAt}) => db.insert(
            DbSchema.tHabits,
            {
              'id': id,
              'name': name,
              'icon': '🏃',
              'type': 'pos',
              'cycle': 'day',
              'start_date': '2026-01-01',
              'created_at': 1,
              'updated_at': 1,
              'deleted_at': deletedAt,
            },
          );
      await add('h1', '🏃 晨间跑步 30min');
      await add('h2', '💧 喝水');
      await add('h3', '🗑 已删习惯', deletedAt: 1700000000000);
    });

    tearDown(() async => db.close());

    test('名字剥离装饰符后再给 UI（NFC 模块零 emoji 硬要求）', () async {
      final opts = await nfcHabitOptions(db);
      expect(opts.map((o) => o.name), containsAll(<String>['晨间跑步 30min', '喝水']));
      for (final o in opts) {
        expect(nfcStripEmoji(o.name), o.name, reason: '出口不许带装饰符');
      }
    });

    test('已删除习惯不进选择器（归档≠删除，归档仍可选）', () async {
      final opts = await nfcHabitOptions(db);
      expect(opts.any((o) => o.name.contains('已删习惯')), isFalse);
      await db.update(DbSchema.tHabits, {'archived_at': 1700000000000},
          where: 'id = ?', whereArgs: ['h1']);
      final after = await nfcHabitOptions(db);
      expect(after.any((o) => o.id == 'h1'), isTrue, reason: '归档只是收起，不是删除');
    });

    test('失效判定按剥离后的名字比对（写入口径与判据同源）', () async {
      expect(await nfcHabitExists('晨间跑步 30min', db), isTrue);
      expect(await nfcHabitExists('🏃 晨间跑步 30min', db), isTrue,
          reason: '卡里存的是剥离后的名字，判据也要剥一遍才比得上');
      expect(await nfcHabitExists('已删习惯', db), isFalse);
      expect(await nfcHabitExists('不存在的习惯', db), isFalse);
      expect(await nfcHabitExists('', db), isFalse);
      expect(await nfcHabitExists(null, db), isFalse);
    });
  });

  group('批1b 出口：母婴（§3-3 · 新建 maternity_mounts）', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      for (final (id, name) in [(1, '小满'), (2, '团团')]) {
        await db.insert(DbSchema.tCareBabies, {
          'id': id,
          'name': name,
          'sex': '女',
          'birth': '2026-01-01',
          'color': 'sky',
          'avatar': '🍼',
          'created_at': 1,
          'updated_at': 1,
        });
      }
    });

    tearDown(() async => db.close());

    test('宝宝档案出口（id＋名，按 id 升序）', () async {
      final babies = await nfcBabyOptions(db);
      expect(babies.map((b) => b.name), <String>['小满', '团团']);
      expect(babies.first.id, 1);
    });

    test('记录类型出口＝内置 12 类且不含 custom（占位定义不是可绑类型）', () {
      final kinds = nfcCareKindOptions();
      expect(kinds.length, 12);
      expect(kinds.any((k) => k.id == 'custom'), isFalse,
          reason: 'custom 是「自定义」占位，不是一条可绑定的固定记录类型');
      expect(kinds.map((k) => k.name), containsAll(<String>['睡眠', '换尿布', '母乳亲喂']));
    });

    test('宝宝＋记录类型都还在才算有效（C24：任缺即失效）', () async {
      expect(await nfcBabyCareExists('1/nurse', db), isTrue);
      expect(await nfcBabyCareExists('1/不存在的类型', db), isFalse);
      expect(await nfcBabyCareExists('9/nurse', db), isFalse);
      expect(await nfcBabyCareExists('坏格式', db), isFalse);
      expect(await nfcBabyCareExists(null, db), isFalse);
      // 删档＝母婴侧级联真删 ⇒ 绑该宝宝的卡必须判失效。
      await db.delete(DbSchema.tCareBabies, where: 'id = ?', whereArgs: [1]);
      expect(await nfcBabyCareExists('1/nurse', db), isFalse);
    });
  });

  group('批1b 出口：批量目标解析（§5 列表左节点与目标摘要同源）', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      await db.insert(DbSchema.tBooks, {
        'id': 'bk1',
        'title': '活着',
        'author': '余华',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert(DbSchema.tBooks, {
        'id': 'bk2',
        'title': '已删',
        'author': 'x',
        'created_at': 1,
        'updated_at': 1,
        'deleted_at': 1700000000000,
      });
      await db.insert(DbSchema.tHabits, {
        'id': 'h1',
        'name': '🏃 晨间跑步',
        'icon': '🏃',
        'type': 'pos',
        'cycle': 'day',
        'start_date': '2026-01-01',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert(DbSchema.tCareBabies, {
        'id': 1,
        'name': '小满',
        'sex': '女',
        'birth': '2026-01-01',
        'color': 'sky',
        'avatar': '🍼',
        'created_at': 1,
        'updated_at': 1,
      });
    });

    tearDown(() async => db.close());

    NfcCard mk(String id, String kind, String? ref, {String? sub}) => NfcCard(
          id: id,
          name: '卡$id',
          targetKind: kind,
          targetRef: ref,
          targetSub: sub,
          createdAt: 0,
        );

    test('五类目标一次解析：名字给对、有效性判对（含已失效分支）', () async {
      final cards = [
        mk('c00000000001', 'timer_cat', '1'), // 种子分类「工作」
        mk('c00000000002', 'read_book', 'bk1'),
        mk('c00000000003', 'read_book', 'bk2'), // 软删的书 ⇒ 失效
        mk('c00000000004', 'nav', 'habit', sub: '晨间跑步'),
        mk('c00000000005', 'nav', 'habit', sub: '不存在的习惯'), // ⇒ 失效
        mk('c00000000006', 'nav', 'care', sub: '1/nurse'),
        mk('c00000000007', 'nav', 'care', sub: '9/nurse'), // 宝宝不存在 ⇒ 失效
        mk('c00000000008', 'nav', 'ledger'),
        mk('c00000000009', 'nav', '已退役动作'), // ⇒ 失效
        mk('c00000000010', 'timer_cat', '99999'), // 分类不存在 ⇒ 失效
      ];
      final st = await nfcTargetStates(cards, db);
      expect(st.length, 10);

      expect(st['c00000000001']!.alive, isTrue);
      expect(st['c00000000001']!.name, '工作');
      expect(nfcTargetLabelOf(cards[0], targetName: st['c00000000001']!.name),
          '计时 · 工作');

      expect(st['c00000000002']!.name, '活着');
      expect(st['c00000000003']!.alive, isFalse, reason: '软删的书＝目标已失效（B24）');
      expect(st['c00000000004']!.alive, isTrue);
      expect(nfcTargetLabelOf(cards[3], targetName: st['c00000000004']!.name),
          '打卡 · 晨间跑步');
      expect(st['c00000000005']!.alive, isFalse);
      expect(st['c00000000006']!.alive, isTrue);
      expect(st['c00000000006']!.name, '小满 · 母乳亲喂');
      expect(nfcTargetLabelOf(cards[5], targetName: st['c00000000006']!.name),
          '呵护宝宝 · 小满 · 母乳亲喂');
      expect(st['c00000000007']!.alive, isFalse);
      expect(st['c00000000008']!.alive, isTrue);
      expect(st['c00000000009']!.alive, isFalse);
      expect(st['c00000000010']!.alive, isFalse);
    });

    test('空列表不查库（列表为空时不该因为读目标把屏打红）', () async {
      final st = await nfcTargetStates(const <NfcCard>[], db);
      expect(st, isEmpty);
    });
  });

  group('批3c · 贴卡执行前是否先退界面（消除热启动闪现）', () {
    test('计时卡开始 ⇒ 先退（只改数据＋起胶囊）', () {
      expect(
        nfcHidesBeforeRunPure(
          targetKind: NfcTargetKind.timerCat,
          targetRef: '3',
          targetSub: null,
          runningSameTarget: false,
        ),
        isTrue,
      );
    });

    test('计时卡结束 ⇒ 不退（留前台看「已结束·N 分钟」toast）', () {
      expect(
        nfcHidesBeforeRunPure(
          targetKind: NfcTargetKind.timerCat,
          targetRef: '3',
          targetSub: null,
          runningSameTarget: true,
        ),
        isFalse,
      );
    });

    test('阅读卡开始 ⇒ 先退', () {
      expect(
        nfcHidesBeforeRunPure(
          targetKind: NfcTargetKind.readBook,
          targetRef: 'b1',
          targetSub: null,
          runningSameTarget: false,
        ),
        isTrue,
      );
    });

    test('阅读卡结束 ⇒ 不退（要弹「记进度」层）', () {
      expect(
        nfcHidesBeforeRunPure(
          targetKind: NfcTargetKind.readBook,
          targetRef: 'b1',
          targetSub: null,
          runningSameTarget: true,
        ),
        isFalse,
      );
    });

    test('打卡卡（已绑具体习惯）⇒ 先退', () {
      expect(
        nfcHidesBeforeRunPure(
          targetKind: NfcTargetKind.nav,
          targetRef: kNfcRefHabit,
          targetSub: '晨间跑步',
          runningSameTarget: false,
        ),
        isTrue,
      );
    });

    test('打卡卡（没绑习惯）⇒ 不退（要 toast＋回首页让人补绑）', () {
      expect(
        nfcHidesBeforeRunPure(
          targetKind: NfcTargetKind.nav,
          targetRef: kNfcRefHabit,
          targetSub: '  ',
          runningSameTarget: false,
        ),
        isFalse,
      );
    });

    test('普通 nav.*（记一笔等）⇒ 不退（目的就是打开页面）', () {
      expect(
        nfcHidesBeforeRunPure(
          targetKind: NfcTargetKind.nav,
          targetRef: 'ledger',
          targetSub: null,
          runningSameTarget: false,
        ),
        isFalse,
      );
    });
  });
}