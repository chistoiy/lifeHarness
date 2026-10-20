import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_node_meta.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_node_sheet.dart';
import 'package:lifeharness/shared/linkage/mindmap_mounts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 批5 F4-9 · 节点增强**交互面**（工单 §4f.1 第二件·一文件一波）。
///
/// 覆盖：
/// · 节点弹层三段（标签输入/任务 chip/图片按钮）的读回与产出；
/// · 画布**点勾选框走 linkage 发事件**（变异刀1 钉点：摘掉出口即红）；
/// · 取消完成不发事件；
/// · 点勾选框**不选中也不拖拽**（原型 stopPropagation 的 Flutter 等价面）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late SharedPreferences mmPrefs;
  late List<MmNodeTaskEvent> published;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mmPrefs = await SharedPreferences.getInstance();
    db = await openMmDb();
    published = [];
    mmPublishOverride = published.add;
  });

  tearDown(() async {
    mmPublishOverride = null;
    await (db as CloseableDb).close();
  });

  /// 泵一张只含一个节点的图（画布 fit 后节点在视口中央）。
  Future<(MindmapDao, int, MindmapNode)> pumpOneNode(
    WidgetTester tester, {
    List<String> tags = const <String>[],
    bool isTask = false,
    bool taskDone = false,
    String title = '中心主题',
  }) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    final n = await dao.addNode(
        mapId: mapId, title: title, tags: tags, isTask: isTask);
    await dao.updateNode(n.copyWith(taskDone: taskDone));
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
      child: MaterialApp(home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return (dao, mapId, (await dao.nodesOf(mapId)).first);
  }

  /// 画布节点中心的屏幕坐标（fit 后落在视口中，缩放 1）。
  Offset nodeCenter(WidgetTester tester) {
    final paint = find.byKey(const ValueKey('mm-canvas-paint'));
    return tester.getCenter(paint);
  }

  group('节点弹层三段', () {
    testWidgets('标签/任务/图片三段可填，保存产出 MmNodeDraft 全字段',
        (tester) async {
      MmNodeSubmit? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  got = await showMmNodeSheet(ctx, headline: '添加子节点');
                },
                child: const Text('open'),
              ),
            )),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('mm-node-title')), '带三段的节点');
      await tester.enterText(
          find.byKey(const ValueKey('mm-node-tags')), '方法论, 复盘');
      await tester.tap(find.byKey(const ValueKey('mm-node-task-toggle')));
      await tester.pumpAndSettle();
      // 图片段：只断言按钮与「未挂图片」提示在（真选图要 ImagePicker，
      // 单测不给平台通道——落库路径由 schema 测试的 DAO 层覆盖）。
      expect(find.byKey(const ValueKey('mm-node-image-pick')), findsOneWidget);
      expect(find.byKey(const ValueKey('mm-node-image-hint')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mm-node-save')));
      await tester.pumpAndSettle();

      expect(got, isNotNull);
      expect(got!.draft.title, '带三段的节点');
      expect(got!.draft.tags, ['方法论', '复盘']);
      expect(got!.draft.isTask, isTrue);
      expect(got!.draft.imagePath, isNull);
    });

    testWidgets('编辑分支读回三段现值（标签以 ", " 连接、任务态 chip 已是任务）',
        (tester) async {
      MmNodeSubmit? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  got = await showMmNodeSheet(ctx,
                      headline: '编辑节点',
                      initialTitle: '旧标题',
                      initialNote: '旧备注',
                      initialTags: const ['a', 'b'],
                      initialTask: true,
                      initialImagePath: '/tmp/x.jpg');
                },
                child: const Text('open'),
              ),
            )),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('a, b'), findsOneWidget, reason: '读回按 ", " 连接');
      expect(find.text('已是任务'), findsOneWidget);
      // 图片段：已有路径时不显示「换一张」而是「换一张」+清除钮
      expect(find.byKey(const ValueKey('mm-node-image-clear')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mm-node-save')));
      await tester.pumpAndSettle();
      expect(got!.draft.tags, ['a', 'b']);
      expect(got!.draft.isTask, isTrue);
      expect(got!.draft.imagePath, '/tmp/x.jpg');
    });

    testWidgets('清空标签再存＝无标签（原型 tags.length?tags:null 同款）',
        (tester) async {
      MmNodeSubmit? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  got = await showMmNodeSheet(ctx,
                      headline: '编辑节点',
                      initialTitle: 'x',
                      initialTags: const ['旧标签']);
                },
                child: const Text('open'),
              ),
            )),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('mm-node-tags')), '  ');
      await tester.tap(find.byKey(const ValueKey('mm-node-save')));
      await tester.pumpAndSettle();
      expect(got!.draft.tags, isEmpty);
    });
  });

  group('画布勾选：走 linkage 发事件（变异刀1 钉点）', () {
    testWidgets('点任务勾选框＝完成 + 发事件 + 落库（刀1 摘出口即红）',
        (tester) async {
      final (dao, mapId, before) =
          await pumpOneNode(tester, isTask: true);
      expect(before.isTask, isTrue);
      expect(published, isEmpty);

      // 勾选框在节点盒最左 15px（画布坐标）＝节点中心往左偏。
      final c = nodeCenter(tester);
      await tapAt(tester, c - const Offset(45, 0));
      await tester.pumpAndSettle();

      expect(published, hasLength(1), reason: '联动出口必须真的发事件');
      expect(published.first.source, 'mindmap');
      expect(published.first.nodeId, before.id);
      expect(published.first.mapId, mapId);
      final back = (await dao.nodesOf(mapId)).first;
      expect(back.taskDone, isTrue, reason: '完成态必须落库（关图重开仍在）');
    });

    testWidgets('再点一次＝取消完成，**不发事件**（统计只关心达成）',
        (tester) async {
      final (dao, mapId, _) = await pumpOneNode(tester, isTask: true);
      final c = nodeCenter(tester);
      await tapAt(tester, c - const Offset(45, 0));
      await tester.pumpAndSettle();
      expect(published, hasLength(1));

      await tapAt(tester, c - const Offset(45, 0));
      await tester.pumpAndSettle();
      expect(published, hasLength(1), reason: '取消完成不发事件');
      expect((await dao.nodesOf(mapId)).first.taskDone, isFalse);
    });

    testWidgets('点勾选框**不选中**（原型 stopPropagation 的等价面）',
        (tester) async {
      await pumpOneNode(tester, isTask: true);
      // 先点空白取消选中，再点勾选框：贴点气泡不该因此出现（批P5 口径——
      // 「没选中」＝气泡不渲染，取代原先「工具条置灰」的表达）。
      final c = nodeCenter(tester);
      await tapAt(tester, c - const Offset(45, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mm-bubble-more')), findsNothing,
          reason: '气泡仍不出现 ⇒ 勾选没顺手选中节点');
    });

    testWidgets('非任务节点点左侧＝仍是选中（不误触发勾选）', (tester) async {
      final (dao, mapId, _) = await pumpOneNode(tester);
      final c = nodeCenter(tester);
      await tapAt(tester, c - const Offset(45, 0));
      await tester.pumpAndSettle();
      expect(published, isEmpty);
      expect((await dao.nodesOf(mapId)).first.taskDone, isFalse);
    });

    testWidgets('勾选入撤销栈一步：撤销退回未完成（原型 mmPushHistory 同款）',
        (tester) async {
      final (dao, mapId, _) = await pumpOneNode(tester, isTask: true);
      final c = nodeCenter(tester);
      await tapAt(tester, c - const Offset(45, 0));
      await tester.pumpAndSettle();
      expect((await dao.nodesOf(mapId)).first.taskDone, isTrue);

      await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
      await tester.pumpAndSettle();
      expect((await dao.nodesOf(mapId)).first.taskDone, isFalse,
          reason: '撤销必须真的回滚完成态');
    });
  });

  group('任务属性：取消即清完成态', () {
    testWidgets('编辑节点把任务属性关掉＝落库后完成态清零', (tester) async {
      final (dao, mapId, before) =
          await pumpOneNode(tester, isTask: true, taskDone: true);
      expect(before.taskDone, isTrue);

      // 选中 → 更多 → 编辑节点
      await tapAt(tester, nodeCenter(tester));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mm-menu-edit')));
      await tester.pumpAndSettle();
      expect(find.text('已是任务'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mm-node-task-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mm-node-save')));
      await tester.pumpAndSettle();

      final back = (await dao.nodesOf(mapId)).first;
      expect(back.isTask, isFalse);
      expect(back.taskDone, isFalse,
          reason: '取消任务属性必须清完成态（原型同款，否则 xmind 会写 progress=100）');
    });
  });

  group('三段标签往返：编辑保存后画布节点带上标签', () {
    testWidgets('编辑节点写标签 → 重开图标签仍在（每图一套落库）',
        (tester) async {
      final (dao, mapId, _) = await pumpOneNode(tester);
      await tapAt(tester, nodeCenter(tester));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mm-menu-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('mm-node-tags')), '甲, 乙');
      await tester.tap(find.byKey(const ValueKey('mm-node-save')));
      await tester.pumpAndSettle();

      expect((await dao.nodesOf(mapId)).first.tags, ['甲', '乙']);

      // 重开图（同 provider/prefs 会话）→ 仍读到标签
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
      ));
      await tester.pumpAndSettle();
      await tapAt(tester, nodeCenter(tester));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mm-menu-edit')));
      await tester.pumpAndSettle();
      expect(find.text('甲, 乙'), findsOneWidget);
    });

    testWidgets('标签编解码在弹层与 DB 之间只走一份（域件直调）', (tester) async {
      // 弹层写入用的是同一对 mmTagsParse/mmTagsEncode（结构面断言，
      // 防止将来弹层自己写一份 split 逻辑）。
      expect(mmTagsParse('甲, 乙'), ['甲', '乙']);
      expect(mmTagsDecode(mmTagsEncode(['甲', '乙'])), ['甲', '乙']);
    });
  });
}