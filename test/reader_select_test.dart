import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_sel_layer.dart'
    show brSelToolsDecode;

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

  /// [withSettingsRoute]＝给「阅读器设置」那条 `pushNamed('/read/settings?sec=5')`
  /// 挂一条桩路由（F-12 用例要跑真实的「推进设置页→改库→返回」往返；
  /// 其余用例不需要，保持原 `MaterialApp(home:)` 形态不受影响）。
  Widget wrap(Widget home, EpubDoc doc, {AiClient? ai, bool withSettingsRoute = false}) =>
      ProviderScope(
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
    child: withSettingsRoute
        ? MaterialApp.router(
            routerConfig: GoRouter(initialLocation: '/', routes: [
              GoRoute(path: '/', builder: (_, _) => home),
              GoRoute(
                  path: '/read/settings',
                  builder: (_, _) =>
                      const Scaffold(body: Text('ROUTE-STUB'))),
            ]),
          )
        : MaterialApp(home: home),
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

  /// 拦截 Clipboard.setData（同 log_page_test 手法），返回收集到的文本列表。
  List<String> mockClipboard(WidgetTester t) {
    final copied = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return copied;
  }

  Future<void> openReader(WidgetTester t, EpubDoc doc, String id,
      {AiClient? ai, bool settings = false}) async {
    await useSurface(t, const Size(420, 780));
    await repo.addBook(Book(
      id: id,
      title: '划词书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ));
    await t.pumpWidget(
        wrap(ReaderPage(bookId: id), doc, ai: ai, withSettingsRoute: settings));
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

  /// 轮4①：收集带底色 span 的文本（精确铺底的验表面；根样式无背景，只认子 span）。
  List<String> paintedTexts(WidgetTester t, String key) {
    final rt = t.widget<RichText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(RichText),
      ),
    );
    final out = <String>[];
    void walk(InlineSpan s) {
      if (s is! TextSpan) return;
      if (s.style?.backgroundColor != null && (s.text?.isNotEmpty ?? false)) {
        out.add(s.text!);
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
    walk(rt.text);
    return out;
  }

  /// 段 wrap Container 的底色（轮4① 后精确划线＝null，整段旧行＝非 null）。
  Color? containerColor(WidgetTester t, String tapKey) {
    final box = t.widget<Container>(
      find
          .descendant(
            of: find.byKey(ValueKey(tapKey)),
            matching: find.byType(Container),
          )
          .first,
    );
    return (box.decoration as BoxDecoration?)?.color;
  }

  /// 轮5①：拖选区手柄到目标段的某条边（tail＝下沿／head＝上沿），x＝段内横向比例。
  Future<void> dragHandle(
    WidgetTester t,
    String handle,
    String para, {
    required bool tail,
    double x = .5,
  }) async {
    final hr = t.getRect(find.byKey(ValueKey(handle)));
    final pr = t.getRect(find.byKey(ValueKey(para)));
    final gx = pr.left + pr.width * x;
    final gy = tail ? pr.bottom - 1 : pr.top + 1;
    await t.dragFrom(
      Offset(hr.center.dx, hr.center.dy),
      Offset(gx - hr.center.dx, gy - hr.center.dy),
    );
    await step(t);
  }

  group('批3-S · 选区与浮条', () {
    testWidgets('长按段落出浮条 · 点空隙收选区不误翻页', (t) async {
      await openReader(t, _doc(), 's1');
      await selectPara(t, 'brpTap-0-3');
      for (final k in ['brSelCopy', 'brSelHl', 'brSelQuote', 'brSelThink', 'brSelAi', 'brSelDict', 'brSelShare']) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
      // 轮5①：扩选改手柄拖动，工具条不再放前扩/后扩。
      for (final k in ['brGrowL', 'brGrowR']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      expect(find.byKey(const ValueKey('brHStart')), findsOne);
      expect(find.byKey(const ValueKey('brHEnd')), findsOne);
      // 再点段落空隙：选区收起，chrome 不误切（dispatch 优先清选区）。
      final r = t.getRect(find.byKey(const ValueKey('brpTap-0-3')));
      await t.tapAt(Offset(210, r.bottom + 5));
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
      expect(find.byKey(const ValueKey('br-bottom')), findsOne);
    });

    testWidgets('轮4③ 长按句首选首句 · 轮5① 手柄拖动扩到整段/跨段', (t) async {
      // V1.53.4④：本例语义＝选句档（长按命中整句），显式钉住粒度设置。
      await repo.setKv('read.brSelGran', '选句');
      await openReader(t, _doc(), 's2');
      final full = '三之0。$_lorem';
      final p4 = '三之1。$_lorem';
      await selectParaTop(t, 'brpTap-0-3');
      // 段首长按 → 精确命中首句「三之0。」（4 字）。
      final n1 = await copiedLen(t);
      expect(n1, '三之0。'.length);
      // 复制会收选区；再长按同处 → 同一句（确定性）。
      await selectParaTop(t, 'brpTap-0-3');
      expect(await copiedLen(t), n1);
      // 尾端手柄拖到本段下沿 → 选区吃满整段。
      await selectParaTop(t, 'brpTap-0-3');
await dragHandle(t, 'brHEnd', 'brpTap-0-3', tail: true);
      expect(await copiedLen(t), full.length);
      // 尾端手柄拖进下一段 → 跨段连选（中间一个换行）。
      await selectParaTop(t, 'brpTap-0-3');
      await dragHandle(t, 'brHEnd', 'brpTap-0-4', tail: true);
      expect(await copiedLen(t), full.length + 1 + p4.length);
      // 首端手柄反向拖到上一段段首 → 上一段整段并入（尾端仍是原首句）。
      await selectParaTop(t, 'brpTap-0-4');
      await dragHandle(t, 'brHStart', 'brpTap-0-3', tail: false, x: .02);
      expect(await copiedLen(t), full.length + 1 + '三之1。'.length);
      expect(find.byKey(const ValueKey('brSelBar')), findsNothing);
      await clearToasts(t);
    });

    testWidgets('真机反馈（2026-09-28）：段中选句不顶格重排 · 建选区即展开顶栏', (t) async {
      await openReader(t, _doc(), 's9');
      const para = '三之0。$_lorem';
      final fnd = find.byKey(const ValueKey('brpTap-0-3'));
      final r0 = t.getRect(fnd);
      // 末行中段长按 → 确定性命中第二句（a>0）；旧实现在这里丢 2em 缩进前缀，
      // 整段顶格重排（分页器却仍按带缩进测量 → 行数/高度都会变）。
      final rr = r0;
      await t.longPressAt(Offset(rr.left + rr.width * .5, rr.bottom - 5));
      await step(t);
      expect(find.byKey(const ValueKey('brSelBar')), findsOne);
      // ① 选区建立 → chrome 自动展开：书名/计时/搜索/设置随顶栏可见。
      expect(find.byKey(const ValueKey('br-top')), findsOne);
      expect(find.byKey(const ValueKey('br-sess-chip')), findsOne);
      expect(find.byKey(const ValueKey('brBtnSearch')), findsOne);
      expect(find.byKey(const ValueKey('brBtnMore')), findsOne);
      // ② 选中段显示文本仍带缩进前缀（与未选中完全一致 → 不重排）。
      final rt = t.widget<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('brp-0-3')),
          matching: find.byType(RichText),
        ),
      );
      final shown = rt.text.toPlainText();
      expect(shown.startsWith('\u3000\u3000'), isTrue, reason: '缩进前缀恒在');
      expect(shown, '\u3000\u3000$para');
      expect(t.getRect(fnd).height, r0.height, reason: '段落高度不因选区变化');
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
    // 真机反馈 F-12：在阅读器里改「阅读设置 → 选区工具条工具」再返回，工具条必须当场换名单。
    // 本例钉**数据面**（工具条严格按当前 `read.brSelBar` 渲染，改完重开即生效）；
    // 「从设置页返回这一动作会触发重读」的接线在 `onReadSet` 的 await-pop → `_reloadHls()`，
    // 桩路由在测试里推不动（go_router 的 push 在本夹具不生效），**由真机 6082 复验**。
    testWidgets('工具条名单按当前设置渲染（改完重开阅读器即生效）', (t) async {
      await repo.setKv('read.brSelBar', '复制,查询');
      await openReader(t, _doc(), 's15');
      await selectPara(t, 'brpTap-0-1');
      expect(find.byKey(const ValueKey('brSelCopy')), findsOne);
      expect(find.byKey(const ValueKey('brSelDict')), findsOne,
          reason: '进页时名单含「查询」');
      // 改名单（＝设置页落库的同一句 setKv），重开阅读器读到的就是新名单。
      await repo.setKv('read.brSelBar', '复制');
      await t.pumpWidget(wrap(const SizedBox.shrink(), _doc()));
      await step(t);
      await openReader(t, _doc(), 's15');
      await selectPara(t, 'brpTap-0-1');
      expect(find.byKey(const ValueKey('brSelCopy')), findsOne);
      expect(find.byKey(const ValueKey('brSelDict')), findsNothing,
          reason: '名单里已经没有「查询」，工具条不许再画它');
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
      // 轮4①：cf 带字符偏移落库，色底只铺所选字（span 级）；Container 不再整段涂。
      expect(q.cf!.o0, isNotNull, reason: 'cf 必须携带字符偏移');
      expect(q.cf!.o1, isNotNull);
      expect(paintedTexts(t, 'brp-0-3').join(), q.body);
      expect(containerColor(t, 'brpTap-0-3'), isNull,
          reason: '精确划线不得整段铺底');
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
      // 真机反馈⑤候选2补票：这条分支旧实现只断言了 kv，渲染从未被覆盖——
      // 轮4① 后暂存行同样带偏移，色底走 span 级精确铺底（Container 不整段涂）。
      expect(paintedTexts(t, 'brp-0-4').join(), isNotEmpty,
          reason: 'brSync 关的暂存划线也要真的铺上色底');
      expect(containerColor(t, 'brpTap-0-4'), isNull);
      await clearToasts(t);
    });

    testWidgets('真机反馈⑤A：删划线后重划同一句 → 重新入账并上色', (t) async {
      await openReader(t, _doc(), 's13');
      // 首划 → 入账
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-共鸣')));
      await step(t, ms: 300);
      expect(await repo.quotesOf('s13'), hasLength(1));
      await clearToasts(t);
      // 删划线（软删进垃圾箱）
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brDelHl')));
      await step(t, ms: 300);
      expect(await repo.quotesOf('s13'), isEmpty);
      await clearToasts(t);
      // 重划同一句：旧实现 dedup 撞软删行 → 返回 null 不入账 → 正文永不上色
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-重点')));
      await step(t, ms: 300);
      final qs = await repo.quotesOf('s13');
      expect(qs, hasLength(1), reason: '删后重划必须重新入账');
      expect(qs.single.cf, isNotNull);
      expect(paintedTexts(t, 'brp-0-3').join(), isNotEmpty,
          reason: '重划后正文必须上色（span 级）');
      expect(containerColor(t, 'brpTap-0-3'), isNull,
          reason: '轮4① 重划也不得整段铺底');
      await clearToasts(t);
    });

    testWidgets('真机反馈⑤B：在库书摘同句（无 cf）→ 划线补 cf 定位、不重复入账', (t) async {
      await openReader(t, _doc(), 's14');
      // 先按正常链路划一句，拿到「手抄摘录」将来要仿形的行内容
      await selectPara(t, 'brpTap-0-4');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-共鸣')));
      await step(t, ms: 300);
      final first = (await repo.quotesOf('s14')).single;
      await clearToasts(t);
      // 模拟用户更早手抄过同句：同 dedup 键、无 cf/rid 的在库行
      await db.update('book_quotes', {'cf': null, 'rid': null},
          where: 'id = ?', whereArgs: [first.id]);
      // 重开阅读器：无 cf 行不铺色（先证明「看不见底色」是撞车现场）
      await t.pumpWidget(wrap(const SizedBox.shrink(), _doc()));
      await step(t);
      await t.pumpWidget(wrap(ReaderPage(bookId: 's14'), _doc()));
      await step(t, times: 4);
      final r0 = t.getRect(find.byKey(const ValueKey('brpTap-0-4')));
      await t.tapAt(Offset(210, r0.bottom + 5));
      await step(t);
      expect(containerColor(t, 'brpTap-0-4'), isNull,
          reason: '无 cf 的书摘行不该铺色');
      // 再对同句划线：dedup 撞在库行 → 修法＝给该行补 cf 并提示已定位
      await selectPara(t, 'brpTap-0-4');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-重点')));
      await step(t, ms: 300);
      expect(find.textContaining('已在书摘中，已定位'), findsOne);
      final qs = await repo.quotesOf('s14');
      expect(qs, hasLength(1), reason: '撞车不新增行，只给已有行补 cf');
      expect(qs.single.cf, isNotNull);
      expect(qs.single.tag, '重点');
      expect(paintedTexts(t, 'brp-0-4').join(), isNotEmpty,
          reason: '补 cf 后当屏即上色（轮4① span 级精确铺底）');
      expect(containerColor(t, 'brpTap-0-4'), isNull);
      await clearToasts(t);
    });

    testWidgets('轮4① 段中选一句划线 → 只该句铺底，段内其余字干净（重开仍精确）', (t) async {
      // 真机反馈（图6）：选一句划线整段近满页涂色。根因＝cf 只存段区间。
      await repo.setKv('read.brSelGran', '选句');
      await openReader(t, _doc(), 's15');
      const para = '三之0。$_lorem';
      final r0 = t.getRect(find.byKey(const ValueKey('brpTap-0-3')));
      // 末行中段长按 → 确定性命中第二句（o0>0，首句与缩进前缀都不该带色）。
      await t.longPressAt(Offset(r0.left + r0.width * .5, r0.bottom - 5));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-共鸣')));
      await step(t, ms: 300);
      final q = (await repo.quotesOf('s15')).single;
      expect(q.body, _lorem);
      expect(q.cf!.o0, '三之0。'.length, reason: '偏移必须落库（变异校验点）');
      expect(q.cf!.o1, para.length);
      expect(paintedTexts(t, 'brp-0-3').join(), _lorem,
          reason: '底色只吃所选句，不含缩进前缀与首句');
      expect(containerColor(t, 'brpTap-0-3'), isNull,
          reason: '精确划线不得整段铺底');
      await clearToasts(t);
      // 重开阅读器：库内行重读后仍按字符区间铺底（不是整段）。
      await t.pumpWidget(wrap(const SizedBox.shrink(), _doc()));
      await step(t);
      await t.pumpWidget(wrap(ReaderPage(bookId: 's15'), _doc()));
      await step(t, times: 4);
      expect(paintedTexts(t, 'brp-0-3').join(), _lorem);
      expect(containerColor(t, 'brpTap-0-3'), isNull);
      await clearToasts(t);
    });

    testWidgets('轮4① 旧数据（cf 无偏移）→ 维持整段铺底旧行为', (t) async {
      await openReader(t, _doc(), 's16');
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelHl')));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brColor-共鸣')));
      await step(t, ms: 300);
      // 模拟 V1.59 轮4 前的存量行：抹掉偏移键（JSON 列内直改）。
      final q = (await repo.quotesOf('s16')).single;
      expect(q.cf!.isPrecise, isTrue);
      await db.update('book_quotes', {'cf': '{"c":0,"p0":3,"p1":3}'},
          where: 'id = ?', whereArgs: [q.id]);
      await t.pumpWidget(wrap(const SizedBox.shrink(), _doc()));
      await step(t);
      await t.pumpWidget(wrap(ReaderPage(bookId: 's16'), _doc()));
      await step(t, times: 4);
      expect(containerColor(t, 'brpTap-0-3'), isNotNull,
          reason: '旧行无偏移＝整段底色行为不许变（向后兼容）');
      expect(paintedTexts(t, 'brp-0-3'), isEmpty,
          reason: '整段口径不再叠 span 级底色');
      await clearToasts(t);
    });
  });

  group('治理backlog⑥ · 分享出处引用', () {
    // 工单 docs/治理backlog行为改工单-20260929.md ⑥：旧实现把**段序号**（sel.p0）
    // 喂给 _cfi 的页参数 → 引用尾段数值是段号而非页号，与书签/进度条（_pos.pg）口径
    // 错位。修复＝分享用当前页号（原型 index-bookshelf.html brShare 同步修正）。
    testWidgets('引用尾段＝当前页号 · 非段序号', (t) async {
      final copied = mockClipboard(t);
      await openReader(t, _doc(), 's10');
      // 翻到第 2 页（0 基 pg=1），选一段 pi≥2 的段落：
      // 旧实现尾段＝pi（≥2）≠1 → 本例必红；新实现＝当前页号 1。
      await t.tapAt(const Offset(412, 350));
      await step(t);
      await selectPara(t, 'brpTap-0-7');
      await t.tap(find.byKey(const ValueKey('brSelShare')));
      await step(t);
      expect(copied, hasLength(1));
      expect(copied.single, contains('· epub/2/2/1'),
          reason: '分享引用 CFI 尾段应为当前页号（与书签同口径）');
      expect(copied.single, contains('——《划词书》第一章'),
          reason: '脚注模板前缀不变（clipAuto 回读依赖 ——《书名》）');
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
      // V1.53.4④：默认档改「选字」后本例命中单字——下限从 4 收到 1。
      final body = t.widget<TextField>(find.byKey(const ValueKey('qef-body')));
      final txt = body.controller!.text;
      expect('三之0。$_lorem'.contains(txt), isTrue);
      expect(txt.length, inInclusiveRange(1, '三之0。$_lorem'.length - 1));
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
      // AI：默认总开关关 → 先二选一（V1.53.4②），选完仍由统一入口在通道内
      // toast 归因，阅读侧不再自建弹层。
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelAi')));
      await step(t, ms: 300, times: 2);
      expect(find.byKey(const ValueKey('sheetBrAiChoice')), findsOne);
      await t.tap(find.byKey(const ValueKey('brAiChoiceInsight')));
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
      // V1.53.4②：AI 解读先二选一；深度解读＝既有 read.quote_insight。
      await t.tap(find.byKey(const ValueKey('brSelAi')));
      await step(t, ms: 300, times: 2);
      expect(find.byKey(const ValueKey('sheetBrAiChoice')), findsOne);
      await t.tap(find.byKey(const ValueKey('brAiChoiceInsight')));
      await step(t, ms: 300, times: 2);
      // ① 发送前审阅弹层（内容由通道负责）。
      expect(find.byKey(const ValueKey('ai-review-send')), findsOne);
      expect(hits, 0, reason: '未确认前零请求');
      // V1.53.4③：System/User 默认折叠——正文盒不在树上（标题行预览只有 30 字）；
      // 点开 System 后全文才渲染。
      expect(
          find.byWidgetPredicate((w) =>
              w is SelectableText &&
              (w.data ?? '').contains('不空泛吹捧')),
          findsNothing);
      await t.tap(find.byKey(const ValueKey('ai-review-sys')));
      await step(t);
      expect(
          find.byWidgetPredicate((w) =>
              w is SelectableText &&
              (w.data ?? '').contains('不空泛吹捧')),
          findsOne);
      await t.tap(find.byKey(const ValueKey('ai-review-send')));
      await step(t, ms: 300, times: 3);
      // ② 请求一次 + 结果弹层渲染 insight（标题按模式 V1.53.4②）。
      expect(hits, 1);
      expect(find.byKey(const ValueKey('sheetBrAi')), findsOne);
      expect(find.text('AI 深度解读'), findsOne);
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

  group('V1.53.4① · 手柄跨页扩选（工单 20261001-①）', () {
    testWidgets('拖出页顶自动回翻同章上一页并延续扩选', (t) async {
      final copied = mockClipboard(t);
      await repo.setKv('read.brSelGran', '选句'); // 本例复验轮4③选句建选（与①无关）
      await openReader(t, _doc(), 's11');
      // 翻到第 2 页（s10 实测 brpTap-0-7 在第 2 页；过渡结束后首页段落应已卸载）。
      await t.tapAt(const Offset(412, 350));
      await step(t, ms: 300, times: 2);
      expect(find.byKey(const ValueKey('brpTap-0-7')), findsOne);
      expect(find.byKey(const ValueKey('brpTap-0-3')), findsNothing,
          reason: '已离开第 1 页');
      // 长按第 2 页段落首行 → 选句落定，首手柄出现。
      await selectParaTop(t, 'brpTap-0-7');
      // 首手柄拖过页文字区上沿 → 自动回翻一页（同章），选区吃进邻页交界段。
      final hr = t.getRect(find.byKey(const ValueKey('brHStart')));
      await t.dragFrom(hr.center, Offset(0, -(hr.center.dy - 40)));
      await step(t, ms: 300, times: 2);
      expect(find.byKey(const ValueKey('brpTap-0-3')), findsOne,
          reason: '已回翻到第 1 页');
      expect(find.byKey(const ValueKey('brpTap-0-7')), findsNothing,
          reason: '过渡结束后第 2 页应卸载（旧行为：端点冻住不翻页）');
      // 回翻后继续在新页上拖到「三之0」段首 → 扩选延续（旧行为会冻在页边）。
      await dragHandle(t, 'brHStart', 'brpTap-0-3', tail: false, x: .02);
      await t.tap(find.byKey(const ValueKey('brSelCopy')));
      await step(t);
      expect(copied, hasLength(1));
      expect(copied.single, contains('一之1。'), reason: '尾端原句保留');
      expect(copied.single, startsWith('三之0。'), reason: '跨页扩选延续到第 1 页段落');
      expect(copied.single, contains('\n'));
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

  group('V1.53.4②④⑤ · 长按粒度 / 工具条配置 / 解释链路', () {
    testWidgets('④ 默认选字：长按命中单字（复制恰 1 字）', (t) async {
      await openReader(t, _doc(), 't20');
      await selectParaTop(t, 'brpTap-0-3');
      expect(await copiedLen(t), 1, reason: '默认档＝选字，命中「三」');
      await clearToasts(t);
    });

    testWidgets('⑤ read.brSelBar 名单驱动显隐（划线,复制 → 只上两枚）', (t) async {
      expect(brSelToolsDecode(null), hasLength(9), reason: '未配置＝默认全量（V1.54 批B 加 X-Ray）');
      expect(brSelToolsDecode('划线,复制'), ['划线', '复制']);
      expect(brSelToolsDecode('不存在,复制'), ['复制'], reason: '野名字剔除');
      await repo.setKv('read.brSelBar', '划线,复制');
      await openReader(t, _doc(), 't21');
      await selectPara(t, 'brpTap-0-3');
      expect(find.byKey(const ValueKey('brSelHl')), findsOne);
      expect(find.byKey(const ValueKey('brSelCopy')), findsOne);
      expect(find.byKey(const ValueKey('brSelQuote')), findsNothing);
      expect(find.byKey(const ValueKey('brSelAi')), findsNothing);
      await clearToasts(t);
    });

    testWidgets('② 解释路径：read.explain 门控零请求→审阅→text 结果→前缀填感想', (t) async {
      await seedPrefs({
        'ai.master': true,
        'ai.caps': '{"read.explain":true}',
      });
      var hits = 0;
      await openReader(
        t,
        _doc(),
        't22',
        ai: AiClient(
          client: MockClient((req) async {
            hits++;
            return http.Response.bytes(
                utf8.encode(jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'content': '这是一段词句解释正文，释义背景与简析各给一句。'
                      }
                    }
                  ]
                })),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }),
        ),
      );
      await selectPara(t, 'brpTap-0-3');
      await t.tap(find.byKey(const ValueKey('brSelAi')));
      await step(t, ms: 300, times: 2);
      expect(find.byKey(const ValueKey('sheetBrAiChoice')), findsOne);
      await t.tap(find.byKey(const ValueKey('brAiChoiceExplain')));
      await step(t, ms: 300, times: 2);
      expect(find.text('发送给 AI · 词句解释'), findsOne);
      expect(find.byKey(const ValueKey('ai-review-send')), findsOne);
      expect(hits, 0, reason: '确认前零请求');
      await t.tap(find.byKey(const ValueKey('ai-review-send')));
      await step(t, ms: 300, times: 3);
      expect(hits, 1);
      expect(find.byKey(const ValueKey('sheetBrAi')), findsOne);
      expect(find.text('AI 解释'), findsOne);
      expect(find.textContaining('这是一段词句解释'), findsOne);
      await t.tap(find.byKey(const ValueKey('brAiToQuote')));
      await step(t, ms: 300, times: 3);
      final tf = t.widget<TextField>(find.byKey(const ValueKey('qef-thought')));
      expect(tf.controller!.text, startsWith('【AI 解释】'));
      await t.pageBack();
      await step(t, ms: 300, times: 3);
      await clearToasts(t);
    });
  });
}
