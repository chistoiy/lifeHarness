import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/xray/xray_dao.dart';
import 'package:lifeharness/features/read/data/xray/xray_engine.dart'
    show XrayMention;

/// V1.54 批C · 复用与备份（F9/F10 + §13 路径 B 核对）
///
/// 钉三件事：
/// 1. `.xraybak` 导出→清空→导入 **全等回还**（含 deleted/user_added 状态、aliases、
///    GLOBAL 词典与任务态——用户整理结果就是要带走的东西）；
/// 2. 册内 MD5 不齐＝**整册拒收**（防拼改包污染归属键）；
/// 3. `.lhbak` 整包备份对 X-Ray 四表**零排除**：备份器按 sqlite_master 动态枚举
///    （新表天然随行），排除组来源（care.syncExcluded）源码级不得点名 xray 表。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const md5A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const md5B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const md5Bad = 'cccccccccccccccccccccccccccccccc';

  late Database db;
  late XrayDao dao;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1, onCreate: (d, _) async {
      for (final sql in DbSchema.createStatements) {
        await d.execute(sql);
      }
    }));
    dao = XrayDao(db);
    await db.insert(DbSchema.tBooks, {
      'id': 'bkA',
      'title': '书A',
      'md5': md5A,
      'created_at': 1,
      'updated_at': 1,
    });
    // A 册：active 词条（1 条带文锚点 + 1 条纯锚点）、user_added、deleted 各一 + 任务态。
    await dao.writeRunResult(md5: md5A, rows: [
      XrayWriteEntity(
          name: '波洛',
          type: 'per',
          n: 2,
          chs: 2,
          score: 5.5,
          channels: 1,
          tocFlag: true,
          aliases: const ['波洛先生'],
          anchors: const [XrayMention(0, 3, '波洛说'), XrayMention(1, 7)]),
    ]);
    await db.insert(DbSchema.tXrayEntity, {
      'book_md5': md5A,
      'name': '我加的词',
      'type': 'term',
      'n': 0,
      'chs': 0,
      'score': 1,
      'src_channels': 0,
      'status': 'user_added',
      'aliases': '[]',
      'toc_flag': 0,
    });
    await db.insert(DbSchema.tXrayEntity, {
      'book_md5': md5A,
      'name': '被屏蔽词',
      'type': 'term',
      'n': 1,
      'chs': 1,
      'score': 2,
      'src_channels': 1,
      'status': 'deleted',
      'aliases': '[]',
      'toc_flag': 0,
    });
    await dao.upsertTask(
        md5: md5A,
        totalCh: 12,
        rangeStart: 0,
        rangeEnd: 11,
        status: 'success',
        processedCh: 12);
    await dao.putUserWord(scope: md5A, word: '我加的词', action: 'add', type: 'term');
    await dao.putUserWord(scope: 'GLOBAL', word: '全局禁词', action: 'forbid');
    // B 册：只有词条无任务（部分索引分享包也合法）。
    await dao.writeRunResult(md5: md5B, rows: [
      XrayWriteEntity(
          name: '伦敦',
          type: 'loc',
          n: 1,
          chs: 1,
          score: 1.2,
          channels: 4,
          tocFlag: false,
          aliases: const [],
          anchors: const [XrayMention(2, 0)]),
    ]);
  });
  tearDown(() => db.close());

  test('.xraybak 导出→清空→导入：状态/别名/词典/任务态全等回还', () async {
    final bundle = await dao.exportBundle();
    expect(((bundle['indices'] as List)).length, 2);
    final a = (bundle['indices'] as List)
        .cast<Map<Object?, Object?>>()
        .firstWhere((e) => e['md5'] == md5A);
    expect((a['entities'] as List), hasLength(3),
        reason: 'deleted/user_added 状态行原样随行（分享=分享整理结果）');
    expect(a['task'], isNotNull);

    // 本机清空两册（含词典），模拟换机/另一台设备。
    await dao.resetBook(md5A);
    await dao.resetBook(md5B);
    await db.delete(DbSchema.tXrayUserdict);
    expect(await dao.indexedBookCount(), 0);

    final r = await dao.importBundle(bundle);
    expect((r.books, r.bad), (2, 0));
    expect(await dao.indexedBookCount(), 2);
    final ents = await dao.allEntities(md5A);
    final luo = ents.firstWhere((e) => e.name == '波洛');
    expect(luo.aliases, ['波洛先生']);
    expect(luo.tocFlag, isTrue);
    expect(ents.where((e) => e.name == '我加的词'), hasLength(1),
        reason: 'user_added 读侧在册');
    expect(ents.where((e) => e.name == '被屏蔽词'), isEmpty,
        reason: 'deleted 行随包携带但读侧仍不可见');
    expect((await dao.task(md5A))?.status, 'success');
    expect((await dao.task(md5A))?.processedCh, 12);
    final layer = await dao.userLayer(md5A);
    expect(layer.added, contains('我加的词'));
    expect(layer.forbidden, contains('全局禁词'), reason: 'GLOBAL 词典随包迁移');
    final anchors = await dao.anchorsOf(md5A, luo.id);
    expect(anchors, hasLength(2));
    expect(anchors.first.snippet, '波洛说');
    expect(anchors.last.snippet, isNull, reason: '纯锚点行不造 snippet');
  });

  test('册内 MD5 不齐 → 整册拒收并报 bad', () async {
    final bundle = await dao.exportBundle();
    final list = (bundle['indices'] as List).cast<Map<Object?, Object?>>();
    // 篡改：把 B 册一条 mention 的归属指到 A 册。
    final bIdx = list.indexWhere((e) => e['md5'] == md5B);
    ((list[bIdx]['mentions'] as List).first as Map)['book_md5'] = md5Bad;
    final r = await dao.importBundle(bundle);
    expect(r.bad, 1, reason: '拼改册必须显形');
    expect(r.books, 1);
    expect(r.md5s, [md5A]);
  });

  test('版本不符的包直接抛（不当可修复数据吞掉）', () async {
    await expectLater(dao.importBundle({'v': 99, 'indices': const []}),
        throwsA(isA<FormatException>()));
  });

  test('.lhbak 核对：备份器动态枚举 + 排除组源码不点名 X-Ray 表', () {
    // 路径 B 语义＝新表天然随主库走：备份打包必须按 sqlite_master 动态列表，
    // 而不是维护白名单——白名单哪天漏登记就静默丢 X-Ray 数据。
    final lhBak = File('lib/core/backup/lh_bak.dart').readAsStringSync();
    expect(lhBak, contains('sqlite_master'),
        reason: '导出必须动态枚举表，X-Ray 四表才能零改动随行');
    // 排除组（care.syncExcluded 一族）不得把 X-Ray 表排除出快照/整包。
    final scanned = [
      'lib/core/backup/lh_bak.dart',
      'lib/core/backup/backup_service.dart',
      'lib/core/sync/snapshot_service.dart',
      'lib/features/care/data/care_repository.dart',
    ];
    final offenders = <String>[];
    for (final rel in scanned) {
      final f = File(rel);
      if (!f.existsSync()) continue;
      final lines = f.readAsLinesSync()
        ..removeWhere((l) => l.trim().startsWith('//'));
      if (lines.any((l) => RegExp(r'xray_|\bXray').hasMatch(l) == true &&
          RegExp(r"'xray_(task|entity|mention|userdict)'").hasMatch(l))) {
        offenders.add(rel);
      }
    }
    expect(offenders, isEmpty,
        reason: 'X-Ray 四表须随 .lhbak 与同步快照走（§13 路径 B）；'
            '谁把它写进排除组，谁就制造换机丢索引');
  });
}
