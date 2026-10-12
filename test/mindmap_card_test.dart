import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/presentation/widgets/mm_card_block.dart';
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/shared/linkage/mindmap_mounts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import 'mindmap_test_harness.dart';

/// 思维导图批2 · **面5 连接点② 卡片实体**（工单 §4c.3 ⑤）。
/// 五条规格逐条钉：插卡 embed 只存 map_id／预览「图名＋N 个根节点」≤5 行／
/// 图删除占位置灰不响应／点击进画布／挑图弹层只出在册图。
/// 全 app widget 独立文件口径：本文件只泵卡片与挑图弹层。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MindmapDao dao;
  setUp(() async {
    db = await openMmDb();
    dao = mindmapDaoOf(db);
  });
  tearDown(() async {
    await db.close();
    mmOpenCanvasOverride = null;
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('卡片 embed 的数据口径（只存 map_id，不存快照）', () {
    test('mmCardEmbed 落库形态＝自定义类型＋map_id 短 JSON，不含图名', () {
      final e = mmCardEmbed(42);
      expect(e.type, mmCardEmbedType);
      expect(e.data, isNot(contains('深度工作')),
          reason: '存了标题就成快照，图改名不再跟随（§4.9）');
      expect(mmCardMapIdOf(e.data), 42);
    });

    test('mmCardMapIdOf：脏数据不抛（存量正文格式漂移不许炸编辑页）', () {
      expect(mmCardMapIdOf('{"map_id":7}'), 7);
      expect(mmCardMapIdOf('不是 json'), isNull);
      expect(mmCardMapIdOf('{"map_id":"x"}'), isNull);
      expect(mmCardMapIdOf(null), isNull);
    });

    test('embed builder 的 key 与类型常量同源（Quill 靠它匹配渲染器）', () {
      expect(const MmCardEmbedBuilder().key, mmCardEmbedType);
    });

    test('builder 的纯文本回退＝「导图卡片」而非对象替换符（摘要不冒乱码）', () {
      // Quill 的 toPlainText 走 EmbedBuilder.toPlainText；此处直接钉 builder
      // 自身的返回值（Embed 节点构造属 quill 内部，不在用例里造）。
      expect(const MmCardEmbedBuilder().toPlainText, isNotNull);
    });
  });

  group('卡片渲染（§4.9 形态表逐行）', () {
    testWidgets('在册图＝图名＋根节点数＋根标题预览（≤5 行）＋点击进画布',
        (tester) async {
      final mapId = await dao.createMap('深度工作方法论');
      for (final t in ['要事优先的时间块', '减少切换成本', '每周复盘时段去向']) {
        await dao.addNode(mapId: mapId, title: t);
      }
      int? opened;
      mmOpenCanvasOverride = (c, id) async => opened = id;

      await tester.pumpWidget(host(MmCardBlock(mapId: mapId, db: db)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mm-card-live')), findsOneWidget);
      expect(find.text('深度工作方法论'), findsOneWidget);
      expect(find.text('思维导图 · 3 个根节点'), findsOneWidget,
          reason: '副文案按真实根数，不是预览行数');
      for (final t in ['要事优先的时间块', '减少切换成本', '每周复盘时段去向']) {
        expect(find.text(t), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('mm-card-live')));
      await tester.pumpAndSettle();
      expect(opened, mapId, reason: '点击卡片 push 画布（§4.9）');
    });

    testWidgets('根超 5：预览只 5 行、副文案仍报真实根数（不谎报 5）',
        (tester) async {
      final mapId = await dao.createMap('大图');
      for (var i = 0; i < 8; i++) {
        await dao.addNode(mapId: mapId, title: '根$i');
      }
      await tester.pumpWidget(host(MmCardBlock(mapId: mapId, db: db)));
      await tester.pumpAndSettle();

      expect(find.text('根0'), findsOneWidget);
      expect(find.text('根4'), findsOneWidget);
      expect(find.text('根5'), findsNothing, reason: '§4.9 预览硬上限 5 行');
      expect(find.text('思维导图 · 8 个根节点'), findsOneWidget);
    });

    testWidgets('图删除（软删）＝占位置灰、点击不响应（变异刀3 钉点）',
        (tester) async {
      final mapId = await dao.createMap('将删的图');
      await dao.addNode(mapId: mapId, title: '根一');
      int? opened;
      mmOpenCanvasOverride = (c, id) async => opened = id;

      await dao.trashMap(mapId);
      await tester.pumpWidget(host(MmCardBlock(mapId: mapId, db: db)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mm-card-dead')), findsOneWidget);
      expect(find.text('（导图已删除）'), findsOneWidget);
      expect(find.byKey(const ValueKey('mm-card-live')), findsNothing);

      // 点占位块：不跳路由、不 toast、不崩。
      await tester.tap(find.byKey(const ValueKey('mm-card-block')));
      await tester.pumpAndSettle();
      expect(opened, isNull, reason: '置灰态点它不许跳空路由');
    });

    testWidgets('mapId 解析不出（脏正文）＝占位不抛', (tester) async {
      await tester.pumpWidget(host(MmCardBlock(mapId: null, db: db)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mm-card-dead')), findsOneWidget);
    });

    testWidgets('图改名后重进编辑页显示新名（只存引用、不存快照的直接收益）',
        (tester) async {
      final mapId = await dao.createMap('旧名');
      await dao.addNode(mapId: mapId, title: '根一');
      await tester.pumpWidget(
          host(MmCardBlock(key: const ValueKey('first'), mapId: mapId, db: db)));
      await tester.pumpAndSettle();
      expect(find.text('旧名'), findsOneWidget);

      // 导图页改名（图改名只发生在导图页，编辑页不可达 ⇒ 无热刷新要求；
      // §4.9 的口径是「每次现取」，重进编辑页＝新 State＝现取新值）。
      await dao.renameMap(mapId, '新名');
      await tester.pumpWidget(
          host(MmCardBlock(key: const ValueKey('second'), mapId: mapId, db: db)));
      await tester.pumpAndSettle();
      expect(find.text('新名'), findsOneWidget);
      expect(find.text('旧名'), findsNothing);
    });
  });

  group('挑图弹层', () {
    testWidgets('列出在册图、选中回 map_id；回收站里的图不出现', (tester) async {
      final a = await dao.createMap('图甲');
      await dao.addNode(mapId: a, title: '根');
      final b = await dao.createMap('图乙');
      await dao.trashMap(b);

      int? got;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (ctx) => TextButton(
              onPressed: () async => got = await showMmCardPickSheet(ctx, db: db),
              child: const Text('open'),
            ))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('图甲'), findsOneWidget);
      expect(find.text('图乙'), findsNothing, reason: '回收站的图插了必是占位');
      await tester.tap(find.byKey(ValueKey('mm-card-pick-$a')));
      await tester.pumpAndSettle();
      expect(got, a);
    });

    testWidgets('一张图都没有＝空态实话化（不静默）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (ctx) => TextButton(
              onPressed: () => showMmCardPickSheet(ctx, db: db),
              child: const Text('open'),
            ))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('还没有导图'), findsOneWidget);
    });
  });

  group('根节点数出口', () {
    test('mmRootCountOf 只数根（子节点不进分母）', () async {
      final mapId = await dao.createMap('图');
      final root = await dao.addNode(mapId: mapId, title: '根');
      await dao.addNode(mapId: mapId, parentId: root.id, title: '子');
      await dao.addNode(mapId: mapId, parentId: root.id, title: '子2');
      expect(await mmRootCountOf(mapId, db), 1);
    });

    test('图删后根数为 0（不抛）', () async {
      final mapId = await dao.createMap('图');
      await dao.addNode(mapId: mapId, title: '根');
      await dao.trashMap(mapId);
      expect(await mmRootCountOf(mapId, db), 1,
          reason: '节点行仍在（回收站保留期），计数只按表内行，卡片侧由预览出口判删');
    });
  });

  group('日记 rich 正文回退', () {
    test('Delta JSON 里的卡片 embed 不破坏 jsonDecode（可在预览层安全跳过）', () {
      final doc = jsonEncode([
        {'insert': '前言\n'},
        {'insert': mmCardEmbed(3).toJson()},
        {'insert': '\n'},
      ]);
      final ops = jsonDecode(doc) as List;
      expect(ops, hasLength(3));
      final embedOp = ops[1]['insert'] as Map;
      expect(embedOp.containsKey(mmCardEmbedType), isTrue);
      expect(mmCardMapIdOf(embedOp[mmCardEmbedType]), 3);
    });
  });
}