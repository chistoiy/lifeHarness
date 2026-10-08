import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/health/data/health_repository.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_symptom.dart';
import 'package:lifeharness/features/health/presentation/health_providers.dart';
import 'package:lifeharness/features/health/presentation/health_routes.dart';
import 'package:lifeharness/features/health/presentation/health_symptom_page.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 健康批3.5a · 症状与不适屏（原型 `tools/health/v2_pages.html#p-symptom`）。
///
/// 六条判定（工单执行面板第 4 项）：
/// · **五块同源**：发作卡与直方图看全量，词云与流水看筛选后的子集（原型 `syRender` 就是先算
///   live/hist 再 `filter(part)`）——点部位后发作卡必须一动不动，否则两处各取各的数；
/// · 部位**包含匹配**：一条「头部·四肢」的记录，点头部或四肢都在，两处筛选结果有交集；
/// · 「标记结束」写库后整屏重取：发作卡少一行、计数改口、流水副行的「持续 X」当场 +15 分钟；
/// · 档案 chips 切换＝整模块重取，**跨档案不聚合**（§11.1），别人档案的行一枚不出；
/// · 删除走二次确认，确认后流水与发作卡同步收窄；
/// · 部位角标只给真出现过的部位（「全部」与零条部位不写 0）。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定钟 `now` 构造，禁写死今天。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19, 10, 30);
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

  /// 症状屏 pump：建库＋固定钟＋模块真实路由（栈页一律 push）。
  Future<(ProviderContainer, GoRouter)> pumpSym(WidgetTester tester) async {
    await useSurface(tester, const Size(420, 2400));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
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
    router.push('/health/symptom');
    await settle5(tester);
    return (container, router);
  }

  String keyText(WidgetTester t, String key) =>
      (t.widget<Text>(find.byKey(ValueKey(key)))).data ?? '';

  /// 等级徽标的 key 挂在外壳 Container 上（着色的是底），读数要往里面取那枚 Text。
  String badgeText(WidgetTester t, String key) => (t.widget<Text>(
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))))
      .data ?? '';

  /// 点弹层里的按钮：症状表体比外壳的 640 上限高，底部的取消/保存落在滚动区视口外
  /// （中心坐标会算到屏幕下方），必须先滚进视口再点，否则 tap 打空。
  Future<void> tapSheet(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await settle5(t);
    await t.tap(f);
  }

  /// 流水行的键序（最新在上）。
  List<String> rowKeys(WidgetTester t) => t
      .widgetList<InkWell>(find.byType(InkWell))
      .map((r) => r.key)
      .whereType<ValueKey<String>>()
      .map((k) => k.value)
      .where((v) => v.startsWith('hsym-row-'))
      .toList();

  /// 发作卡行——与流水行分开数，别把「发作中」那一行当成两条记录。
  List<String> liveKeys(WidgetTester t) => t
      .widgetList<Row>(find.byType(Row))
      .map((r) => r.key)
      .whereType<ValueKey<String>>()
      .map((k) => k.value)
      .where((v) => v.startsWith('hsym-live-row-'))
      .toList();

  /// 部位行里的 chips（档案 chips 行也是 PillChip，所以按 kParts 收口再数）。
  List<String> partLabels(WidgetTester t) => t
      .widgetList<PillChip>(find.descendant(
          of: find.byKey(HealthSymptomPage.kParts), matching: find.byType(PillChip)))
      .map((c) => c.label)
      .toList();

  /// 四条种子：A/B 发作中（30 分/90 分），C 已结束且带药标与两图，D 只属于别人档案。
  Future<(int, int, int, int)> seedFour() async {
    final a = await repo.addSymptom(const SymptomRecord(
        profileId: 1,
        date: '2026-09-19',
        time: '08:00',
        name: '头痛',
        level: 6,
        parts: ['头部', '四肢'],
        durationMin: 30,
        desc: '右侧太阳穴跳痛',
        ongoing: true));
    final b = await repo.addSymptom(const SymptomRecord(
        profileId: 1,
        date: '2026-09-18',
        time: '21:00',
        name: '乏力',
        level: 2,
        parts: ['全身'],
        durationMin: 90,
        trig: '熬夜后',
        ongoing: true));
    final c = await repo.addSymptom(const SymptomRecord(
        profileId: 1,
        date: '2026-09-17',
        time: '12:00',
        name: '腹痛',
        level: 8,
        parts: ['胸腹'],
        durationMin: 45,
        desc: '阵发，绞痛，汗',
        drugRelated: true,
        photos: ['p1', 'p2']));
    final d = await repo.addSymptom(const SymptomRecord(
        profileId: 2, date: '2026-09-19', name: '咳嗽', level: 3, durationMin: 20));
    return (a, b, c, d);
  }

  testWidgets('空白档案：发作卡出「无」＋空态、直方图仍有 11 根柱、流水出空态', (tester) async {
    await pumpSym(tester);
    expect(find.text('症状与不适'), findsOneWidget);
    expect(keyText(tester, 'hsym-live-n'), '无');
    expect(find.text(symLiveEmptyTx), findsOneWidget);
    expect(find.byKey(HealthSymptomPage.kLive), findsNothing);
    // 直方图是「刻度」而不是「数据」：零记录也要铺满 0~10 十一根矮柱，不能画成空卡片。
    for (var i = 0; i <= 10; i++) {
      expect(find.byKey(ValueKey('hsym-hist-$i')), findsOneWidget);
    }
    expect(find.text('0 ~ 10 分'), findsOneWidget);
    expect(keyText(tester, 'hsym-cloud-n'), '暂无文本');
    expect(find.byType(EmptyDashRow), findsOneWidget);
    expect(find.text(symEmptyTx), findsOneWidget);
    expect(find.byKey(HealthSymptomPage.kList), findsNothing);
    // 部位行＝「全部」＋原型七枚（横向懒构建：视口外的「全身」这轮还不建）。
    expect(partLabels(tester), ['全部', ...symParts.take(6)]);
    await tester.drag(find.byKey(HealthSymptomPage.kParts), const Offset(-200, 0));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hsym-part-全身')), findsOneWidget);
    expect(find.byKey(const ValueKey('hsym-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('hsym-add-inline')), findsOneWidget);
  });

  testWidgets('三条种子：发作卡计数、流水倒序、用药相关角标与照片计数都在', (tester) async {
    final (a, b, c, _) = await seedFour();
    await pumpSym(tester);

    expect(keyText(tester, 'hsym-live-n'), '2 项');
    // 发作卡＝取数序（date ASC）：发作最早、拖得最久的那条在最上面；
    // 与流水的「最新在上」刻意相反（原型 `syRender`：live 直接 filter 不 sort，list 才 sort）。
    expect(liveKeys(tester), ['hsym-live-row-$b', 'hsym-live-row-$a']);
    expect(find.text('头痛 · 头部·四肢 · 6 分'), findsOneWidget);
    expect(find.byKey(ValueKey('hsym-end-$a')), findsOneWidget);

    expect(rowKeys(tester).length, 3, reason: '别人档案那条（d）一枚都不出现');
    expect(find.byKey(ValueKey('hsym-row-$a')), findsOneWidget);
    expect(
        find.text('2026-09-17 12:00 · 胸腹 · 持续 45 分钟 · 照片 2 · 阵发，绞痛，汗'), findsOneWidget);
    expect(find.text('用药相关'), findsOneWidget, reason: '§184：药物不良反应靠这枚角标承载');
    // 徽标上屏的就是存量分（6/2/8），色档由域层给——这里只钉读数不糊颜色。
    expect(badgeText(tester, 'hsym-badge-$a'), '6');
    expect(badgeText(tester, 'hsym-badge-$b'), '2');
    expect(badgeText(tester, 'hsym-badge-$c'), '8');
    expect(keyText(tester, 'hsym-cloud-n'), '7 个高频词',
        reason: '三源切词：头痛/右侧太阳穴跳痛/乏力/熬夜后/腹痛/阵发/绞痛');
    expect(find.byKey(const ValueKey('hsym-word-汗')), findsNothing,
        reason: '「，汗」这种单字不进榜（刀2 在屏上的那一半：摘掉长度守卫就会多出一枚）');
  });

  testWidgets('部位筛选＝包含匹配且只收窄流水与词云：发作卡纹丝不动', (tester) async {
    final (a, b, c, _) = await seedFour();
    await pumpSym(tester);
    expect(rowKeys(tester).length, 3);

    // 「头部」只命中 A（A 同时带头部与四肢）。
    await tester.tap(find.byKey(const ValueKey('hsym-part-头部')));
    await settle5(tester);
    expect(rowKeys(tester), ['hsym-row-$a']);
    expect(find.byKey(ValueKey('hsym-row-$c')), findsNothing);
    expect(liveKeys(tester), ['hsym-live-row-$b', 'hsym-live-row-$a'],
        reason: '发作卡看全量：筛部位不该把 B 滤掉');

    // 同一个 A 在「四肢」下也在——两处筛选结果有交集才算包含匹配。
    await tester.tap(find.byKey(const ValueKey('hsym-part-四肢')));
    await settle5(tester);
    expect(rowKeys(tester), ['hsym-row-$a']);

    await tester.tap(find.byKey(const ValueKey('hsym-part-胸腹')));
    await settle5(tester);
    expect(rowKeys(tester), ['hsym-row-$c']);
    expect(find.byKey(const ValueKey('hsym-hist-6')), findsOneWidget,
        reason: '直方图是刻度盘，筛选不改桶');

    await tester.tap(find.byKey(const ValueKey('hsym-part-全部')));
    await settle5(tester);
    expect(rowKeys(tester).length, 3);
    expect(find.byKey(ValueKey('hsym-row-$b')), findsOneWidget);
  });

  testWidgets('词云跟着筛选走（与流水同一份子集）', (tester) async {
    final (a, _, c, _) = await seedFour();
    await pumpSym(tester);
    // 筛到「胸腹」只剩 C：榜里只剩 C 自己的词。
    await tester.tap(find.byKey(const ValueKey('hsym-part-胸腹')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('hsym-word-阵发')), findsOneWidget);
    expect(find.byKey(const ValueKey('hsym-word-绞痛')), findsOneWidget);
    expect(keyText(tester, 'hsym-cloud-n'), '3 个高频词');
    expect(find.byKey(const ValueKey('hsym-word-右侧太阳穴跳痛')), findsNothing,
        reason: 'A（id=$a）已被筛掉，它的描述词不该还留在榜上');
    expect(find.byKey(ValueKey('hsym-row-$c')), findsOneWidget);
  });

  testWidgets('标记结束：发作卡当场少一行、计数改口、流水副行时长 +15 分钟', (tester) async {
    final (a, b, _, _) = await seedFour();
    final (container, _) = await pumpSym(tester);
    expect(keyText(tester, 'hsym-live-n'), '2 项');

    await tester.tap(find.byKey(ValueKey('hsym-end-$a')));
    await settle5(tester);
    expect(find.text(symEndTx), findsOneWidget);
    expect(keyText(tester, 'hsym-live-n'), '1 项');
    expect(liveKeys(tester), ['hsym-live-row-$b'], reason: '只剩 B 在发作');
    expect(find.byKey(ValueKey('hsym-live-row-$a')), findsNothing);
    // 流水行还在，但「发作中」掉了、时长 30→45。
    expect(find.byKey(ValueKey('hsym-row-$a')), findsOneWidget);
    expect(find.text('头痛 · 头部·四肢 · 6 分'), findsNothing);
    expect(find.text('头痛 · 发作中'), findsNothing);
    expect(find.text('2026-09-19 08:00 · 头部·四肢 · 持续 45 分钟 · 右侧太阳穴跳痛'), findsOneWidget);

    final stored =
        (await container.read(healthRepositoryProvider).symptoms(1)).firstWhere((s) => s.id == a);
    expect(stored.ongoing, isFalse);
    expect(stored.durationMin, 45);
  });

  testWidgets('删除走二次确认：取消不动一行，确认后流水与发作卡同步收窄', (tester) async {
    final (a, _, _, _) = await seedFour();
    await pumpSym(tester);
    expect(rowKeys(tester).length, 3);

    await tester.tap(find.byKey(ValueKey('hsym-del-$a')));
    await settle5(tester);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.text(symDelTx), findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.text('取消')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hsym-row-$a')), findsOneWidget);
    expect(rowKeys(tester).length, 3);

    await tester.tap(find.byKey(ValueKey('hsym-del-$a')));
    await settle5(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')));
    await settle5(tester);
    expect(find.byKey(ValueKey('hsym-row-$a')), findsNothing);
    expect(rowKeys(tester).length, 2);
    expect(keyText(tester, 'hsym-live-n'), '1 项', reason: '发作卡与流水同源，一起收窄');
    expect(find.text('已删除'), findsOneWidget);
    expect(await repo.symptoms(1), hasLength(2));
  });

  testWidgets('档案 chips 切换＝整模块重取，跨档案不聚合（§11.1）', (tester) async {
    await repo.saveProfile(const HealthProfile(id: 0, name: '小明', rel: '子'));
    final (_, _, _, d) = await seedFour();
    final (container, _) = await pumpSym(tester);
    final fam = (await repo.profiles()).firstWhere((p) => p.rel == '子');
    expect(container.read(activeHealthProfileProvider), 1);

    expect(find.byKey(ValueKey('hsym-profile-${fam.id}')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('hsym-profile-${fam.id}')));
    await settle5(tester);
    expect(container.read(activeHealthProfileProvider), fam.id);
    // 别人档案只有 D 一条（咳嗽，无时刻无部位）。
    expect(rowKeys(tester), ['hsym-row-$d']);
    expect(find.text('2026-09-19 · 全身 · 持续 20 分钟'), findsOneWidget);
    expect(keyText(tester, 'hsym-live-n'), '无', reason: 'D 没标发作中，不把我的发作算到孩子头上');
  });

  testWidgets('部位角标只给真出现过的部位：「全部」与零条部位不写 0', (tester) async {
    await seedFour();
    await pumpSym(tester);
    final labels = partLabels(tester);
    expect(labels.first, '全部');
    expect(labels, containsAll(<String>['头部 1', '四肢 1', '胸腹 1']));
    expect(labels.where((l) => l.endsWith(' 0')), isEmpty, reason: '写 0 会被读成「有 0 次」');
    expect(labels, contains('关节'), reason: '没出现过的部位只留名字，不带条数');
  });

  testWidgets('点流水行＝就地改（带原读数），顶栏与卡内「＋ 记录」开空表', (tester) async {
    final (a, _, _, _) = await seedFour();
    await pumpSym(tester);

    await tester.tap(find.byKey(ValueKey('hsym-row-$a')));
    await settle5(tester);
    expect(find.text('修改 2026-09-19 的症状'), findsOneWidget);
    expect(find.byKey(const ValueKey('hsy-save')), findsOneWidget);
    await tapSheet(tester, 'hsy-cancel');
    await settle5(tester);
    expect(find.byKey(const ValueKey('hsy-save')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('hsym-add')));
    await settle5(tester);
    expect(find.text('记录症状'), findsOneWidget);
    await tapSheet(tester, 'hsy-cancel');
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('hsym-add-inline')));
    await settle5(tester);
    expect(find.text('记录症状'), findsOneWidget);
    await tapSheet(tester, 'hsy-cancel');
    await settle5(tester);
    expect(rowKeys(tester).length, 3, reason: '三次开关弹层都不该改写流水');
  });
}
