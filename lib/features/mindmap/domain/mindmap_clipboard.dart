/// 思维导图节点剪贴板（批2 F4-2 · 冻结方案 §2.5）。
///
/// 口径：复制/剪切抓**完整后代闭包**行集快照；粘贴生成**新 id**（不保留原 id），
/// 父子关系按「旧根→新根、旧内部 id→新 id」重映射；可跨图（rows 的 map_id
/// 在粘贴时改写为目标图）。含子级与否由调用侧决定（F4-2「含子级可选」：
/// 只带节点本身＝rows 只装一行）。
library;

import 'mindmap_models.dart';

/// 会话级剪贴板（内存态，不持久化——F4-2 未要求；App 退出即失，与常规剪贴板一致）。
class MmClipboard {
  MmClipboard._();

  static List<MindmapNode>? _rows;

  /// true＝剪切来（粘贴后应清空，剪切语义）。
  static bool isCut = false;

  static bool get hasContent => _rows != null && _rows!.isNotEmpty;

  /// 根行（rows[0]）标题预览用。
  static String? get previewTitle => _rows?.first.title;

  /// 根行下完整后代数（预览「N 个子级」用）。
  static int get descendantCount => (_rows?.length ?? 1) - 1;

  static void put(List<MindmapNode> rows, {required bool cut}) {
    assert(rows.isNotEmpty, '剪贴板不接受空行集');
    _rows = List.of(rows);
    isCut = cut;
  }

  /// 取出（粘贴用）：返回行集副本；剪切语义下清空剪贴板。
  static List<MindmapNode>? take() {
    final r = _rows;
    if (r == null) return null;
    if (isCut) clear();
    return List.of(r);
  }

  /// 复制语义：读而不清。
  static List<MindmapNode>? peek() => _rows == null ? null : List.of(_rows!);

  static void clear() {
    _rows = null;
    isCut = false;
  }
}

/// 粘贴重映射：把剪贴板行集落到目标图，全部换成新 id、父子按映射重挂。
/// 返回（新根, 全部新行·父先子后），调用侧走 `MmCommands.addSubtree` 入栈。
/// 入参 `newRootParent`＝粘贴落点的父节点（null＝贴成新根）。
Future<(MindmapNode, List<MindmapNode>)> pasteRemap({
  required List<MindmapNode> rows,
  required int targetMapId,
  required int? newRootParent,
  required int Function() nextId,
  required int now,
}) async {
  assert(rows.isNotEmpty, '粘贴空行集');
  final root = rows.first;
  // 新 id 分配（先按旧序给全部行换 id，再第二趟补 parent 映射——两趟防错挂，
  // 与 MindmapDao.copyMap 同款手法）。
  final idMap = <int, int>{}; // 旧 id → 新 id
  final newRows = <MindmapNode>[];
  for (final n in rows) {
    final nid = nextId();
    if (n.id != null) idMap[n.id!] = nid;
    newRows.add(MindmapNode(
      id: nid,
      mapId: targetMapId,
      parentId: null, // 第二趟补
      noteId: n.noteId,
      title: n.title,
      note: n.note,
      side: n.side,
      sort: n.sort,
      dx: 0, // 粘贴不带原拖拽偏移：新落点从自动布局基线起步
      dy: 0,
      folded: n.folded,
      createdAt: now,
      updatedAt: now,
    ));
  }
  final out = <MindmapNode>[];
  for (var i = 0; i < rows.length; i++) {
    final old = rows[i];
    final neu = newRows[i];
    final parent = identical(old, root)
        ? newRootParent
        : (old.parentId == null ? null : idMap[old.parentId]);
    out.add(neu.copyWith(parentId: parent, clearParent: parent == null));
  }
  return (out.first, out);
}
