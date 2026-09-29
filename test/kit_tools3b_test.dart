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
import 'package:lifeharness/features/kits/domain/kit_imgz.dart';
import 'package:lifeharness/features/kits/presentation/kit_providers.dart';
import 'package:lifeharness/features/kits/presentation/kit_routes.dart';
import 'package:lifeharness/features/kits/presentation/tools/kit_imgz_page.dart';

/// V1.47 批3c · 图片体积缩小屏。
/// 四个环节（取图/解码/压缩/另存）全部走注入缝，用例里不碰真实异步 I/O；
/// 界面上的字节数来自假源真实字节长度，格式与百分比由域层实算。
/// 独立文件防 isolate 污染；DB 走内存 ffi。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late KitRepository repo;
  late ProviderContainer container;

  List<String> pickResult = const [];
  KitImgzSource? Function(String path)? loaderOverride;
  int compressCalls = 0;
  int lastEdge = 0, lastQuality = 0;
  bool lastMark = false;
  int outBytes = 25000;
  String? savedName;
  Uint8List? savedBytes;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = KitRepository(db);
    SharedPreferences.setMockInitialValues({});
    pickResult = const ['/dcim/a.jpg'];
    loaderOverride = null;
    compressCalls = 0;
    lastEdge = 0;
    lastQuality = 0;
    lastMark = false;
    outBytes = 25000;
    savedName = null;
    savedBytes = null;
    KitImgz.pathPicker = () async => pickResult.isEmpty ? null : pickResult;
    KitImgz.loader = (path) async {
      // 显式判空：`override?.call(path) ?? 默认源` 会把「失败=返回 null」吞成默认源。
      if (loaderOverride != null) return loaderOverride!(path);
      return KitImgzSource(
        width: 4000,
        height: 3000,
        bytes: Uint8List(100000),
      );
    };
    KitImgz.compress = (src, edge, quality, mark) async {
      compressCalls++;
      lastEdge = edge;
      lastQuality = quality;
      lastMark = mark;
      final plan = kitImgzPlan(srcW: src.width, srcH: src.height, maxEdge: edge);
      return KitImgzResult(
        outW: plan.outW,
        outH: plan.outH,
        bytes: Uint8List(outBytes),
      );
    };
    KitImgz.save = (name, bytes) async {
      savedName = name;
      savedBytes = bytes;
      return 'C:/down/$name';
    };
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

  String infoOf(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('kit-imgz-info'))).data!;

  group('1 · 参数台', () {
    testWidgets('初始态：默认最长边/质量 · 单选说明 · 参数未落库', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'imgz');
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('kit-imgz-edge')))
            .controller!
            .text,
        '1600',
      );
      expect(find.byKey(const ValueKey('kit-imgz-q')), findsNothing);
      expect(find.byKey(const ValueKey('kit-imgz-q-v')), findsNothing);
      expect(find.byKey(const ValueKey('kit-imgz-info')), findsNothing);
      expect(find.byKey(const ValueKey('kit-imgz-prev')), findsNothing);
      expect(find.text('单选时不产生队列 · 多选后逐张本地压缩'), findsOneWidget);
      expect(compressCalls, 0);
      await drainLogTimer(tester);
    });

    testWidgets('选图后信息行实算 · 质量行出现 · 首压参数随界面', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'imgz');
      await tester.tap(find.byKey(const ValueKey('kit-imgz-pick')));
      await settle5(tester);
      final info = infoOf(tester);
      expect(info, contains('原图 4000×3000 · 98KB'));
      expect(info, contains('缩至 1600×1200'));
      expect(info, contains('体积减少 75.0%'));
      expect(info, contains('JPEG 质量档已生效'));
      expect(compressCalls, 1);
      expect((lastEdge, lastQuality, lastMark), (1600, 60, false));
      expect(find.byKey(const ValueKey('kit-imgz-q')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-imgz-q-v'))).data,
        '60',
      );
      await drainLogTimer(tester);
    });

    testWidgets('水印开关：界面标记 + 重压传参 + 落库 imgzMk', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'imgz');
      await tester.tap(find.byKey(const ValueKey('kit-imgz-pick')));
      await settle5(tester);
      final before = compressCalls;
      await tester.tap(find.byKey(const ValueKey('kit-imgz-mark')));
      await settle5(tester);
      expect(compressCalls, greaterThan(before));
      expect(lastMark, isTrue);
      expect(infoOf(tester), contains('已加右下角水印'));
      final d = await repo.toolData('imgz');
      expect(d['imgzMk'], true);
      expect(d['imgzEdge'], 1600);
      expect(d['imgzQ'], 60);
      await pollText(tester, '右下角水印已加');
      await clearToasts(tester);
    });

    testWidgets('质量滑杆拖到最右=90 · 最长边输入实时重压', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'imgz');
      await tester.tap(find.byKey(const ValueKey('kit-imgz-pick')));
      await settle5(tester);
      final slider = find.byKey(const ValueKey('kit-imgz-q'));
      final wide = tester.getRect(slider);
      await tester.drag(slider, Offset(wide.width, 0));
      await settle5(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('kit-imgz-q-v'))).data,
        '90',
      );
      expect(lastQuality, 90);

      await tester.enterText(find.byKey(const ValueKey('kit-imgz-edge')), '800');
      await settle5(tester);
      expect(lastEdge, 800);
      expect(infoOf(tester), contains('缩至 800×600'));
      final d = await repo.toolData('imgz');
      expect(d['imgzEdge'], 800);
      expect(d['imgzQ'], 90);
      await drainLogTimer(tester);
    });

    testWidgets('WebP 只给待插入口径 · 不谎报格式', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'imgz');
      await tester.tap(find.byKey(const ValueKey('kit-imgz-fmt-webp')));
      await settle5(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('kit-imgz-webp-note')))
            .data,
        contains('WebP 编码器需系统原生通道'),
      );
      await pollText(tester, '已按 JPEG 真实压缩');
      await clearToasts(tester);
      await tester.tap(find.byKey(const ValueKey('kit-imgz-pick')));
      await settle5(tester);
      expect(infoOf(tester), contains('WEBP 质量档已生效'));
      await drainLogTimer(tester);
    });
  });

  group('2 · 批量队列', () {
    testWidgets('多选逐张真压 · 队列行与合计都是真实字节', (tester) async {
      await useSurface(tester);
      pickResult = const ['/dcim/a.jpg', '/dcim/b.jpg', '/dcim/c.jpg'];
      outBytes = 30000;
      await pumpTool(tester, 'imgz');
      await tester.tap(find.byKey(const ValueKey('kit-imgz-pick')));
      await settle5(tester);
      expect(compressCalls, 3);
      expect(find.text('单选时不产生队列 · 多选后逐张本地压缩'), findsNothing);
      expect(find.byKey(const ValueKey('kit-imgz-item-2')), findsOneWidget);
      final sum = tester
          .widget<Text>(find.byKey(const ValueKey('kit-imgz-sum')))
          .data!;
      expect(sum, contains('批量合计 3 张 · 已压 3 张'));
      expect(sum, contains('每张都为本机真实编码'));
      expect(sum, contains('节省 70%'));
      await drainLogTimer(tester);
    });

    testWidgets('清空后回单选口径 · 保存走注入缝并回报路径', (tester) async {
      await useSurface(tester);
      await pumpTool(tester, 'imgz');
      await tester.tap(find.byKey(const ValueKey('kit-imgz-pick')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('kit-imgz-save')));
      await settle5(tester);
      expect(savedName, 'compressed.jpg');
      expect(savedBytes?.length, 25000);
      await pollText(tester, '已保存 24KB → C:/down/compressed.jpg');
      await clearToasts(tester);

      await tester.tap(find.byKey(const ValueKey('kit-imgz-clear')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('kit-imgz-info')), findsNothing);
      expect(find.text('单选时不产生队列 · 多选后逐张本地压缩'), findsOneWidget);
      await drainLogTimer(tester);
    });

    testWidgets('取图取消不动状态 · 解码失败只标失败不给假结果', (tester) async {
      await useSurface(tester);
      pickResult = const [];
      await pumpTool(tester, 'imgz');
      await tester.tap(find.byKey(const ValueKey('kit-imgz-pick')));
      await settle5(tester);
      expect(compressCalls, 0);
      expect(find.byKey(const ValueKey('kit-imgz-info')), findsNothing);

      pickResult = const ['/dcim/bad.jpg'];
      loaderOverride = (_) => null;
      await tester.tap(find.byKey(const ValueKey('kit-imgz-pick')));
      await settle5(tester);
      expect(compressCalls, 0);
      expect(infoOf(tester), contains('本机处理失败'));
      expect(find.text('本机读不到这张图'), findsOneWidget);
      await pollText(tester, '本机读不到这张图');
      await clearToasts(tester);
    });
  });
}
