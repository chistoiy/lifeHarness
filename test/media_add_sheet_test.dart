import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';
import 'package:lifeharness/features/media/presentation/media_shelf_page.dart';

import 'helpers.dart';

/// 影音游批2 · 新条目录入弹层（工单执行面板第 3 项末句：
/// 「m-sheet-add 按 kind 出四套不同字段，不是同一张表单换标题」）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<void> openSheet(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/media/shelf',
      routes: [...mediaPageRoutes()],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-fab-add')));
    await settle5(tester);
    expect(find.text('新条目'), findsOneWidget);
  }

  void expectField(String label) => expect(
    find.byKey(ValueKey('mds-add-field-$label')),
    findsOneWidget,
    reason: '该类型应有字段：$label',
  );

  void expectNoField(String label) => expect(
    find.byKey(ValueKey('mds-add-field-$label')),
    findsNothing,
    reason: '不该出现的字段：$label',
  );

  testWidgets('四类各自的录入字段互不相同（四套表单，不是一张换标题）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await openSheet(tester);

    // 电影＝时长(min)＋进度方式两档＋百分比
    expectField('时长(min)');
    expectField('进度(%)');
    expectNoField('季数');
    expectNoField('曲目数');
    expectNoField('周目数');
    expect(find.byKey(const ValueKey('mds-add-way-pct')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-add-way-min')), findsOneWidget);

    // 剧集＝季数＋总集数＋看到第几集；进度方式只有「按集」，没有第二档可选
    await tester.tap(find.byKey(const ValueKey('mds-add-kind-series')));
    await settle5(tester);
    expectField('季数');
    expectField('总集数');
    expectField('看到第几集');
    expectNoField('时长(min)');
    expectNoField('曲目数');
    expect(find.byKey(const ValueKey('mds-add-way-ep')), findsNothing,
        reason: '单档类型不给多余的方式 chips');

    // 音乐＝曲目数，且明确「循环次数不在这里填」
    await tester.tap(find.byKey(const ValueKey('mds-add-kind-music')));
    await settle5(tester);
    expectField('曲目数');
    expectNoField('总集数');
    expectNoField('周目数');
    expect(find.textContaining('循环次数按听歌会话自动计'), findsOneWidget);

    // 游戏＝周目数＋三档进度方式（剧情主线%/周目/成就完成度）
    await tester.tap(find.byKey(const ValueKey('mds-add-kind-game')));
    await settle5(tester);
    expectField('周目数');
    expectField('主线进度(%)');
    expect(find.byKey(const ValueKey('mds-add-way-mainpct')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-add-way-playthrough')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-add-way-achv')), findsOneWidget);
  });

  testWidgets('空标题保存＝就地红字且不落库；补上标题才写入', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    final input = find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名'));
    final tf = tester.widget<TextField>(input);
    expect(tf.decoration!.errorText, '请先写名称', reason: '校验要写在字段旁（LH-K32）');
    expect(find.byType(SnackBar), findsNothing, reason: '模态弹层里不借道提示条');
    expect(await db.query(md.tMediaItems), isEmpty);
    await tester.enterText(input, '奥本海默');
    await settle5(tester);
    expect(
      tester.widget<TextField>(input).decoration!.errorText,
      isNull,
      reason: '补输入即撤错',
    );
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    await clearToasts(tester);
    expect(await db.query(md.tMediaItems), hasLength(1));
  });

  testWidgets('四类各存一条＝progress_way 与默认分区四套都不同（刀3 钉这里）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final want = {
      MediaItem.kMovie: '电影录的',
      MediaItem.kSeries: '剧集录的',
      MediaItem.kMusic: '专辑录的',
      MediaItem.kGame: '游戏录的',
    };
    for (final entry in want.entries) {
      await openSheet(tester);
      await tester.tap(find.byKey(ValueKey('mds-add-kind-${entry.key}')));
      await settle5(tester);
      await tester.enterText(
        find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
        entry.value,
      );
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('mds-add-save')));
      await settle5(tester);
      await clearToasts(tester);
    }
    final rows = await db.query(md.tMediaItems);
    expect(rows, hasLength(4));
    final byKind = {for (final r in rows) '${r['kind']}': r};
    expect(byKind[MediaItem.kMovie]!['progress_way'], MediaItem.kWayPct);
    expect(byKind[MediaItem.kSeries]!['progress_way'], MediaItem.kWayEp);
    expect(byKind[MediaItem.kMusic]!['progress_way'], MediaItem.kWayLoops);
    expect(byKind[MediaItem.kGame]!['progress_way'], MediaItem.kWayMainPct);
    // 默认分区按类各归各的（同一 state 列四义）
    expect(byKind[MediaItem.kMovie]!['state'], '未看');
    expect(byKind[MediaItem.kMusic]!['state'], '未听');
    expect(byKind[MediaItem.kGame]!['state'], '未玩');
    // 角色标签跟着类走，不留空
    expect(byKind[MediaItem.kMusic]!['creator_role'], '艺人');
    expect(byKind[MediaItem.kGame]!['publisher_role'], '发行商');
  });

  testWidgets('保存连点只落一条（防重入）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await openSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '连点测试',
    );
    await settle5(tester);
    final save = find.byKey(const ValueKey('mds-add-save'));
    await tester.tap(save);
    await tester.tap(save);
    await settle5(tester);
    await clearToasts(tester);
    expect(await db.query(md.tMediaItems), hasLength(1));
  });
}
