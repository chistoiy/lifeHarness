import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_goal.dart';
import 'package:lifeharness/features/media/data/media_repo_session.dart';
import 'package:lifeharness/features/media/data/media_cover.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/presentation/media_add_sheet.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/media/presentation/media_routes.dart';

import 'helpers.dart';

/// 影音游批2 · 新条目录入弹层（工单执行面板第 3 项末句：
/// 「m-sheet-add 按 kind 出四套不同字段，不是同一张表单换标题」）。
/// 批6 追加＝封面行（缩略位 3:4·三枚钮·首字现算·移除清零·失败不落值·编辑态回写原条目）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;
  late Directory tmp;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
    // 批8a 新增插入位吃 settings 表 KV（缺表＝mediaKvSafe 回落 head，照 stat 页件补表定式）。
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} (key TEXT PRIMARY KEY, value TEXT)',
    );
    // 封面图夹具＝真文件（`Image.file` 解码失败会走 errorBuilder，键就取不到了）；
    // 建文件用同步写，异步 I/O 在 FakeAsync 下永不返回（既定坑）。
    tmp = Directory.systemTemp.createTempSync('lh_addcover6');
  });
  tearDown(() async {
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 1×1 PNG 落一张真临时图，返回路径。
  String tmpImg(String name) {
    final f = File(p.join(tmp.path, name))
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        ),
      );
    return f.path;
  }

  /// 取图口桩：记下来自哪一档（拍照/相册），并按脚本给成功/失败/取消三种收场。
  final picked = <ImageSource>[];
  MdsCoverPick coverPick({
    MdsCoverOutcome outcome = MdsCoverOutcome.ok,
    String? path,
  }) =>
      (src) async {
        picked.add(src);
        return (
          outcome: outcome,
          path: outcome == MdsCoverOutcome.ok ? path : null,
        );
      };

  Future<void> openSheet(
    WidgetTester tester, {
    MediaItem? existing,
    MdsCoverPick? cover,
  }) async {
    final container = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(repo),
        if (cover != null)
          mediaCoverPickProvider.overrideWithValue(cover),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/media/shelf',
      routes: [
        // 编辑态直开同一表单（入口链路「架面→详情→更多→编辑条目信息」由
        // `media_ops_edit_sheet_test.dart` 钉，本文件只管表单自己）。
        GoRoute(
          path: '/edit',
          builder: (_, _) => Consumer(
            builder: (ctx, ref, _) => TextButton(
              onPressed: () => showMediaAddSheet(ctx, ref, existing: existing),
              child: const Text('open-edit'),
            ),
          ),
        ),
        ...mediaPageRoutes(),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    if (existing == null) {
      await tester.tap(find.byKey(const ValueKey('mds-fab-add')));
      await settle5(tester);
      expect(find.text('新条目'), findsOneWidget);
    } else {
      router.push('/edit');
      await settle5(tester);
      await tester.tap(find.text('open-edit'));
      await settle5(tester);
      expect(find.text('编辑条目'), findsOneWidget);
    }
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

  testWidgets('保存进行中按钮给禁用帧，一次点按只落一条（防重入）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await openSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '连点测试',
    );
    await settle5(tester);
    final save = find.byKey(const ValueKey('mds-add-save'));
    await tester.tap(save);
    // 写入未落定前那一帧：按钮必须显式禁用（不给「连点两下靠运气」的证据）
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull,
        reason: '保存进行中要给可见禁用帧（LH-K32 防重入口径）');
    await settle5(tester);
    await clearToasts(tester);
    expect(await db.query(md.tMediaItems), hasLength(1),
        reason: '一次点按只落一条');
  });

  // ==================== 批6 · 封面行 ====================

  Finder coverRow() => find.byKey(const ValueKey('mds-add-cover-row'));
  Finder coverSlot() => find.byKey(const ValueKey('mds-add-cover'));
  Finder coverImg() => find.byKey(const ValueKey('mds-add-cover-img'));

  Future<String?> dbCover(String title) async {
    final rows = await db.query(
      md.tMediaItems,
      columns: ['cover_path'],
      where: 'title = ?',
      whereArgs: [title],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['cover_path'] as String?;
  }

  testWidgets('封面行到位＝66×88 竖版缩略位＋拍照·相册两枚，未选图不出「移除」', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await openSheet(tester);
    expect(coverRow(), findsOneWidget);
    final sz = tester.getSize(coverSlot());
    expect(sz.width, 66);
    // 拍板①：缩略位统一 3:4 竖版（与架面主形态同比例），现算高宽比＝1.33
    expect((sz.height / sz.width).toStringAsFixed(2), '1.33');
    expect(find.byKey(const ValueKey('mds-add-cover-cam')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-add-cover-lib')), findsOneWidget);
    expect(find.byKey(const ValueKey('mds-add-cover-del')), findsNothing,
        reason: '没图就没有可移除的东西');
    // 行内只留功能词：卡位本身不写字（禁教学文案）
    final tx = tester
        .widgetList<Text>(find.descendant(of: coverRow(), matching: find.byType(Text)))
        .map((t) => t.data)
        .toSet();
    expect(tx, {'拍照', '相册'}, reason: '行内除三枚功能词外不许有说明文案');
  });

  testWidgets('未选图＝色板＋标题首字回落，且首字随输入当场变（不是写死）', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await openSheet(tester);
    expect(
      find.descendant(of: coverSlot(), matching: find.byType(Text)),
      findsNothing,
      reason: '空标题＝色板整块空着，不摆一个空字占位、也不摆假图',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '沙丘 2',
    );
    await settle5(tester);
    expect(
      find.descendant(of: coverSlot(), matching: find.text('沙')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '奥本海默',
    );
    await settle5(tester);
    expect(
      find.descendant(of: coverSlot(), matching: find.text('奥')),
      findsOneWidget,
      reason: '首字现算：改了标题卡位还写着「沙」就是写死了',
    );
    expect(
      find.descendant(of: coverSlot(), matching: find.text('沙')),
      findsNothing,
    );
  });

  testWidgets('相册选上一张＝缩略位吃图且「移除」现身；拍照/相册两档分开传（不再多弹一层）',
      (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final img = tmpImg('cover.png');
    picked.clear();
    await openSheet(tester, cover: coverPick(path: img));
    await tester.tap(find.byKey(const ValueKey('mds-add-cover-lib')));
    await settle5(tester);
    expect(coverImg(), findsOneWidget, reason: '缩略位换成用户那张图');
    expect(find.byKey(const ValueKey('mds-add-cover-del')), findsOneWidget);
    expect(picked, [ImageSource.gallery], reason: '点相册＝直接开相册，中间不弹自己的两格菜单');
    await tester.tap(find.byKey(const ValueKey('mds-add-cover-cam')));
    await settle5(tester);
    expect(picked, [ImageSource.gallery, ImageSource.camera]);
  });

  testWidgets('取图读不出＝一句实话，缩略位与条目都不落半个值', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await openSheet(
      tester,
      cover: coverPick(outcome: MdsCoverOutcome.failed),
    );
    await tester.tap(find.byKey(const ValueKey('mds-add-cover-lib')));
    await settle5(tester);
    expect(find.textContaining('图读不出来'), findsOneWidget);
    expect(coverImg(), findsNothing);
    expect(find.byKey(const ValueKey('mds-add-cover-del')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '读不出这条',
    );
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    await clearToasts(tester);
    expect(await dbCover('读不出这条'), isNull, reason: '失败＝条目 cover_path 不落半个值');
  });

  testWidgets('取消取图＝静默，不弹「读不出来」骗人', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    await openSheet(
      tester,
      cover: coverPick(outcome: MdsCoverOutcome.canceled),
    );
    await tester.tap(find.byKey(const ValueKey('mds-add-cover-lib')));
    await settle5(tester);
    expect(find.textContaining('图读不出来'), findsNothing);
    expect(coverImg(), findsNothing);
  });

  testWidgets('新建带封面保存＝cover_path 落真路径；点移除后＝落 null', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final img = tmpImg('cover.png');
    await openSheet(tester, cover: coverPick(path: img));
    await tester.tap(find.byKey(const ValueKey('mds-add-cover-lib')));
    await settle5(tester);
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '带封面',
    );
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    await clearToasts(tester);
    expect(await dbCover('带封面'), img, reason: '存文件不存 dataURL：落的是路径');

    await openSheet(tester, cover: coverPick(path: img));
    await tester.tap(find.byKey(const ValueKey('mds-add-cover-lib')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-add-cover-del')));
    await settle5(tester);
    expect(coverImg(), findsNothing, reason: '移除当场回落色板，不等保存');
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '移除过',
    );
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    await clearToasts(tester);
    expect(await dbCover('移除过'), isNull);
  });

  testWidgets('编辑态开层＝初值回显已有封面，保存只回写原条目（不新建重复条目）',
      (tester) async {
    await useSurface(tester, const Size(420, 1200));
    final img = tmpImg('cover.png');
    final id = await repo.addItem(MediaItem(
      kind: MediaItem.kMovie,
      title: '旧名',
      state: '未看',
      progressWay: MediaItem.kWayPct,
      createdAt: 1,
      updatedAt: 1,
    ));
    await repo.setItemCover(id, img);
    await openSheet(tester, existing: await repo.itemById(id), cover: coverPick(path: img));
    expect(coverImg(), findsOneWidget, reason: '编辑态要把条目已有封面摆回来');
    expect(find.byKey(const ValueKey('mds-add-cover-del')), findsOneWidget);
    expect(find.text('保存改动'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')),
      '新名',
    );
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    await clearToasts(tester);
    final rows = await db.query(md.tMediaItems);
    expect(rows, hasLength(1), reason: '编辑＝回写原条目，不许新建一条重复的');
    expect(rows.single['title'], '新名');
    expect(rows.single['id'], id);
    expect(rows.single['cover_path'], img, reason: '没动封面＝原值保留（mergedOnto 口径）');
  });

  testWidgets('新增插入位（media.newPos）：置顶＝created_at now，置底＝全库最小-1',
      (tester) async {
    await useSurface(tester, const Size(420, 1000));
    // 先在库一条基准条目（created_at=1000），tail 的落位基准＝min-1=999。
    await repo.addItem(MediaItem(
      id: 'base0',
      kind: MediaItem.kMovie,
      title: '基准片',
      state: '在看',
      progressWay: MediaItem.kWayPct,
      createdAt: 1000,
      updatedAt: 1000,
    ));
    await openSheet(tester);
    await tester.enterText(
        find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')), '置顶新片');
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    await clearToasts(tester);
    final head = await repo.itemById(
        ((await db.query(md.tMediaItems, where: "id != 'base0'")).first['id'])
            as String);
    expect(head!.createdAt! > 1000, isTrue, reason: '默认置顶档＝now，不早于既有条目');

    await repo.setKv('media.newPos', 'tail');
    await openSheet(tester);
    await tester.enterText(
        find.byKey(const ValueKey('mds-add-field-片名 / 专辑 / 游戏名')), '置底新片');
    await tester.tap(find.byKey(const ValueKey('mds-add-save')));
    await settle5(tester);
    await clearToasts(tester);
    final tail = (await db.query(md.tMediaItems, where: 'id != ?',
            whereArgs: ['base0'], orderBy: 'created_at ASC'))
        .first;
    expect(tail['created_at'], await repo.minLiveCreatedAt(),
        reason: 'tail＝全库在册最小-1 落位（原型「追加到末尾」同语义）');
  });
}
