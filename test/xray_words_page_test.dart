import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/ai/ai_client.dart';
import 'package:lifeharness/core/ai/ai_providers.dart';
import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_vault.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/data/xray/xray_dao.dart';
import 'package:lifeharness/features/read/data/xray/xray_words_io.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/xray_words_page.dart';

import 'helpers.dart';

/// V1.54.1 批2 · X-Ray 词库管理页（GLOBAL 养成词库 CRUD＋启用开关）。
/// 独立文件铁律：全 app widget 用例不与他页同 isolate 混跑。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late XrayDao dao;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    dao = XrayDao(db);
  });
  tearDown(() => db.close());

  Future<ProviderContainer> openPage(WidgetTester t, {Widget? home}) async {
    await useSurface(t, const Size(420, 1600));
    await t.pumpWidget(ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        // AI 三件套 fake（ai_wire 族同款）：prefs 默认总开关关＝gate 稳定给拒绝原因，
        // 中心页门控行显示「未启用」，点开始＝提示零请求（R7 既有语义，不新造）。
        aiPromptPackProvider.overrideWithValue(const AiPromptPack(
            version: 1, defaultBaseUrl: '', defaultModel: '', tasks: [])),
        aiKeyVaultProvider.overrideWithValue(AiKeyVault.inMemory()),
        aiClientProvider.overrideWithValue(AiClient()),
      ],
      child: MaterialApp(home: home ?? const XrayWordsPage()),
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    return ProviderScope.containerOf(
        t.element(find.byType(XrayWordsPage)));
  }

  int rowCount(WidgetTester t) => find
      .byWidgetPredicate((w) =>
          w is Container &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('xrw-row-'))
      .evaluate()
      .length;

  testWidgets('空态与开关：默认开，翻转写 read.xrUserDict 并给反馈', (t) async {
    final c = await openPage(t);
    expect(find.text('还没有养成词 · 阅读中长按选词即可养入'), findsOne);
    final sw = t.widget<Switch>(find.byKey(const ValueKey('xrwToggle')));
    expect(sw.value, isTrue, reason: '养词库默认开');
    await t.tap(find.byKey(const ValueKey('xrwToggle')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(
        t.widget<Switch>(find.byKey(const ValueKey('xrwToggle'))).value,
        isFalse);
    expect(await repo.kv('read.xrUserDict'), 'false');
    expect(find.textContaining('纯预置视角'), findsWidgets);
    await clearToasts(t);
    // 再翻回来，开关语义双向可逆。
    await t.tap(find.byKey(const ValueKey('xrwToggle')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(await repo.kv('read.xrUserDict'), 'true');
    expect(c, isNotNull);
  });

  testWidgets('添加置顶＋重复守卫＋按书行不混入', (t) async {
    await dao.putUserWord(
        scope: 'OTHER_MD5', word: '按书词', action: 'add'); // 按书覆盖层
    final c = await openPage(t);
    await t.enterText(find.byKey(const ValueKey('xrwAddInp')), '沉没成本');
    await t.tap(find.byKey(const ValueKey('xrwAddGo')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(rowCount(t), 1, reason: 'GLOBAL 添加成功且按书行不出现');
    expect(find.text('沉没成本'), findsOne);
    expect((await dao.listGlobalDict()).map((r) => r.word), ['沉没成本']);
    // 重复添加＝守卫提示，不产生第二行。
    await clearToasts(t);
    await t.enterText(find.byKey(const ValueKey('xrwAddInp')), '沉没成本');
    await t.tap(find.byKey(const ValueKey('xrwAddGo')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(rowCount(t), 1);
    expect(find.textContaining('已在词库'), findsOne);
    expect(c, isNotNull);
  });

  testWidgets('改动作/删除/改名：三操作走 DAO 并回读', (t) async {
    await dao.putUserWord(scope: 'GLOBAL', word: '旧词', action: 'add', type: 'term');
    await openPage(t);
    expect(find.text('加词'), findsOne, reason: '动作徽标＝加词');
    // 改动作 → 屏蔽。
    await t.tap(find.byKey(const ValueKey('xrw-fl-0')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('屏蔽'), findsOne);
    expect((await dao.listGlobalDict()).first.action, 'forbid');
    // 改名。
    await t.tap(find.byKey(const ValueKey('xrw-rn-0')));
    await t.pump(const Duration(milliseconds: 200));
    await t.enterText(find.byKey(const ValueKey('xrwRenameIn')), '新词');
    await t.tap(find.byKey(const ValueKey('xrwRenameGo')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('新词'), findsOne);
    // 删除（确认弹层）。
    await t.tap(find.byKey(const ValueKey('xrw-del-0')));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byKey(const ValueKey('xrwDelGo')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(await dao.listGlobalDict(), isEmpty, reason: '词级删除只删该动作行');
    expect(find.textContaining('还没有养成词'), findsOne);
  });

  testWidgets('类型筛选：per/term 分桶计数与过滤', (t) async {
    await dao.putUserWord(scope: 'GLOBAL', word: '波洛', action: 'add', type: 'per');
    await dao.putUserWord(scope: 'GLOBAL', word: '认知负担', action: 'add', type: 'term');
    await openPage(t);
    expect(rowCount(t), 2);
    await t.tap(find.byKey(const ValueKey('xrw-tp-per')));
    await t.pump(const Duration(milliseconds: 150));
    expect(rowCount(t), 1);
    expect(find.text('波洛'), findsOne);
    expect(find.text('认知负担'), findsNothing);
    await t.tap(find.byKey(const ValueKey('xrw-tp-all')));
    await t.pump(const Duration(milliseconds: 150));
    expect(rowCount(t), 2);
  });

  testWidgets('批3 导入导出：导出落盘 + 导入预检确认后合并', (t) async {
    // 夹具建在用例体内（真实区），且一律用**同步**文件 API：
    // FakeAsync 下 `await createTemp`/`writeAsString` 永不返回＝用例挂死（先例见记忆）。
    final tmp = Directory.systemTemp.createTempSync('xrwords_page_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final inFile = File('${tmp.path}/in.xrwords')
      ..writeAsStringSync(jsonEncode({
        'v': 1,
        'kind': 'xrwords',
        'preset': {'id': 'x', 'files': {}},
        'entries': [
          {'word': '新词', 'action': 'add', 'type': 'per', 'ts': 1},
          {'word': '旧词', 'action': 'add', 'type': 'term', 'ts': 2},
        ],
      }));
    // 被测导出走真文件写（dir.create + writeAsString）：假异步泵不动，
    // 每轮等文案开一次真实事件循环（ledger_l15 / journal waitFinder 先例）。
    Future<void> pollContains(String needle, {int times = 50}) async {
      for (var i = 0; i < times; i++) {
        if (find.textContaining(needle).evaluate().isNotEmpty) return;
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 60));
      }
      fail('文案未出现：$needle');
    }

    await dao.putUserWord(scope: 'GLOBAL', word: '旧词', action: 'add', type: 'term');
    await t.pumpWidget(ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        // 钩子直通临时目录；预置词表同步读磁盘（指纹用，避开假异步）。
        xrayWordsIoProvider.overrideWith((ref) => XrayWordsIoService(
              ref.watch(xrayDaoProvider),
              docsOverride: tmp,
              saveAs: (src) async => src,
              pickFile: () async => inFile.path,
              readAsset: (p) async => File(p).readAsStringSync(),
            )),
      ],
      child: const MaterialApp(home: XrayWordsPage()),
    ));
    await pollContains('导出养成词库');
    // 导出：saveAs 直通 → toast 报条数，文件在临时目录。
    await t.tap(find.byKey(const ValueKey('xrwExp')));
    await pollContains('已导出 1 条');
    expect(Directory('${tmp.path}/xray_words').listSync(),
        isNotEmpty, reason: '导出文件落盘');
    await clearToasts(t);
    // 导入：预检弹层报 新增1/覆盖1 → 确认 → 合并 + 回读。
    await t.tap(find.byKey(const ValueKey('xrwImp')));
    await pollContains('新增 1 · 覆盖 1');
    await t.tap(find.byKey(const ValueKey('xrwImpGo')));
    await pollContains('导入完成 · 新增 1 · 覆盖 1 · 跳过 0');
    expect((await dao.listGlobalDict()).map((r) => r.word).toSet(),
        {'旧词', '新词'});
  });

  // ---- V1.59 批3 · 中心页三段同页（工单＝docs/handoff/交棒话术-20261003-XRay中心三段同页.md） ----

  Future<void> pumpFor(WidgetTester t, {int times = 8, int ms = 150}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  testWidgets('三 chips 同页：默认词条段·切段互不串·各段行齐', (t) async {
    await openPage(t);
    expect(find.text('X-Ray 中心'), findsOne, reason: '页标题按原型改「X-Ray 中心」');
    for (final k in ['xrc-t-word', 'xrc-t-ai', 'xrc-t-idx']) {
      expect(find.byKey(ValueKey(k)), findsOne);
    }
    expect(find.byKey(const ValueKey('xrwScroll')), findsOne,
        reason: '拍板②：默认段＝词条');
    // 段二：门控/范围/预算五档/开始/查看汇总齐。
    await t.tap(find.byKey(const ValueKey('xrc-t-ai')));
    await pumpFor(t);
    expect(find.byKey(const ValueKey('xrcAiScroll')), findsOne);
    expect(find.byKey(const ValueKey('xrcGateLbl')), findsOne);
    expect(find.text('未选书 · 点开始精化先选一本'), findsWidgets);
    for (final v in [1000, 2000, 3000, 5000, 8000]) {
      expect(find.byKey(ValueKey('xrcB-$v')), findsOne);
    }
    expect(find.byKey(const ValueKey('xrcAiGo')), findsOne);
    expect(find.byKey(const ValueKey('xrcAiRev')), findsOne);
    expect(find.text('未跑 · 逐批顺序请求，批间可暂停续跑（AI 未启用时点按只提示）'),
        findsOne, reason: '闲置明细行＝原型 xrcAiLast 同字');
    // 段三：索引面板/备份/重置三行＋范围三档＋脚注。
    await t.tap(find.byKey(const ValueKey('xrc-t-idx')));
    await pumpFor(t);
    expect(find.byKey(const ValueKey('xrcIdxScroll')), findsOne);
    for (final k in ['xrcIdxOpen', 'xrcBak', 'xrcReset', 'xrcR-page', 'xrcR-chapter', 'xrcR-book', 'xrcIdxFoot']) {
      expect(find.byKey(ValueKey(k)), findsOne);
    }
    // 回词条段：原 CRUD 面完整（行为零改动判据）。
    await t.tap(find.byKey(const ValueKey('xrc-t-word')));
    await pumpFor(t, times: 3);
    expect(find.byKey(const ValueKey('xrwToggle')), findsOne);
    await drainLogTimer(t);
  });

  testWidgets('拍板①：不带书点「开始精化」＝先弹书选择（枚举选择页，禁循环切）', (t) async {
    final b = await repo.addBook(Book(
      id: 'xrb1',
      title: '中心页书',
      author: '甲',
      createdAt: 1,
      updatedAt: 1,
      local: true,
      epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
    ));
    await openPage(t);
    await t.tap(find.byKey(const ValueKey('xrc-t-ai')));
    await pumpFor(t);
    await t.tap(find.byKey(const ValueKey('xrcAiGo')));
    await pumpFor(t);
    expect(find.byKey(const ValueKey('xrcBookSheet')), findsOne);
    expect(find.text(b.title), findsOne);
    // 选中之后进 _prepDoc（假路径指纹取数不发真请求），页面不崩、范围行仍显书名。
    await t.tap(find.byKey(ValueKey('xrcBook-${b.id}')));
    await pumpFor(t);
    expect(find.text('中心页书 · 0 条'), findsWidgets,
        reason: '选书后「本次范围」行带书（同一条行＝选书入口，不另造控件）');
    await drainLogTimer(t);
  });

  testWidgets('深链直达：initialSeg=idx 落索引备份段；词条段不受书影响', (t) async {
    await openPage(t, home: const XrayWordsPage(initialSeg: 'idx'));
    await pumpFor(t);
    expect(find.byKey(const ValueKey('xrcIdxScroll')), findsOne);
    expect(find.text('未解析'), findsOne);
    await drainLogTimer(t);
  });

  testWidgets('交付判据④：明细文本模板只许活在 xrRefineLogBlock（源码守护）', (t) async {
    // 两地各算一份迟早分叉——中心页文件里出现明细行模板即红（工单 §4 钉的闸）。
    final src = File('lib/features/read/presentation/xray_words_page.dart')
        .readAsStringSync();
    expect(src, contains('xrRefineLogBlock('),
        reason: '中心页必须走共用渲染函数');
    for (final tpl in ['已出建议 删', '· 本批 ', '用时 ']) {
      expect(src, isNot(contains(tpl)),
          reason: '明细模板「$tpl」不得在中心页再写一份（xrRefineLogBlock 独占）');
    }
  });
}
