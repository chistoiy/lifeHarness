import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/ai/ai_client.dart' show AiClient;
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_quote.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader_page.dart';

import 'helpers.dart';

// V1.50 批3 · 划词与同库（选区/七操作/划线入库 cf·rid/删除互清/brSync 暂存/
// 词典/感想预填/AI 门控/全书检索双入口）。独立文件；IO 全走 loader override。
const _lorem = '这是划词实测正文素材，默认字号下约两到三行。';

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

EpubDoc _doc() => EpubDoc(
  format: 'EPUB3',
  title: '划词书',
  author: '甲',
  toc: const [],
  chapters: [
    EpubChapter(
      href: 'c1',
      title: '第一章',
      paras: [
        const EpubPara(kind: EpubParaKind.heading, text: '第一章', headingLevel: 1),
        _p('第一段。$_lorem'),
        _p('锚定效应贯穿全书。$_lorem'),
        _p('三之0。$_lorem'),
        _p('三之1。$_lorem'),
        // 轮4③：拉丁长段（无句读）→ 验证词边界回落。放首页可及处。
        _p(
          'This rather long English sentence exists to prove the Latin '
          'fallback: when a paragraph carries no CJK punctuation at all the '
          'selection still snaps to word boundaries instead of swallowing '
          'the entire block of text wholesale.',
        ),
        ...List.generate(10, (i) => _p('一之$i。$_lorem')),
      ],
    ),
    EpubChapter(
      href: 'c2',
      title: '第二章',
      paras: [
        const EpubPara(kind: EpubParaKind.heading, text: '第二章', headingLevel: 1),
        ...List.generate(20, (i) => _p('二之$i。$_lorem')),
      ],
    ),
  ],
  imageCount: 0,
  totalChars: 4000,
);

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;
  // 统一入口 aiRunWithReview 会先校验能力点已注册 → 默认用真提示词包。
  final pack = AiPromptPack.decode(
      File('assets/ai_prompts/prompts.json').readAsStringSync());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  Widget wrap(Widget home, EpubDoc doc, {AiClient? ai}) => ProviderScope(
    overrides: [
      readRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
      epubDocLoaderProvider.overrideWithValue((_) async => doc),
      // 真提示词包 + 内存 Key（默认未授权、master 默认关 → 门控拒绝零请求）。
      aiPromptPackProvider.overrideWithValue(pack),
      aiKeyVaultProvider.overrideWithValue(
          ai == null ? AiKeyVault.inMemory() : AiKeyVault.inMemory(apiKey: 'sk-t')),
      // 接通统一入口的用例注入 MockClient（零真实网络）；不传＝用默认实现。
      if (ai != null) aiClientProvider.overrideWithValue(ai),
    ],
    child: MaterialApp(home: home),
  );

  /// 换一套 SharedPreferences 种子（AI 开关类用例需在测试内改 pref）。
  Future<void> seedPrefs(Map<String, Object> m) async {
    SharedPreferences.setMockInitialValues(m);
    prefs = await SharedPreferences.getInstance();
  }

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> openReader(WidgetTester t, EpubDoc doc, String id,
      {AiClient? ai}) async {
    await useSurface(t, const Size(420, 780));
    await repo.addBook(Book(
      id: id,
      title: '划词书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ));
    await t.pumpWidget(wrap(ReaderPage(bookId: id), doc, ai: ai));
    await step(t, times: 4);
    // 段落空隙带点 chrome（段内长按才是划词，点按只走 body 分派）。
    final r = t.getRect(find.byKey(const ValueKey('brpTap-0-2')));
    await t.tapAt(Offset(210, r.bottom + 5));
    await step(t);
    expect(find.byKey(const ValueKey('br-bottom')), findsOne);
  }

  Future<void> selectPara(WidgetTester t, String key) async {
    // V1.53 轮3：长按段落下摘抄工具条（点按已改为冒泡收放 chrome）。
    // 轮4③：长按默认命中一句（落点＝段中心）。
    await t.longPress(find.byKey(ValueKey(key)));
    await step(t);
    expect(find.byKey(const ValueKey('brSelBar')), findsOne);
  }

  /// 轮4③：长按段首行左缘 → 确定性命中首句。
  Future<void> selectParaTop(WidgetTester t, String key) async {
    final r = t.getRect(find.byKey(ValueKey(key)));
    await t.longPressAt(Offset(r.left + 12, r.top + 5));
    await step(t);
    expect(find.byKey(const ValueKey('brSelBar')), findsOne);
  }

  /// 当前选区文本（工具条「复制」不弹 toast 场景不便，这里直接读渲染段）。
  /// 段 wrap 内 Text.rich 全文＝显示文本（含缩进），选中子串长度另经复制测得。
  Future<int> copiedLen(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('brSelCopy')));
    await step(t);
    final toast = t.widgetList<Text>(find.byType(Text)).firstWhere(
      (w) => (w.data ?? '').startsWith('已复制 '),
      orElse: () => const Text(''),
    );
    final m = RegExp(r'已复制 (\d+) 字').firstMatch(toast.data ?? '');
    await clearToasts(t);
    return m == null ? -1 : int.parse(m.group(1)!);
  }

  group('批3-S · 选区与浮条', () {
    testWidgets('长按段落出浮条 · 点空隙收选区不误翻页', (t) async {
      await openReader(t, _doc(), 's1');
      await selectPara(t, 'brpTap-0-3');
      for (final k in ['brGrowL', 'brSelCopy', 'brSelHl', 'brSelQuote', 'brSelThink', 'brSelAi', 'brSelDict', 'brSelShare', 'brGrowR']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      // 再点段落空隙：选区收起，chrome 不误切（dispatch 优先清选区）。
      final r = t.getRect(find.byKey(const ValueKey('brpTap-0-3')));
      await t.tapAt(Offset(210, r.bottom + 5));
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
      expect(find.byKey(const ValueKey('br-bottom')), findsOne);
    });

    testWidgets('轮4③ 长按句首选首句 · 后扩按句推进', (t) async {
      await openReader(t, _doc(), 's2');
      final full = '三之0。$_lorem';
      await selectParaTop(t, 'brpTap-0-3');
      // 段首长按 → 精确命中首句「三之0。」（4 字）。
      final n1 = await copiedLen(t);
      expect(n1, '三之0。'.length);
      // 复制后选区已收；再长按段首 → 同一句（确定性）。
      await selectParaTop(t, 'brpTap-0-3');
      expect(await copiedLen(t), n1);
      // 后扩一次＝补到下一句（不越过整段）。
      await selectParaTop(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brGrowR')));
      await step(t);
      final got2 = await copiedLen(t);
      expect(got2, full.length);
      // 再后扩＝本段用尽 → 跨段吞下「三之1。」整段（含换行连接）。
      await selectParaTop(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brGrowR')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brGrowR')));
      await step(t);
      expect(await copiedLen(t), full.length + '三之1。$_lorem'.length + 1);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
      await clearToasts(t);
    });

    testWidgets('轮4③ 拉丁长段无句读 → 词边界回落（不吃整段）', (t) async {
      await openReader(t, _doc(), 's8');
      const latin =
          'This rather long English sentence exists to prove the Latin '
          'fallback: when a paragraph carries no CJK punctuation at all the '
          'selection still snaps to word boundaries instead of swallowing '
          'the entire block of text wholesale.';
      final fnd = find.byKey(const ValueKey('brpTap-0-4'));
      expect(fnd, findsOne, reason: '拉丁段应在首页');
      await t.longPress(fnd);
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsOne);
      final n = await copiedLen(t);
      expect(n, greaterThan(0));
      expect(n, lessThan(latin.length), reason: '只选一个词组范围，非整段');
    });
  });

  group('批3-S · 划线⇄摘录同源', () {
    testWidgets('选色即入库：kind/tag/cf/rid/origin 全量断言 + 色底渲染', (t) async {
      await openReader(t, _doc(), 's3');
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      expect(find.byKey(const ValueKey('brColorPop')), findsOne);
      expect(find.byKey(const ValueKey('brDelHl')), findsOne);
      await t.tap(find.byKey(const ValueKey('brColor-共鸣')));
      await step(t, ms: 300);
      expect(find.textContaining('已划线（共鸣）'), findsOne);
      expect(find.textContaining('高亮即一条划线书摘'), findsOne);
      final qs = await repo.quotesOf('s3');
      expect(qs, hasLength(1));
      final q = qs.first;
      expect(q.kind, BookQuote.kKindMark);
      expect(q.tag, '共鸣');
      expect(q.rid, startsWith('r'));
      expect(q.origin, '阅读器');
      // 轮4③：长按默认命中一句 → body 是整段的真子串（句粒度）。
      final full3 = '三之0。$_lorem';
      expect(q.body, isNotEmpty);
      expect(full3.contains(q.body), isTrue);
      expect(q.body.length, lessThan(full3.length + 1));
      expect(q.chapter, '第一章');
      expect(q.cf!.covers(0, 3), isTrue);
      expect(q.cf!.covers(0, 4), isFalse);
      // 色底：该段 wrap Container 有非空底色装饰。
      final box = t.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('brpTap-0-3')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration?)?.color, isNotNull);
      await clearToasts(t);

      // 删除互清：再选同段 → 删划线 → 书摘行软删（quotesOf 不再返回）。
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brDelHl')));
      await step(t, ms: 300);
      expect(find.textContaining('已删除划线'), findsOne);
      expect(await repo.quotesOf('s3'), isEmpty);
      await clearToasts(t);
    });

    testWidgets('brSync 关：划线暂存 kv 不落库，仍照常上色', (t) async {
      await repo.setKv('read.brSync', 'false');
      await openReader(t, _doc(), 's4');
      await selectPara(t, 'brpTap-0-4');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-重点')));
      await step(t, ms: 300);
      expect(await repo.quotesOf('s4'), isEmpty);
      final raw = await repo.kv('reader.hl');
      expect(raw, isNotNull);
      final list = jsonDecode(raw!) as List;
      expect(list.single['tg'], '重点');
      expect((list.single as Map)['c'], 0);
      await clearToasts(t);
    });
  });

  group('批3-S · 表单/AI/词典', () {
    testWidgets('感想预填：原文框=选区文本 · 想法框空且聚焦，返回后选区已收', (t) async {
      await openReader(t, _doc(), 's5');
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelThink')));
      await step(t, ms: 300, times: 2);
      // 原型 brToThink：选区落「原文摘录」框，焦点落想法框（想法框留空待录）。
      // 轮4③：选区＝长按命中的一句（严格短于整段）。
      final body = t.widget<TextField>(find.byKey(const ValueKey('qef-body')));
      final txt = body.controller!.text;
      expect('三之0。$_lorem'.contains(txt), isTrue);
      expect(txt.length, inInclusiveRange(4, '三之0。$_lorem'.length - 1));
      final tf = t.widget<TextField>(find.byKey(const ValueKey('qef-thought')));
      expect(tf.controller!.text, isEmpty);
      expect(tf.autofocus, isTrue);
      await t.pageBack();
      await step(t, ms: 300, times: 3);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
    });

    testWidgets('词典命中「锚定」→ AI 未开总开关给门控提示', (t) async {
      await openReader(t, _doc(), 's6');
      // 轮4③：长按段首命中含「锚定」的首句。
      await selectParaTop(t, 'brpTap-0-2');
      await t.tap(find.byKey(const ValueKey('brSelDict')));
      await step(t, ms: 400);
      expect(find.byKey(const ValueKey('sheetBrDict')), findsOne);
      expect(find.textContaining('ān dìng'), findsOne);
      await t.tapAt(const Offset(210, 60));
      await step(t, ms: 400);
      expect(find.byKey(const ValueKey('sheetBrDict')), findsNothing);
      // AI：默认总开关关 → 统一入口在通道内 toast 归因，阅读侧不再自建弹层。
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelAi')));
      await step(t, ms: 300, times: 3);
      expect(find.textContaining('AI 未启用'), findsOne);
      expect(find.byKey(const ValueKey('sheetBrAi')), findsNothing);
      expect(find.byKey(const ValueKey('ai-review-send')), findsNothing);
      await clearToasts(t);
    });

    testWidgets('R7 接入门：AI 解读走 aiRunWithReview（审阅→MockClient→结果弹层）', (t) async {
      await seedPrefs({
        'ai.master': true,
        'ai.caps': '{"read.quote_insight":true}',
      });
      var hits = 0;
      await openReader(
        t,
        _doc(),
        's9',
        ai: AiClient(
          client: MockClient((req) async {
            hits++;
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'content':
                            '{"insight":"这段把犹豫写成行动，适合做排期评审的开场。","tags":["决断"]}'
                      }
                    }
                  ],
                  'usage': {'prompt_tokens': 10, 'completion_tokens': 20},
                }),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelAi')));
      await step(t, ms: 300, times: 2);
      // ① 发送前审阅弹层（内容由通道负责）。
      expect(find.byKey(const ValueKey('ai-review-send')), findsOne);
      expect(hits, 0, reason: '未确认前零请求');
      await t.tap(find.byKey(const ValueKey('ai-review-send')));
      await step(t, ms: 300, times: 3);
      // ② 请求一次 + 结果弹层渲染 insight。
      expect(hits, 1);
      expect(find.byKey(const ValueKey('sheetBrAi')), findsOne);
      expect(find.textContaining('排期评审的开场'), findsOne);
      await t.tap(find.byKey(const ValueKey('brAiToQuote')));
      await step(t, ms: 300, times: 3);
      // ③ 「填为感想」仍落到摘录编辑页（原语义不变）。
      final tf = t.widget<TextField>(find.byKey(const ValueKey('qef-thought')));
      expect(tf.controller!.text, contains('【AI 解读】'));
      await t.pageBack();
      await step(t, ms: 300, times: 3);
      await clearToasts(t);
    });
  });

  testWidgets('批3-S · 全书检索：输入即搜→点命中→跳原文挂上/下一处', (t) async {
    await openReader(t, _doc(), 's7');
    await t.tap(find.byKey(const ValueKey('brBtnSearch')));
    await step(t, ms: 300, times: 2);
    await t.enterText(find.byKey(const ValueKey('brSq')), '二之7。');
    // 轮4②：检索防抖 260ms → 多帧后再断言。
    await step(t, times: 3);
    expect(find.byKey(const ValueKey('brSInfo')), findsOne);
    expect(t.widget<Text>(find.byKey(const ValueKey('brSInfo'))).data, contains('命中 1 处'));
    await t.tap(find.byKey(const ValueKey('brSHit-0')));
    await step(t, ms: 300, times: 2);
    // 回阅读页：命中条在 + 已跳到第二章首页附近。
    expect(find.byKey(const ValueKey('brHitsBar')), findsOne);
    expect(find.textContaining('处匹配'), findsOne);
  });
}
