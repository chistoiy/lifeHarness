import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/xray/xray_dao.dart';
import 'package:lifeharness/features/read/data/xray/xray_engine.dart'
    show XrayMention;
import 'package:lifeharness/features/read/data/xray/xray_refine.dart';

/// V1.54.1 批4 · AI 精化逻辑面（切批/解析/逐批执行/暂停续跑/落库）。
///
/// 零网络：模型调用一律走注入的 `XrBatchCaller` 假缝，且**与真实协议同形**
/// （返回 `Map<String,dynamic>?`，失败靠抛）——缝自己吞掉握手就等于没测。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  List<XrRefineCandidate> cands(int n) => [
        for (var i = 0; i < n; i++)
          XrRefineCandidate(name: '词条$i', type: 'term', n: 100 - i, chs: 5)
      ];

  String? typeOf(List<XrRefineSuggestion> s, XrRefineKind k, String w) {
    final m = s.where((e) => e.kind == k && e.word == w).toList();
    return m.isEmpty ? null : m.first.type;
  }

  int countOf(List<XrRefineSuggestion> s, XrRefineKind k) =>
      s.where((e) => e.kind == k).length;

  group('1 · 切批', () {
    test('预算越小批次越多（联动必须成立，不许钉下限）', () {
      final all = cands(8);
      final big = xrSplitBatches(all, 1000);
      final small = xrSplitBatches(all, 40);
      expect(big, hasLength(1));
      expect(small.length, greaterThan(1),
          reason: '预算 1000→40 批次数必须变多（原型首轮就是把下限钉成 6 把联动遮住了）');
      expect(small.expand((b) => b).length, 8, reason: '切批不丢词');
    });

    test('单条超预算自成一批，不挤掉也不丢；空输入零批', () {
      final one = [
        XrRefineCandidate(name: '超长的词条名字长得离谱', type: 'term', n: 1, chs: 1)
      ];
      expect(xrSplitBatches(one, 4), hasLength(1));
      expect(xrSplitBatches(const [], 100), isEmpty);
    });
  });

  group('2 · 建议解析', () {
    test('三段齐备 · 类型越界丢弃 · add 无合法类型回落 term · 同键去重', () {
      final s = xrParseRefineJson({
        'remove': [' 几乎 ', '概念', '', 7],
        'retype': [
          {'word': '玫瑰战争', 'type': 'org'},
          {'word': '怪类', 'type': 'xxx'},
          {'word': '', 'type': 'per'},
        ],
        'add': [
          {'word': '波洛', 'type': 'per', 'why': '漏召'},
          {'word': '无名'},
          {'word': '波洛', 'type': 'per'},
        ],
      });
      expect(countOf(s, XrRefineKind.remove), 2);
      expect(typeOf(s, XrRefineKind.remove, '几乎'), isNull, reason: 'trim 后入清单');
      expect(countOf(s, XrRefineKind.retype), 1);
      expect(typeOf(s, XrRefineKind.retype, '玫瑰战争'), 'org');
      expect(countOf(s, XrRefineKind.add), 2);
      expect(typeOf(s, XrRefineKind.add, '波洛'), 'per');
      expect(typeOf(s, XrRefineKind.add, '无名'), 'term');
    });

    test('缺段容忍：只给 remove 也只出一条（模型少答不等于失败）', () {
      expect(xrParseRefineJson({'remove': ['种种']}), hasLength(1));
      expect(xrParseRefineJson({}), isEmpty);
    });
  });

  group('3 · 逐批执行', () {
    test('顺序跑完 · 批数由预算定 · 每批不重不漏', () async {
      final seen = <String>[];
      final r = XrRefineRunner(
          budgetChars: 40,
          caller: (b) async {
            seen.addAll(b.map((e) => e.name));
            return {
              'remove': [b.first.name]
            };
          });
      await r.run(cands(8));
      expect(r.stage, XrRefineStage.done);
      expect(r.doneBatches, r.totalBatches);
      expect(r.failedBatches, 0);
      expect(seen.toSet().length, 8, reason: '所有候选都被送到过模型');
      expect(countOf(r.suggestions, XrRefineKind.remove), r.totalBatches);
    });

    test('单批失败重试一次后跳过，不整链中断', () async {
      var calls = 0;
      final r = XrRefineRunner(
          budgetChars: 40,
          caller: (b) async {
            calls++;
            if (calls == 2 || calls == 3) throw const FormatException('不合约定');
            return {'add': [
              {'word': '新词${b.first.name}', 'type': 'per'}
            ]};
          });
      await r.run(cands(8));
      expect(r.stage, XrRefineStage.done);
      expect(r.retriedBatches, 1, reason: '失败批只重试一次');
      expect(r.failedBatches, 1);
      expect(r.doneBatches, r.totalBatches, reason: '失败批之后继续跑到尾');
      expect(countOf(r.suggestions, XrRefineKind.add), r.totalBatches - 1);
    });

    test('暂停只挂起下一批；resume 让同一个 run 接着跑', () async {
      var calls = 0;
      late XrRefineRunner r; // 闭包要回调 r.pause()，不能写成 final r = …（声明前引用）
      r = XrRefineRunner(
          budgetChars: 40,
          pace: const Duration(milliseconds: 2),
          caller: (b) async {
            calls++;
            if (calls == 3) r.pause();
            return {'remove': [b.first.name]};
          });
      final f = r.run(cands(12));
      // 轮询到暂停态（真事件循环，非 FakeAsync：本文件是纯逻辑用例）
      for (var i = 0; i < 100 && r.stage != XrRefineStage.paused; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      expect(r.stage, XrRefineStage.paused);
      expect(calls, 3, reason: '暂停后不再发下一批');
      expect(r.doneBatches, 3, reason: '暂停前已发出的批照常收');
      expect(r.progress, lessThan(1));
      r.resume();
      await f;
      expect(r.stage, XrRefineStage.done);
      expect(r.doneBatches, r.totalBatches);
      expect(calls, r.totalBatches);
    });

    test('连续两批失败＝自动中止（端点/额度炸了不再往下烧 token）', () async {
      var calls = 0;
      final r = XrRefineRunner(
          budgetChars: 40,
          caller: (b) async {
            calls++;
            throw const FormatException('端点无响应');
          });
      await r.run(cands(12));
      expect(r.stage, XrRefineStage.cancelled);
      expect(r.failedBatches, 2);
      expect(r.doneBatches, 1, reason: '第 2 批失败即止，游标没往前推');
      expect(r.totalBatches, greaterThan(2), reason: '后面的批没再发');
      expect(calls, 4, reason: '两批各「首发+重试一次」＝4 次调用封顶');
    });

    test('cancel 即停，已完成批次的建议保留（token 不白花）', () async {
      late XrRefineRunner r;
      var calls = 0;
      r = XrRefineRunner(
          budgetChars: 40,
          pace: const Duration(milliseconds: 2),
          caller: (b) async {
            calls++;
            if (calls == 2) r.cancel();
            return {'remove': [b.first.name]};
          });
      await r.run(cands(12));
      expect(r.stage, XrRefineStage.cancelled);
      expect(r.doneBatches, lessThan(r.totalBatches));
      expect(r.suggestions.length, r.doneBatches);
    });
  });

  group('4 · 落库（三类动作各走既有通道 · 零迁移）', () {
    late Database db;
    late XrayDao dao;
    const md5 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: DbSchema.version));
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      dao = XrayDao(db);
      await db.insert(DbSchema.tBooks, {
        'id': 'bkA',
        'title': '书A',
        'md5': md5,
        'created_at': 1,
        'updated_at': 1,
      });
      await dao.writeRunResult(md5: md5, rows: [
        XrayWriteEntity(
            name: '几乎',
            type: 'term',
            n: 30,
            chs: 4,
            score: 2.0,
            channels: 1,
            tocFlag: false,
            aliases: const [],
            anchors: const [XrayMention(0, 3, '几乎如此')]),
        XrayWriteEntity(
            name: '玫瑰战争',
            type: 'term',
            n: 12,
            chs: 3,
            score: 1.5,
            channels: 1,
            tocFlag: false,
            aliases: const [],
            anchors: const [XrayMention(1, 2, '玫瑰战争起')]),
      ]);
    });

    tearDown(() async => db.close());

    test('删/改类/补 三类各归其位，库里没有的词只计跳过', () async {
      final c = await xrApplySuggestions(dao, md5, [
        XrRefineSuggestion(kind: XrRefineKind.remove, word: '几乎'),
        XrRefineSuggestion(kind: XrRefineKind.remove, word: '库里没有的词'),
        XrRefineSuggestion(
            kind: XrRefineKind.retype, word: '玫瑰战争', type: 'org'),
        XrRefineSuggestion(
            kind: XrRefineKind.retype, word: '玫瑰战争', type: 'xxx'),
        XrRefineSuggestion(kind: XrRefineKind.add, word: '波洛', type: 'per'),
      ]);
      expect(c.removed, 1);
      expect(c.retyped, 1);
      expect(c.added, 1);
      expect(c.skipped, 2, reason: '不存在实体 + 非法类型');

      final e = await dao.entityByName(md5, '几乎');
      expect(e!.status, 'deleted', reason: '删除走状态位，不是物理删行');
      final r = await dao.entityByName(md5, '玫瑰战争');
      expect(r!.type, 'org');
      final book = await db.query(DbSchema.tXrayUserdict,
          where: 'scope = ?', whereArgs: [md5]);
      expect(book.map((x) => x['word']), contains('玫瑰战争'),
          reason: '改类的登记落本书 scope');
      expect(await dao.listGlobalDict(), isEmpty, reason: '本书动作不污染全局');
      expect((await dao.allEntities(md5)).map((x) => x.name), contains('波洛'));
      expect((await dao.allEntities(md5)).map((x) => x.name),
          isNot(contains('几乎')), reason: '删除后列表不再出该词');
    });

    test('升级为全局：屏蔽进 GLOBAL 黑名单、补词登记成全局养成词', () async {
      final c = await xrApplySuggestions(dao, md5, [
        XrRefineSuggestion(kind: XrRefineKind.remove, word: '几乎'),
        XrRefineSuggestion(kind: XrRefineKind.add, word: '马普尔', type: 'per'),
      ], toGlobal: true);
      expect(c.removed, 1);
      expect(c.added, 1);
      final g = await dao.listGlobalDict();
      final keys = g.map((x) => '${x.word}/${x.action}').toSet();
      expect(keys, contains('几乎/forbid'));
      expect(keys, contains('马普尔/add'));
    });
  });
}
