import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/features/dashboard/presentation/dashboard_page.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserSettings.homeCardOrder 序列化', () {
    test('默认顺序 = 原型 DASH_IDS 六卡', () {
      expect(UserSettings.defaults.homeCardOrder,
          ['greeting', 'mood', 'events', 'inboxBar', 'chart', 'grid']);
    });

    test('往返读写保持顺序；未知 id 剔除、缺失卡片补尾', () {
      final s = UserSettings.defaults
          .copyWith(homeCardOrder: ['grid', 'ghost', 'greeting']);
      final map = s.toMap();
      final back = UserSettings.fromMap(map.cast<String, Object?>());
      // ghost 未知被剔除，其余保序，缺失四卡按默认序补尾
      expect(back.homeCardOrder,
          ['grid', 'greeting', 'mood', 'events', 'inboxBar', 'chart']);
    });

    test('SettingsRepository 持久化后经 load 恢复', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepository(prefs);
      await repo.save(UserSettings.defaults.copyWith(
          homeCardOrder: ['mood', 'greeting', 'events', 'inboxBar', 'chart', 'grid']));
      final reloaded = SettingsRepository(prefs).load();
      expect(reloaded.homeCardOrder.first, 'mood');
    });
  });

  group('仪表盘编排（原型 dashToggle/dashMove）', () {
    late SharedPreferences prefs;
    late Database db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
    });

    tearDown(() async => db.close());

    ProviderContainer boot() => ProviderContainer(overrides: [
          todoRepositoryProvider
              .overrideWithValue(TodoRepository(TodoDao(db), EventBus())),
          journalRepositoryProvider
              .overrideWithValue(JournalRepository(JournalDao(db))),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ]);

    testWidgets('V1.27 H1 长按卡片进入编排：提示条+每卡↑↓钮；条内✓完成持久化并提示',
        (tester) async {
      final container = boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: const MaterialApp(home: DashboardPage())));
      await tester.pumpAndSettle();

      // 右上「⇄ 编排」钮已删；问候卡底部有长按提示行
      expect(find.text('⇄ 编排'), findsNothing);
      expect(find.text('长按任意卡片可编排顺序'), findsOneWidget);

      // V1.27 H1：长按任意卡片 → 进入编排模式
      await tester.longPress(find.byKey(const ValueKey('card-press-greeting')));
      await tester.pumpAndSettle();
      expect(find.text('已进入编排模式 · 拖动或 ↑↓ 调整'), findsOneWidget);

      expect(find.textContaining('编排模式：拖动卡片调整顺序'), findsOneWidget);
      expect(find.byKey(const ValueKey('up-greeting')), findsOneWidget);
      expect(find.byKey(const ValueKey('down-mood')), findsOneWidget);
      expect(find.byKey(const ValueKey('dash-done-btn')), findsOneWidget);

      // 顶卡下移一位 → 提示条内 ✓ 完成 保存
      await tester.tap(find.byKey(const ValueKey('down-greeting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dash-done-btn')));
      await tester.pumpAndSettle();

      expect(find.text('主页布局已保存 · 下次启动保持此顺序'), findsOneWidget);
      expect(container.read(settingsControllerProvider).homeCardOrder.first, 'mood');
      expect(SettingsRepository(prefs).load().homeCardOrder.first, 'mood');
      expect(find.textContaining('编排模式'), findsNothing); // 退出编辑态
    });

    testWidgets('重启后按已保存顺序渲染（心情卡置顶于问候卡之前）', (tester) async {
      await SettingsRepository(prefs).save(UserSettings.defaults
          .copyWith(homeCardOrder: ['mood', 'greeting', 'events', 'inboxBar', 'chart', 'grid']));
      final container = boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: const MaterialApp(home: DashboardPage())));
      await tester.pumpAndSettle();

      final yMood = tester.getTopLeft(find.text('😄')).dy;
      final yGreet = tester.getTopLeft(find.textContaining('，CHIST')).dy;
      expect(yMood, lessThan(yGreet), reason: '保存顺序首卡应为心情');
    });

    testWidgets('边界：首位点↑ / 末位点↓ 给提示不越界', (tester) async {
      final container = boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: const MaterialApp(home: DashboardPage())));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey('card-press-greeting')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('up-greeting')));
      await tester.pumpAndSettle();
      expect(find.text('已在第一位'), findsOneWidget);
      expect(container.read(settingsControllerProvider).homeCardOrder.first, 'greeting');

      // 末卡（grid）在懒加载列表尾部：先滚到底再点 ↓
      await tester.drag(find.byType(ReorderableListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('down-grid')));
      await tester.pumpAndSettle();
      expect(find.text('已在最后一位'), findsOneWidget);
    });
  });
}
