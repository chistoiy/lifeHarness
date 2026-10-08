import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_dict.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/presentation/media_add_sheet.dart';
import 'package:lifeharness/features/media/presentation/media_ops_sheet.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';

import 'helpers.dart';

/// 影音游批3续 · 条目操作弹层（`m-sheet-ops`）＋编辑态录入弹层（`m-sheet-edit`）。
///
/// 编辑态的承重判定＝**表单没露出去的字段不许被清成空**（评分/简介/各家外部 id/起止时间）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;
  late String id;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
    id = await repo.addItem(
      MediaItem(
        id: 'mfixed1',
        kind: MediaItem.kSeries,
        title: '熊家餐馆',
        state: '在追',
        progressWay: MediaItem.kWayEp,
        progressTo: '7',
        seasonsCount: 3,
        episodesTotal: 18,
        durationMin: 30,
        creator: '罗森伯格',
        publisher: 'FX',
        source: '自建',
        intro: '厨房里的家事',
        myRating: 8.5,
        externalIds: const {'douban_id': '25812345'},
        tags: const ['下饭'],
        startedAt: 1000,
        lastActivityAt: 2000,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await repo.registerItemNames((await repo.itemById(id))!);
  });
  tearDown(() => db.close());

  Future<void> openSheet(WidgetTester tester, Future<void> Function(BuildContext, WidgetRef) run) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) {
              return TextButton(
                onPressed: () => run(ctx, ref),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle5(tester);
  }

  testWidgets('操作弹层只列真做得动的动作；影音单/导出属后批＝整条不出现（批7 轨迹已上线）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final item = (await repo.itemById(id))!;
    await openSheet(tester, (ctx, ref) => showMediaOpsSheet(ctx, ref, item));
    for (final label in ['编辑条目信息', '改分区（当前：在追）', '记进度', '条目资料', '影音轨迹', '计时明细', '移入回收站']) {
      expect(find.byKey(ValueKey('mds-ops-$label')), findsOneWidget);
    }
    // 剧集没「看完」＝完结档动作按 kind 现算，不硬铺
    expect(find.byKey(const ValueKey('mds-ops-标记「看完」')), findsNothing);
    for (final absent in ['移入影音单', '导出']) {
      expect(find.textContaining(absent), findsNothing, reason: '后批能力不铺假入口');
    }
  });

  testWidgets('标记完结＝改分区＋completed 同场落；移入回收站走公共二次确认', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    // 换一部电影才有「看完」档
    final movie = await repo.addItem(
      MediaItem(
        kind: MediaItem.kMovie,
        title: '呼吸',
        state: '在看',
        progressWay: MediaItem.kWayPct,
        progressTo: '60',
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    final m = (await repo.itemById(movie))!;
    await openSheet(tester, (ctx, ref) => showMediaOpsSheet(ctx, ref, m));
    await tester.tap(find.byKey(const ValueKey('mds-ops-标记「看完」')));
    await settle5(tester);
    final after = await repo.itemById(movie);
    expect(after!.state, '看完');
    expect(after.completed, isTrue);
    await clearToasts(tester);

    // 移除动作＝破坏性，必须过 lhConfirm（全仓唯一版式）
    await openSheet(tester, (ctx, ref) => showMediaOpsSheet(ctx, ref, after));
    await tester.tap(find.byKey(const ValueKey('mds-ops-移入回收站')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('d-confirm-ok')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await settle5(tester);
    expect(await repo.itemById(movie), isNull, reason: '软删后在册读口取不到');
    final raw = await db.query(md.tMediaItems, where: 'id = ?', whereArgs: [movie]);
    expect(raw.single['deleted_at'], isNotNull, reason: '打标不物理删');
    await clearToasts(tester);
  });

  testWidgets('编辑态＝预填现值＋类型锁死＋保存只改表单字段，未露字段照原样', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final item = (await repo.itemById(id))!;
    await openSheet(tester, (ctx, ref) => showMediaAddSheet(ctx, ref, existing: item));
    expect(find.text('编辑条目'), findsOneWidget);
    // 预填：标题与季/集都从库里来（不是空表单让人重填一遍）
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')))
          .controller!.text,
      '熊家餐馆',
    );
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('mds-add-field-总集数')))
          .controller!.text,
      '18',
    );
    // 类型 chip：编辑态点不动（串档＝假账），但仍看得见自己是谁
    await tester.tap(find.byKey(const ValueKey('mds-add-kind-movie')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mds-add-field-总集数')), findsOneWidget,
        reason: '类型被换掉了＝编辑态该锁死');

    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '大熊餐厅',
    );
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    final after = (await repo.itemById(id))!;
    expect(after.title, '大熊餐厅');
    // 表单没这一栏的四件：评分/简介/外部 id/起止时刻——一个都不许丢
    expect(after.myRating, 8.5);
    expect(after.intro, '厨房里的家事');
    expect(after.externalIds['douban_id'], '25812345');
    expect(after.startedAt, 1000);
    expect(after.lastActivityAt, 2000);
    expect(after.createdAt, 1);
    expect(after.tags, ['下饭']);
    expect(after.seasonsCount, 3, reason: '没动的数值不许被清零');
    await clearToasts(tester);
  });

  testWidgets('编辑改名后新名字补进名册，旧名字不自动删（删走管理器）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final item = (await repo.itemById(id))!;
    await openSheet(tester, (ctx, ref) => showMediaAddSheet(ctx, ref, existing: item));
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-主创')),
      '克里斯托弗',
    );
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    final names = (await repo.dictRows('creator')).map((r) => r.name).toList();
    expect(names, contains('克里斯托弗'));
    expect(names, contains('罗森伯格'), reason: '旧名字仍在名册（引用数 0，由管理器删）');
    expect(await repo.refCountOf('creator', '罗森伯格'), 0);
    await clearToasts(tester);
  });
}
