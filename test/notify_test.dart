import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/notifications/notification_service.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/features/settings/presentation/notify_settings_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotifySettings 序列化', () {
    test('UserSettings toMap/fromMap 往返保留 notify', () {
      final s = UserSettings.defaults.copyWith(
          notify: const NotifySettings(
              todoEvent: false, leadMin: 30, diaryReview: true,
              diaryTime: '22:00', inboxClean: true, dnd: true));
      final back = UserSettings.fromMap(s.toMap());
      expect(back.notify.todoEvent, isFalse);
      expect(back.notify.leadMin, 30);
      expect(back.notify.diaryReview, isTrue);
      expect(back.notify.diaryTime, '22:00');
      expect(back.notify.inboxClean, isTrue);
      expect(back.notify.dnd, isTrue);
    });

    test('损坏 notify JSON 回退默认（不炸启动）', () {
      final back = UserSettings.fromMap({'themeId': 'minimal', 'notify': '{bad json'});
      expect(back.notify.todoEvent, isTrue);
    });

    test('SettingsRepository save/load 经 prefs 持久化 notify', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SettingsRepository(await SharedPreferences.getInstance());
      await repo.save(UserSettings.defaults
          .copyWith(notify: const NotifySettings(inboxClean: true)));
      expect(repo.load().notify.inboxClean, isTrue);
    });
  });

  group('NotificationService 测试环境降级', () {
    test('ready=false 时排程/取消全部 no-op 且不抛', () async {
      expect(NotificationService.ready, isFalse);
      await NotificationService.scheduleTodo(
          id: 1, title: 't', remindAt: DateTime.now().add(const Duration(days: 1)));
      await NotificationService.cancel(1);
      await NotificationService.syncDaily(
          inboxClean: true, diaryReview: true, diaryTime: '21:30');
    });

    test('TodoRepository add(remindAt) 在无插件环境不阻塞落库', () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      final repo = TodoRepository(TodoDao(db), EventBus());
      final t = await repo.add(Todo(
          title: '带提醒任务',
          quadrant: Quadrant.q2,
          remindAt: DateTime.now().add(const Duration(hours: 2))));
      expect(t.id, isNotNull);
      expect((await repo.list()).single.remindAt, isNotNull);
      await repo.remove(t);
      await db.close();
    });
  });

  group('提醒通知二级页（原型 p-sub-notify）', () {
    late Database db;
    late TodoRepository todoRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      todoRepo = TodoRepository(TodoDao(db), EventBus());
    });

    tearDown(() async => db.close());

    Future<ProviderContainer> pump(WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoRepositoryProvider.overrideWithValue(todoRepo),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NotifySettingsPage())));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('五卡渲染 + 开关持久化 + 入口状态联动', (tester) async {
      final container = await pump(tester);
      expect(find.text('📅 日程与任务提醒'), findsOneWidget);
      expect(find.text('📔 日记复盘'), findsOneWidget);
      expect(find.text('⚡ 收集箱清理'), findsOneWidget);
      expect(find.text('🔁 习惯提醒'), findsOneWidget);
      expect(find.text('⛔ 免打扰时段'), findsOneWidget);
      expect(find.textContaining('类提醒已开启'), findsOneWidget); // 默认 todoEvent on

      // 打开收集箱整理（开关序：todoEvent/overdue/diary/inbox/习惯/dnd → index 3）。
      await tester.tap(find.byType(Switch).at(3));
      await tester.pumpAndSettle();
      final settings = SettingsRepository(await SharedPreferences.getInstance()).load();
      expect(settings.notify.inboxClean, isTrue);
      expect(container.read(settingsControllerProvider).notify.inboxClean, isTrue);
    });

    testWidgets('复盘时间下拉可选并保存', (tester) async {
      await pump(tester);
      await tester.tap(find.text('21:30'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22:30').last);
      await tester.pumpAndSettle();
      final settings = SettingsRepository(await SharedPreferences.getInstance()).load();
      expect(settings.notify.diaryTime, '22:30');
    });
  });
}
