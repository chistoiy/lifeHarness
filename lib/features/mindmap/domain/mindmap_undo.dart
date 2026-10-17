/// 思维导图撤销/重做命令栈（批2 F4-1 · 冻结方案 §2.5）。
///
/// 口径（冻结方案 F4-1）：
/// · 增/删/改/移/折叠各为一步，支持**多步**撤销与重做；
/// · **不得用 `AppToast` 单次撤销顶替**（那是单条 toast 回调，不是栈）；
/// · 快照式实现（对齐 journal 域 `_mdUndo` 惯例：闭包捕获前后快照，
///   上限 60 条，超出丢最旧）——不引入通用 diff/命令模式依赖。
///
/// undo「加节点」连带其**当下全部后代**（不留孤儿行）；undo「删」整行快照
/// 重插（显式 id，两趟问题不存在——parent 引用的是 id 不是位置）。
library;

import '../data/mindmap_dao.dart';
import 'mindmap_models.dart';

/// 一条可逆操作。`label` 供撤销后的反馈文案取材（调用侧拼「已撤销：label」，
/// C1 口径：文案不出现「可撤销」承诺字样）。
class MmCommand {
  MmCommand({
    required this.label,
    required this.redo,
    required this.undo,
  });

  final String label;
  final Future<void> Function(MindmapDao dao) redo;
  final Future<void> Function(MindmapDao dao) undo;
}

/// 命令栈（每个画布会话一份；跨图切换不共享——粘贴板可跨图，栈不跨图）。
class MmUndoStack {
  static const int limit = 60;

  final List<MmCommand> _done = [];
  final List<MmCommand> _undone = [];

  bool get canUndo => _done.isNotEmpty;
  bool get canRedo => _undone.isNotEmpty;

  /// 入栈（**不执行**——调用侧已先把操作落库，push 只登记逆操作对）。
  /// 执行新命令即清空重做链（所有撤销栈的通用语义）。
  void push(MmCommand c) {
    _done.add(c);
    _undone.clear();
    if (_done.length > limit) _done.removeAt(0);
  }

  /// 返回被撤销命令的 label（栈空返回 null）。
  Future<String?> undo(MindmapDao dao) async {
    if (_done.isEmpty) return null;
    final c = _done.removeLast();
    await c.undo(dao);
    _undone.add(c);
    return c.label;
  }

  Future<String?> redo(MindmapDao dao) async {
    if (_undone.isEmpty) return null;
    final c = _undone.removeLast();
    await c.redo(dao);
    _done.add(c);
    return c.label;
  }

  /// 测试与「切图即清栈」用。
  void clear() {
    _done.clear();
    _undone.clear();
  }
}

/// 命令工厂。全部按「执行前先取快照」的调用约定设计：
/// 调用侧（画布控制器）在**操作生效前**构造命令，传入的前后快照即为 undo/redo 依据。
class MmCommands {
  MmCommands._();

  /// 加节点（含粘贴生成的新子树）：redo 重插快照行，undo 连带后代删。
  static MmCommand addSubtree(MindmapNode root, List<MindmapNode> rows) {
    return MmCommand(
      label: '添加「${root.title}」',
      redo: (dao) async {
        for (final n in rows) {
          await dao.insertNodeFull(n);
        }
      },
      undo: (dao) async {
        // 连带当下全部后代（后续命令加的子级一并退场，不留孤儿）
        final doomed = await dao.descendantIdsOf(root.id!);
        await dao.deleteNodeRows(doomed);
      },
    );
  }

  /// 删节点（含子级）：`rows` 必须是删除前取好的**完整后代闭包**行集
  ///（undo 整行重插＝级联语义的逆；redo 按行集 DELETE——比按链再推导精确）。
  static MmCommand deleteRows(List<MindmapNode> rows, String label) {
    return MmCommand(
      label: label,
      redo: (dao) => dao.deleteNodeRows({
        for (final n in rows) n.id!,
      }),
      undo: (dao) async {
        for (final n in rows) {
          await dao.insertNodeFull(n);
        }
      },
    );
  }

  /// 改节点（编辑标题备注/拖拽偏移/折叠切换共用：前后整值快照）。
  static MmCommand editNode(MindmapNode before, MindmapNode after,
      {String? label}) {
    return MmCommand(
      label: label ?? '修改「${after.title}」',
      redo: (dao) => dao.updateNode(after),
      undo: (dao) => dao.updateNode(before),
    );
  }
}
