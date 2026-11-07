import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_clipboard.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';

import 'mindmap_test_harness.dart';

/// 画布「粘贴」回落系统剪贴板（2026-10-29 补 · 产品报障
/// 「思维导图不支持直接粘贴 md 内容渲染」）。
///
/// 口径：应用内剪贴板（复制/剪切节点）优先；为空时读系统剪贴板文本，
/// 按 `parseMdOutline` 展开成子树贴到目标同级/子级。菜单项**不再按应用内
/// 剪贴板有无置灰**——系统剪贴板有没有内容只有点下去才知道。
const _md = '# 一\n- 一甲\n- 一乙\n# 二\n- 二甲\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openMmDb();
    MmClipboard.clear(); // 会话级静态态，用例之间必须隔离
  });
  tearDown(() async {
    await (db as CloseableDb).close();
    MmClipboard.clear();
  });

  /// 系统剪贴板桩（`Clipboard.getData` → 给定文本）。
  void stubClipboard(WidgetTester tester, String text) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': text} : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  Future<MindmapDao> pumpCanvas(WidgetTester tester, int mapId) async {
    final dao = mindmapDaoOf(db);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child:
          MaterialApp(home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
    ));
    await tester.pumpAndSettle();
    return dao;
  }

  Future<void> tapNode(WidgetTester tester, String title) async {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == title);
    expect(f, findsOneWidget, reason: '画布语义层应能找到节点「$title」');
    await tapAt(tester, tester.getCenter(f));
  }

  Future<void> pickMenuItem(WidgetTester tester, String key) async {
    // SnackBar 浮在底部会盖住「更多」按钮；连续 show 后自动退场计时会失效，
    // 直接摘掉（同 `mindmap_clipboard_menu_test` 的 letToastPass 口径）。
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      final ctx = tester.element(find.byType(Scaffold).first);
      ScaffoldMessenger.of(ctx).removeCurrentSnackBar();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    await tester.tap(find.byKey(const ValueKey('mm-bubble-more')));
    await tester.pumpAndSettle();
    final f = find.byKey(ValueKey('mm-menu-$key'));
    expect(f, findsOneWidget, reason: '菜单里应有「$key」');
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('粘贴子级：系统剪贴板 md → 整棵子树挂到目标下', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('粘贴测试');
    final root = await dao.addNode(mapId: mapId, title: '中心');
    await dao.addNode(mapId: mapId, parentId: root.id, title: '原有');

    stubClipboard(tester, _md);
    await pumpCanvas(tester, mapId);

    await tapNode(tester, '中心');
    await pickMenuItem(tester, 'pasteChild');

    final rows = await dao.nodesOf(mapId);
    // 原有 2 枚 ＋ md 的 5 枚（一/一甲/一乙/二/二甲）。
    expect(rows.length, 7, reason: 'md 五枚节点全部落库（原实现只认应用内剪贴板）');
    final byTitle = {for (final r in rows) r.title: r};
    expect(byTitle['一']!.parentId, root.id, reason: '一级标题挂在目标节点下');
    expect(byTitle['一甲']!.parentId, byTitle['一']!.id, reason: '列表项挂当前标题下');
    expect(byTitle['二']!.parentId, root.id);
    expect(byTitle['二甲']!.parentId, byTitle['二']!.id);
  });

  testWidgets('撤销：一次退掉整片（多根森林不能只退第一棵）', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('撤销测试');
    await dao.addNode(mapId: mapId, title: '中心');

    stubClipboard(tester, _md);
    await pumpCanvas(tester, mapId);

    await tapNode(tester, '中心');
    await pickMenuItem(tester, 'pasteChild');
    expect((await dao.nodesOf(mapId)).length, 6);

    await tester.tap(find.byKey(const ValueKey('mm-undo-btn')));
    await tester.pumpAndSettle();
    expect((await dao.nodesOf(mapId)).length, 1,
        reason: '「一」「二」两棵根都要退掉（只删第一棵会剩半片）');
  });

  testWidgets('剪贴板是空文本：给一句人话，不建节点', (tester) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('空粘贴');
    await dao.addNode(mapId: mapId, title: '中心');

    stubClipboard(tester, '   ');
    await pumpCanvas(tester, mapId);

    await tapNode(tester, '中心');
    await pickMenuItem(tester, 'pasteChild');
    expect((await dao.nodesOf(mapId)).length, 1);
  });
}
