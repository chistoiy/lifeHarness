import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/event_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/category.dart';
import 'package:lifeharness/features/calendar/domain/event_repository.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// V1.52 真机逐屏验收反馈（2026-09-28 第二轮）回归：
/// ① 合并丢块（「与上一个合并」把两段一起弄没）② 撤销不即时刷新
/// ③ 提示条不自动消失 ④ 滚轮可视 5 行（应 3 行）⑤ 一级分类 chip 不显示名称。
///
/// 一律用 390×900 手机视口——桌面视口下 6 列 chip 不挤、滚轮问题也看不出来。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao tbDao;
  late CategoryDao catDao;
  late EventBus bus;
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    tbDao = TimeBlockDao(db);
    catDao = CategoryDao(db);
    bus = EventBus();
  });
  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  Future<void> pumpCal(WidgetTester tester) async {
    await useSurface(tester, const Size(390, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(
            EventRepository(EventDao(db), bus)),
        categoryDaoProvider.overrideWithValue(catDao),
        timeBlockDaoProvider.overrideWithValue(tbDao),
        calViewModeProvider.overrideWith((ref) => 'axis'),
        // 批1 C2：切档不再自动改展开态——轴视图旧前提=展开，显式给。
        monthExpandedProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await settle5(tester);
  }

  /// 轴视图点某段块的卡片 → 打开统一编辑弹层。
  Future<void> editOf(WidgetTester tester, String subtitle) async {
    await tester.tap(find.textContaining(subtitle).first);
    await tester.pumpAndSettle();
    expect(find.text('编辑事件 / 时间块'), findsOneWidget,
        reason: '未打开统一编辑弹层：$subtitle');
  }

  /// 16:47-16:50 娱乐（3 分）与 16:50-17:27 睡眠（37 分）——真机同组数据。
  Future<void> seedPair() async {
    await tbDao.insert(TimeBlock(
        day: d0, startMin: 1007, endMin: 1010, catName: '娱乐', note: '娱乐'));
    await tbDao.insert(TimeBlock(
        day: d0, startMin: 1010, endMin: 1047, catName: '睡眠', note: '睡眠'));
  }

  group('真机反馈第二轮', () {
    testWidgets('① 与上一个合并：只留一段且区间=两段并集（原缺陷＝两段全没）',
        (tester) async {
      await seedPair();
      await pumpCal(tester);
      await editOf(tester, '睡眠 · 37 分钟');

      await tester.tap(find.text('⇧ 与上一个合并'));
      await settle5(tester);

      final day = await tbDao.listByDay(d0);
      expect(day.length, 1, reason: '合并后应只剩一段');
      expect(day.single.startMin, 1007, reason: '起始取更早段');
      expect(day.single.endMin, 1047, reason: '结束取更晚段');
      // 轴视图同步：并集段以 40 分钟呈现，原两段不再出现
      expect(find.textContaining('40 分钟'), findsOneWidget);
      expect(find.textContaining('37 分钟'), findsNothing);
      expect(find.textContaining('娱乐 · 3 分钟'), findsNothing);
      await clearToasts(tester);
    });

    testWidgets('② 与下一个合并：同样只剩一段且区间正确', (tester) async {
      await seedPair();
      await pumpCal(tester);
      await editOf(tester, '娱乐 · 3 分钟');

      await tester.tap(find.text('⇩ 与下一个合并'));
      await settle5(tester);

      final day = await tbDao.listByDay(d0);
      expect(day.length, 1);
      expect(day.single.startMin, 1007);
      expect(day.single.endMin, 1047);
      await clearToasts(tester);
    });

    testWidgets('③ 点撤销当帧恢复两段（原缺陷＝要再操作一次才刷新）',
        (tester) async {
      await seedPair();
      await pumpCal(tester);
      await editOf(tester, '睡眠 · 37 分钟');
      await tester.tap(find.text('⇧ 与上一个合并'));
      await settle5(tester);
      expect((await tbDao.listByDay(d0)).length, 1);

      await tester.tap(find.text('撤销'));
      await settle5(tester);

      final day = await tbDao.listByDay(d0);
      expect(day.length, 2, reason: '撤销回两段');
      // 不追加任何操作，轴视图就该重新出现两段
      expect(find.textContaining('娱乐 · 3 分钟'), findsOneWidget);
      expect(find.textContaining('睡眠 · 37 分钟'), findsOneWidget);
      await clearToasts(tester);
    });

    testWidgets('④ 提示条到时长自动消失（不点撤销也不许永挂）', (tester) async {
      await seedPair();
      await pumpCal(tester);
      await editOf(tester, '睡眠 · 37 分钟');
      await tester.tap(find.text('⇧ 与上一个合并'));
      await settle5(tester);
      expect(find.byType(SnackBar), findsOneWidget);

      // fake 时间下必须小步 pump 才会触发 SnackBar 关闭定时器（helpers 同口径）
      for (var i = 0; i < 80 && find.byType(SnackBar).evaluate().isNotEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SnackBar), findsNothing,
          reason: '8 秒后提示条应已自动退场');
      await clearToasts(tester);
    });

    testWidgets('⑤ 时间滚轮可视 3 行（默认 squeeze 1.45 会显示成 5 行）',
        (tester) async {
      await pumpCal(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('添加事件 / 时间块'), findsOneWidget);

      final pickers = find.byType(CupertinoPicker);
      expect(pickers, findsWidgets);
      for (final el in pickers.evaluate()) {
        final p = el.widget as CupertinoPicker;
        final box = tester.getSize(find.byWidget(p));
        expect(p.squeeze, 1.0,
            reason: 'CupertinoPicker 默认 squeeze=1.45，会把可见行数放大到 ~4.3 行');
        expect((box.height / p.itemExtent).round(), 3,
            reason: '高度/行高须恰为 3 行（原型 .wheelbox 78px / .witem 26px）');
      }
      await clearToasts(tester);
    });

    testWidgets('⑦ 对半拆分：原块收前半 + 新行放后半，两段都在（同族落库路径）',
        (tester) async {
      await tbDao.insert(TimeBlock(
          day: d0, startMin: 540, endMin: 600, catName: '工作', note: '写方案'));
      await pumpCal(tester);
      await editOf(tester, '工作 · 60 分钟');

      await tester.tap(find.text('✂ 对半拆分'));
      await settle5(tester);

      final day = await tbDao.listByDay(d0);
      expect(day.length, 2);
      final spans = (day.map((b) => '${b.startMin}-${b.endMin}').toList()
        ..sort());
      expect(spans, ['540-570', '570-600']);
      expect(find.textContaining('工作 · 30 分钟'), findsNWidgets(2));
      await clearToasts(tester);
    });

    testWidgets('⑥ 一级分类 chip 显示名称（窄屏 6 列下不被挤没）',
        (tester) async {
      for (final n in ['工作学习', '运动健康', '娱乐休闲', '睡眠休息', '餐饮美食']) {
        await catDao.insert(Category(name: n, colorHex: '#6366F1'));
      }
      await pumpCal(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      for (final n in ['工作学习', '运动健康', '娱乐休闲']) {
        expect(find.text(n), findsWidgets, reason: '$n 未渲染');
        final w = tester.getSize(find.text(n).last).width;
        expect(w, greaterThan(20), reason: '$n 文本被压到 $w 逻辑像素＝看不见');
      }
      // 窄列溢出会以 RenderFlex overflow 报错，这里要求零异常
      expect(tester.takeException(), isNull);
      await clearToasts(tester);
    });
  });
}
