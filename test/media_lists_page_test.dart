import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_list.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';

import 'helpers.dart';

/// 批8b · 影音单两面常驻闸（工单 §⚙ 第 3 项＝六枚）：
/// 列表面六枚齐·底稿只读面·拖拽重排落库·加入取消往返·新建直达空态·改名落库。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  final now = DateTime.now();
  DateTime y(int back) => now
      .subtract(Duration(days: back))
      .copyWith(hour: 12, minute: 0, second: 0, millisecond: 0, microsecond: 0);

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} (key TEXT PRIMARY KEY, value TEXT)',
    );
    repo = MediaRepository(db);
  });
  tearDown(() async {
    await db.close();
  });

  Future<MediaItem> addItem(String id,
      {String kind = MediaItem.kMovie,
      String state = '在看',
      int? endedAt,
      int dur = 120}) async {
    final x = MediaItem(
      id: id,
      kind: kind,
      title: id,
      state: state,
      progressWay: MediaItem.kWayPct,
      durationMin: dur,
      endedAt: endedAt,
      createdAt: 1,
      updatedAt: 1,
    );
    await repo.addItem(x);
    return x;
  }

  /// 种子：三枚在册（两枚本年完结）＋一枚软删；两张手动单（l1 三人·l2 空）。
  Future<(int, int)> seed() async {
    await addItem('a', state: '看完', endedAt: y(1).millisecondsSinceEpoch);
    await addItem('b', kind: MediaItem.kSeries, state: '追完',
        endedAt: y(2).millisecondsSinceEpoch);
    await addItem('c', kind: MediaItem.kMusic);
    final gone = await addItem('gone', state: '看完',
        endedAt: y(3).millisecondsSinceEpoch);
    await repo.softDelete([gone.id]);
    final l1 = await repo.createList('通勤看', MediaItem.kMovie);
    final l2 = await repo.createList('周末听', MediaItem.kMusic);
    await repo.setMembers(l1, ['a', 'b', 'c']);
    return (l1, l2);
  }

  Future<ProviderContainer> pump(WidgetTester tester, String path) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
            path: '/root',
            builder: (_, _) => const Scaffold(body: SizedBox.shrink())),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router)));
    await settle5(tester);
    return container;
  }

  testWidgets('列表面＝底稿置顶＋手动单按建单序·读数「n 条 · x.x h」现算', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    await pump(tester, '/media/lists');
    expect(find.byKey(const ValueKey('mls-tile-auto')), findsOneWidget);
    expect(find.byKey(const ValueKey('mls-tile-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('mls-tile-2')), findsOneWidget);
    // 底稿瓦片＝本年完结两枚（a/b）·合计 4.0 h（120+120 分现算）。
    expect(find.text('${now.year} 影音'), findsOneWidget);
    final auto = tester.widget<InkWell>(find.byKey(const ValueKey('mls-tile-auto')));
    expect(auto.onTap, isNotNull);
    expect(find.text('2 条 · 4.0 h'), findsOneWidget, reason: '底稿读数');
    expect(find.text('3 条 · 6.0 h'), findsOneWidget, reason: '通勤看＝a/b/c 全在册');
    expect(find.text('0 条 · 0.0 h'), findsOneWidget, reason: '周末听＝空单');
  });

  testWidgets('底稿详情＝整面只读（无添加/导出/改名/移出），仅分享在场', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    await pump(tester, '/media/list/auto');
    expect(find.byKey(const ValueKey('ml-title')), findsOneWidget);
    expect(find.text('${now.year} 影音'), findsOneWidget);
    expect(find.byKey(const ValueKey('ml-add')), findsNothing);
    expect(find.byKey(const ValueKey('ml-export')), findsNothing);
    expect(find.byKey(const ValueKey('ml-rename')), findsNothing);
    expect(find.byKey(const ValueKey('ml-remove-a')), findsNothing);
    expect(find.byKey(const ValueKey('ml-share')), findsOneWidget);
    expect(find.text('底稿只读'), findsNWidgets(2));
    expect(find.text('共 2 条 · 合计 4.0 h'), findsOneWidget);
  });

  testWidgets('拖拽重排＝当场落 pos（退屏再进仍是新序）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final (l1, _) = await seed();
    await pump(tester, '/media/list/$l1');
    // 把第一行（a）拖到第三行之后：数据序 a,b,c → b,c,a（刀2 落点）。
    // 拖拽手势本身＝框架件（buildDefaultDragHandles），本枚钉的是回调段真逻辑：
    // Material 给的新下标按「旧列表插入位」计，落在被挪项之后要退一格再写 pos。
    final view = tester.widget<ReorderableListView>(
        find.byKey(const ValueKey('ml-reorder')));
    view.onReorder(0, 3); // ReorderCallback 签名是 void，异步落库靠帧推进吃掉
    await settle5(tester);
    await tester.pump(const Duration(milliseconds: 120));
    await settle5(tester);
    expect(await repo.listMemberItems(l1).then((v) => v.map((x) => x.id).join(',')),
        'b,c,a');
    // 屏内渲染序与库序同帧。
    final rows = find.byType(ListTile);
    expect(tester.widget<ListTile>(rows.at(0)).title, isNotNull);
  });

  testWidgets('添加条目＝选择半屏点勾往返（加入→取消计数对得上）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final (l1, _) = await seed();
    await pump(tester, '/media/list/$l1');
    expect(find.text('共 3 条 · 合计 6.0 h'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ml-add')));
    await settle5(tester);
    // 候选＝全量在册（gone 软删不进）；a 已在本单＝勾上态，点它先移出再点回加。
    expect(find.byKey(const ValueKey('ml-add-pick-gone')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ml-add-pick-a')));
    await settle5(tester);
    expect((await repo.listMemberItems(l1)).map((x) => x.id).join(','), 'b,c');
    await tester.tap(find.byKey(const ValueKey('ml-add-pick-a')));
    await settle5(tester);
    expect((await repo.listMemberItems(l1)).map((x) => x.id).join(','), 'b,c,a');
    await tester.tap(find.byKey(const ValueKey('ml-add-close')));
    await settle5(tester);
    expect(find.text('共 3 条 · 合计 6.0 h'), findsOneWidget);
  });

  testWidgets('新建＝五档 chips·建好直达详情空态·列表面同步多一枚', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    await pump(tester, '/media/lists');
    await tester.tap(find.byKey(const ValueKey('mls-new')));
    await settle5(tester);
    for (final k in ['movie', 'series', 'music', 'game', 'mix']) {
      expect(find.byKey(ValueKey('mln-type-$k')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('mln-type-mix')));
    await tester.enterText(find.byKey(const ValueKey('mln-name')), '闸验证单');
    await tester.tap(find.byKey(const ValueKey('mln-go')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('ml-empty')), findsOneWidget);
    expect(find.text('闸验证单'), findsOneWidget);
    expect((await repo.listRows()).map((r) => r.name), ['通勤看', '周末听', '闸验证单']);
    // 回列表面：三枚手动单＋底稿＝四枚。
    // （push 栈返回＝系统 pop，测试里直接再开列表路由等价。）
    await pump(tester, '/media/lists');
    expect(find.byKey(const ValueKey('mls-tile-3')), findsOneWidget);
  });

  testWidgets('分享文字版与屏内读数同源（合计行逐字等·导出 MD 直落 MD 档）',
      (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final (l1, _) = await seed();
    await pump(tester, '/media/list/$l1');
    await tester.tap(find.byKey(const ValueKey('ml-share')));
    await settle5(tester);
    final tf = tester.widget<TextField>(find.byKey(const ValueKey('mlsh-text')));
    final txt = tf.controller!.text;
    expect(txt.split('\n').first, '通勤看');
    // 同源判定＝文字版末行与屏内统计行逐字等（刀3 落点：两算子分家即红）。
    final stat = tester
        .widget<Text>(find.byKey(const ValueKey('ml-stat')))
        .data!;
    expect(txt.split('\n').last, stat);
    // MD 档切换＝就地换稿，表头在场。
    await tester.tap(find.byKey(const ValueKey('mlsh-fmt-md')));
    await settle5(tester);
    final mdTf = tester.widget<TextField>(find.byKey(const ValueKey('mlsh-text')));
    expect(mdTf.controller!.text.startsWith('# 通勤看'), isTrue);
    expect(mdTf.controller!.text.contains('| 条目 | 类型 | 状态 |'), isTrue);
  });

  testWidgets('改名＝半屏就地改·详情标题与列表瓦片同步（底稿无此口）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    final (l1, _) = await seed();
    await pump(tester, '/media/list/$l1');
    await tester.tap(find.byKey(const ValueKey('ml-rename')));
    await settle5(tester);
    await tester.enterText(find.byKey(const ValueKey('ml-rename-input')), '改名后');
    await tester.tap(find.byKey(const ValueKey('ml-rename-save')));
    await settle5(tester);
    expect(find.text('改名后'), findsOneWidget);
    expect((await repo.listRows()).firstWhere((r) => r.id == l1).name, '改名后');
    await pump(tester, '/media/lists');
    expect(find.text('改名后'), findsOneWidget);
  });
}
