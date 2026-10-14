import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart'
    show sharedPreferencesProvider;
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart'
    show calendarTickerProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/shared/linkage/timer_bar_overlay.dart';

/// 悬浮胶囊两形态守护（批A · 悬浮胶囊增强批 2026-10-14 原型过门口径）：
/// 紧凑胶囊（默认不显书名·点「时间」显/隐）⇄ 贴边圆圈（只显时长·点击直接展开）·
/// 两态严格互斥 · 位置记忆 per 形态入 kv（read.pillPos / read.pillFabPos）·
/// 秒显 m:ss→h:mm:ss（圆圈面 h:mm）。
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

  /// 壳层同款装配（与 read_timer_bar_test 同构）：条内 InkWell 要 Material
  /// 祖先；calendarTicker 换空流防「A Timer is still pending」。
  Widget host() => ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          calendarTickerProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TimerBarOverlay(
              child: SizedBox.expand(key: const ValueKey('probe')),
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

  testWidgets('默认紧凑：不显书名，含时间／＋笔记／■ 结束', (tester) async {
    await repo.setKv('read.timerUI', '顶部胶囊');
    await repo.startSession('a');
    await boot(tester);
    expect(find.byKey(const ValueKey('read-bar')), findsOneWidget);
    expect(find.textContaining('书A'), findsNothing,
        reason: '默认紧凑：不显书名（产品口径 2026-10-14）');
    expect(find.byKey(const ValueKey('read-pill-note')), findsOneWidget,
        reason: 'C6 案A：＋笔记入口在位');
    expect(find.byKey(const ValueKey('read-pill-end')), findsOneWidget);
  });

  testWidgets('点「时间」显/隐书名', (tester) async {
    await repo.setKv('read.timerUI', '顶部胶囊');
    await repo.startSession('a');
    await boot(tester);
    expect(find.textContaining('阅读中'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('read-pill-time')));
    await tester.pump();
    expect(find.textContaining('阅读中'), findsOneWidget,
        reason: '点时间显示书名字样');
    await tester.tap(find.byKey(const ValueKey('read-pill-time')));
    await tester.pump();
    expect(find.textContaining('阅读中'), findsNothing, reason: '再点收起');
  });

  testWidgets('拖到屏幕右缘 → 贴边圆圈（两态互斥）；点圆圈直接展开回胶囊', (tester) async {
    await repo.setKv('read.timerUI', '顶部胶囊');
    await repo.startSession('a');
    await boot(tester);
    await tester.drag(
        find.byKey(const ValueKey('read-bar')), const Offset(900, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('read-fab')), findsOneWidget,
        reason: '贴边折叠成圆圈（只显时长）');
    expect(find.byKey(const ValueKey('read-bar')), findsNothing,
        reason: '两态互斥：圆圈在场胶囊必须退场');
    expect(find.byKey(const ValueKey('read-pill-end')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('read-fab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('read-bar')), findsOneWidget,
        reason: '点圆圈直接展开（位置接住圆圈处）');
    expect(find.byKey(const ValueKey('read-fab')), findsNothing);
  });

  testWidgets('位置记忆：拖后落 kv，重挂后按 kv 恢复同一落点', (tester) async {
    await repo.setKv('read.timerUI', '顶部胶囊');
    await repo.startSession('a');
    await boot(tester);
    await tester.drag(
        find.byKey(const ValueKey('read-bar')), const Offset(200, 300));
    await tester.pumpAndSettle();
    final raw = await repo.kv('read.pillPos');
    expect(raw, isNotNull, reason: '拖动落 kv（read.pillPos per 形态）');
    // 重挂（模拟重进 app）：胶囊按 kv 恢复到同一落点（测试窗口 800×600）。
    await tester.pumpWidget(const SizedBox.shrink());
    await boot(tester);
    final rect = tester.getRect(find.byKey(const ValueKey('read-bar')));
    final p = raw!.split(',').map(double.parse).toList();
    expect(rect.left, closeTo(p[0] * 800, 2));
    expect(rect.top, closeTo(p[1] * 600, 2));
  });

  test('秒显格式：pillFmtHMS m:ss→h:mm:ss；圆圈面 pillFabFmt h:mm', () {
    expect(pillFmtHMS(const Duration(seconds: 75)), '1:15');
    expect(pillFmtHMS(const Duration(seconds: 3599)), '59:59');
    expect(pillFmtHMS(const Duration(hours: 1, minutes: 2, seconds: 5)),
        '1:02:05');
    expect(pillFabFmt(const Duration(seconds: 75)), '1:15');
    expect(pillFabFmt(
        const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02');
  });
}
