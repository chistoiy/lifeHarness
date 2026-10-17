import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_clipboard.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_undo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mindmap_test_harness.dart';

/// 批2 F4-1/F4-2 · 撤销/重做命令栈＋节点剪贴板（工单 §4c.3 ①）。
/// 纯逻辑件（DAO＋栈闭环），无 widget——与画布 widget 测试分文件（隔离纪律）。
///
/// 栈语义：`push` **不执行**（画布真实顺序＝操作先落库、再入栈）；
/// undo/redo 按快照逆/正落库。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MindmapDao dao;
  late MmUndoStack stack;
  late int mapId;

  setUp(() async {
    db = await openMmDb();
    dao = mindmapDaoOf(db);
    stack = MmUndoStack();
    mapId = await dao.createMap('栈测试图');
    MmClipboard.clear();
  });

  tearDown(() async {
    await db.close();
    MmClipboard.clear();
  });

  /// 画布「加节点」真实顺序：落库→快照→push。
  Future<MindmapNode> addVia(String title, {int? parentId}) async {
    final n = await dao.addNode(mapId: mapId, parentId: parentId, title: title);
    final rows = await dao.nodesOfIds({n.id!});
    stack.push(MmCommands.addSubtree(n, rows));
    return n;
  }

  group('F4-1 撤销/重做命令栈', () {
    test('逐步退：undo 只退最近一步；redo 按快照复放（显式 id 父子不悬空）',
        () async {
      final a = await addVia('甲');
      await addVia('甲子', parentId: a.id);
      expect((await dao.nodesOf(mapId)).length, 2);

      await stack.undo(dao);
      var titles =
          (await dao.nodesOf(mapId)).map((n) => n.title).toList();
      expect(titles, ['甲'], reason: '只退「加甲子」一步');
      await stack.undo(dao);
      expect(await dao.nodesOf(mapId), isEmpty, reason: '退「加甲」＝清图');

      await stack.redo(dao);
      expect((await dao.nodesOf(mapId)).map((n) => n.title), ['甲']);
      await stack.redo(dao);
      titles = (await dao.nodesOf(mapId)).map((n) => n.title).toList();
      expect(titles, containsAll(['甲', '甲子']), reason: '甲子快照 parent 指甲的原 id，甲已先复原');
    });

    test('删一步：undo 整行重插带原 id、redo 按行集再删', () async {
      final a = await addVia('根');
      final b = await addVia('子', parentId: a.id);
      // 画布删除真实顺序：取完整后代闭包快照→落库级联删→push
      final doomed = await dao.descendantIdsOf(a.id!);
      final rows = await dao.nodesOfIds(doomed);
      await dao.deleteNodeCascade(a.id!);
      stack.push(MmCommands.deleteRows(rows, '删除「根」（连带 1 个子级）'));
      expect(await dao.nodesOf(mapId), isEmpty);

      await stack.undo(dao);
      final restored = await dao.nodesOf(mapId);
      expect(restored.length, 2);
      expect(restored.map((n) => n.id), containsAll([a.id, b.id]),
          reason: '整行显式 id 重插，父子引用不悬空');
      final child = restored.firstWhere((n) => n.id == b.id);
      expect(child.parentId, a.id);

      await stack.redo(dao);
      expect(await dao.nodesOf(mapId), isEmpty);
    });

    test('改一步（编辑标题备注）：undo/redo 前后值互写', () async {
      final a = await addVia('原名');
      final before = (await dao.nodeById(a.id!))!;
      final after = before.copyWith(title: '新名', note: '有备注了');
      await dao.updateNode(after); // 画布真实顺序：先落库
      stack.push(MmCommands.editNode(before, after));
      expect((await dao.nodeById(a.id!))!.title, '新名');

      await stack.undo(dao);
      final undone = (await dao.nodeById(a.id!))!;
      expect(undone.title, '原名');
      expect(undone.note, '');

      await stack.redo(dao);
      final redone = (await dao.nodeById(a.id!))!;
      expect(redone.title, '新名');
      expect(redone.note, '有备注了');
    });

    test('移一步（拖拽偏移 dx/dy）与折叠一步同走 editNode 通道', () async {
      final a = await addVia('节点');
      final before = (await dao.nodeById(a.id!))!;
      final moved = before.copyWith(dx: 60, dy: 40);
      await dao.updateNode(moved);
      stack.push(MmCommands.editNode(before, moved, label: '移动节点'));
      final folded = moved.copyWith(folded: true);
      await dao.updateNode(folded);
      stack.push(MmCommands.editNode(moved, folded, label: '折叠子级'));
      expect((await dao.nodeById(a.id!))!.folded, isTrue);

      await stack.undo(dao); // 退折叠
      final cur = (await dao.nodeById(a.id!))!;
      expect(cur.folded, isFalse);
      expect(cur.dx, 60, reason: '只退最近一步，移动保留');

      await stack.undo(dao); // 退移动
      final base = (await dao.nodeById(a.id!))!;
      expect(base.dx, 0);
      expect(base.dy, 0);
    });

    test('多步：五步全退＝回到空图；redo 链按原序复放', () async {
      final titles = ['一', '二', '三', '四', '五'];
      for (final t in titles) {
        await addVia(t);
      }
      expect((await dao.nodesOf(mapId)).length, 5);
      for (var i = 0; i < 5; i++) {
        await stack.undo(dao);
      }
      expect(stack.canUndo, isFalse);
      expect(await dao.nodesOf(mapId), isEmpty);
      for (var i = 0; i < 5; i++) {
        await stack.redo(dao);
      }
      expect((await dao.nodesOf(mapId)).length, 5);
      expect(stack.canRedo, isFalse);
    });

    test('undo 后 push 新命令＝重做链作废（指针右侧清空）', () async {
      await addVia('甲');
      await stack.undo(dao);
      expect(stack.canRedo, isTrue);
      await addVia('乙');
      expect(stack.canRedo, isFalse, reason: '新命令入栈即弃重做链');
      await stack.undo(dao);
      expect(await dao.nodesOf(mapId), isEmpty);
    });

    test('栈上限 60：超出丢最旧（对齐 _mdUndo 惯例）', () async {
      for (var i = 0; i < MmUndoStack.limit + 5; i++) {
        await addVia('n$i');
      }
      var steps = 0;
      while (stack.canUndo) {
        await stack.undo(dao);
        steps++;
      }
      expect(steps, MmUndoStack.limit);
      expect((await dao.nodesOf(mapId)).length, 5);
    });

    test('空栈 undo/redo 返回 null 不炸', () async {
      expect(await stack.undo(dao), isNull);
      expect(await stack.redo(dao), isNull);
    });
  });

  group('F4-2 节点剪贴板', () {
    test('复制（peek 读而不清）→ 粘贴生成新 id、父子重挂、跨图换 map_id', () async {
      final a = await addVia('根');
      await addVia('子', parentId: a.id);
      final rows = await dao.nodesOfIds(await dao.descendantIdsOf(a.id!));
      MmClipboard.put(rows, cut: false);

      final mapB = await dao.createMap('目标图');
      final taken = MmClipboard.peek()!;
      expect(MmClipboard.hasContent, isTrue, reason: '复制语义读而不清');
      final (newRoot, newRows) = await pasteRemap(
        rows: taken,
        targetMapId: mapB,
        newRootParent: null,
        nextId: () => 777001,
        now: 12345,
      );
      expect(newRoot.title, '根');
      expect(newRoot.mapId, mapB);
      expect(newRoot.id, isNot(a.id), reason: '粘贴生成新 id');
      expect(newRows.length, 2);
      final newChild = newRows[1];
      expect(newChild.parentId, newRoot.id, reason: '父子按映射重挂');
      expect(newChild.mapId, mapB);
      expect(newChild.dx, 0, reason: '粘贴不带原拖拽偏移');
      expect((await dao.nodesOf(mapId)).length, 2, reason: '原图行未动');
    });

    test('剪切（take 取即清）语义', () async {
      final a = await addVia('独苗');
      final rows = await dao.nodesOfIds({a.id!});
      MmClipboard.put(rows, cut: true);
      expect(MmClipboard.isCut, isTrue);
      MmClipboard.take();
      expect(MmClipboard.hasContent, isFalse, reason: '剪切取走即清');
    });

    test('含子级可选：只带节点本身＝单行闭包', () async {
      final a = await addVia('父');
      await addVia('子', parentId: a.id);
      MmClipboard.put(await dao.nodesOfIds({a.id!}), cut: false);
      final taken = MmClipboard.peek()!;
      expect(taken.length, 1, reason: 'F4-2「含子级可选」的不带子级形态');
      final (_, newRows) = await pasteRemap(
        rows: taken,
        targetMapId: mapId,
        newRootParent: null,
        nextId: () => 999001,
        now: 1,
      );
      expect(newRows.length, 1);
    });

    test('粘贴落点为子级：newRootParent 挂上、undo「粘贴」整树退场', () async {
      final a = await addVia('落点');
      final b = await addVia('别枝');
      MmClipboard.put(await dao.nodesOfIds({b.id!}), cut: false);
      final (_, newRows) = await pasteRemap(
        rows: MmClipboard.peek()!,
        targetMapId: mapId,
        newRootParent: a.id,
        nextId: () => 888001,
        now: 1,
      );
      for (final n in newRows) {
        await dao.insertNodeFull(n);
      }
      final pasted = newRows.first;
      expect((await dao.nodeById(pasted.id!))!.parentId, a.id);

      stack.push(MmCommands.addSubtree(pasted, newRows));
      await stack.undo(dao);
      expect(await dao.nodeById(pasted.id!), isNull, reason: '撤销粘贴＝整树退场');
      expect(await dao.nodeById(a.id!), isNotNull, reason: '落点父节点不受连坐');
    });
  });
}
