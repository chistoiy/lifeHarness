import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart'
    show calendarTickerProvider;
import 'package:lifeharness/features/media/presentation/media_providers.dart'
    show mediaTimerBarVisibleProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/stats/read_timer_page.dart';
import 'package:lifeharness/shared/linkage/timer_bar_overlay.dart';

/// 阅读模块批2 · 交付链与导航常驻用例（F2-5 悬浮条占位 / F2-6 双退出收敛）。
///
/// 规格＝`docs/handoff/阅读模块-冻结版开发方案-20261013.md` §2.2，
/// 用例清单＝`docs/handoff/交棒话术-20261014-阅读模块批2交付链与状态层.md` §0.3。
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

  final now = DateTime.now().millisecondsSinceEpoch;

  Book bk(String id, String t) => Book(
        id: id,
        title: t,
        author: '作者$t',
        state: Book.kStateReading,
        pages: 100,
        readPages: 0,
        lastReadAt: now,
        createdAt: now,
        updatedAt: now,
      );

  // ---------------- F2-5 悬浮条占位 ----------------

  /// 装配壳层同款悬浮条 + 一枚量尺（量尺位置＝壳内容顶）。
  /// 外套 `Scaffold`＝条内 `InkWell`（■ 结束）要 `Material` 祖先，与真壳同构。
  /// 量尺取满宽（`SizedBox.expand`）：Stack 在松约束下按子件尺寸收缩，
  /// 不给满宽的话条会被压到 80px 宽。
  ///
  /// `calendarTickerProvider`（条内的 1s `Stream.periodic` 分钟级刷新）在此**换成空流**：
  /// 它与 F2-5 的预留契约无关，留着只会踩「A Timer is still pending」
  /// （`media_timer_page_test` 用「当场拆容器」解同一题）。
  Widget shell({required bool readOn, required bool mediaOn}) => ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          readTimerBarVisibleProvider.overrideWith((ref) async => readOn),
          mediaTimerBarVisibleProvider.overrideWithValue(mediaOn),
          calendarTickerProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TimerBarOverlay(
              child: SizedBox.expand(key: ValueKey('probe')),
            ),
          ),
        ),
      );

  Future<void> bootShell(
    WidgetTester tester, {
    required bool readOn,
    required bool mediaOn,
  }) async {
    await useSurface(tester, const Size(400, 800));
    await tester.pumpWidget(shell(readOn: readOn, mediaOn: mediaOn));
    await tester.pumpAndSettle();
    // provider 解析（可见位 + runningSession 的 sqflite 往返）要混真事件循环才推进。
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  /// 安全区顶（测试窗口默认 0，仍按现场取，避免写死）。
  double topPadOf(WidgetTester tester) =>
      MediaQuery.paddingOf(tester.element(find.byType(TimerBarOverlay))).top;

  double probeTop(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('probe'))).top;

  testWidgets('F2-5 无条在跑：壳内容零占位（旧行为不变）', (tester) async {
    await bootShell(tester, readOn: false, mediaOn: false);
    expect(probeTop(tester), closeTo(0, .01), reason: '条不在场 ⇒ 不垫空间');
    expect(find.byKey(const ValueKey('read-bar')), findsNothing);
    expect(find.byKey(const ValueKey('media-bar')), findsNothing);
    await drainLogTimer(tester);
  });

  testWidgets('F2-5 单条在跑：壳内容按「落点 + 条高」预留，首卡不再被压住', (tester) async {
    await repo.addBook(bk('b1', '原子习惯'));
    await repo.startSession('b1');
    await bootShell(tester, readOn: true, mediaOn: false);
    expect(find.byKey(const ValueKey('read-bar')), findsOneWidget,
        reason: '在跑＝胶囊条真渲染');
    final topPad = topPadOf(tester);
    expect(
      probeTop(tester),
      closeTo(topPad + kTimerBarTopOffset + kTimerBarHeight, .01),
      reason: 'F2-5：条可见时内容下移等量，首卡不被条压住',
    );
    final barTop = tester.getRect(find.byKey(const ValueKey('read-bar'))).top;
    expect(barTop, closeTo(topPad + kTimerBarTopOffset, .01),
        reason: '条落点＝安全区 + 60（让过页面自带顶栏）');
    // 条底不越过内容顶（预留量正好等于条占位）。
    expect(
      tester.getRect(find.byKey(const ValueKey('read-bar'))).bottom,
      lessThanOrEqualTo(probeTop(tester) + .01),
      reason: '预留量必须 ≥ 条占位，否则首卡仍被压',
    );
    await drainLogTimer(tester);
  });

  testWidgets('F2-5 两条并存：预留加一档（含条间距）', (tester) async {
    // 影音条自身的渲染面由 `media_timer_page_test` 覆盖；本例只钉 F2-5 的
    // 预留契约＝按「在场条数」加档，两条并存时多算一条条高 + 一段间距。
    await repo.addBook(bk('b1', '原子习惯'));
    await repo.startSession('b1');
    await bootShell(tester, readOn: true, mediaOn: true);
    expect(find.byKey(const ValueKey('read-bar')), findsOneWidget);
    final topPad = topPadOf(tester);
    expect(
      probeTop(tester),
      closeTo(
          topPad + kTimerBarTopOffset + 2 * kTimerBarHeight + kTimerBarGap, .01),
      reason: '两条并存＝条高×2 + 间距',
    );
    await drainLogTimer(tester);
  });

  // ---------------- F2-6 双退出收敛 ----------------

  testWidgets('F2-6 计时页只有一枚退出钮：rt-back 在 · rt-collapse 已摘除',
      (tester) async {
    await repo.addBook(bk('b1', '胶囊书'));
    await useSurface(tester, const Size(400, 900));

    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (_, _) => Scaffold(
            body: Center(
              child: Builder(
                builder: (c) => FilledButton(
                  key: const ValueKey('go-timer'),
                  onPressed: () => c.push('/read/timer/b1'),
                  child: const Text('开计时页'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/read/timer/:id',
          builder: (_, s) => ReadTimerPage(bookId: s.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        readRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('go-timer')));
    await tester.pumpAndSettle();

    expect(find.byType(ReadTimerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('rt-back')), findsOneWidget,
        reason: 'F2-6：唯一退出钮＝返回');
    expect(find.byKey(const ValueKey('rt-collapse')), findsNothing,
        reason: 'F2-6：原「收起」与「返回」同义，已收敛为一枚——不许再出现第二枚退出钮');

    // 未在跑：返回＝静默回退，不弹「回胶囊继续」提示。
    await tester.tap(find.byKey(const ValueKey('rt-back')));
    await tester.pumpAndSettle();
    expect(find.byType(ReadTimerPage), findsNothing, reason: '返回＝退出计时页');
    expect(find.textContaining('计时未结束'), findsNothing,
        reason: '未在跑时不该出「回胶囊继续」提示');
  });
}
