import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/nfc.dart';
import 'package:lifeharness/features/nfc/data/nfc_repo.dart';
import 'package:lifeharness/features/nfc/domain/nfc_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// NFC 卡片批1／批1b · 数据层守护（工单 §2 F1-1 / F1-2 / C31 / C33 / B18 / B28；
/// 批1b §2 三列与 v48→v49 迁移）。
///
/// 6109 实锤的铁律：迁移批必跑 S6（version=migrations 最高键+1）＋
/// S7（真升级路径，禁只测 onCreate——测试库走 onCreate 全量 DDL，升级路径平时零覆盖）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('NFC 迁移与 schema（v49 基线）', () {
    test('S6 version 常量 = migrations 最高键 + 1（漏改 version＝升级静默失效）',
        () {
      final maxKey = DbSchema.migrations.keys.reduce((a, b) => a > b ? a : b);
      expect(DbSchema.version, maxKey + 1,
          reason: 'migrations 已定义到 $maxKey → ${maxKey + 1}，'
              '但 version=${DbSchema.version} 没跟上——真机 user_version 已到 '
              '${maxKey + 1} 以上时该迁移永不执行（6109 日记全断同源）');
    });

    test('S7 真升级 v47 库 → v49：nfc_cards 建出且十三列齐全（批1b 三列含内）',
        () async {
      const name = 'nfctest_upgrade_v47to49.db';
      await databaseFactory.deleteDatabase(name);
      final old = await databaseFactory.openDatabase(name);
      await old.execute('CREATE TABLE journal_entries (id INTEGER PRIMARY KEY)');
      await old.execute('PRAGMA user_version = 47');
      await old.close();

      final upgraded = await databaseFactory.openDatabase(name,
          options: OpenDatabaseOptions(
            version: DbSchema.version,
            onUpgrade: (d, from, to) async {
              for (var v = from; v < to; v++) {
                for (final sql in DbSchema.migrations[v] ?? const <String>[]) {
                  await d.execute(sql);
                }
              }
            },
          ));
      final tables = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      expect(tables.map((r) => r['name']), contains(DbSchema.tNfcCards));

      final cols = await upgraded
          .rawQuery('PRAGMA table_info(${DbSchema.tNfcCards})');
      // 十列（批1）＋ 批1b 三列逐条点名。
      expect(cols.map((c) => c['name']),
          containsAll(<String>[
            'id',
            'name',
            'target_kind',
            'target_ref',
            'tag_key',
            'tag_kind',
            'created_at',
            'last_used_at',
            'use_count',
            'written_at',
            'desc_text',
            'color',
            'target_sub',
          ]));
      await upgraded.close();
    });

    test('真升级 v48 库 → v49：批1b 三列 ALTER 补上（批1 已装机的库走这条）',
        () async {
      const name = 'nfctest_upgrade_v48to49.db';
      await databaseFactory.deleteDatabase(name);
      final old = await databaseFactory.openDatabase(name);
      // 批1 的库：v48 口径的 nfc_cards（无三新列）。
      for (final sql in DbSchema.migrations[47]!) {
        await old.execute(sql);
      }
      await old.execute('PRAGMA user_version = 48');
      await old.close();

      final upgraded = await databaseFactory.openDatabase(name,
          options: OpenDatabaseOptions(
            version: DbSchema.version,
            onUpgrade: (d, from, to) async {
              for (var v = from; v < to; v++) {
                for (final sql in DbSchema.migrations[v] ?? const <String>[]) {
                  await d.execute(sql);
                }
              }
            },
          ));
      final cols = (await upgraded
              .rawQuery('PRAGMA table_info(${DbSchema.tNfcCards})'))
          .map((c) => c['name'])
          .toList();
      expect(cols, containsAll(<String>['desc_text', 'color', 'target_sub']),
          reason: '批1 已装机的库升上来若缺这三列，管理屏读写当场全挂');
      // 老卡三列取默认 NULL＝无色无描述无二级参数（升级不丢既有语义）。
      await upgraded.insert(DbSchema.tNfcCards, {
        'id': 'oldcard00001',
        'name': '旧卡',
        'target_kind': 'nav',
        'target_ref': 'ledger',
        'created_at': 1,
        'use_count': 0,
      });
      final row = (await upgraded.query(DbSchema.tNfcCards)).first;
      expect(row['desc_text'], isNull);
      expect(row['color'], isNull);
      expect(row['target_sub'], isNull);
      await upgraded.close();
    });

    test('老库 44→49 直升不撞 duplicate column（老口径建表 + 新列 ALTER 的拆分闸）',
        () async {
      // v45/v47 实锤教训：若 mig[47] 的建表语句里带上批1b 三列，
      // 老库直升会先 CREATE（已含三列）再 ALTER ADD（同列）⇒ duplicate column 崩。
      // 本刀直接按老库路径跑：mig[47] → mig[48]，一步不许抛。
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.migrations[47]!) {
        await db.execute(sql);
      }
      for (final sql in DbSchema.migrations[48]!) {
        await db.execute(sql);
      }
      final cols = (await db.rawQuery('PRAGMA table_info(${DbSchema.tNfcCards})'))
          .map((c) => c['name'])
          .toList();
      expect(cols, containsAll(<String>['desc_text', 'color', 'target_sub']));
      expect(cols.toSet().length, cols.length, reason: '出现重名列＝列被加了两次');
      await db.close();
    });

    test('onCreate 全量 DDL 同样建出 nfc_cards（双写 DDL 闸）', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      expect(tables.map((r) => r['name']), contains(DbSchema.tNfcCards));
      final cols = (await db.rawQuery('PRAGMA table_info(${DbSchema.tNfcCards})'))
          .map((c) => c['name'])
          .toList();
      // 新装库与升级库的列集必须一致（少一列＝两条路径行为分叉）。
      expect(cols, containsAll(<String>['desc_text', 'color', 'target_sub']));
      await db.close();
    });

    test('id 是主键（变异刀1 靶点：降级为普通列 ⇒ UPSERT 断言红）', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      final cols = await db.rawQuery('PRAGMA table_info(${DbSchema.tNfcCards})');
      final idCol = cols.firstWhere((c) => c['name'] == 'id');
      expect(idCol['pk'], 1, reason: 'id 必须是 PRIMARY KEY（UPSERT 锚点）');
      await db.close();
    });

    test('tag_key 有 UNIQUE 约束（B28 撞车 UPSERT 的前提）', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      // 直接插两行同 tag_key ⇒ 第二行必须被数据库拒（不是应用层自觉）。
      final repo = NfcRepo(db);
      await repo.create(
          name: 'A', targetKind: NfcTargetKind.nav, tagKey: 'ndef:x');
      expect(
        () => repo.create(
            name: 'B', targetKind: NfcTargetKind.nav, tagKey: 'ndef:x'),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('目标类型枚举四值与冻结档 §2.0 一致', () {
      expect(NfcTargetKind.all, <String>['nav', 'timer_cat', 'read_book', 'timer_duration']);
      expect(isKnownNfcTargetKind('nav'), isTrue);
      expect(isKnownNfcTargetKind('timer_cat'), isTrue);
      expect(isKnownNfcTargetKind('unknown_kind'), isFalse);
    });
  });

  group('id 生成合规（C33：12 位 base62·禁 uuid/时间戳/自增）', () {
    test('连续生成 200 个 id 全部 12 位 base62 且互不相同', () {
      final ids = <String>{};
      for (var i = 0; i < 200; i++) {
        final id = generateNfcCardId();
        expect(id.length, kNfcIdLen, reason: 'id=$id 不是 12 位');
        expect(isValidNfcCardId(id), isTrue, reason: 'id=$id 不合 base62');
        ids.add(id);
      }
      expect(ids.length, 200, reason: '出现撞号');
    });

    test('格式校验拒 uuid 形态/超长/含分隔符（B35：防注入的唯一闸）', () {
      expect(isValidNfcCardId('a1b2c3d4e5f6'), isTrue);
      expect(isValidNfcCardId('550e8400-e29b-41d4-a716-446655440000'), isFalse);
      expect(isValidNfcCardId('a1b2c3d4e5'), isFalse); // 11 位
      expect(isValidNfcCardId('a1b2c3d4e5f6g'), isFalse); // 含非 base62 字符
      expect(isValidNfcCardId("a1b2'c3d4e5f"), isFalse); // 含单引号（注入尝试）
      expect(isValidNfcCardId('a1b2c3d4e5f;'), isFalse); // 含分号
    });
  });

  group('NfcRepo CRUD（F1-2）', () {
    late Database db;
    late NfcRepo repo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = NfcRepo(db);
    });

    tearDown(() async => db.close());

    test('建卡 → 按 id 取 → 列全表 → 删卡', () async {
      final a = await repo.create(name: '学习', targetKind: NfcTargetKind.timerCat, targetRef: '3');
      final b = await repo.create(name: '记一笔', targetKind: NfcTargetKind.nav, targetRef: 'ledger');
      expect(a.id, isNot(b.id));

      final got = await repo.byId(a.id);
      expect(got!.name, '学习');
      expect(got.targetRef, '3');
      expect(got.useCount, 0);
      expect(got.lastUsedAt, isNull);
      expect(got.isWritten, isFalse);
      expect(got.hasTarget, isTrue);

      expect((await repo.listAll()).length, 2);
      await repo.delete(a.id);
      expect((await repo.listAll()).length, 1);
      expect(await repo.byId(a.id), isNull);
    });

    test('按 tag_key 取（F1-2 明确要求：写卡后回查走这条）', () async {
      await repo.create(
          name: '床头',
          targetKind: NfcTargetKind.timerCat,
          targetRef: '1',
          tagKey: ndefTagKeyOf('abcdefgh1234'),
          tagKind: NfcTagKind.ndef);
      final got = await repo.byTagKey('ndef:abcdefgh1234');
      expect(got!.name, '床头');
      expect(got.tagKind, NfcTagKind.ndef);
      expect(await repo.byTagKey('ndef:不存在'), isNull);
    });

    test('改名换目标**不重写标签**（C3：改数据零贴卡 ⇒ written_at/tag_key 不动）',
        () async {
      final c = await repo.create(name: '旧名', targetKind: NfcTargetKind.nav, targetRef: 'inbox');
      await repo.markWritten(c.id, tagKey: ndefTagKeyOf(c.id), tagKind: NfcTagKind.ndef);
      final before = await repo.byId(c.id);

      await repo.update(c.id, name: '新名', targetKind: NfcTargetKind.readBook, targetRef: 'bk1');
      final after = await repo.byId(c.id);
      expect(after!.name, '新名');
      expect(after.targetKind, NfcTargetKind.readBook);
      expect(after.targetRef, 'bk1');
      expect(after.writtenAt, before!.writtenAt, reason: '改名换目标不该动写入态');
      expect(after.tagKey, before.tagKey, reason: '改名换目标不该动标签');
    });

    test('记一次使用：use_count+1 且 last_used_at 落时间戳', () async {
      final c = await repo.create(name: '玄关', targetKind: NfcTargetKind.nav, targetRef: 'ledger');
      await repo.markUsed(c.id, nowMs: 1700000000000);
      await repo.markUsed(c.id, nowMs: 1700000005000);
      final got = await repo.byId(c.id);
      expect(got!.useCount, 2);
      expect(got.lastUsedAt, 1700000005000);
    });
  });

  group('写入态 written_at（C31：唯一判据·不靠读标签反推）', () {
    late Database db;
    late NfcRepo repo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = NfcRepo(db);
    });

    tearDown(() async => db.close());

    test('三态：NULL⇒未写入 / 写卡后为毫秒戳 / UID 只读卡显「只读卡」而非「未写入」',
        () async {
      final c = await repo.create(name: 'A', targetKind: NfcTargetKind.nav, targetRef: 'inbox');
      expect((await repo.byId(c.id))!.isWritten, isFalse);
      expect((await repo.byId(c.id))!.writtenAt, isNull);

      await repo.markWritten(c.id,
          tagKey: ndefTagKeyOf(c.id), tagKind: NfcTagKind.ndef, nowMs: 1700000000000);
      final w = await repo.byId(c.id);
      expect(w!.isWritten, isTrue);
      expect(w.writtenAt, 1700000000000);
      expect(w.isReadOnlyTag, isFalse);

      final u = await repo.create(
          name: 'B',
          targetKind: NfcTargetKind.nav,
          targetRef: 'inbox',
          tagKey: 'uid:deadbeefcafe',
          tagKind: NfcTagKind.uid);
      final ur = await repo.byId(u.id);
      // UID 只读卡即使 written_at 为空，UI 也要说「只读卡」——两者语义不同：
      // 「未写入」是可补的动作，「只读卡」是换卡才能解决的物理限制。
      expect(ur!.isReadOnlyTag, isTrue);
      expect(ur.isWritten, isFalse);
    });

    test('换卡覆盖写入覆盖写入态（B29：tag_kind 升为 ndef 且换 key）', () async {
      final c = await repo.create(
          name: '门禁',
          targetKind: NfcTargetKind.nav,
          targetRef: 'inbox',
          tagKey: 'uid:aabbccdd1122',
          tagKind: NfcTagKind.uid);
      await repo.rebindTag(c.id, tagKey: ndefTagKeyOf(c.id), tagKind: NfcTagKind.ndef);
      final after = await repo.byId(c.id);
      expect(after!.tagKind, NfcTagKind.ndef);
      expect(after.tagKey, ndefTagKeyOf(c.id));
      // 旧 UID 行不留双份：按旧 key 查已查不到。
      expect(await repo.byTagKey('uid:aabbccdd1122'), isNull);
    });

    test('删行即写入态随之消失（C31：写入态不另存他处）', () async {
      final c = await repo.create(name: 'A', targetKind: NfcTargetKind.nav, targetRef: 'inbox');
      await repo.markWritten(c.id, tagKey: ndefTagKeyOf(c.id), tagKind: NfcTagKind.ndef);
      await repo.delete(c.id);
      expect(await repo.byId(c.id), isNull);
      expect(await repo.byTagKey(ndefTagKeyOf(c.id)), isNull);
    });
  });

  group('备份恢复 UPSERT（B18 按 id / B28 tag_key 撞车）', () {
    late Database db;
    late NfcRepo repo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = NfcRepo(db);
    });

    tearDown(() async => db.close());

    test('同一 id 恢复两次不产生第二行（B18：后到覆盖）', () async {
      final row = <String, Object?>{
        'id': 'aaaaaaaaaaaa',
        'name': '旧名',
        'target_kind': 'nav',
        'target_ref': 'inbox',
        'tag_key': null,
        'tag_kind': null,
        'created_at': 1700000000000,
        'last_used_at': null,
        'use_count': 3,
        'written_at': null,
      };
      await repo.upsertFromBackup(row);
      await repo.upsertFromBackup(<String, Object?>{
        ...row,
        'name': '新名',
        'use_count': 9,
      });
      final all = await repo.listAll();
      expect(all.length, 1, reason: '同 id 恢复两次出现第二行 ⇒ UPSERT 没生效');
      expect(all.first.name, '新名');
      expect(all.first.useCount, 9);
    });

    test('tag_key 撞车：清空旧行的 key，不留双份（B28：以最近绑定的为准）', () async {
      final old = await repo.create(
          name: '旧卡',
          targetKind: NfcTargetKind.nav,
          targetRef: 'inbox',
          tagKey: 'ndef:shared0001',
          tagKind: NfcTagKind.ndef);
      await repo.upsertFromBackup(<String, Object?>{
        'id': 'bbbbbbbbbbbb',
        'name': '新卡',
        'target_kind': 'nav',
        'target_ref': 'todo',
        'tag_key': 'ndef:shared0001',
        'tag_kind': 'ndef',
        'created_at': 1700000000000,
        'last_used_at': null,
        'use_count': 0,
        'written_at': null,
      });
      final byKey = await repo.byTagKey('ndef:shared0001');
      expect(byKey!.id, 'bbbbbbbbbbbb', reason: '撞车后应以新行为准');
      final oldRow = await repo.byId(old.id);
      expect(oldRow!.tagKey, isNull, reason: '旧行的 key 应被清空，不留双份');
    });
  });

  group('批1b 三列（desc_text / color / target_sub · 工单 §2）', () {
    late Database db;
    late NfcRepo repo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = NfcRepo(db);
    });

    tearDown(() async => db.close());

    test('建卡带三列 → 读回逐列保真（含 desc 列名不是保留字 `desc`）', () async {
      final c = await repo.create(
        name: '床头阅读卡',
        targetKind: NfcTargetKind.readBook,
        targetRef: 'bk1',
        descText: '睡前读两页',
        color: 4,
      );
      final got = await repo.byId(c.id);
      expect(got!.descText, '睡前读两页');
      expect(got.color, 4);
      expect(got.colorIndex, 4);
      expect(got.targetSub, isNull);

      // 打卡卡：二级参数落 target_sub（**不新增 target_kind 枚举值**）。
      final h = await repo.create(
          name: '晨跑卡',
          targetKind: NfcTargetKind.nav,
          targetRef: kNfcRefHabit,
          targetSub: '晨间跑步 30min');
      final hg = await repo.byId(h.id);
      expect(hg!.isHabitTarget, isTrue);
      expect(hg.targetSub, '晨间跑步 30min');
      expect(hg.targetKind, NfcTargetKind.nav, reason: '打卡是 nav 下的动作，不是新枚举值');
    });

    test('颜色越界/未设一律兜回 0（脏数据不炸色板索引）', () async {
      final a = await repo.create(name: 'A', targetKind: NfcTargetKind.nav, targetRef: 'inbox');
      expect((await repo.byId(a.id))!.colorIndex, 0, reason: 'null ⇒ 0');
      final b = await repo.create(
          name: 'B', targetKind: NfcTargetKind.nav, targetRef: 'inbox', color: 99);
      expect((await repo.byId(b.id))!.colorIndex, 0, reason: '越界 ⇒ 0');
      expect(kNfcColors.length, kNfcColorCount);
      expect(kNfcColorNames.length, kNfcColorCount);
    });

    test('备份恢复按 id UPSERT 时三列一并保真（C8-V3：换机后卡片样子不变）', () async {
      await repo.upsertFromBackup(<String, Object?>{
        'id': 'cccccccccccc',
        'name': '玄关卡',
        'target_kind': 'nav',
        'target_ref': 'care',
        'target_sub': '2/diaper',
        'tag_key': null,
        'tag_kind': null,
        'created_at': 1700000000000,
        'last_used_at': null,
        'use_count': 0,
        'written_at': null,
        'desc_text': '出门换尿布',
        'color': 3,
      });
      final got = await repo.byId('cccccccccccc');
      expect(got!.descText, '出门换尿布');
      expect(got.color, 3);
      expect(got.targetSub, '2/diaper');
      expect(got.isCareTarget, isTrue);
    });
  });

  group('批1b 两形态写入（N15 两向语义：只改目标不动卡片／只改卡片不动目标）', () {
    late Database db;
    late NfcRepo repo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = NfcRepo(db);
    });

    tearDown(() async => db.close());

    test('updateTarget 只写目标三列：卡片名/描述/颜色纹丝不动', () async {
      final c = await repo.create(
        name: '书桌学习卡',
        targetKind: NfcTargetKind.timerCat,
        targetRef: '1',
        descText: '坐下就计时',
        color: 0,
      );
      await repo.updateTarget(c.id,
          targetKind: NfcTargetKind.nav, targetRef: kNfcRefHabit, targetSub: '晨间跑步');
      final got = await repo.byId(c.id);
      expect(got!.targetKind, NfcTargetKind.nav);
      expect(got.targetRef, kNfcRefHabit);
      expect(got.targetSub, '晨间跑步');
      expect(got.name, '书桌学习卡', reason: '绑定目标形态不该动卡片名');
      expect(got.descText, '坐下就计时', reason: '绑定目标形态不该动描述');
      expect(got.color, 0, reason: '绑定目标形态不该动颜色');
    });

    test('updateCardInfo 只写卡片三列：目标三列纹丝不动', () async {
      final c = await repo.create(
        name: '旧名',
        targetKind: NfcTargetKind.nav,
        targetRef: kNfcRefHabit,
        targetSub: '晨间跑步',
      );
      await repo.updateCardInfo(c.id, name: '改名后的卡', descText: '新描述', color: 3);
      final got = await repo.byId(c.id);
      expect(got!.name, '改名后的卡');
      expect(got.descText, '新描述');
      expect(got.color, 3);
      expect(got.targetRef, kNfcRefHabit, reason: '卡片信息形态不该动目标');
      expect(got.targetSub, '晨间跑步', reason: '卡片信息形态不该动二级参数');
    });

    test('换大类时 target_sub 必须能被清回 null（不留「打卡的习惯名挂在计时分类上」）',
        () async {
      final c = await repo.create(
        name: '卡',
        targetKind: NfcTargetKind.nav,
        targetRef: kNfcRefHabit,
        targetSub: '晨间跑步',
      );
      await repo.updateTarget(c.id,
          targetKind: NfcTargetKind.timerCat, targetRef: '2', targetSub: null);
      final got = await repo.byId(c.id);
      expect(got!.targetSub, isNull, reason: '全量落写（不是「非空才写」）才清得掉');
      expect(got.isHabitTarget, isFalse);
    });

    test('两形态写入都不碰写入态与标签（C3：改数据零贴卡）', () async {
      final c = await repo.create(name: '卡', targetKind: NfcTargetKind.nav, targetRef: 'inbox');
      await repo.markWritten(c.id, tagKey: ndefTagKeyOf(c.id), tagKind: NfcTagKind.ndef);
      final before = await repo.byId(c.id);
      await repo.updateCardInfo(c.id, name: '新名', descText: null, color: 2);
      await repo.updateTarget(c.id,
          targetKind: NfcTargetKind.readBook, targetRef: 'bk9', targetSub: null);
      final after = await repo.byId(c.id);
      expect(after!.writtenAt, before!.writtenAt);
      expect(after.tagKey, before.tagKey);
      expect(after.tagKind, before.tagKind);
    });
  });

  group('批1b 域层纯判定（标签口径 / 二级参数 / 装饰符剥离）', () {
    NfcCard card(String kind, String? ref, {String? sub}) => NfcCard(
          id: 'aaaaaaaaaaaa',
          name: '卡',
          targetKind: kind,
          targetRef: ref,
          targetSub: sub,
          createdAt: 0,
        );

    test('目标类名逐条：打卡/呵护宝宝不再笼统显示「快捷动作」', () {
      expect(card(NfcTargetKind.nav, 'ledger').targetKindLabel, '快捷动作');
      expect(card(NfcTargetKind.nav, kNfcRefHabit, sub: '跑步').targetKindLabel, '打卡');
      expect(card(NfcTargetKind.nav, kNfcRefCare, sub: '1/nurse').targetKindLabel, '呵护宝宝');
      expect(card(NfcTargetKind.timerCat, '1').targetKindLabel, '计时');
      expect(card(NfcTargetKind.readBook, 'b1').targetKindLabel, '阅读');
      expect(card(NfcTargetKind.nav, null).targetKindLabel, isNull,
          reason: '未绑定的卡不显类名');
      expect(card(NfcTargetKind.nav, kNfcRefHabit, sub: '跑步').targetKindIcon, 'habit');
      expect(card(NfcTargetKind.nav, kNfcRefCare, sub: '1/nurse').targetKindIcon, 'care');
    });

    test('目标标签全文（列表主行逐字口径）', () {
      expect(nfcTargetLabelOf(card(NfcTargetKind.timerCat, '1'), targetName: '学习'),
          '计时 · 学习');
      expect(nfcTargetLabelOf(card(NfcTargetKind.readBook, 'b1'), targetName: '活着'),
          '阅读 · 活着');
      expect(
          nfcTargetLabelOf(card(NfcTargetKind.nav, kNfcRefHabit, sub: '晨间跑步 30min')),
          '打卡 · 晨间跑步 30min');
      expect(
          nfcTargetLabelOf(card(NfcTargetKind.nav, kNfcRefCare, sub: '1/nurse'),
              targetName: '小满 · 母乳亲喂'),
          '呵护宝宝 · 小满 · 母乳亲喂');
      // 动作类＝动作名本身（不加「快捷动作 · 」前缀），动作名同源桌面动作表。
      expect(nfcTargetLabelOf(card(NfcTargetKind.nav, 'ledger')), '记一笔');
      expect(nfcTargetLabelOf(card(NfcTargetKind.nav, '已退役动作')), '未绑定');
      expect(nfcTargetLabelOf(card(NfcTargetKind.nav, null)), '未绑定');
    });

    test('二级参数拼装与拆解（脏数据不猜、按失效处理）', () {
      expect(nfcCareSubOf(3, 'diaper'), '3/diaper');
      expect(nfcCareSubParse('3/diaper'), (3, 'diaper'));
      expect(nfcCareSubParse(null), isNull);
      expect(nfcCareSubParse(''), isNull);
      expect(nfcCareSubParse('3'), isNull);
      expect(nfcCareSubParse('/diaper'), isNull);
      expect(nfcCareSubParse('abc/diaper'), isNull);
      expect(nfcCareSubParse('3/'), isNull);
    });

    test('装饰符剥离：习惯名与引用他模块数据一律零 emoji', () {
      expect(nfcStripEmoji('🏃 晨间跑步 30min'), '晨间跑步 30min');
      expect(nfcStripEmoji('📖读书'), '读书');
      expect(nfcStripEmoji('  喝水💧  '), '喝水');
      expect(nfcStripEmoji('晨跑'), '晨跑');
      // 剥完为空＝回落原名（空 chip 不可点也不可辨；三处同源不会「选得上却判失效」）。
      expect(nfcHabitDisplayName('🏃'), '🏃');
      expect(nfcHabitDisplayName('🏃 晨跑'), '晨跑');
    });
  });

  group('隐私（F1-1b：指纹与 tag_key 原文永不进日志）', () {
    test('脱敏串只留后 4 位', () {
      expect(maskedTagKey('uid:deadbeefcafe'), 'uid:****cafe');
      expect(maskedTagKey('ndef:abcdefgh1234'), 'ndef:****1234');
      expect(maskedTagKey('uid:ab'), 'uid:****');
      expect(maskedTagKey(null), '(无)');
      expect(maskedTagKey(''), '(无)');
    });

    test('脱敏串不含指纹/卡号原文（唯一允许出现在日志里的形态）', () {
      const key = 'uid:0123456789abcdef';
      final m = maskedTagKey(key);
      expect(m.contains('0123456789abcdef'), isFalse);
      expect(m.contains('0123'), isFalse, reason: '只许留后 4 位');
      expect(m.endsWith('cdef'), isTrue);
    });
  });
}