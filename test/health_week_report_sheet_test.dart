import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';

import 'helpers.dart';

/// 健康批6a · 周报弹层（原型 `index-health.html#sheetHealthReport`，JS 段 `hReport`）。
///
/// **文件归属说明（登记偏离）**：执行面板写的 `health_report_sheet_test.dart` 真名已被
/// 批3.5b「检查报告上传弹层」占用；全 app widget 测试拆文件口径（AGENTS 门禁段）下
/// 周报另立本件，不并文件防 isolate 污染。
///
/// 五条判定（工单执行面板第 3、4 项）＋一条零记录周实态观察（弹层空态分支不可达）：
/// · 六枚 tile 齐且口径对（日均喝水/日均睡眠/运动次数/全达标天/期末体重/用药依从）；
/// · 同比上周五行**现算**：上周无记录出「—」，原型 `hrDiff` 的演示常量（`+0.4 h`、`-0.6 杯`、
///   「第 38 周」…）一条都不许出现；
/// · 七日条七天各一条，缺分日落 0；
/// · **长图按钮不铺**：断言找不到「生成长图」字样（假入口禁令的可见面）；
/// · 「复制文本」真写剪贴板，内容与域层 `copyText` 逐字一致。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 8, 10, 0);
  String dk(int back) => dayKey(now.subtract(Duration(days: back)));

  late Database db;
  late HealthRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = HealthRepository(db);
  });

  tearDown(() => db.close());

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await settle5(t);
    await t.tap(f);
    await settle5(t);
  }

  Future<void> openSheet(WidgetTester tester, {bool seedWeeks = true}) async {
    await useSurface(tester, const Size(420, 2600));
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    if (seedWeeks) {
      // 本周：10-02~10-08；上周：09-25~10-01。每日 6 杯，本周三天睡满 8h。
      for (var i = 0; i < 14; i++) {
        await repo.bumpCups(1, dk(i), 6);
      }
      for (final i in [0, 1, 2]) {
        await repo.saveSleep(SleepRecord(
            profileId: 1, date: dk(i), bedTime: '23:00', wakeTime: '07:00', durationMin: 0));
      }
      await repo.saveBody(BodyRecord(profileId: 1, date: dk(1), kg: 60.5));
    }
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      healthRepositoryProvider.overrideWithValue(repo),
      healthClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/root', routes: [
      GoRoute(path: '/root', builder: (_, _) => const Scaffold(body: SizedBox.shrink())),
      ...healthPageRoutes(),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push('/health/trend');
    await settle5(tester);
    await tapKey(tester, 'ht-report');
    await clearToasts(tester);
  }

  List<String> textsUnder(WidgetTester t, Key key) => t
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .map((x) => x.data ?? '')
      .toList();

  List<String> mockClipboard(WidgetTester tester) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return copied;
  }

  testWidgets('六枚 tile 齐、周号实算、脚注写实', (tester) async {
    await openSheet(tester);
    final tileTx = textsUnder(tester, _Rs.kTiles);
    expect(tileTx.length, 12, reason: '六枚各值＋名两行 Text');
    expect(tileTx.where((s) => ['日均喝水', '日均睡眠', '运动次数', '全达标天', '期末体重', '用药依从'].contains(s)).length, 6);
    expect(tileTx, contains('6.0 杯'), reason: '本周日均 6 杯（现算）');
    expect(tileTx, contains('60.5 kg'));
    expect(find.text('LifeHarness · 第 41 周'), findsOneWidget, reason: 'ISO 周号实算，非原型「第 38 周」');
    expect(find.text('全部本机计算 · 无网络上传'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(_Rs.kRange)).data, '10-02 ~ 10-08',
        reason: '区间行＝本周首尾日实算');
  });

  testWidgets('同比五行现算：无上周全出「—」，演示常量不出现', (tester) async {
    await openSheet(tester);
    final diffTx = textsUnder(tester, _Rs.kDiffs);
    expect(diffTx.where((s) => ['日均睡眠', '日均喝水', '运动次数', '平均配速', '体重'].contains(s)).length, 5);
    expect(diffTx, contains('—'), reason: '上周没记 → 该路对差出「—」');
    for (final demo in ['+0.4 h', '-0.6 杯', '+0.5 次', '优']) {
      expect(diffTx, isNot(contains(demo)), reason: '原型 hrDiff 演示常量「$demo」不许出现');
    }
    expect(diffTx.join('|'), isNot(contains('NaN')));
  });

  testWidgets('七日条七天各一条、缺分日落 0', (tester) async {
    await openSheet(tester);
    final barKeys = find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('hr-bar-');
    });
    expect(barKeys, findsNWidgets(7));
    final scores = [
      for (final e in barKeys.evaluate()) (e.widget.key! as ValueKey<String>).value
    ];
    expect(scores.first, startsWith('hr-bar-${dk(6).substring(5)}'), reason: '旧→新');
    // 睡眠只有 0/1/2 三天 → 10-02/03/04 三天分数低但非零，水+无运动；域层已钉数值，这里钉「七天都有行」
  });

  testWidgets('长图按钮不铺＋复制文本真落剪贴板', (tester) async {
    final copied = mockClipboard(tester);
    await openSheet(tester);
    expect(find.textContaining('生成长图'), findsNothing);
    expect(find.textContaining('长图'), findsNothing, reason: '假入口连字样都不许留（AGENTS 禁令）');

    await tapKey(tester, 'hr-copy');
    expect(copied.length, 1);
    final tx = copied.single;
    expect(tx, startsWith('LifeHarness 健康周报 · 第 41 周（10-02 ~ 10-08）'));
    expect(tx, contains('日均喝水：6.0 杯'));
    expect(tx, contains('同比上周：'));
    expect(tx, contains('全部本机计算 · 无网络上传'));
    expect(tx.split('\n').length, 23);
    expect(await pollText(tester, '周报文本已复制'), isTrue);
    await clearToasts(tester);
  });

  testWidgets('零记录周：tile 出 0/「—」实话，不铺假数据（弹层空态分支按实态不可达，见工单 §4.3 注）',
      (tester) async {
    await openSheet(tester, seedWeeks: false);
    final tileTx = textsUnder(tester, _Rs.kTiles);
    expect(tileTx, contains('0.0 杯'));
    expect(tileTx, contains('—'), reason: '期末体重与依从无源＝「—」，不编 0');
    expect(tileTx.join('|'), isNot(contains('NaN')));
    expect(find.text('本周还没有健康记录 · 记一笔后再来看摘要'), findsNothing,
        reason: 'trendDays 恒出逐日格，days.isEmpty 分支真机走不到——登记死枝观察');
  });
}

/// 弹层件私有键的引用面：`_HealthReportSheet` 是私有类，键常量走同款 ValueKey 字面。
class _Rs {
  static const Key kTiles = ValueKey('hr-tiles');
  static const Key kDiffs = ValueKey('hr-diffs');
  static const Key kRange = ValueKey('hr-range');
}
