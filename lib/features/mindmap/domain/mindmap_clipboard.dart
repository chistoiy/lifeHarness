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

/// 把「按 id 集取回的无序行集」整理成**根在前、父先子后**的树序。
///
/// 为什么必须有这一道：`MindmapDao.nodesOfIds` 走 `WHERE id IN (...)`，SQLite
/// 不保证返回序；而 [pasteRemap] 依赖 `rows.first`＝根、且父行先于子行（第二趟
/// 补 parent_id 用的是**已生成的映射**，与行序无关，但插入顺序仍是父先子后
/// 才不依赖延迟外键）。同层按 `sort` 升序，黏贴出来的枝内顺序才可预期。
///
/// 不可达的行（父引用不在集内＝数据异常）兜底追加在末尾：宁可多带一行，
/// 也不要静默吞掉用户的节点。
List<MindmapNode> mmOrderSubtree(List<MindmapNode> rows, int rootId) {
  if (rows.isEmpty) return const [];
  int cmp(MindmapNode a, MindmapNode b) {
    final c = a.sort.compareTo(b.sort);
    return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
  }

  final byParent = <int?, List<MindmapNode>>{};
  for (final r in rows) {
    byParent.putIfAbsent(r.parentId, () => []).add(r);
  }
  for (final v in byParent.values) {
    v.sort(cmp);
  }
  final out = <MindmapNode>[];
  final seen = <int>{};
  void walk(MindmapNode n) {
    if (n.id != null && !seen.add(n.id!)) return; // 环兜底：一条路只走一次
    out.add(n);
    for (final k in byParent[n.id] ?? const <MindmapNode>[]) {
      walk(k);
    }
  }

  walk(rows.firstWhere((r) => r.id == rootId, orElse: () => rows.first));
  for (final r in rows) {
    if (r.id == null || !seen.contains(r.id)) out.add(r);
  }
  return out;
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
      // 批P3：**`is_task` 与 `task_done` 必须成对跟走**。模型有一条不变量
      // 「非任务不得带完成态」（`copyWith` 里 `(isTask ?? this.isTask) ? ... : false`），
      // 只搬 taskDone 不搬 isTask，下面 copyWith 会把完成态掰回 false——表现就是
      // 「复制一份已勾选的清单，粘出来全没勾」。
      isTask: n.isTask,
      taskDone: n.taskDone,
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
