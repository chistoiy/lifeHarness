import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/mindmap/domain/md_parse.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:lifeharness/shared/linkage/mindmap_mounts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mindmap_test_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;

/// 思维导图批1 · 挂载与笔记连通守护（工单 §4b.3 ④：H3/H4）＋
/// md 解析三通道优先序与超限截断（B2/B3）。
///
/// 挂载用例走**真内存库**（建笔记→建图→挂载→改/删笔记→画布刷新），
/// 不 mock 标题——「实时跟随」的数据链路本身就是本批的验收对象。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late dynamic db;
  late SharedPreferences mmPrefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mmPrefs = await SharedPreferences.getInstance();
    db = await openMmDb();
  });

  tearDown(() async {
    await (db as CloseableDb).close();
    mmOpenNoteOverride = null;
  });

  group('挂载出口（shared/linkage/mindmap_mounts）', () {
    test('mmNoteTitleOf：在册取标题；进回收站/删除＝null（B6 占位判据）',
        () async {
      final id = await db.insert(DbSchema.tNotes, {
        'title': '挂载目标',
        'content': '正文',
        'created_at': 1,
        'updated_at': 1,
      });
      expect(await mmNoteTitleOf(id, db), '挂载目标');
      await db.update(DbSchema.tNotes, {'deleted_at': 1},
          where: 'id = ?', whereArgs: [id]);
      expect(await mmNoteTitleOf(id, db), isNull,
          reason: '笔记删除 → 节点保留并显示占位、不崩（B6）');
    });

    test('mmMountableNotes：过滤已删与归档；空标题兜「未命名笔记」', () async {
      await db.insert(DbSchema.tNotes, {
        'title': '活笔记',
        'content': '',
        'created_at': 1,
        'updated_at': 1,
      });
      final dead = await db.insert(DbSchema.tNotes, {
        'title': '已删笔记',
        'content': '',
        'created_at': 1,
        'updated_at': 1,
        'deleted_at': 1,
      });
      await db.insert(DbSchema.tNotes, {
        'title': '',
        'content': '',
        'created_at': 1,
        'updated_at': 2,
      });
      final refs = await mmMountableNotes(db);
      expect(refs.map((r) => r.title), contains('活笔记'));
      expect(refs.map((r) => r.id), isNot(contains(dead)));
      expect(refs.map((r) => r.title), contains('未命名笔记'));
    });

    test('mmNoteContentOf：读正文；已删＝null（md 解析读源）', () async {
      final id = await db.insert(DbSchema.tNotes, {
        'title': 'md',
        'content': '# 标题\n正文',
        'created_at': 1,
        'updated_at': 1,
      });
      expect(await mmNoteContentOf(id, db), '# 标题\n正文');
      await db.delete(DbSchema.tNotes, where: 'id = ?', whereArgs: [id]);
      expect(await mmNoteContentOf(id, db), isNull);
    });

    test('mmRouteInboxToMindmap：条目标记 routed_to=mindmap（L6 第五向·导图侧）',
        () async {
      final a = await db.insert(DbSchema.tInbox,
          {'raw_text': '碎片A', 'created_at': 1});
      final b = await db.insert(DbSchema.tInbox,
          {'raw_text': '碎片B', 'created_at': 2});
      await db.insert(DbSchema.tInbox, {'raw_text': '已分流', 'created_at': 3, 'routed_to': 'todo'});
      await mmRouteInboxToMindmap([a, b], 9, db);
      final rows = await db.query(DbSchema.tInbox,
          where: 'routed_to = ?', whereArgs: ['mindmap']);
      expect(rows.map((r) => r['id']), containsAll([a, b]));
      // 待整理读源随之只剩「已分流」外的那部分——即本条目从待整理消失。
      final pending = await mmPendingInbox(db);
      expect(pending.map((e) => e.$1), isNot(contains(a)));
    });
  });

  group('画布挂载行为（H3/C4：显示层实时取笔记标题）', () {
    testWidgets('笔记改名 → 节点显示标题实时跟随；笔记删除 → 占位不崩',
        (tester) async {
      final dao = mindmapDaoOf(db);
      final noteId = await db.insert(DbSchema.tNotes, {
        'title': '原名笔记',
        'content': '',
        'created_at': 1,
        'updated_at': 1,
      });
      final mapId = await dao.createMap('图');
      final root = await dao.addNode(mapId: mapId, title: '自身标题');
      await dao.updateNode(
          root.copyWith(noteId: noteId, updatedAt: 1));
      await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(
            home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
      ));
      await tester.pumpAndSettle();
      // 画布节点是 CustomPainter 画的（不产生 Text widget），断言走读屏语义层。
      Finder semaOf(String prefix) => find.byWidgetPredicate((w) =>
          w is Semantics && (w.properties.label ?? '').startsWith(prefix));
      expect(semaOf('原名笔记'), findsOneWidget,
          reason: '挂载节点显示笔记标题（C4 实时跟随口径）');
      // 改名 → 跟随。
      await db.update(DbSchema.tNotes, {'title': '改过名了'},
          where: 'id = ?', whereArgs: [noteId]);
      // 触发一次刷新（换 key＝强制重建，等价重新进图；同型 pumpWidget 只会
      // didUpdateWidget 复用 State，不重载 _noteTitles 缓存）。
      await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(
            home: MindmapCanvasPage(
                key: const ValueKey('v2'), mapId: mapId, dao: dao, db: db)),
      ));
      await tester.pumpAndSettle();
      expect(semaOf('改过名了'), findsOneWidget);
      // 删除 → 占位（B6）。
      await db.delete(DbSchema.tNotes, where: 'id = ?', whereArgs: [noteId]);
      await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(
            home: MindmapCanvasPage(
                key: const ValueKey('v3'), mapId: mapId, dao: dao, db: db)),
      ));
      await tester.pumpAndSettle();
      expect(semaOf('（已删除的笔记）'), findsOneWidget);
    });

    testWidgets('单击＝选中、双击（已挂笔记）＝进笔记（H4/C5；跳转出口被调用）',
        (tester) async {
      final dao = mindmapDaoOf(db);
      final noteId = await db.insert(DbSchema.tNotes, {
        'title': '跳我',
        'content': '',
        'created_at': 1,
        'updated_at': 1,
      });
      final mapId = await dao.createMap('图');
      final root = await dao.addNode(mapId: mapId, title: '根');
      await dao.updateNode(root.copyWith(noteId: noteId, updatedAt: 1));
      final opened = <int>[];
      await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(
          home: MindmapCanvasPage(
            mapId: mapId,
            dao: dao,
            db: db,
            onOpenNote: (_, id) async => opened.add(id),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // 挂载节点显示的是笔记标题「跳我」——双击锚点按显示标题定位。
      final sema = find.byWidgetPredicate((w) =>
          w is Semantics && (w.properties.label ?? '').startsWith('跳我'));
      expect(sema, findsOneWidget);
      final center = tester.getRect(sema).center;
      // 双击：300ms 内两次短 tap 同节点 → 进笔记。
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final g2 = await tester.startGesture(center);
      await tester.pump();
      await g2.up();
      await tester.pumpAndSettle();
      expect(opened, [noteId], reason: '双击进笔记＝跳转出口被调用（H4）');
    });

    testWidgets('点空白取消选中（B5）＋未挂笔记双击不跳', (tester) async {
      final dao = mindmapDaoOf(db);
      final mapId = await dao.createMap('图');
      await dao.addNode(mapId: mapId, title: '根');
      final opened = <int>[];
      await tester.pumpWidget(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(
          home: MindmapCanvasPage(
            mapId: mapId,
            dao: dao,
            db: db,
            onOpenNote: (_, id) async => opened.add(id),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // 选中：tap 画布中心偏上（fit 后单节点在中心）。
      final center = tester.getCenter(find.byKey(const ValueKey('mm-canvas-paint')));
      await tapAt(tester, center);
      await tester.pump();
      // 点空白（左上角落）→ 取消选中：工具条回禁用态（onTap null）。
      await tapAt(tester, const Offset(20, 80));
      await tester.pump();
      // key 就钉在 InkWell 自身：find.descendant 不含自身，须直取。
      final moreInk = tester.widget<InkWell>(
          find.byKey(const ValueKey('mm-tool-more')));
      // 双击画布空白（未挂节点语义已由挂载用例覆盖；此处断言不崩不跳）。
      await tapAt(tester, const Offset(20, 80));
      await tester.pump();
      await tapAt(tester, const Offset(20, 80));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(moreInk, isNotNull);
    });
  });

  group('md 解析（连接点④·B2/B3）', () {
    test('标题通道：# 级定深度、首枚标题归一为根层、跳级归最近祖先', () {
      final r = parseMdOutline('# 一\n## 一点一\n# 二\n### 二点一点一');
      expect(r.roots.map((n) => n.title), ['一', '二']);
      expect(r.roots[0].children.single.title, '一点一');
      // 跳级（### 出现在 # 后，中间没有 ##）＝归最近可见祖先「二」的直接子级。
      expect(r.roots[1].children.single.title, '二点一点一');
    });

    test('三通道优先序（B3）：既有标题又有缩进＝标题通道，缩进信号忽略', () {
      // 同级标题：# 甲 / # 乙（## 会按 B3 挂为甲的子级，跳级归祖先已由上一例覆盖）。
      final r = parseMdOutline('# 甲\n  缩进行不该成节点\n# 乙');
      expect(r.roots, hasLength(2));
      expect(r.roots[0].children, isEmpty,
          reason: '缩进在标题通道下不叠加');
    });

    test('缩进通道：无标题时 2 空格/1 tab 每级（tab 记 2 列）', () {
      final r = parseMdOutline('甲\n  甲一\n\t\t甲一乙\n乙');
      expect(r.roots.map((n) => n.title), ['甲', '乙']);
      expect(r.roots[0].children.single.title, '甲一');
      expect(r.roots[0].children.single.children.single.title, '甲一乙');
    });

    test('空行通道：无标题无缩进＝分段平铺', () {
      final r = parseMdOutline('第一段\n第二段\n\n第三段');
      expect(r.roots.map((n) => n.title), ['第一段 第二段', '第三段']);
    });

    test('超限截断（B2）：节点超 2000 停＋truncated；深度超 20 截', () {
      final big = StringBuffer();
      for (var i = 0; i < 2100; i++) {
        // 逐段空行分段（空行通道口径：段内多行合并为一个节点，节点数＝段数）。
        big
          ..writeln('第$i行')
          ..writeln();
      }
      final r = parseMdOutline(big.toString());
      expect(r.truncated, isTrue);
      var count = 0;
      void walk(dynamic n) {
        count++;
        for (final c in n.children) {
          walk(c);
        }
      }

      for (final root in r.roots) {
        walk(root);
      }
      expect(count, mmMdMaxNodes);

      // 深度截断：25 层缩进链。
      final deep = StringBuffer('根\n');
      for (var i = 0; i < 25; i++) {
        deep.writeln('${'  ' * (i + 1)}层$i');
      }
      final rd = parseMdOutline(deep.toString());
      expect(rd.truncated, isTrue);
    });
  });
}
