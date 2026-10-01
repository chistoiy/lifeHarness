import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/xray/xray_dao.dart';
import 'package:lifeharness/features/read/data/xray/xray_engine.dart';
import 'package:lifeharness/features/read/data/xray/xray_lexicon.dart';

/// X-Ray DAO 往返（需求 V1.54 · 批1d 落库面）
///
/// 钉的是**语义**而不是 CRUD：重解析不许把用户状态洗白、不许锚点翻倍、
/// 「重置索引」不许动用户词典（§7）。这三条都是以后最容易「顺手简化」掉的东西。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const md5 = 'AAA';
  late Database db;
  late XrayDao dao;

  Future<void> insertBook(String id, {String? hash}) async {
    await db.insert(DbSchema.tBooks, {
      'id': id,
      'title': '书$id',
      'md5': hash,
      'created_at': 1,
      'updated_at': 1,
    });
  }

  /// 造两个引擎实体（term 走全量锚点，per 只给部分锚点，模拟真实产出形状）。
  List<XrayEntity> ents() {
    final per = XrayEntity('李伟', XrayType.person)
      ..n = 3
      ..score = 7.5
      ..channels = XrayChan.regex
      ..aliases.add('李伟探长');
    per.hit(0, 2, snippet: '李伟说过');
    final term = XrayEntity('认知革命', XrayType.term)
      ..n = 5
      ..score = 4.0
      ..channels = XrayChan.ngram;
    term.hit(1, 0);
    term.hit(2, 7);
    return [per, term];
  }

  Map<String, List<XrayMention>> anchors() => {
        '李伟': [XrayMention(0, 2, '李伟说过')],
        '认知革命': const [XrayMention(1, 0), XrayMention(2, 7)],
      };

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: DbSchema.version));
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = XrayDao(db);
    await insertBook('b1', hash: md5);
    await insertBook('b2', hash: md5);
    await insertBook('b3');
  });
  tearDown(() => db.close());

  test('books.md5：懒补算与同指纹架位查找', () async {
    expect(await dao.bookMd5('b3'), isNull, reason: '存量书没补算前应为 null');
    await dao.setBookMd5('b3', md5);
    expect(await dao.bookMd5('b3'), md5);
    expect(await dao.bookIdsWithMd5(md5, exceptBookId: 'b1'), containsAll(['b2', 'b3']),
        reason: 'F9 复用提示：同 MD5 的其它架位都要能找出来');
  });

  test('任务态：断点只推进游标，不动其它字段', () async {
    expect(await dao.task(md5), isNull);
    await dao.upsertTask(
        md5: md5,
        totalCh: 12,
        rangeStart: 0,
        rangeEnd: 11,
        status: xsStatusRunning,
        processedCh: 0);
    await dao.patchTaskProgress(md5: md5, processedCh: 5);
    final t = (await dao.task(md5))!;
    expect(t.processedCh, 5);
    expect(t.totalCh, 12, reason: '只该动 processed_ch/update_time');
    expect(t.rangeEnd, 11);
    expect(t.isDone, isFalse);
    await dao.patchTaskProgress(md5: md5, processedCh: 12, status: xsStatusSuccess);
    expect((await dao.task(md5))!.isDone, isTrue);
  });

  test('整批写入：锚点全量落库，snippet 只在前若干条', () async {
    await dao.writeChapterResult(
        md5: md5, entities: ents(), anchorsByName: anchors());
    final term = (await dao.entitiesOfType(md5, 'term')).single;
    expect(await dao.anchorsOf(md5, term.id), hasLength(2),
        reason: '§6：锚点全量存，跳转才数得清页码');
    final per = (await dao.entitiesOfType(md5, 'per')).single;
    expect((await dao.anchorsOf(md5, per.id)).single.snippet, '李伟说过');
    expect(per.aliases, contains('李伟探长'),
        reason: '称谓组合名是 JSON 列：写坏或读坏都会让 F8 自动合并失去依据');
    expect(per.tocFlag, isFalse);
    expect(await dao.parsedChapterCount(md5), 3,
        reason: '「已解析 x/y 章」按锚点跨章去重，面板不自己数');
  });

  test('锚点段级去重：同段多次命中只落一条，提及数不跟着掉', () async {
    // 真机 2026-10-01 16:03 人类简史「几乎」详情：第一章段 42 整行重复列两次。
    // 引擎侧每次出现都记一条 mention（n 要数次数），多通道合并还会带来非相邻重复，
    // 所以去重收在落库唯一出口，而不是收在某个通道的循环里。
    final e = ents();
    e[1].hit(1, 0); // 同段第二次出现 → n 变，锚点不该变
    await dao.writeChapterResult(
        md5: md5,
        entities: e,
        anchorsByName: {
          '李伟': [
            XrayMention(0, 2, '李伟说过'),
            XrayMention(0, 2, null), // 重复且没带文：留带文的那条
          ],
          '认知革命': const [
            XrayMention(1, 0),
            XrayMention(1, 0),
            XrayMention(2, 7),
            XrayMention(1, 0), // 非相邻重复（合并通道带来）
          ],
        });
    final term = (await dao.entitiesOfType(md5, 'term')).single;
    expect(await dao.anchorsOf(md5, term.id), hasLength(2),
        reason: '出场列表一格一条，否则 F5 位置数不对、迷你分布条同位叠点');
    expect(term.n, 8, reason: '去重只动锚点，提及数仍按出现次数计');
    final per = (await dao.entitiesOfType(md5, 'per')).single;
    final pa = await dao.anchorsOf(md5, per.id);
    expect(pa, hasLength(1));
    expect(pa.single.snippet, '李伟说过', reason: '留下的那条必须带 snippet');
  });

  test('冷启动收尸：上个进程留下的 running 一律转 pause', () async {
    await dao.upsertTask(
        md5: md5,
        totalCh: 12,
        rangeStart: 0,
        rangeEnd: 11,
        status: xsStatusRunning,
        processedCh: 5);
    await dao.upsertTask(
        md5: 'BBB',
        totalCh: 4,
        rangeStart: 0,
        rangeEnd: 3,
        status: xsStatusSuccess,
        processedCh: 4);
    expect(await dao.reapStaleRunning(), 1,
        reason: '只收 running；成功/暂停/失败都是终态或用户态，不许动');
    expect((await dao.task(md5))!.status, xsStatusPause);
    expect((await dao.task('BBB'))!.status, xsStatusSuccess);
  });

  test('重解析：刷新计数与分值，但用户状态与词典不许被洗白', () async {
    await dao.writeChapterResult(
        md5: md5, entities: ents(), anchorsByName: anchors());
    // 用户先把「李伟」屏蔽掉（F8②），再来一次重解析
    final per = (await dao.entitiesOfType(md5, 'per')).single;
    await db.update(DbSchema.tXrayEntity, {'status': xsStatusDeleted},
        where: 'id = ?', whereArgs: [per.id]);

    final again = ents()..first.score = 99;
    await dao.writeChapterResult(
        md5: md5, entities: again, anchorsByName: anchors());

    final rows = await db.query(DbSchema.tXrayEntity,
        columns: ['name', 'status', 'score'], where: 'name = ?', whereArgs: ['李伟']);
    expect(rows.single['status'], xsStatusDeleted,
        reason: '解析无权把「用户屏蔽」洗回在册（§7 覆盖层语义）');
    expect((rows.single['score'] as num).toDouble(), 99,
        reason: '但分值/计数必须刷新，否则重跑后排序是旧的');
    expect(await dao.entitiesOfType(md5, 'per'), isEmpty,
        reason: '读侧 deleted 一律不出现');

    final mentions = await db.query(DbSchema.tXrayMention, where: 'book_md5 = ?', whereArgs: [md5]);
    expect(mentions, hasLength(3), reason: '锚点整批替换，重跑不叠加出双倍出场');
  });

  test('用户层：加词/屏蔽读回，GLOBAL 与按书两档都进同一个视图', () async {
    await dao.putUserWord(scope: md5, word: '案子', action: xsActForbid);
    await dao.putUserWord(scope: xsScopeGlobal, word: '侦探', action: xsActForbid);
    await dao.putUserWord(scope: md5, word: '认知革命', action: xsActAdd);
    final layer = await dao.userLayer(md5);
    expect(layer.forbidden, containsAll(['案子', '侦探']));
    expect(layer.added, contains('认知革命'));

    await dao.promoteToGlobal(md5, '案子');
    final other = await dao.userLayer('OTHER_MD5');
    expect(other.forbidden, contains('案子'), reason: '升级到全局后，别的书也受影响');
    expect((await dao.userLayer(md5)).forbidden, contains('案子'));
  });

  test('批2 GLOBAL 词库管理面：列表只含 GLOBAL、改名/换动作/删行不越界', () async {
    // 造数：GLOBAL 两动作 + 按书一行（按书行不得混进管理页列表）。
    await dao.putUserWord(
        scope: xsScopeGlobal, word: '波洛', action: xsActAdd, type: 'per');
    await dao.putUserWord(scope: md5, word: '案子', action: xsActForbid);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await dao.putUserWord(scope: xsScopeGlobal, word: '侦探', action: xsActForbid);

    final list = await dao.listGlobalDict();
    expect(list.map((r) => r.word), ['侦探', '波洛'],
        reason: '最近养入在前；按书行（案子）不得出现');
    expect(list[1].type, 'per');

    // 改名：只动 (波洛,add) 行；同词其他动作行（若有）不受牵连。
    await dao.updateGlobalDict(word: '波洛', action: xsActAdd, newWord: '赫丘勒');
    expect((await dao.listGlobalDict()).map((r) => r.word),
        containsAll(['侦探', '赫丘勒']));
    expect((await dao.listGlobalDict()).where((r) => r.word == '波洛'), isEmpty);

    // 换动作＝旧行删新行写（唯一键含 action）：侦探 forbid→add。
    await dao.updateGlobalDict(
        word: '侦探', action: xsActForbid, toAction: xsActAdd);
    final after = await dao.listGlobalDict();
    expect(after.where((r) => r.word == '侦探').map((r) => r.action), ['add']);
    final layer = await dao.userLayer(md5);
    expect(layer.forbidden, isNot(contains('侦探')), reason: '换动作后旧动作必须失效');
    expect(layer.added, contains('侦探'));

    // 精确删：只删 add 行；词级删（action=null）把该词所有动作行清掉。
    await dao.deleteGlobalDict('侦探', action: xsActAdd);
    expect((await dao.listGlobalDict()).where((r) => r.word == '侦探'), isEmpty);
    await dao.putUserWord(scope: xsScopeGlobal, word: '赫丘勒', action: xsActAdd);
    await dao.putUserWord(scope: xsScopeGlobal, word: '赫丘勒', action: xsActForbid);
    expect(await dao.deleteGlobalDict('赫丘勒'), 2, reason: '词级删清所有动作行');
    expect(await dao.listGlobalDict(), isEmpty);
    // 幂等：删不存在的词返回 0 不抛错。
    expect(await dao.deleteGlobalDict('不存在'), 0);
  });

  test('重置索引清三层，但用户词典是用户资产不许一起抹（§7）', () async {
    await dao.writeChapterResult(
        md5: md5, entities: ents(), anchorsByName: anchors());
    await dao.putUserWord(scope: md5, word: '波洛', action: xsActAdd);
    await dao.upsertTask(
        md5: md5,
        totalCh: 3,
        rangeStart: 0,
        rangeEnd: 2,
        status: xsStatusSuccess);

    await dao.resetBook(md5);
    expect(await dao.entityCount(md5), 0);
    expect(await dao.parsedChapterCount(md5), 0);
    expect(await dao.task(md5), isNull);
    expect((await dao.userLayer(md5)).added, contains('波洛'),
        reason: '「重置」的语义是重跑解析，不是删掉用户整理的词');
    expect(await dao.bookMd5('b1'), md5, reason: '指纹本身也不是索引数据，不许清');
  });

  test('空库读取不炸：面板首屏路径', () async {
    expect(await dao.entitiesOfType('NOPE', 'per'), isEmpty);
    expect(await dao.searchEntities('NOPE', '李'), isEmpty);
    expect(await dao.entityCount('NOPE'), 0);
    expect((await dao.userLayer('NOPE')).forbidden, isEmpty);
    final e = XrayLexicon(_bank());
    expect(e.blocked('李伟'), isFalse, reason: '没登记过就不该被屏蔽（默认放行）');
  });
}

/// 真词表（与 lexicon 测试同源，走磁盘读取——本用例只关心 DAO，不测装载）。
XrayWordBank _bank() => XrayWordBank.parse({
      for (final n in XrayWordBank.assetNames)
        n: File('assets/xray/dicts/$n').readAsStringSync(),
    });

/// 表名/状态常量别名（测试里直连表要写全 DbSchema，这几行只为可读性）。
const xsStatusRunning = 'running';
const xsStatusPause = 'pause';
const xsStatusSuccess = 'success';
const xsStatusDeleted = 'deleted';
const xsActForbid = 'forbid';
const xsActAdd = 'add';
const xsScopeGlobal = 'GLOBAL';
