import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_list_page.dart';
import 'package:lifeharness/shared/trash/trash_models.dart';
import 'package:lifeharness/shared/trash/trash_specs.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批1 · 图管理交互守护（工单 §4b.3 ⑦：F2-2/F2-4）。
/// 原型 `mmRenameSave` 的 map 分支此前是死代码——本文件钉「真入口真调用」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  setUp(() async {
    db = await openMmDb();
  });
  tearDown(() async {
    await (db as CloseableDb).close();
  });

  testWidgets('图列表行内更多 → 重命名：弹层带现名、保存后列表即时刷新（F2-2）',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('旧名图');
    await dao.addNode(mapId: mapId, title: '根');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: MindmapListPage(dao: dao)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('旧名图'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('mm-row-more-$mapId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-rename')));
    await tester.pumpAndSettle();
    // 读回现名（rename map 分支真打开）。
    final titleField = tester.widget<TextField>(
        find.byKey(const ValueKey('mm-node-title')));
    expect(titleField.controller!.text, '旧名图');
    await tester.enterText(
        find.byKey(const ValueKey('mm-node-title')), '新名图');
    await tester.tap(find.byKey(const ValueKey('mm-node-save')));
    await tester.pumpAndSettle();
    expect(find.text('新名图'), findsOneWidget);
    expect(await dao.mapById(mapId).then((m) => m!.title), '新名图');
  });

  testWidgets('图列表行内更多 → 删除导图：二次确认后进回收站第九类（F2-4）',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('要删的图');
    await dao.addNode(mapId: mapId, title: '根');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: MindmapListPage(dao: dao)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('mm-row-more-$mapId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-del')));
    await tester.pumpAndSettle();
    // lhConfirm 双钮（d-confirm-ok/cancel 既有锚点）。
    expect(find.byKey(const ValueKey('d-confirm-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await tester.pumpAndSettle();
    // 列表即时移除。
    expect(find.text('要删的图'), findsNothing);
    // 真进第九类（spec 读源可见）。
    final rows = await trashSpecOf(TrashKind.mindmap).rows(db);
    expect(rows.map((e) => e.rawId), contains(mapId));
    // 恢复回列表（换 key＝强制重建，等价重新进页；同型 pumpWidget 只会
    // didUpdateWidget 复用 State，列表不重载）。
    await dao.restoreMap(mapId);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          home: MindmapListPage(key: const ValueKey('v2'), dao: dao)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('要删的图'), findsOneWidget);
  });

  testWidgets('复制图：行内更多 → 复制 → 列表出现「原名 副本」新行（F2-3）',
      (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('原图');
    await dao.addNode(mapId: mapId, title: '根');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: MindmapListPage(dao: dao)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('mm-row-more-$mapId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mm-menu-copy')));
    await tester.pumpAndSettle();
    expect(find.text('原图 副本'), findsOneWidget);
    final rows = await dao.listLive();
    expect(rows, hasLength(2));
  });
}
