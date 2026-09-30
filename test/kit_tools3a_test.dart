
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/kits/data/kit_repository.dart';
import 'package:lifeharness/features/kits/presentation/kit_providers.dart';
import 'package:lifeharness/features/kits/presentation/kit_routes.dart';

/// V1.47 批3 · 工具屏 B 上半（尺子 / 测距）。
/// 反馈轮4：Ping 与网络测速两件按产品裁定摘除，本文件只留长度类两屏。
/// 独立文件防 isolate 污染；DB 走内存 ffi；随机源一律注入固定种子。
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

  /// 读某键上的文案（键可能挂在外层 Container / SizedBox 徽标上）。
  String textOf(WidgetTester tester, String key) {
    final direct = find.byKey(ValueKey(key));
    if (tester.widget(direct) is Text) {
      return tester.widget<Text>(direct).data ?? '';
    }
    return tester
        .widget<Text>(
          find.descendant(of: direct, matching: find.byType(Text)).first,
        )
        .data ??
        '';
  }

  /// 徽标里的数值（`1.024×` → 1.024）。
  double numOf(WidgetTester tester, String key) =>
      double.parse(textOf(tester, key).replaceAll('×', '').trim());

  /// 读数里的整数毫米（`92 mm` → 92）。
  int mmOf(WidgetTester tester, String key) =>
      int.parse(textOf(tester, key).split(' ').first);

  group('3 · 尺子', () {
    testWidgets('参数台齐备 · 量程按视口实算 · 倍率 1.000×', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'ruler');
      expect(find.byKey(const ValueKey('kit-ruler-unit-cm')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-ruler-unit-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('kit-ruler-dir-short')), findsOneWidget);
      // 视口逻辑长边 800px × 25.4/160 = 127mm（量程随视口实算，不写死设备型号）。
      expect(textOf(tester, 'kit-ruler-span-card'), '量程 127 mm');
      expect(textOf(tester, 'kit-ruler-cal-v'), '1.000×');
      expect(textOf(tester, 'kit-ruler-last'), '全屏尺子上按住红线滑动即可读数');
      await drainLogTimer(tester);
    });

    testWidgets('切短边后量程变小（长边 → 短边取视口两边的小者）', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'ruler');
      int spanOf() => int.parse(textOf(tester, 'kit-ruler-span-card').split(' ')[1]);
      final longSpan = spanOf();
      await tester.tap(find.byKey(const ValueKey('kit-ruler-dir-short')));
      await settle5(tester);
      final shortSpan = spanOf();
      expect(shortSpan, lessThan(longSpan));
      // 视口 800×600 逻辑像素：长边 127mm / 短边 95mm（=px×25.4/160 取整）。
      expect((longSpan, shortSpan), (127, 95));
      final d = await repo.toolData('ruler');
      expect(d['dir'], 'short');
      await clearToasts(tester);
    });

    testWidgets('换尺边必须真的转屏：长边=横向、短边=竖向', (tester) async {
      await useSurface(tester);
      final calls = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemChrome.setPreferredOrientations') {
              calls.add(call.arguments);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await pumpTool(tester, 'ruler');
      // 默认长边：进入即要求横向；参数台自带方向文案，不点也看得懂。
      expect(calls.last, ['DeviceOrientation.landscapeLeft']);
      expect(textOf(tester, 'kit-ruler-dir-long'), contains('横向'));
      expect(textOf(tester, 'kit-ruler-dir-short'), contains('竖向'));
      calls.clear();
      await tester.tap(find.byKey(const ValueKey('kit-ruler-dir-short')));
      await settle5(tester);
      expect(calls.last, ['DeviceOrientation.portraitUp']);
      calls.clear();
      await tester.tap(find.byKey(const ValueKey('kit-ruler-dir-long')));
      await settle5(tester);
      expect(calls.last, ['DeviceOrientation.landscapeLeft']);
      // 从全屏舞台回到参数台：按当前尺边重新对齐方向（舞台里可能换过尺边）。
      calls.clear();
      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs-close')));
      await settle5(tester);
      expect(calls.last, ['DeviceOrientation.landscapeLeft']);
      await clearToasts(tester);
    });

    testWidgets('全屏舞台：拖动游标改读数 + 落库 + 退出回参数台', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'ruler');
      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs')));
      await settle5(tester);
      // 进入即给量程 40% 的游标初值（原型 rsCur）。
      expect(mmOf(tester, 'kit-ruler-fs-big'), 51);

      // 尺面内向右拖 60 逻辑像素 → 读数跟着游标走。
      await tester.drag(
        find.byKey(const ValueKey('kit-ruler-fs-tape')),
        const Offset(60, 0),
        warnIfMissed: false,
      );
      await settle5(tester);
      final after = textOf(tester, 'kit-ruler-fs-big');
      final cur = mmOf(tester, 'kit-ruler-fs-big');
      expect(cur, isNot(51));
      expect(cur, inInclusiveRange(1, 127));
      expect(textOf(tester, 'kit-ruler-fs-zero-pos'), contains('零点 0 mm'));
      final d = await repo.toolData('ruler');
      expect(d['cur'], cur);
      expect(d['unit'], 'cm');

      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs-close')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-ruler-fs-big')), findsNothing);
      expect(textOf(tester, 'kit-ruler-last'), after);
      await drainLogTimer(tester);
    });

    testWidgets('±1mm 微调 · 零点把手拖动 · in 单位换算', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'ruler');
      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs')));
      await settle5(tester);
      final mm = mmOf(tester, 'kit-ruler-fs-big');
      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs-plus')));
      await settle5(tester);
      expect(textOf(tester, 'kit-ruler-fs-big'), '${mm + 1} mm');
      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs-minus')));
      await settle5(tester);
      expect(textOf(tester, 'kit-ruler-fs-big'), '$mm mm');

      // 零点向右拖 40 逻辑像素（≈7mm）→ 读数变小、零点位置跟着走。
      await tester.drag(
        find.byKey(const ValueKey('kit-ruler-fs-zero')),
        const Offset(40, 0),
        warnIfMissed: false,
      );
      await settle5(tester);
      expect(mmOf(tester, 'kit-ruler-fs-big'), lessThan(mm));
      expect(textOf(tester, 'kit-ruler-fs-zero-pos'), isNot(contains('零点 0 mm')));

      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs-in')));
      await settle5(tester);
      expect(textOf(tester, 'kit-ruler-fs-big'), endsWith('in'));
      await drainLogTimer(tester);
    });

    testWidgets('银行卡校准改倍率并落库 · 重置回 1.000', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'ruler');
      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs')));
      await settle5(tester);
      await tester.drag(
        find.byKey(const ValueKey('kit-ruler-fs-tape')),
        const Offset(60, 0),
        warnIfMissed: false,
      );
      await settle5(tester);
      expect(mmOf(tester, 'kit-ruler-fs-big'), isNot(0));
      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs-bank')));
      await settle5(tester);
      expect(textOf(tester, 'kit-ruler-fs-cal-v'), isNot('1.000×'));
      // 校准结果钉在滑杆区间内（读数小于 74mm 时会顶到 1.15×）。
      expect(numOf(tester, 'kit-ruler-fs-cal-v'), inInclusiveRange(.85, 1.15));
      final d = await repo.toolData('ruler');
      expect(d['cal'], isNot(1.0));
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-ruler-fs-close')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-ruler-cal-reset')));
      await settle5(tester);
      expect(textOf(tester, 'kit-ruler-cal-v'), '1.000×');
      final d2 = await repo.toolData('ruler');
      expect(d2['cal'], 1.0);
      await drainLogTimer(tester);
    });
  });

  group('4 · 测距', () {
    testWidgets('地图模式：提示浮标 + 点选累计 + 撤销/清空', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'dist');
      expect(textOf(tester, 'kit-dist-hint'), contains('模拟地图 · 轻点落点'));
      expect(textOf(tester, 'kit-dist-total'), '总长 0 m · 0 个点');
      expect(find.byKey(const ValueKey('kit-dist-walk')), findsNothing);
      expect(find.byKey(const ValueKey('kit-dist-trail')), findsNothing);

      final canvas = find.byKey(const ValueKey('kit-dist-canvas'));
      final tl = tester.getTopLeft(canvas);
      await tester.tapAt(tl + const Offset(30, 40));
      await settle5(tester);
      await tester.tapAt(tl + const Offset(90, 120));
      await settle5(tester);
      // 像素距离 100 × 2.5m/px = 250m。
      expect(textOf(tester, 'kit-dist-total'), '总长 250 m · 2 个点');
      await tester.tap(find.byKey(const ValueKey('kit-dist-undo')));
      await settle5(tester);
      expect(textOf(tester, 'kit-dist-total'), '总长 0 m · 1 个点');
      await tester.tap(find.byKey(const ValueKey('kit-dist-clear')));
      await settle5(tester);
      expect(textOf(tester, 'kit-dist-total'), '总长 0 m · 0 个点');
      await clearToasts(tester);
    });

    testWidgets('比例尺滑杆改读数并落库 · 距离随比例尺放大', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'dist');
      final canvas = find.byKey(const ValueKey('kit-dist-canvas'));
      final tl = tester.getTopLeft(canvas);
      await tester.tapAt(tl + const Offset(20, 20));
      await settle5(tester);
      await tester.tapAt(tl + const Offset(120, 20));
      await settle5(tester);
      expect(textOf(tester, 'kit-dist-total'), '总长 250 m · 2 个点');

      final slider = find.byKey(const ValueKey('kit-dist-scale'));
      final wide = tester.getRect(slider);
      await tester.drag(slider, Offset(wide.width, 0));
      await settle5(tester);
      expect(textOf(tester, 'kit-dist-scale-v'), '10.0 m/px');
      expect(textOf(tester, 'kit-dist-total'), '总长 1.00 km · 2 个点');
      expect(textOf(tester, 'kit-dist-hint'), contains('1px≈10.0m'));
      final d = await repo.toolData('dist');
      expect(d['distScale'], 10.0);
      expect(d['distMode'], 'map');
      await drainLogTimer(tester);
    });

    testWidgets('GPS 模式：比例尺行隐藏 · 模拟行走 15 点全部实算', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'dist');
      await tester.tap(find.byKey(const ValueKey('kit-dist-mode-gps')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-dist-scale')), findsNothing);
      expect(textOf(tester, 'kit-dist-hint'), 'GPS 轨迹 · 轻点采集定位点 · 大圆距离');
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-dist-walk')));
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 260));
      }
      await settle5(tester);
      final total = textOf(tester, 'kit-dist-total');
      expect(total, contains('15 个点'));
      expect(total, matches(RegExp(r'^总长 \d+(\.\d+)? (m|km) · 15 个点$')));
      expect(textOf(tester, 'kit-dist-trail'), contains(','));
      final d = await repo.toolData('dist');
      expect(d['distMode'], 'gps');
      await pollText(tester, '模拟行走 60s 完成');
      await clearToasts(tester);
    });
  });
}
