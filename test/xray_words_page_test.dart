import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/data/xray/xray_dao.dart';
import 'package:lifeharness/features/read/data/xray/xray_words_io.dart';
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

  Future<ProviderContainer> openPage(WidgetTester t) async {
    await useSurface(t, const Size(420, 1600));
    await t.pumpWidget(ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: XrayWordsPage()),
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
}
