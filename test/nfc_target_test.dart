import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/nfc/domain/nfc_card.dart';
import 'package:lifeharness/shared/linkage/nfc_mounts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// NFC 卡片批2 · 目标解析与失效判定（工单 §1 受影响测试清单第三件）。
///
/// 覆盖：
/// · 四类目标解析（nav 动作 / timer_cat / read_book / habit·care 二级）；
/// · 目标已删走失效分支（C24/F2-8）；
/// · 同名分类按 **catId** 区分（B23：不按名字判）；
/// · 书软删（进回收站）＝失效（B24 反例：仅 `deleted_at IS NULL` 才算有效）。
///
/// ⚠ 管理屏「● 计时中」的同源判据（`_runningOf`）由页面承担，本文件钉**数据层**
/// 的解析与失效口径——那是触发链「要不要执行」的唯一依据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSchema.tCategories} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER, name TEXT NOT NULL, color TEXT, tag TEXT,
        sort INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSchema.tBooks} (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL DEFAULT '佚名',
        deleted_at INTEGER
      )
    ''');
  });

  tearDown(() async => db.close());

  NfcCard card({
    String id = 'aBcD1234efGh',
    String targetKind = 'nav',
    String? targetRef = 'journal',
    String? targetSub,
  }) =>
      NfcCard(
        id: id,
        name: '卡',
        targetKind: targetKind,
        targetRef: targetRef,
        targetSub: targetSub,
        createdAt: 0,
      );

  group('nav 类目标解析（动作表唯一来源）', () {
    test('动作在表内 → alive，名字＝动作名', () async {
      final m = await nfcTargetStates([card(targetRef: 'journal')], db);
      expect(m['aBcD1234efGh']!.alive, isTrue);
      expect(m['aBcD1234efGh']!.name, '写日记');
    });

    test('动作不在表（退役）→ 失效', () async {
      final m = await nfcTargetStates([card(targetRef: '不存在的动作')], db);
      expect(m['aBcD1234efGh']!.alive, isFalse);
    });
  });

  group('timer_cat 类（按 catId 区分·B23）', () {
    test('分类在册 → alive，名字＝分类名', () async {
      await db.insert(DbSchema.tCategories, {'name': '学习', 'sort': 0});
      final m = await nfcTargetStates([card(targetKind: 'timer_cat', targetRef: '1')], db);
      expect(m['aBcD1234efGh']!.alive, isTrue);
      expect(m['aBcD1234efGh']!.name, '学习');
    });

    test('同名分类按 id 区分：绑 1 号但 1 号已删、2 号同名 → 失效', () async {
      // 只存在 2 号「学习」；卡绑的是 1 号（不存在）。
      await db.insert(DbSchema.tCategories, {'id': 2, 'name': '学习', 'sort': 0});
      final m = await nfcTargetStates([card(targetKind: 'timer_cat', targetRef: '1')], db);
      expect(m['aBcD1234efGh']!.alive, isFalse, reason: 'B23：按 id 判，不按名字');
    });

    test('分类已删 → 失效（C24）', () async {
      final m = await nfcTargetStates([card(targetKind: 'timer_cat', targetRef: '99')], db);
      expect(m['aBcD1234efGh']!.alive, isFalse);
    });
  });

  group('read_book 类（软删＝失效·B24）', () {
    test('书在册 → alive', () async {
      await db.insert(DbSchema.tBooks, {'id': 'bk1', 'title': '活着'});
      final m = await nfcTargetStates([card(targetKind: 'read_book', targetRef: 'bk1')], db);
      expect(m['aBcD1234efGh']!.alive, isTrue);
      expect(m['aBcD1234efGh']!.name, '活着');
    });

    test('书软删（进回收站）→ 失效', () async {
      await db.insert(DbSchema.tBooks, {'id': 'bk1', 'title': '活着', 'deleted_at': 1});
      final m = await nfcTargetStates([card(targetKind: 'read_book', targetRef: 'bk1')], db);
      expect(m['aBcD1234efGh']!.alive, isFalse, reason: 'B24：deleted_at 非空＝进回收站＝失效');
    });

    test('书完全不存在 → 失效', () async {
      final m = await nfcTargetStates([card(targetKind: 'read_book', targetRef: 'bkX')], db);
      expect(m['aBcD1234efGh']!.alive, isFalse);
    });
  });

  group('存在性判据（toggle 前的最后一道闸 · 与解析同源）', () {
    test('nfcCategoryExists：有／无', () async {
      await db.insert(DbSchema.tCategories, {'name': '学习', 'sort': 0});
      expect(await nfcCategoryExists(1, db), isTrue);
      expect(await nfcCategoryExists(2, db), isFalse);
    });

    test('nfcBookExists：在册 true / 软删 false / 不存在 false', () async {
      await db.insert(DbSchema.tBooks, {'id': 'bk1', 'title': 'A'});
      await db.insert(DbSchema.tBooks, {'id': 'bk2', 'title': 'B', 'deleted_at': 1});
      expect(await nfcBookExists('bk1', db), isTrue);
      expect(await nfcBookExists('bk2', db), isFalse);
      expect(await nfcBookExists('bk3', db), isFalse);
    });
  });

  group('二级目标参数拆解（habit / care）', () {
    test('呵护宝宝 sub 拆解：合法 / 非法', () {
      expect(nfcCareSubParse('3/sleep'), (3, 'sleep'));
      expect(nfcCareSubParse('bad'), isNull);
      expect(nfcCareSubParse('/sleep'), isNull);
      expect(nfcCareSubParse('3/'), isNull);
      expect(nfcCareSubParse(null), isNull);
    });

    test('打卡目标判定：isHabitTarget / isCareTarget 只认 nav 大类', () {
      expect(card(targetKind: 'nav', targetRef: kNfcRefHabit).isHabitTarget, isTrue);
      expect(card(targetKind: 'nav', targetRef: kNfcRefCare).isCareTarget, isTrue);
      expect(card(targetKind: 'timer_cat', targetRef: 'habit').isHabitTarget, isFalse);
    });
  });

  group('toggle 判据三分支（C19 同一次贴卡反向操作 · 工单 §5）', () {
    test('时间卡：目标正在计时 ⇒ 结束', () {
      expect(
        nfcTimerToggleAction(runningCatId: 3, targetCatId: 3),
        NfcToggleAction.end,
      );
    });

    test('时间卡：跑的是别的分类 ⇒ 开始（startTiming 自带收口·B20）', () {
      expect(
        nfcTimerToggleAction(runningCatId: 9, targetCatId: 3),
        NfcToggleAction.start,
      );
    });

    test('时间卡：无计时中 ⇒ 开始', () {
      expect(
        nfcTimerToggleAction(runningCatId: null, targetCatId: 3),
        NfcToggleAction.start,
      );
    });

    test('阅读卡：目标正在读 ⇒ 结束', () {
      expect(
        nfcReadToggleAction(runningBookId: 'bk1', targetBookId: 'bk1'),
        NfcToggleAction.end,
      );
    });

    test('阅读卡：读的是别的书 ⇒ 开始', () {
      expect(
        nfcReadToggleAction(runningBookId: 'bk2', targetBookId: 'bk1'),
        NfcToggleAction.start,
      );
    });

    test('阅读卡：无在跑会话 ⇒ 开始', () {
      expect(
        nfcReadToggleAction(runningBookId: null, targetBookId: 'bk1'),
        NfcToggleAction.start,
      );
    });

    test('同 id 同名不同实例：时间判据按 id 相等（非名字）', () {
      // 同名分类另一个 id（9）在跑时，贴目标 3 ⇒ 开始（不误结束别人的计时）。
      expect(
        nfcTimerToggleAction(runningCatId: 9, targetCatId: 3),
        NfcToggleAction.start,
      );
    });
  });
}
