import 'helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/settings/presentation/settings_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 「我的」页版式三档切换守护（2026-10-12 · 原型 p-profile 三版式落实现）。
///
/// 判据（每刀都能被单点变异打红）：
/// ① 默认＝hero：连击环在册、组标题无编号；
/// ② 切 chapters：编号 01–04 出现、连击环退场；
/// ③ 切 minimal：编号与连击环均无；
/// ④ 持久化：切档后 prefs `lh.my_layout` 落到对应值。
///
/// 独立文件防 isolate 污染（照 round4_settings_taps_test 先例）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SharedPreferences prefs;
  late EventBus bus;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
  });

  tearDown(() async {
    await bus.dispose();
    await db.close();
  });

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    // 大视口：设置页很长，ListView 懒构建会让视口外的组标题（编号 03/04）不渲染。
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todoRepositoryProvider
          .overrideWithValue(TodoRepository(TodoDao(db), bus)),
      journalRepositoryProvider
          .overrideWithValue(JournalRepository(JournalDao(db))),
      readRepositoryProvider.overrideWithValue(ReadRepository(db)),
      eventRepositoryProvider
          .overrideWithValue(EventRepository(EventDao(db), bus)),
      timeBlockDaoProvider.overrideWithValue(TimeBlockDao(db)),
      categoryDaoProvider.overrideWithValue(CategoryDao(db)),
    ]);
    addTearDown(c.dispose);
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await settle5(tester);
    return c;
  }

  Future<void> switchTo(
      WidgetTester t, ProviderContainer c, String lay) async {
    await c.read(settingsControllerProvider.notifier).setMyLayout(lay);
    await settle5(t);
  }

  /// 行间发丝计数（`_EntryRow` 底部的 Border）——用于区分「去发丝」的 minimal。
  int hairlines(WidgetTester t) => t
      .widgetList<Container>(find.byType(Container))
      .where((w) =>
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border != null)
      .length;

  testWidgets('① 默认 hero：连击环在册、无组标题编号', (t) async {
    await pumpSettings(t);
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'hero 身份卡未渲染（默认版式应为 hero）');
    expect(find.text('01'), findsNothing, reason: '默认版式不应出现章节编号');
  });

  testWidgets('② chapters：编号 01–04 出现、连击环退场', (t) async {
    final c = await pumpSettings(t);
    await switchTo(t, c, 'chapters');
    for (final n in ['01', '02', '03', '04']) {
      expect(find.text(n), findsOneWidget, reason: '缺章节编号 $n');
    }
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'chapters 应显 legacy 身份行，不显 hero 连击环');
    expect(hairlines(t), greaterThan(0),
        reason: 'chapters 应保留行间发丝（连续卷轴感）');
  });

  testWidgets('③ minimal：编号与连击环均无', (t) async {
    final c = await pumpSettings(t);
    await switchTo(t, c, 'minimal');
    expect(find.text('01'), findsNothing, reason: 'minimal 组标题不带编号');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(hairlines(t), 0, reason: 'minimal 应去发丝（仅留白分组）');
  });

  testWidgets('④ 持久化：切 chapters 后写入 lh.my_layout', (t) async {
    final c = await pumpSettings(t);
    await switchTo(t, c, 'chapters');
    expect(prefs.getString('lh.my_layout'), 'chapters',
        reason: '切档未落盘（刷新即回默认）');
  });
}
