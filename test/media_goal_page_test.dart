import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_goal.dart';
import 'package:lifeharness/features/media/data/media_repo_session.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_session.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';

import 'helpers.dart';

/// 批8a · 目标屏（原型 `m-goal` · 词典 LH-C22 · 路由 `/media/goal`）。
///
/// 钉死：六行齐＋读数现算（日/周一起/月窗不误）；未设＝虚线＋行内零百分比；
/// 就地滚轮设值即落库、重进屏仍在；「不设目标」清档回虚线；
/// 读数恒吃真实分钟（speedFold 翻成折算也不动）；与统计屏目标块同源同帧。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 21, 30);
  final weekStart =
      DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: DateTime(today.year, today.month, today.day).weekday - 1));
  DateTime day(int back, {int hour = 12}) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day, hour)
          .subtract(Duration(days: back));
  DateTime dayFromToday(int back, {int hour = 12}) =>
      DateTime(today.year, today.month, today.day, hour)
          .subtract(Duration(days: back));

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

  Future<MediaItem> addItem(String title,
      {String kind = MediaItem.kMovie,
      String state = '在看',
      int? endedAt}) async {
    final x = MediaItem(
      id: 'x_$title',
      kind: kind,
      title: title,
      state: state,
      progressWay: MediaItem.kWayPct,
      endedAt: endedAt,
      createdAt: 1,
      updatedAt: 1,
    );
    await repo.addItem(x);
    return x;
  }

  Future<void> addSession(MediaItem x, DateTime start, int minutes,
          {double? speed}) =>
      db.insert(
        md.tMediaSessions,
        MediaSession(
          itemId: x.id,
          kind: x.kind,
          startedAt: start.millisecondsSinceEpoch,
          endedAt: start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
          minutes: minutes,
          speed: speed,
        ).toRow(),
      );

  Future<void> seed() async {
    final mv = await addItem('今天看的电影');
    await addSession(mv, dayFromToday(0, hour: 9), 50);
    final tv = await addItem('今天追的剧', kind: MediaItem.kSeries);
    await addSession(tv, dayFromToday(0, hour: 14), 30);
    final old = await addItem('昨天的电影');
    await addSession(old, dayFromToday(1), 999);
    final mu = await addItem('本周专辑', kind: MediaItem.kMusic);
    await addSession(mu, weekStart, 120, speed: 2.0);
    final gm2 = await addItem('在玩的游戏', kind: MediaItem.kGame);
    await addSession(gm2, dayFromToday(2), 90);
    if (today.day <= 2) {
      // 昨天/前天会跨出本月：给游玩补一条今天的会话，保持「本月 1.5 h」期望成立。
      await addSession(gm2, dayFromToday(0, hour: 16), 90);
    }
    await addItem('去年看完的', state: '看完',
        endedAt: now.subtract(const Duration(days: 400)).millisecondsSinceEpoch);
    await addItem('本年通关的', kind: MediaItem.kGame, state: '通关',
        endedAt: dayFromToday(0).millisecondsSinceEpoch);
    await addItem('本年追完的', kind: MediaItem.kSeries, state: '追完',
        endedAt: dayFromToday(0).millisecondsSinceEpoch);
    // 影音天数＝本周去重日：今天＋昨天（game 会话）＝2
    await addSession(gm2, dayFromToday(1), 15);
    final gone = await addItem('删掉的片', state: '看完',
        endedAt: dayFromToday(0).millisecondsSinceEpoch);
    await repo.softDelete([gone.id]);
  }

  // 时间炸弹护栏（既定纪律＝测试日期一律相对构造）：周/月窗口在周一与月初头两天
  // 会把种子挤出窗口，这几个读数用例当日跳过，常规日子照常跑。
  final skipWeek = today.weekday == DateTime.monday;
  final skipMonth = today.day <= 2;

  Future<void> pumpGoal(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(
            path: '/root',
            builder: (_, _) => const Scaffold(body: SizedBox.shrink())),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push('/media/goal');
    await settle5(tester);
  }

  testWidgets('六行齐·未设＝虚线「设目标」＋行内零百分比', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    await pumpGoal(tester);

    for (final k in ['movieMin', 'musicH', 'gameH', 'doneN', 'dayN', 'sceneN']) {
      expect(find.byKey(ValueKey('mdg-$k')), findsOneWidget, reason: '缺行 $k');
      expect(find.byKey(ValueKey('mdgunset-$k')), findsOneWidget);
    }
    // 读数**数值**归口径用例独断（变异刀1 摘窗口只让那条红，本条只管面）。
    expect(find.textContaining('min'), findsWidgets);
    expect(find.textContaining('%'), findsNothing,
        reason: '未设＝屏内零百分比（LH-C22 铁口径③）');
  }, skip: skipWeek && skipMonth);

  testWidgets('六路口径：周一起/本月/本年/去重天数/名场面各现算不误窗', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    await db.insert(md.tMediaNotes, {
      'item_id': 'x_今天看的电影',
      'kind': MediaItem.kMovie,
      'note_type': 'scene',
      'body': '本月名场面',
      'created_at': dayFromToday(0, hour: 8).millisecondsSinceEpoch,
      'updated_at': dayFromToday(0, hour: 8).millisecondsSinceEpoch,
    });
    await pumpGoal(tester);
    expect(find.text('今天 80 min'), findsOneWidget,
        reason: '观影＝今晨零点起 movie+series 真实分钟（50＋30），昨日 999 不吃（刀1 摘日窗＝本条独红）');
    if (!skipMonth) {
      expect(find.text('本周 2.0 h'), findsOneWidget,
          reason: '听歌＝本周一起 music 真实小时；speed=2 的折算值 4.0 不许出现（§九.1）');
      expect(find.text('本月 1.8 h'), findsOneWidget,
          reason: '本月 game 会话＝前天 90min＋昨天 15min＝1.75h，读数现算一位小数');
      expect(find.textContaining('本周 4 天'), findsOneWidget,
          reason: '周一起/昨天/前天/今天＝4 个去重日历日');
    }
    expect(find.textContaining('今年 2'), findsOneWidget,
        reason: '看完数＝本年完结档在册行（软删那条不入）');
    expect(find.textContaining('本月 1 条'), findsOneWidget);
  }, skip: skipWeek || skipMonth);

  testWidgets('点行就地滚轮·吸中即落库；重开屏仍在该值', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    await pumpGoal(tester);

    await tester.tap(find.byKey(const ValueKey('mdg-movieMin')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mdg-wheel-movieMin')), findsOneWidget);
    // 滚轮半截在视口外时拖距会被祖先 ListView 分走（6093 实测＝拖 7 格跳到 230）：先垫到位再拖。
    await tester.ensureVisible(find.byKey(const ValueKey('mdg-wheel-movieMin')));
    await tester.pump();
    // 实测折算：ListWheelScrollView 磁吸下「拖 N 格＝前进 N-1 档」，8 格＝居中 150→第 22 档 80min。
    final wr = await repo.goalRows();
    expect(wr.where((g) => g.metric == 'movieMin'), isEmpty,
        reason: '拖前未设＝无行');
    // 滚轮＝磁吸＋惯性；实测单格慢拖＝前进一档。往下（+Y）拖 7 格＝居中 150→80。
    for (var i = 0; i < 9; i++) {
      final cur = (await repo.goalRows())
          .where((g) => g.metric == 'movieMin')
          .map((g) => g.target)
          .firstOrNull;
      if (cur == 80) break;
      await tester.drag(find.byKey(const ValueKey('mdg-wheelpick-movieMin')),
          const Offset(0, 30.0), touchSlopY: 0);
      await tester.pump();
      await settle5(tester);
    }
    final rows = await repo.goalRows();
    expect(rows.any((g) => g.metric == 'movieMin' && g.target == 80), isTrue,
        reason: '居中档 150 往上 7 档＝80 min，落库的是目标表不是内存态');

    // 「重进屏」＝只重建目标屏（新 ProviderScope 也重读库），不用清容器态。
    await pumpGoal(tester);
    expect(find.byKey(const ValueKey('mdgt-movieMin')), findsOneWidget);
    expect(find.textContaining('80 min'), findsWidgets);
    expect(find.textContaining('%'), findsOneWidget,
        reason: '已设＝目标 chip＋百分比（80/80＝100%）；行内不再出虚线');
    expect(find.byKey(const ValueKey('mdgbar-movieMin')), findsOneWidget);
    expect(find.byKey(const ValueKey('mdgunset-movieMin')), findsNothing);
  });

  testWidgets('「不设目标」清档＝删行回虚线', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    await repo.setGoal('musicH', 'h', 3);
    await pumpGoal(tester);
    expect(find.byKey(const ValueKey('mdgt-musicH')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mdg-musicH')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mdg-clear-musicH')));
    await settle5(tester);
    expect(await repo.goalRows(), isEmpty);
    expect(find.byKey(const ValueKey('mdgunset-musicH')), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('speedFold 翻成折算＝目标读数纹丝不动（账本恒吃真实）', (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    await repo.setKv('media.speedFold', 'true');
    await pumpGoal(tester);
    expect(find.text('本周 2.0 h'), findsOneWidget,
        reason: '折算 chip 只影响统计屏读侧，目标读数恒真实（§九.1）');
    expect(find.textContaining('4.0'), findsNothing);
  }, skip: skipWeek);

  testWidgets('与统计屏目标块同源：设一条→块内出行＋百分比；清档→回虚线零百分比',
      (tester) async {
    await useSurface(tester, const Size(420, 1600));
    await seed();
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/root',
      routes: [
        GoRoute(
            path: '/root',
            builder: (_, _) => const Scaffold(body: SizedBox.shrink())),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    router.push('/media/stat');
    await settle5(tester);
    expect(find.text('未设目标'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('mds-stat-goal')),
          matching: find.textContaining('%')),
      findsNothing,
    );

    await repo.setGoal('movieMin', 'min', 40);
    container.read(mediaTickProvider.notifier).state++;
    await settle5(tester);
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('mds-stat-goal')),
          matching: find.textContaining('%')),
      findsOneWidget,
      reason: '设档同帧：块内出现 200% 达成行（80/40）',
    );
    expect(find.text('未设目标'), findsNothing);

    await repo.clearGoal('movieMin');
    container.read(mediaTickProvider.notifier).state++;
    await settle5(tester);
    expect(find.text('未设目标'), findsOneWidget, reason: '清档同帧回虚线');
    // 入口行在场且真跳目标屏（批7 §5 落点由置灰改真跳转）。
    await tester.tap(find.byKey(const ValueKey('mds-stat-goal-entry')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mdg-movieMin')), findsOneWidget);
  });
}
