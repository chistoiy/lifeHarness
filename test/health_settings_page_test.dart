import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_export.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/features/health/presentation/health_settings_page.dart';

import 'helpers.dart';

/// 健康批6b · 健康设置屏（原型 `index-health.html#p-hSet`，JS 段 `hRenderSet`/`hToggleKg`/`hExport`）。
///
/// 六条判定（工单 §3 · 面板第 3 项口径延用）：
/// · 四卡九行齐，**开关/滚轮当场写 prefs 且当场回显**（写档必带 healthTouch，否则「点了没反应」）；
/// · 两个提醒时刻**存而不排程**：屏上不出现「已排程」字样（批8 才接通知通道）；
/// · 单位切换只改展示档（kg/斤、km/mile），备份开关落 `health.include_in_backup`；
/// · 导出＝就地面板（范围滚轮＋格式两档＋预览字段行），「按月份」才出月份滚轮；
/// · 导出**真落盘**到注入的目录，完成提示带条数与「含敏感记录」一句实话；
/// · 原型里那两枚本仓不铺的（悬浮球喝水快捷＝需求延后项、分类映射＝联动未实现）**不许出现**。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 8, 10, 0);
  String dk(int back) => dayKey(now.subtract(Duration(days: back)));

  late Database db;
  late HealthRepository repo;
  late SharedPreferences prefs;
  late ProviderContainer container;
  late Directory tmp;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
    tmp = Directory.systemTemp.createTempSync('lh_health_export_');
  });

  tearDown(() async {
    await db.close();
    // Windows 偶发句柄未放：导出目录删不掉不算红（同备份测试口径）。
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpSettings(WidgetTester tester,
      {Map<String, Object> prefsValues = const {}}) async {
    await useSurface(tester, const Size(420, 2400));
    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(() => now),
      // 导出落点注临时目录（widget 测试不碰 plugin 通道与真异步 I/O）。
      healthExportDirProvider.overrideWithValue(() async => tmp.path),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/root', routes: [
      GoRoute(path: '/root', builder: (_, _) => const Scaffold(body: SizedBox.shrink())),
      GoRoute(
          path: '/settings/notify',
          builder: (_, _) => const Scaffold(body: Text('通知中心桩'))),
      ...healthPageRoutes(),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push('/health/settings');
    await settle5(tester);
  }

  /// 滚轮往上拖 n 格＝档位 +n（本屏滚轮 itemExtent 30）。
  Future<void> spin(WidgetTester t, Key wheelKey, int steps) async {
    await t.ensureVisible(find.byKey(wheelKey));
    await t.drag(find.byKey(wheelKey), Offset(0, -30.0 * steps));
    await t.pump();
    await settle5(t);
  }

  /// 取导出回执文案（runAsync 段跑完再扫一次树；动态文件名用不上 `pollText` 的全文匹配）。
  String generatedToast(WidgetTester t) => t
      .widgetList<Text>(find.byType(Text))
      .map((e) => e.data ?? '')
      .firstWhere((s) => s.startsWith('已生成'), orElse: () => '');

  group('健康设置屏', () {
    testWidgets('四卡九行齐＋脚注（默认读数照 HealthSettings.defaults）', (tester) async {
      await pumpSettings(tester);
      expect(find.byKey(HealthSettingsPage.kDash), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kCup), findsOneWidget);
      expect(find.text('250 ml'), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kStage), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kNotify), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kDaily), findsOneWidget);
      expect(find.text('21:30'), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kRemind), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kKgUnit), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kKmUnit), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kBackup), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kExportRow), findsOneWidget);
      expect(find.text(healthLocalOnlyFootnote), findsOneWidget);
      // 默认档：概览卡/随本地备份＝开，分期补录＝关（HealthSettings.defaults 同源）。
      expect(tester.widget<Switch>(find.byKey(HealthSettingsPage.kDash)).value, isTrue);
      expect(tester.widget<Switch>(find.byKey(HealthSettingsPage.kBackup)).value, isTrue);
      expect(tester.widget<Switch>(find.byKey(HealthSettingsPage.kStage)).value, isFalse);
    });

    testWidgets('延后项与未实现联动不铺（悬浮球喝水快捷／分类映射整行缺席）', (tester) async {
      await pumpSettings(tester);
      expect(find.textContaining('悬浮球'), findsNothing);
      expect(find.textContaining('分类映射'), findsNothing);
    });

    testWidgets('提醒时刻两行存而不排程：不出现「已排程」字样', (tester) async {
      await pumpSettings(tester);
      expect(find.textContaining('已排程'), findsNothing);
      expect(find.textContaining('未接系统排程'), findsWidgets);
    });

    testWidgets('一杯换算量滚轮当场写档并回显', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.descendant(
          of: find.byKey(HealthSettingsPage.kCup),
          matching: find.byKey(const ValueKey('hs-cup-row'))));
      await settle5(tester);
      // 默认 250 在第 3 档（200/220/250/300/…），上拖 1 格＝300 ml。
      await spin(tester, const ValueKey('hs-cup-wheel'), 1);
      expect(prefs.getInt('health.cup_ml'), 300);
      // 行首读数当场跟着换（滚轮里也有「300 ml」那一格，所以只认行首那一枚）。
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('hs-cup-row')), matching: find.text('300 ml')),
          findsOneWidget);
    });

    testWidgets('体重单位切到斤＝写档＋提示实话（存储口径写在行注里）', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.byKey(const ValueKey('hs-kg-unit-斤')));
      await settle5(tester);
      expect(prefs.getString('health.kg_unit'), '斤');
      expect(find.textContaining('体重单位 → 斤 · 1 kg = 2 斤'), findsOneWidget);
      expect(find.textContaining('存储恒 kg'), findsOneWidget);
      await clearToasts(tester);
    });

    testWidgets('本地备份开关：关＝写 false 并给含敏感实话', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.byKey(HealthSettingsPage.kBackup));
      await settle5(tester);
      expect(prefs.getBool('health.include_in_backup'), isFalse);
      expect(find.textContaining('本模块数据排除出备份（含敏感用药记录）'), findsOneWidget);
      await clearToasts(tester);
      // 再打开：档回来且提示换向（开关不许只改数值不给可见变化）。
      await tester.tap(find.byKey(HealthSettingsPage.kBackup));
      await settle5(tester);
      expect(prefs.getBool('health.include_in_backup'), isTrue);
      expect(find.textContaining('健康数据将写入本地备份'), findsOneWidget);
    });

    testWidgets('提醒通知中心行可达（跳 /settings/notify）', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.byKey(HealthSettingsPage.kNotify));
      await settle5(tester);
      expect(find.text('通知中心桩'), findsOneWidget);
    });

    testWidgets('导出面板就地展开：格式档换预览字段行，按月份才出月份滚轮', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.byKey(HealthSettingsPage.kExportRow));
      await settle5(tester);
      expect(find.byKey(HealthSettingsPage.kExportPanel), findsOneWidget);
      expect(find.text(healthFieldNote('csv')), findsOneWidget);
      expect(find.byKey(HealthSettingsPage.kMonthWheel), findsNothing);
      // 切 JSON 档：预览字段行跟着换格式（预览与落盘格式不许各说各话）。
      await tester.tap(find.byKey(const ValueKey('hs-fmt-json')));
      await settle5(tester);
      expect(find.text(healthFieldNote('json')), findsOneWidget);
      expect(find.text(healthFieldNote('csv')), findsNothing);
      // 范围滚轮拖到第 4 档（按月份）→ 月份滚轮出现。
      await spin(tester, HealthSettingsPage.kScopeWheel, 3);
      expect(find.byKey(HealthSettingsPage.kMonthWheel), findsOneWidget);
      expect(find.textContaining('按月份'), findsWidgets);
    });

    testWidgets('导出真落盘：文件名 health_*.csv、含表头与种子行、提示带敏感实话', (tester) async {
      await repo.bumpCups(1, dk(0), 3);
      await repo.bumpCups(1, dk(40), 5);
      await pumpSettings(tester);
      await tester.tap(find.byKey(HealthSettingsPage.kExportRow));
      await settle5(tester);
      // 真异步 I/O（查库＋写盘＋close）在 FakeAsync 下永不返回＝用例假死，
      // 必须整段放进 runAsync 跑真事件循环（既定坑：widget 测试禁真异步 I/O）。
      await tester.runAsync(() async {
        await tester.tap(find.byKey(HealthSettingsPage.kRun));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      // 提示条要先有一帧才进树（runAsync 里走真时钟，fake 时钟没推进＝没建帧）。
      await tester.pump();
      final toast = generatedToast(tester);
      expect(toast, isNotEmpty,
          reason: '导出完成必须给可见回执；日志尾＝'
              '${AppLog.allText().split("\n").where((l) => l.contains("导出")).join(" ⏎ ")}');

      final csv = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.csv'))
          .toList();
      expect(csv, hasLength(1), reason: '导出要落在注入的目录里（生产＝应用文档目录）');
      final base = csv.single.path.split(RegExp(r'[\\/]')).last;
      expect(base, matches(RegExp(r'^health_\d{8}_\d{6}\.csv$')));
      final text = csv.single.readAsStringSync();
      expect(text.split('\n').first, healthCsvHeader);
      expect(text, contains('${dk(0)},喝水,3 杯,,'));
      expect(text, contains('${dk(40)},喝水,5 杯,,'));

      // 提示四件实话：文件名＋范围条数＋敏感＋落点（工单 §3 明令）。
      expect(toast, contains(base));
      expect(toast, contains('本机全部 2 条'));
      expect(toast, contains(healthExportSensitiveNote));
      expect(toast, contains('落点'),
          reason: '给真实路径（原型那句「落点见「数据与同步」」在这台机上不成立）');
    });
  });
}
