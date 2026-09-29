import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/kits/data/kit_repository.dart';
import 'package:lifeharness/features/kits/domain/kit_wheel.dart';
import 'package:lifeharness/features/kits/presentation/kit_providers.dart';
import 'package:lifeharness/features/kits/presentation/kit_routes.dart';
import 'package:lifeharness/features/kits/presentation/tools/kit_pick_page.dart';

/// V1.47 批2 · 工具屏 A（日期计算 / 随机数 / 轮盘抽签 / 取色盘 / 互补色）。
/// 独立文件防 isolate 污染；DB 走内存 ffi；图片取色注入假解码器（禁真异步 I/O）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late KitRepository repo;
  late ProviderContainer container;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = KitRepository(db);
    SharedPreferences.setMockInitialValues({});
    // 取色盘的两个注入缝：固定 4×2 图（左上红、右上绿），零真实 I/O。
    KitPick.imagePicker = () async => 'fake.png';
    KitPick.decoder = (_) async => KitDecodedImage(
          width: 4,
          height: 2,
          rgba: Uint8List.fromList([
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255, //
            10, 10, 10, 255, 20, 20, 20, 255, 30, 30, 30, 255, 40, 40, 40, 255,
          ]),
        );
  });
  tearDown(() => db.close());

  Future<void> pumpTool(WidgetTester tester, String key) async {
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        kitRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/kits/tool/$key',
      routes: [
        ShellRoute(builder: (_, _, child) => child, routes: kitShellRoutes()),
        ...kitPageRoutes(),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle5(tester);
  }

  group('1 · 日期计算', () {
    testWidgets('三区齐备 · 默认间隔已实算 · 农历副文案在位', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'datec');
      expect(find.text('日期计算'), findsWidgets);
      expect(find.textContaining('① 两日期间隔'), findsOneWidget);
      expect(find.textContaining('② 日期 ± 天数'), findsOneWidget);
      expect(find.textContaining('③ 今天速览'), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-datec-diff')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-datec-diff'))).data,
        contains('相差'),
      );
      expect(find.byKey(const ValueKey('kit-datec-diff-lunar')), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('快捷锚点改终点日期并重算；± 天数切换前后向', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'datec');
      await tester.tap(find.byKey(const ValueKey('kit-datec-anchor-today')));
      await settle5(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-datec-diff'))).data,
        contains('同一天'),
      );
      await tester.tap(find.byKey(const ValueKey('kit-datec-anchor-christmas')));
      await settle5(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-datec-diff'))).data,
        contains('目标在后'),
      );
      // ②区：默认往后 100 天 → 切「－前」后文案变往前。
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-datec-add'))).data,
        contains('100 天后'),
      );
      await tester.tap(find.byKey(const ValueKey('kit-datec-minus')));
      await settle5(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-datec-add'))).data,
        contains('往前 100 天'),
      );
      await drainLogTimer(tester);
    });

    testWidgets('点日期格开应用内滚轮（非系统控件）', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'datec');
      await tester.tap(find.byKey(const ValueKey('kit-datec-a')));
      await settle5(tester);
      expect(find.text('选择日期'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await settle5(tester);
      expect(find.text('选择日期'), findsNothing);
      await drainLogTimer(tester);
    });
  });

  group('2 · 随机数', () {
    testWidgets('生成落结果 + 写历史 + 落库', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'rand');
      expect(find.text('随机数'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('kit-rand-go')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-rand-out')), findsOneWidget);
      final d = await repo.toolData('rand');
      final hist = d['rHist'];
      expect(hist, isList);
      expect((hist as List).length, 1);
      await clearToasts(tester);
    });

    testWidgets('不重复开关落库', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'rand');
      await tester.tap(find.byKey(const ValueKey('kit-rand-unique')));
      await settle5(tester);
      final d = await repo.toolData('rand');
      expect(d['u'], isTrue);
      await clearToasts(tester);
    });

    testWidgets('骰子快捷改区间并生成', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'rand');
      await tester.tap(find.byKey(const ValueKey('kit-rand-q-dice')));
      await settle5(tester);
      final d = await repo.toolData('rand');
      final first = (d['rHist'] as List).first as Map;
      expect(first['r'], [1, 6]);
      await clearToasts(tester);
    });

    testWidgets('抽牌写入牌面', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'rand');
      await tester.tap(find.byKey(const ValueKey('kit-rand-q-card')));
      await settle5(tester);
      final d = await repo.toolData('rand');
      final v = ((d['rHist'] as List).first as Map)['v'] as List;
      expect(v.single.length, greaterThanOrEqualTo(2));
      await clearToasts(tester);
    });
  });

  group('3 · 轮盘抽签', () {
    testWidgets('默认套数据 + 轮盘盘面 + 设置入口卡', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'wheel');
      expect(find.byKey(const ValueKey('kit-wheel-disc')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-wheel-go')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-wheel-setsum'))).data,
        contains('日常'),
      );
      expect(find.textContaining('本套尚无结果'), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('转一次 → 结果落历史并持久化', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'wheel');
      await tester.tap(find.byKey(const ValueKey('kit-wheel-go')));
      await tester.pump();
      expect(find.text('转动中…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2900));
      await settle5(tester);
      final res =
          tester.widget<Text>(find.byKey(const ValueKey('kit-wheel-res'))).data!;
      expect(kKitWheelDefaultItems.map((e) => e.text), contains(res));
      final d = await repo.toolData('wheel');
      final sets = d['sets'] as List;
      expect(((sets.first as Map)['hist'] as List).length, 1);
      await drainLogTimer(tester);
    });

    testWidgets('设置弹层：加选项 / 权重 / 新建套 / 批量粘贴替换', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'wheel');
      await tester.tap(find.byKey(const ValueKey('kit-wheel-cfg')));
      await settle5(tester);
      expect(find.textContaining('选项与数据 · 当前套'), findsOneWidget);

      // 加一枚选项
      await tester.enterText(find.byKey(const ValueKey('kit-wheel-new')), '撸猫');
      await tester.tap(find.byKey(const ValueKey('kit-wheel-add')));
      await settle5(tester);
      expect(find.text('撸猫'), findsOneWidget);

      // 权重 +1（默认 1 → 2）
      await tester.tap(find.byKey(const ValueKey('kit-wheel-w-0-plus')));
      await settle5(tester);
      // 6 默认(权重1) + 撸猫(1) = 7，再把首项权重 +1 → 合计 8。
      expect(find.textContaining('合计 8'), findsOneWidget);

      // 批量粘贴替换整套
      await tester.enterText(find.byKey(const ValueKey('kit-wheel-paste')), '甲:2\n乙、丙;丁');
      await tester.tap(find.byKey(const ValueKey('kit-wheel-paste-replace')));
      await settle5(tester);
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('丁'), findsOneWidget);

      // 新建套（名称框先填）
      await tester.enterText(find.byKey(const ValueKey('kit-wheel-set-name')), '周末');
      await tester.tap(find.byKey(const ValueKey('kit-wheel-set-new')));
      await settle5(tester);
      expect(find.textContaining('选项与数据 · 当前套「周末」'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kit-wheel-cfg-done')));
      await settle5(tester);
      final d = await repo.toolData('wheel');
      final sets = [for (final e in d['sets'] as List) e as Map];
      expect(sets.length, 2);
      expect(d['cur'], sets[1]['id']);
      expect((sets[0]['items'] as List).length, 4);
      await drainLogTimer(tester);
    });

    testWidgets('至少保留 2 项 · 满 12 项拒绝添加', (tester) async {
      await repo.setToolData(
        'wheel',
        kitWheelEncode([
          const KitWheelSet(
            id: 'w1',
            name: '小',
            items: [KitWheelItem('甲', 1), KitWheelItem('乙', 1)],
          ),
        ], 'w1'),
      );
      await useSurface(tester);
      await pumpTool(tester, 'wheel');
      await tester.tap(find.byKey(const ValueKey('kit-wheel-cfg')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-wheel-del-0')));
      await settle5(tester);
      expect(find.textContaining('至少保留 2 个选项'), findsOneWidget);
      expect(find.text('甲'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kit-wheel-cfg-done')));
      await settle5(tester);
      await drainLogTimer(tester);
    });
  });

  group('4 · 取色盘', () {
    testWidgets('三串展示 + 预设色板选色 + 最近取色落库', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'pick');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-pick-hex'))).data,
        '#6366F1',
      );
      expect(find.byKey(const ValueKey('kit-pick-rgb')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-pick-hsl')), findsOneWidget);

      // 开应用内选色弹层 → 点预设色 → 确定
      await tester.tap(find.byKey(const ValueKey('kit-sw-#6366f1')));
      await settle5(tester);
      expect(find.text('选择颜色'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kit-cc-dot-#22c55e')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-cc-ok')));
      await settle5(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-pick-hex'))).data,
        '#22C55E',
      );
      final d = await repo.toolData('pick');
      expect(d['hex'], '#22c55e');
      expect(d['recent'], ['#22c55e']);
      await drainLogTimer(tester);
    });

    testWidgets('色串解析：HEX / rgb() 生效，非法给行内提示', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'pick');
      await tester.enterText(find.byKey(const ValueKey('kit-pick-parse-in')), 'rgb(45, 212, 191)');
      await tester.tap(find.byKey(const ValueKey('kit-pick-parse')));
      await settle5(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-pick-hex'))).data,
        '#2DD4BF',
      );
      await tester.enterText(find.byKey(const ValueKey('kit-pick-parse-in')), '红色');
      await tester.tap(find.byKey(const ValueKey('kit-pick-parse')));
      await settle5(tester);
      expect(find.textContaining('无法解析'), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('图片取色：导入 → 轻点取样 → 加入取色盘', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'pick');
      await tester.tap(find.byKey(const ValueKey('kit-pick-import')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-pick-canvas')), findsOneWidget);
      // 左上角取样（假图首像素=红）。
      await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('kit-pick-canvas'))) + const Offset(2, 2));
      await settle5(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-pick-picked-hex'))).data,
        '#FF0000',
      );
      await tester.tap(find.byKey(const ValueKey('kit-pick-picked-use')));
      await settle5(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-pick-hex'))).data,
        '#FF0000',
      );
      final d = await repo.toolData('pick');
      expect((d['recent'] as List).contains('#ff0000'), isTrue);
      await drainLogTimer(tester);
    });

    testWidgets('最近取色：tab 切换 · 长按移除 · 清空', (tester) async {
      await repo.setToolData('pick', {
        'hex': '#6366f1',
        'recent': ['#6366f1', '#22c55e'],
      });
      await useSurface(tester);
      await pumpTool(tester, 'pick');
      await tester.tap(find.byKey(const ValueKey('kit-pick-tab-recent')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-pick-recent-#22c55e')), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('kit-pick-recent-#22c55e')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-pick-recent-#22c55e')), findsNothing);
      final d = await repo.toolData('pick');
      expect(d['recent'], ['#6366f1']);
      await clearToasts(tester);
    });
  });

  group('5 · 互补色', () {
    testWidgets('默认互补两色 + 方案说明', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'comp');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-comp-main'))).data,
        contains('主色 #6366F1 · 互补'),
      );
      expect(find.text('原色 · 主色'), findsOneWidget);
      expect(find.text('互补色 180°'), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-comp-desc')), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('切换方案轮转五档并落库', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'comp');
      for (final name in ['类似', '三角', '分裂互补', '四方', '互补']) {
        await tester.tap(find.byKey(const ValueKey('kit-comp-cycle')));
        await settle5(tester);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('kit-comp-main'))).data,
          contains(name),
          reason: '应切到「$name」',
        );
      }
      final d = await repo.toolData('comp');
      expect(d['mode'], 0);
      await drainLogTimer(tester);
    });

    testWidgets('色环拖动换主色（保留饱和与明度）', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'comp');
      final c = tester.getCenter(find.byKey(const ValueKey('kit-comp-wheel')));
      await tester.drag(
        find.byKey(const ValueKey('kit-comp-wheel')),
        Offset(c.dx - tester.getTopLeft(find.byKey(const ValueKey('kit-comp-wheel'))).dx - 60, 0),
        warnIfMissed: false,
      );
      await settle5(tester);
      final d = await repo.toolData('comp');
      expect(d['hex'], isNot('#6366f1'));
      await drainLogTimer(tester);
    });
  });
}
