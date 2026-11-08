import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/notifications/notification_service.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/core/settings/user_settings.dart';
import 'package:lifeharness/core/widgets/notify_wheel_rows.dart';
import 'package:lifeharness/core/widgets/wheel_time.dart';
import 'package:lifeharness/features/settings/presentation/notify_settings_page.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:lifeharness/shared/widgets/lh_wheel.dart';
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

    test('免打扰起止往返保留；旧包缺键回落 23/7；越界读侧收敛', () {
      final s = const NotifySettings(dndStartHour: 22, dndEndHour: 6);
      final back = NotifySettings.fromMap(s.toMap());
      expect(back.dndStartHour, 22);
      expect(back.dndEndHour, 6);
      final legacy = NotifySettings.fromMap(const {'dnd': true});
      expect(legacy.dndStartHour, 23);
      expect(legacy.dndEndHour, 7);
      final bad = NotifySettings.fromMap(const {
        'dndStartHour': -9,
        'dndEndHour': 99,
      });
      expect(bad.dndStartHour, 0);
      expect(bad.dndEndHour, 23);
      expect(s.copyWith(dndEndHour: 8).dndStartHour, 22);
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

  group('反馈批3 · 免打扰窗口判据（可配置·整点半开区间）', () {
    setUp(() => NotificationService.configureDndWindow(
        startHour: 23, endHour: 7));
    tearDown(() => NotificationService.configureDndWindow(
        startHour: 23, endHour: 7));

    bool at(int h, [int m = 0]) =>
        NotificationService.inDndWindow(DateTime(2026, 1, 1, h, m));

    test('默认 23–7 跨午夜：四点边界与旧口径逐值一致', () {
      expect(at(22, 59), isFalse);
      expect(at(23), isTrue);
      expect(at(6, 59), isTrue);
      expect(at(7), isFalse);
      expect(at(12), isFalse);
      expect(dndWindowLabel(23, 7), '23:00 – 07:00');
    });

    test('自定义跨午夜 22–6：判据跟着窗口走，22 点在窗内', () {
      NotificationService.configureDndWindow(startHour: 22, endHour: 6);
      expect(at(21, 59), isFalse);
      expect(at(22, 30), isTrue);
      expect(at(5, 59), isTrue);
      expect(at(6), isFalse);
      expect(dndWindowLabel(22, 6), '22:00 – 06:00');
    });

    test('同日窗口 9–12：不跨午夜，夜里不误吞', () {
      NotificationService.configureDndWindow(startHour: 9, endHour: 12);
      expect(at(8, 59), isFalse);
      expect(at(9), isTrue);
      expect(at(11, 59), isTrue);
      expect(at(12), isFalse);
      expect(at(23), isFalse);
      expect(at(3), isFalse);
    });

    test('起＝止＝空窗口：不吞任何提醒，顺延保持原时刻', () {
      NotificationService.configureDndWindow(startHour: 7, endHour: 7);
      for (var h = 0; h < 24; h++) {
        expect(at(h), isFalse, reason: '$h 点不该被空窗口吞掉');
      }
      final t = DateTime(2026, 1, 1, 3, 20);
      expect(NotificationService.deferOutOfDnd(t), t);
      expect(dndWindowLabel(7, 7), '未设置免打扰时段');
    });

    test('configureDndWindow 越界夹到 0..23（不落非法小时）', () {
      NotificationService.configureDndWindow(startHour: -5, endHour: 99);
      expect(NotificationService.dndStartHour, 0);
      expect(NotificationService.dndEndHour, 23);
    });

    test('顺延终点＝窗口止点：23:30→次日 07:00 / 03:00→当日 07:00 / 12:00 原样',
        () {
      expect(NotificationService.deferOutOfDnd(DateTime(2026, 1, 1, 23, 30)),
          DateTime(2026, 1, 2, 7));
      expect(NotificationService.deferOutOfDnd(DateTime(2026, 1, 1, 3)),
          DateTime(2026, 1, 1, 7));
      expect(NotificationService.deferOutOfDnd(DateTime(2026, 1, 1, 12)),
          DateTime(2026, 1, 1, 12));
    });

    test('自定义同日窗口 9–12：顺延到当日 12:00，不写死 07:00', () {
      NotificationService.configureDndWindow(startHour: 9, endHour: 12);
      expect(NotificationService.deferOutOfDnd(DateTime(2026, 1, 1, 10, 15)),
          DateTime(2026, 1, 1, 12));
      expect(NotificationService.deferOutOfDnd(DateTime(2026, 1, 1, 8)),
          DateTime(2026, 1, 1, 8));
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
      NotificationService.configureDndWindow(startHour: 23, endHour: 7);
    });

    tearDown(() async {
      NotificationService.configureDndWindow(startHour: 23, endHour: 7);
      await db.close();
    });

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
      expect(find.text('日程与任务提醒'), findsOneWidget);
      expect(find.text('日记复盘'), findsOneWidget);
      expect(find.text('⚡ 收集箱清理'), findsOneWidget);
      expect(find.text('习惯提醒'), findsOneWidget);
      expect(find.text('⛔ 免打扰时段'), findsOneWidget);
      expect(find.textContaining('类提醒已开启'), findsOneWidget); // 默认 todoEvent on

      // 打开收集箱整理（开关序：todoEvent/overdue/diary/inbox/习惯/dnd → index 3）。
      await tester.tap(find.byType(Switch).at(3));
      await tester.pumpAndSettle();
      final settings = SettingsRepository(await SharedPreferences.getInstance()).load();
      expect(settings.notify.inboxClean, isTrue);
      expect(container.read(settingsControllerProvider).notify.inboxClean, isTrue);
    });

    testWidgets('复盘时间就地滚轮可任选时刻并保存（非四档常量）', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('nf-diary-value')), findsOneWidget);
      expect(find.text('21:30'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nf-diary-value')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nf-diary-box')), findsOneWidget,
          reason: '滚轮必须就地展开在卡片内，不是二次弹层');
      expect(find.byType(InlineWheelTime), findsOneWidget);
      final wheels = find.byType(CupertinoPicker);
      expect(wheels, findsNWidgets(2), reason: '时/分双列');
      // 各上滑一格：21→22、30→31（31 分不在原四档常量里＝真的可任选）。
      await tester.drag(wheels.at(0), const Offset(0, -32));
      await tester.pumpAndSettle();
      await tester.drag(wheels.at(1), const Offset(0, -32));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nf-diary-confirm')));
      await tester.pumpAndSettle();
      final settings = SettingsRepository(await SharedPreferences.getInstance()).load();
      expect(settings.notify.diaryTime, '22:31');
      expect(find.text('22:31'), findsOneWidget);
      expect(find.byKey(const ValueKey('nf-diary-box')), findsNothing,
          reason: '确定后滚轮收起，值落回行上');
    });

    testWidgets('免打扰起止就地滚轮落库，并灌入提醒顺延判据', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('nf-dnd-value')), findsOneWidget);
      expect(find.text('23:00 – 07:00'), findsOneWidget);
      // 600 高测试视口下末卡在折叠线外，先滚进来再点（否则 tap 打在树外）。
      await tester.ensureVisible(find.byKey(const ValueKey('nf-dnd-value')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nf-dnd-value')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nf-dnd-box')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('nf-dnd-box')));
      await tester.pumpAndSettle();
      expect(find.byType(LHWheel), findsNWidgets(2), reason: '起/止整点双列');
      final wheels = find.byType(CupertinoPicker);
      expect(wheels, findsNWidgets(2));
      // 起列初始 23＝最后一档，往回拖一格 → 22。
      await tester.drag(wheels.at(0), const Offset(0, 30));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('nf-dnd-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nf-dnd-confirm')));
      await tester.pumpAndSettle();
      final settings = SettingsRepository(await SharedPreferences.getInstance()).load();
      expect(settings.notify.dndStartHour, 22);
      expect(settings.notify.dndEndHour, 7);
      expect(NotificationService.dndStartHour, 22,
          reason: '落库后必须立刻灌进全局判据，不能等下次启动');
      expect(NotificationService.inDndWindow(DateTime(2026, 1, 1, 22, 30)), isTrue);
      expect(NotificationService.inDndWindow(DateTime(2026, 1, 1, 21, 59)), isFalse);
      expect(find.text('22:00 – 07:00'), findsOneWidget);
    });
  });
}
