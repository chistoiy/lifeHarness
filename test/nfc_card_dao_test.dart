import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/nfc.dart';
import 'package:lifeharness/features/nfc/data/nfc_repo.dart';
import 'package:lifeharness/features/nfc/domain/nfc_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// NFC 卡片批1 · 数据层守护（工单 §2 F1-1 / F1-2 / C31 / C33 / B18 / B28）。
///
/// 6109 实锤的铁律：迁移批必跑 S6（version=migrations 最高键+1）＋
/// S7（真升级路径，禁只测 onCreate——测试库走 onCreate 全量 DDL，升级路径平时零覆盖）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('NFC v47→v48 迁移与 schema', () {
    test('S6 version 常量 = migrations 最高键 + 1（漏改 version＝升级静默失效）',
        () {
      final maxKey = DbSchema.migrations.keys.reduce((a, b) => a > b ? a : b);
      expect(DbSchema.version, maxKey + 1,
          reason: 'migrations 已定义到 $maxKey → ${maxKey + 1}，'
              '但 version=${DbSchema.version} 没跟上——真机 user_version 已到 '
              '${maxKey + 1} 以上时该迁移永不执行（6109 日记全断同源）');
    });

    test('S7 真升级 v47 库 → v48：nfc_cards 建出且九列齐全', () async {
      const name = 'nfctest_upgrade_v47to48.db';
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
      // F1-1 十列逐条点名（C31 的 written_at 是最容易被漏的一列）。
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
          ]));
      await upgraded.close();
    });

    test('onCreate 全量 DDL 同样建出 nfc_cards（双写 DDL 闸）', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      expect(tables.map((r) => r['name']), contains(DbSchema.tNfcCards));
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