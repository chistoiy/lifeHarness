import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/stats/read_stat_page.dart';
import 'package:lifeharness/features/settings/presentation/settings_page.dart';

/// UX 审计真机批 · 批3 实现面（U4 热力图默认视口与月份刻度／U10 固定栏目锁定态）。
/// 独立文件：全 app widget 用例混文件会 isolate 污染（AGENTS 门禁段）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

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

  final now = DateTime.now();
  int ms(int daysAgo) => now.millisecondsSinceEpoch - daysAgo * 86400000;

  Book bk(String id, String t, String st, {int pages = 100, int rp = 0}) => Book(
    id: id,
    title: t,
    author: '作者$t',
    state: st,
    pages: pages,
    readPages: rp,
    lastReadAt: ms(1),
    createdAt: ms(30),
    updatedAt: ms(1),
  );

  Widget scope(Widget home) => ProviderScope(
    overrides: [
      readRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(home: home),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> waitFinder(WidgetTester tester, Finder f,
      {int times = 15}) async {
    for (var i = 0; i < times; i++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
    }
    expect(f, findsOneWidget);
  }

  /// 开统计屏。视口取 500 宽：800 宽时全年 845px 内容几乎不用滚（测不出定位），
  /// 而 390 手机宽会先撞上目标卡「三枚按钮横排」的存量溢出（另案 U11 登记），
  /// 与本批判据无关，故取一个「内容比视口宽、又不触发那处旧伤」的中间值。
  Future<void> openStat(WidgetTester tester) async {
    await tester.pumpWidget(scope(const ReadStatPage()));
    await settle(tester);
    await waitFinder(tester, find.byKey(const ValueKey('rs-ctl')));
    await useSurface(tester, const Size(500, 2400));
    await settle(tester);
  }

  /// 热力图横向滚动件的位置与可视矩形（刻度枚一定在其中，拿它当探针最稳）。
  ScrollPosition heatPos(WidgetTester tester, {String label = 'rs-heat-m1'}) =>
      Scrollable.of(tester.element(find.byKey(ValueKey(label)))).position;

  Rect heatView(WidgetTester tester, {String label = 'rs-heat-m1'}) =>
      tester.getRect(
        find
            .ancestor(
              of: find.byKey(ValueKey(label)),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );

  bool inView(Rect cell, Rect view) =>
      cell.right > view.left + 1 && cell.left < view.right - 1;

  group('U4 阅读热力图：默认视口定位＋月份刻度', () {
    testWidgets('当年全年＝进屏即离开 1 月，今天那一格落在可视区内', (tester) async {
      await repo.addBook(bk('u4a', '甲本', Book.kStateReading, rp: 20));
      await repo.addManualSession(
        day: now,
        bookId: 'u4a',
        minutes: 40,
        fromPage: 0,
        toPage: 10,
      );
      await openStat(tester);
      final doy = now.difference(DateTime(now.year)).inDays;
      final cell = find.byKey(ValueKey('rs-heat-$doy'));
      expect(cell, findsOneWidget);
      expect(heatPos(tester).pixels, greaterThan(0));
      expect(inView(tester.getRect(cell), heatView(tester)), isTrue);
      // 旧缺陷现场＝1 月那列被滚出屏外（视口不再从头开始）。
      expect(
        inView(
          tester.getRect(find.byKey(const ValueKey('rs-heat-0'))),
          heatView(tester),
        ),
        isFalse,
      );
    });

    testWidgets('全年档 12 枚月份刻度 · 节距与周列一致 · 切月只剩该月一枚',
        (tester) async {
      await repo.addBook(bk('u4b', '乙本', Book.kStateReading, rp: 20));
      await repo.addManualSession(
        day: now,
        bookId: 'u4b',
        minutes: 30,
        fromPage: 0,
        toPage: 6,
      );
      await openStat(tester);
      final first = DateTime(now.year);
      for (var m = 1; m <= 12; m++) {
        expect(
          find.byKey(ValueKey('rs-heat-m$m')),
          findsOneWidget,
          reason: '全年档应有 12 枚月份刻度',
        );
      }
      // 刻度落在「该月首日的周列」上：节距＝格宽 13＋间隙 3＝16px。
      final l1 = tester.getTopLeft(find.byKey(const ValueKey('rs-heat-m1')));
      final l2 = tester.getTopLeft(find.byKey(const ValueKey('rs-heat-m2')));
      final expectDx =
          (DateTime(now.year, 2).difference(first).inDays ~/ 7) * 16.0;
      expect(l2.dx - l1.dx, closeTo(expectDx, 0.6));
      // 切月：只剩该月一枚，且该月格子仍在原位（淡显口径未动）。
      await tester.tap(find.byKey(const ValueKey('rs-ctl')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('rs-m-${now.month}')));
      await settle(tester);
      expect(find.byKey(ValueKey('rs-heat-m${now.month}')), findsOneWidget);
      for (final m in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]) {
        if (m == now.month) continue;
        expect(find.byKey(ValueKey('rs-heat-m$m')), findsNothing);
      }
    });

    testWidgets('往年＝视口左缘贴该年第一个有数据的列（不从头摆烂）',
        (tester) async {
      final y = now.year - 2;
      await repo.addBook(bk('u4c', '丙本', Book.kStateDone, rp: 100));
      final day = DateTime(y, 9, 20);
      await repo.addManualSession(
        day: day,
        bookId: 'u4c',
        minutes: 55,
        fromPage: 0,
        toPage: 20,
      );
      await openStat(tester);
      await tester.tap(find.byKey(const ValueKey('rs-ctl')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('rs-y-$y')));
      await settle(tester);
      final col = day.difference(DateTime(y)).inDays ~/ 7;
      final pos = heatPos(tester);
      expect(pos.pixels, greaterThan(0));
      expect(
        pos.pixels,
        lessThanOrEqualTo(pos.maxScrollExtent + 0.5),
        reason: '定位值必须夹在可滚范围内',
      );
      expect(
        inView(
          tester.getRect(find.byKey(ValueKey('rs-heat-${col * 7}'))),
          heatView(tester),
        ),
        isTrue,
      );
    });
  });

  group('U11 目标卡三枚按钮：窄屏不溢出', () {
    testWidgets('390 宽下三枚按钮全在屏内且布局零溢出', (tester) async {
      await repo.addBook(bk('u5', '丁本', Book.kStateDone, rp: 100));
      await tester.pumpWidget(scope(const ReadStatPage()));
      await settle(tester);
      await waitFinder(tester, find.byKey(const ValueKey('rs-ctl')));
      await useSurface(tester, const Size(390, 2400));
      await settle(tester);
      // 旧写法（默认尺寸 OutlinedButton × 3 硬排一行）在这里必炸 RenderFlex overflow。
      expect(tester.takeException(), isNull, reason: 'U11：布局溢出即失败');
      for (final k in ['rs-weekly', 'rs-year', 'rs-goal-edit']) {
        final f = find.byKey(ValueKey(k));
        expect(f, findsOneWidget, reason: '缺按钮 $k');
        final r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(-0.5));
        expect(r.right, lessThanOrEqualTo(390.5), reason: '$k 出屏右缘');
      }
    });
  });

  group('U10 底栏栏目：锚栏目可关其一（2026-10-15 产品改口）', () {
    Widget grid(UserSettings s) => ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 360, child: NavToggleGrid(settings: s)),
        ),
      ),
    );

    Switch sw(WidgetTester t, String id) =>
        t.widget<Switch>(find.byKey(ValueKey('nav-sw-$id')));

    testWidgets('开关值如实反映偏好；锚栏目也可点（不再常开不可点）', (tester) async {
      await tester.pumpWidget(
        grid(
          const UserSettings(
            themeId: 'default',
            mode: ThemeModeOption.system,
            navIds: ['todo', 'calendar'],
          ),
        ),
      );
      await settle(tester);
      for (final id in ['today', 'settings']) {
        expect(sw(tester, id).value, isFalse,
            reason: '$id 不在 navIds 里就该如实画成「关」（旧口径是强画成开）');
        expect(sw(tester, id).onChanged, isNotNull, reason: '$id 不再是不可点');
      }
      expect(sw(tester, 'todo').value, isTrue);
      expect(sw(tester, 'todo').onChanged, isNotNull);
      expect(sw(tester, 'ledger').value, isFalse);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.textContaining('（固定）'), findsNothing,
          reason: '「（固定）」标签随旧口径一起退役');
    });

    testWidgets('导航自定义卡默认折叠（省屏），点标题行展开/收起', (tester) async {
      // 产品 2026-10-15：11 枚开关铺开要占 6 行，把整页顶下去一大截 ⇒ 默认只留一行摘要。
      tester.view.physicalSize = const Size(1200, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: Scaffold(body: NavCustomizeCard(flat: false)),
        ),
      ));
      await settle(tester);

      // 收起态：网格不在，但摘要行在（不开也能看出当前启用几个）。
      expect(find.byKey(const ValueKey('nav-sw-today')), findsNothing,
          reason: '默认折叠：开关网格不许直接铺出来');
      expect(find.textContaining('已启用'), findsOneWidget);
      expect(find.textContaining('至少要留一个'), findsNothing,
          reason: '折叠时连说明行一起收走，才真的省屏');

      await tester.tap(find.byKey(const ValueKey('nav-customize-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('nav-sw-today')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-sw-settings')), findsOneWidget);
      expect(find.textContaining('至少要留一个'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-customize-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('nav-sw-today')), findsNothing,
          reason: '再点应收回');
    });

    testWidgets('今天/我的 在 navIds 里时读成开（与壳层实际渲染一致）', (tester) async {
      await tester.pumpWidget(
        grid(
          const UserSettings(
            themeId: 'default',
            mode: ThemeModeOption.system,
            navIds: ['today', 'todo', 'calendar', 'journal', 'settings'],
          ),
        ),
      );
      await settle(tester);
      expect(sw(tester, 'today').value, isTrue);
      expect(sw(tester, 'settings').value, isTrue);
      expect(sw(tester, 'ledger').value, isFalse);
    });
  });
}
