import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/calendar/presentation/widgets/time_pick_sheet.dart';
import 'package:lifeharness/features/calendar/domain/category.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// F5-4（时间模块批3 · 冻结口径 P2）触控目标 ≥44dp 核对：
/// 可达标项实测 ≥44；受原型定稿约束的项以「已登记豁免」钉值——
/// 改动这些值时本测试红灯，逼同步更新豁免登记（防静默缩热区）。
///
/// 豁免登记（2026-10-13 批3）：
/// ① 月历格 36dp——固定行高（childAspectRatio 方案行高随屏宽膨胀 ~62px，
///    V1.27 批已裁定固定 36）；月历点选另有「点日期开滚轮」兜底精确入口。
/// ② CatPill 26dp——分类网格 3 行受统一添加弹层高度约束（原型定稿形态）；
///    弹层内误触成本低（可返回重选）。
/// ③ 速记列分类行 34dp——格子视图右侧窄列宽度约束（≤ 半屏 1/3）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TimeBlockDao dao;
  late CategoryDao catDao;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TimeBlockDao(db);
    catDao = CategoryDao(db);
    prefs = await SharedPreferences.getInstance();
    await catDao.insert(const Category(name: '工作'));
  });
  tearDown(() async => db.close());

  double widthOf(WidgetTester tester, Finder f) =>
      tester.getSize(f).width;
  double heightOf(WidgetTester tester, Finder f) =>
      tester.getSize(f).height;

  Future<void> pumpCal(WidgetTester tester, {required String mode}) async {
    // 大视口：月历展开后轴视图区在下方（ListView 懒构建），必须整体入树。
    await useSurface(tester, const Size(1080, 3000));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        calViewModeProvider.overrideWith((ref) => mode),
        monthExpandedProvider.overrideWith((ref) => true),
        categoryDaoProvider.overrideWithValue(catDao),
        legacyEventMergeDbProvider.overrideWithValue(db),
        timeBlockDaoProvider.overrideWithValue(dao),
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await settle5(tester);
  }

  testWidgets('核对①月历格＝登记豁免值 36dp 行高', (tester) async {
    await pumpCal(tester, mode: 'axis');
    // 月历面板里任选一个日期格（MonthPanel GridView 单元格）。
    final cell = find.descendant(
        of: find.byKey(const ValueKey('month-panel')),
        matching: find.text('15'));
    if (cell.evaluate().isNotEmpty) {
      final gridCell = find.ancestor(
          of: cell.first, matching: find.byType(GestureDetector)).first;
      final h = heightOf(tester, gridCell);
      expect(h, 36,
          reason: '月历格行高偏离登记豁免值 36dp ⇒ 更新 F5-4 豁免登记');
    }
  });

  testWidgets('核对②CatPill＝登记豁免值 26dp', (tester) async {
    await pumpCal(tester, mode: 'axis');
    await tester.tap(find.textContaining('点此补录').first);
    await settle5(tester);
    final pill = find.byType(CatPill).first;
    expect(heightOf(tester, pill), 26,
        reason: 'CatPill 高度偏离登记豁免值 26dp ⇒ 更新 F5-4 豁免登记');
    expect(widthOf(tester, pill), greaterThanOrEqualTo(60),
        reason: 'CatPill 宽度不得低于视觉最小可点面');
  });

  testWidgets('核对③轴视图块卡可点面（卡整卡为热区，高度 ≥44）', (tester) async {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    await dao.insert(
        TimeBlock(day: day0, startMin: 540, endMin: 600, catName: '工作'));
    await pumpCal(tester, mode: 'axis');
    final card = find.ancestor(
        of: find.textContaining('点卡片修改起止/类型'),
        matching: find.byType(InkWell)).first;
    final h = heightOf(tester, card);
    expect(h, greaterThanOrEqualTo(44),
        reason: '轴视图块卡整卡热区应 ≥44dp，实测=$h');
  });

  testWidgets('核对④F5-2：块卡可读屏（Semantics button＋label）', (tester) async {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    await dao.insert(
        TimeBlock(day: day0, startMin: 540, endMin: 600, catName: '工作'));
    await pumpCal(tester, mode: 'axis');
    final sem = tester.widget<Semantics>(find.ancestor(
        of: find.textContaining('点卡片修改起止/类型'),
        matching: find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == '编辑时间块')).first);
    expect(sem.properties.label, '编辑时间块');
  });
}
