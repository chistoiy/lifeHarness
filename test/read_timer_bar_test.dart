import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart'
    show calendarTickerProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/shared/linkage/timer_bar_overlay.dart';

/// 阅读顶部胶囊（read.timerUI=顶部胶囊）常驻守护（真机反馈 2026-10-14）。
///
/// 两条真机实伤的回归钉：
/// ① 可见性失效链断（改设置/起表后要重进 app 才显）——`readTimerBarVisibleProvider`
///    直挂 readTick 后，kv 写入与起/停表都即时反映；
/// ② 落点口径（条应贴状态栏下悬浮，不该把内容垫掉一大块）——落点＝安全区+8。
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
    await repo.addBook(Book(
        id: 'a',
        title: '书A',
        author: '作者',
        state: Book.kStateReading,
        pages: 100,
        readPages: 1,
        lastReadAt: 1,
        createdAt: 1,
        updatedAt: 1));
  });
  tearDown(() => db.close());

  /// 壳层同款装配（与 read_f2_nav_test 同构）：Scaffold 外套＝条内 InkWell 要
  /// Material 祖先；calendarTicker 换空流防「A Timer is still pending」。
  Widget host({List<Override> extra = const []}) => ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          calendarTickerProvider.overrideWith((ref) => const Stream.empty()),
          ...extra,
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TimerBarOverlay(
              child: SizedBox.expand(key: ValueKey('probe')),
            ),
          ),
        ),
      );

  /// provider 解析（可见位 + runningSession 的 sqflite 往返）要混真事件循环。
  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(host());
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  double topPadOf(WidgetTester tester) =>
      MediaQuery.paddingOf(tester.element(find.byType(TimerBarOverlay))).top;

  testWidgets('顶部胶囊形态 + 在跑会话 ⇒ read-bar 在场（贴顶悬浮）', (tester) async {
    await repo.setKv('read.timerUI', '顶部胶囊');
    expect(await repo.startSession('a'), isNotNull);
    await boot(tester);
    expect(find.byKey(const ValueKey('read-bar')), findsOneWidget);
    final topPad = topPadOf(tester);
    expect(tester.getRect(find.byKey(const ValueKey('read-bar'))).top,
        closeTo(topPad + kTimerBarTopOffset, .01),
        reason: '落点＝安全区+8：贴状态栏下悬浮（真机口径 2026-10-14）');
    expect(tester.getRect(find.byKey(const ValueKey('probe'))).top,
        closeTo(0, .01),
        reason: '纯悬浮：内容零让位（垫位口径已废）');
  });

  testWidgets('全屏形态 ⇒ 不显胶囊', (tester) async {
    await repo.setKv('read.timerUI', '全屏');
    await repo.startSession('a');
    await boot(tester);
    expect(find.byKey(const ValueKey('read-bar')), findsNothing);
  });

  testWidgets('起表后才改「顶部胶囊」＋ bump tick ⇒ 胶囊即时出现（重进才显回归钉）', (tester) async {
    await repo.startSession('a');
    await boot(tester);
    expect(find.byKey(const ValueKey('read-bar')), findsNothing);
    // 模拟设置页 _set：写 kv + bump readTick（同一容器，与真机同构）。
    await repo.setKv('read.timerUI', '顶部胶囊');
    final c = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('probe'))),
        listen: false);
    c.read(readTickProvider.notifier).state++;
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('read-bar')), findsOneWidget,
        reason: 'kv 已写「顶部胶囊」且 tick 已 bump：不重进 app 也应即时显');
  });
}
