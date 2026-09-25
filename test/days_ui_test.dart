import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/days/data/days_repository.dart';
import 'package:lifeharness/features/days/domain/day_models.dart';
import 'package:lifeharness/features/days/presentation/day_edit_page.dart';
import 'package:lifeharness/features/days/presentation/day_remind_page.dart';
import 'package:lifeharness/features/days/presentation/days_page.dart';
import 'package:lifeharness/features/days/presentation/days_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';

/// 批1 · 日子四屏 UI（V1.42 模块11 · 原型 P8/P8a/P8b/P8c 对译断言）。
/// 独立文件防 isolate 污染；固定钟 2026-09-19（daysClockProvider 缝）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19);
  late Database db;
  late DaysRepository repo;
  late TodoRepository todoRepo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = DaysRepository(db);
    todoRepo = TodoRepository(TodoDao(db), EventBus());
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget home) async {
    final container = ProviderContainer(overrides: [
      daysRepositoryProvider.overrideWithValue(repo),
      todoRepositoryProvider.overrideWithValue(todoRepo),
      daysClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp(home: home)));
    await settle5(tester);
  }

  /// toast 长句用包含语义轮询（pollText 是全串 find.text；大 pump 会跳过退场期）。
  Future<bool> pollContains(WidgetTester tester, String part) async {
    for (var i = 0; i < 15; i++) {
      if (find.textContaining(part).evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 80));
    }
    return find.textContaining(part).evaluate().isNotEmpty;
  }

  Future<int> seedBirthday() => repo.addDay(const DayEntry(
        title: '妈妈生日',
        iconId: 'cake',
        colorKey: 'rose',
        category: '生日',
        repeat: DayRepeat.lunar,
        lunarMonth: 8,
        lunarDay: 27,
        remOffsets: [30, 7, 0],
        preps: [DayPrep(dayId: 0, text: '订蛋糕')],
      ));

  group('P8 列表屏', () {
    testWidgets('计数行/双视图/排序翻转/归档过滤/过期直达', (tester) async {
      await useSurface(tester);
      await repo.addDay(const DayEntry(
          title: '妈妈生日',
          iconId: 'cake',
          colorKey: 'rose',
          category: '生日',
          repeat: DayRepeat.lunar,
          lunarMonth: 8,
          lunarDay: 27,
          remOffsets: [30, 7, 0]));
      await repo.addDay(DayEntry(
          title: '日本签证到期',
          iconId: 'alert',
          colorKey: 'slate',
          category: '证件',
          repeat: DayRepeat.once,
          targetDate: DateTime(2026, 9, 16),
          remOffsets: const [30, 7, 0]));
      await repo.addDay(DayEntry(
          title: '老日子',
          iconId: 'doc',
          colorKey: 'slate',
          category: '倒数',
          repeat: DayRepeat.once,
          targetDate: DateTime(2025, 1, 1),
          archived: true));
      await pump(tester, const DaysPage());

      // 农历八月廿七 → 2026-10-07 实算 18 天（不随分类变化）
      expect(find.text('2 个日子 · 最近「妈妈生日」还 18 天'), findsOneWidget);
      expect(find.text('18'), findsWidgets);
      expect(find.text('—'), findsOneWidget); // 过期卡大数字位
      expect(find.textContaining('去处理'), findsWidgets);

      // 切列表视图 → 过期行显「已过3」
      await tester.tap(find.byKey(const ValueKey('d-view-btn')));
      await tester.pumpAndSettle();
      expect(find.text('已过3'), findsOneWidget);

      // 排序翻转
      await tester.tap(find.byKey(const ValueKey('d-sort-btn')));
      await tester.pumpAndSettle();
      expect(find.text('最久优先'), findsOneWidget);

      // 已归档 seg 带计数并可回看
      await tester.tap(find.byKey(const ValueKey('d-cat-已归档')));
      await tester.pumpAndSettle();
      expect(find.text('已归档 1'), findsOneWidget);
      expect(find.text('老日子'), findsWidgets);

      // 过期条目点击 → 提醒中心
      await tester.tap(find.byKey(const ValueKey('d-cat-全部')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日本签证到期').last);
      await settle5(tester);
      expect(find.text('到期提醒中心'), findsOneWidget);
    });

    testWidgets('提醒预览卡 + 新建入口进编辑屏', (tester) async {
      await useSurface(tester);
      await repo.addCertReminder(title: '护照', due: DateTime(2026, 11, 5));
      await pump(tester, const DaysPage());
      expect(find.text('1 项待关注'), findsOneWidget);
      expect(find.textContaining('剩 47 天'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('d-new-day')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('d-edit-save')), findsOneWidget);
    });
  });

  group('P8a 详情屏', () {
    testWidgets('hero 实算/提醒档位/勾选转待办/归档链路', (tester) async {
      await useSurface(tester);
      final id = await seedBirthday();
      await pump(tester, const DaysPage());
      await tester.tap(find.byKey(ValueKey('d-day-card-$id')));
      await settle5(tester);

      expect(find.text('18'), findsOneWidget);
      expect(find.textContaining('天后 · 10月7日'), findsOneWidget);
      expect(find.textContaining('每年（农历）'), findsOneWidget);
      // 六档 chip（选中带 ✓ 后缀，按 key 断言）
      expect(find.byKey(const ValueKey('d-detail-rem-30')), findsOneWidget);
      expect(find.byKey(const ValueKey('d-detail-rem-7')), findsOneWidget);
      expect(find.textContaining('提前 30 天'), findsOneWidget);

      // 勾选准备事项 → 生成待办（联动 L3）
      await tester.tap(find.byKey(const ValueKey('d-prep-1')));
      expect(await pollContains(tester, '已生成待办'), isTrue);
      final todos = await todoRepo.list();
      expect(todos.map((t) => t.title), contains('订蛋糕'));
      await clearToasts(tester);

      // 归档（当前仍在详情）→ toast+pop → 切「已归档」再进（归档态）→ 恢复
      await tester.tap(find.byKey(const ValueKey('d-detail-archive')));
      expect(await pollContains(tester, '已归档「妈妈生日」'), isTrue);
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('d-cat-已归档')));
      await settle5(tester);
      await tester.tap(find.byKey(ValueKey('d-day-card-$id')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('d-detail-arch-bar')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('d-detail-restore')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('d-detail-archive')), findsOneWidget);
    });
  });

  group('P8b 编辑屏', () {
    testWidgets('新建农历日子：换算实算 + 落库 toast', (tester) async {
      await useSurface(tester);
      await pump(tester, DayEditPage(dayId: null));
      await tester.enterText(
          find.byKey(const ValueKey('d-edit-title')), '结婚纪念日');
      await tester.tap(find.byKey(const ValueKey('d-edit-rep-lunar')));
      await tester.pumpAndSettle();
      // 默认八月廿七 · 2026-09-19 视角实算 2026-10-07
      expect(
          find.textContaining('农历 八月廿七 · 对应公历 2026-10-07（逐年自动换算）'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('d-edit-save')));
      expect(await pollContains(tester, '已创建「结婚纪念日」'), isTrue);
      final d = await repo.loadAll();
      expect(d.days.single.title, '结婚纪念日');
      expect(d.days.single.repeat, DayRepeat.lunar);
    });

    testWidgets('空标题拦截 + 删除二次确认后编辑/详情连退回列表', (tester) async {
      await useSurface(tester);
      final id = await seedBirthday();
      await pump(tester, const DaysPage());
      await tester.tap(find.byKey(ValueKey('d-day-card-$id')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('d-detail-edit')));
      await settle5(tester);

      await tester.enterText(find.byKey(const ValueKey('d-edit-title')), '');
      await tester.tap(find.byKey(const ValueKey('d-edit-save')));
      expect(await pollContains(tester, '先填标题'), isTrue);
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('d-edit-del')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
      expect(await pollContains(tester, '已删除日子'), isTrue);
      await settle5(tester);
      expect(find.byKey(ValueKey('d-day-card-$id')), findsNothing);
      final d = await repo.loadAll();
      expect(d.days, isEmpty);
    });
  });

  group('P8c 提醒中心', () {
    testWidgets('派生订阅/三动作/改提醒日三滚轮', (tester) async {
      await useSurface(tester);
      await repo.addCertReminder(
          title: '护照', due: DateTime(2026, 11, 5), tip: '提前 1 个月启动');
      await db.insert(DbSchema.tLedgerRecur, {
        'bk': 1, 'name': '视频会员', 'amt': 25.0, 'account_id': 1,
        'freq': '每月', 'next_date': '2026-09-28', 'active': 1,
      });
      await pump(tester, const DayRemindPage());

      expect(find.text('全部(2)'), findsOneWidget);
      expect(find.textContaining('视频会员'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('d-remind-tab-证件')));
      await tester.pumpAndSettle();
      expect(find.text('护照'), findsOneWidget);
      expect(find.textContaining('提前 1 个月启动'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('d-remind-tab-全部')));
      await tester.pumpAndSettle();

      final d1 = await repo.loadAll();
      final sub = d1.reminders.firstWhere((r) => r.kind == 'sub');
      final cert = d1.reminders.firstWhere((r) => r.kind == 'cert');

      // 延后处理 → 转待办（订阅=续订前缀；提醒不消隐）
      await tester.tap(find.byKey(ValueKey('d-rem-todo-${sub.id}')));
      expect(await pollContains(tester, '已生成待办「视频会员」'), isTrue);
      final todos = await todoRepo.list();
      expect(todos.map((t) => t.title), contains('续订 视频会员'));
      await clearToasts(tester);

      // 改提醒日：三内嵌滚轮 + 实算预览 + 回显「已改提醒」
      await tester.tap(find.byKey(ValueKey('d-rem-snooze-${cert.id}')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('d-snooze-m')), findsOneWidget);
      expect(find.byKey(const ValueKey('d-snooze-d')), findsOneWidget);
      expect(find.byKey(const ValueKey('d-snooze-h')), findsOneWidget);
      expect(find.textContaining('将于'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('d-snooze-save')));
      expect(await pollContains(tester, '提醒日已改为'), isTrue);
      await settle5(tester);
      expect(find.textContaining('已改提醒'), findsOneWidget);
      await clearToasts(tester);

      // 已处理 → 静默归档保留审计（行不删）
      await tester.tap(find.byKey(ValueKey('d-rem-done-${cert.id}')));
      expect(await pollContains(tester, '静默归档保留审计'), isTrue);
      final d2 = await repo.loadAll();
      expect(d2.reminders.firstWhere((r) => r.id == cert.id).handled, isTrue);
      expect(d2.unhandled.length, 1);
    });

    testWidgets('＋证件建档：内嵌日期滚轮落库', (tester) async {
      await useSurface(tester);
      await pump(tester, const DayRemindPage());
      await tester.tap(find.byKey(const ValueKey('d-rem-add-cert')));
      await settle5(tester);
      await tester.enterText(
          find.byKey(const ValueKey('d-cert-title')), '港澳通行证');
      await tester.tap(find.byKey(const ValueKey('d-cert-save')));
      await settle5(tester);
      final d = await repo.loadAll();
      expect(d.reminders.map((r) => r.title), contains('港澳通行证'));
    });
  });
}
