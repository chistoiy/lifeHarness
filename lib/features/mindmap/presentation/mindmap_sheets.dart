import 'package:flutter/material.dart';

import '../../../shared/linkage/mindmap_mounts.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../data/mindmap_dao.dart';
import '../domain/mindmap_models.dart';
import 'mindmap_node_sheet.dart';

/// 思维导图弹层族（批1 · 原型 `sheetMm-*` 对应物）。
///
/// 复用规则（冻结方案 §5.5）：删除确认走 [lhConfirm]（不新造）、弹层用
/// 系统底部上滑骨架（120~180ms 框架自带）、线性图标、文案不教学。
/// 空标题拦截（B8）与节点上限提示（B9）在弹层内给一行人话，不静默。
///
/// **批5**：节点弹层已抽去同目录 `mindmap_node_sheet.dart`（要加标签/任务/图片
/// 三段且返回值换成 `MmNodeDraft`，留在本件会顶破 `size_budget` 预算线）；
/// 本件只剩挂载笔记 / 行内菜单 / md 解析预览 / 删除确认 / 文件夹五族。

/// 挂载笔记弹层（原型 sheetMm-bindNote）：搜索＋列表；已挂载行高亮。
/// 返回值：null＝取消；`-1`＝解绑；其余＝新挂载笔记 id。
Future<int?> showMmBindSheet(BuildContext context, {int? currentNoteId}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _NotePickSheet(currentNoteId: currentNoteId),
  );
}

class _NotePickSheet extends StatefulWidget {
  const _NotePickSheet({this.currentNoteId});

  final int? currentNoteId;

  @override
  State<_NotePickSheet> createState() => _NotePickSheetState();
}

class _NotePickSheetState extends State<_NotePickSheet> {
  List<MmNoteRef> _all = const [];
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    mmMountableNotes().then((v) {
      if (!mounted) return;
      setState(() {
        _all = v;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hits = _q.isEmpty
        ? _all
        : _all.where((n) => n.title.contains(_q)).toList();
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('mm-bind-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text('挂载笔记',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const ValueKey('mm-bind-search'),
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                    hintText: '搜笔记', isDense: true, prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : hits.isEmpty
                      ? Center(
                          child: Text('没有匹配的笔记',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13)))
                      : ListView.builder(
                          itemCount: hits.length,
                          itemBuilder: (bc, i) {
                            final n = hits[i];
                            final cur = n.id == widget.currentNoteId;
                            return ListTile(
                              key: ValueKey('mm-bind-item-${n.id}'),
                              dense: true,
                              leading: Icon(
                                Icons.notes_outlined,
                                size: 20,
                                color: cur
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              title: Text(n.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: cur
                                          ? FontWeight.w700
                                          : FontWeight.w400)),
                              trailing: cur
                                  ? Text('当前挂载',
                                      style: TextStyle(
                                          fontSize: 11, color: cs.primary))
                                  : null,
                              onTap: () => Navigator.pop(bc, n.id),
                            );
                          },
                        ),
            ),
            if (widget.currentNoteId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                child: OutlinedButton(
                  key: const ValueKey('mm-bind-unbind'),
                  onPressed: () => Navigator.pop(context, -1),
                  child: const Text('解绑当前笔记'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 通用行内菜单（长按节点菜单 / 图行更多 / 画布更多共用一份骨架）。
/// 返回选中项的 key；点遮罩＝null。
Future<String?> showMmMenu(
  BuildContext context,
  List<({String key, IconData icon, String label, bool enabled})> items,
) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) {
      final cs = Theme.of(bc).colorScheme;
      return SafeArea(
        // 菜单项数不定：包滚动，短视口（横屏/测试 600 高）不溢出（9/16 上限内自滚）。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              for (final it in items)
                ListTile(
                  key: ValueKey('mm-menu-${it.key}'),
                  dense: true,
                  enabled: it.enabled,
                  leading: Icon(it.icon,
                      size: 20,
                      color: it.enabled
                          ? cs.onSurface
                          : cs.onSurfaceVariant.withValues(alpha: .4)),
                  title: Text(it.label,
                      style: TextStyle(
                          fontSize: 14,
                          color: it.enabled
                              ? null
                              : cs.onSurfaceVariant.withValues(alpha: .4))),
                  onTap: it.enabled ? () => Navigator.pop(bc, it.key) : null,
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// 解析预览弹层（原型 sheetMm-fromMd）：层级树缩进预览＋截断提示＋确认。
Future<bool> showMmFromMdPreview(
  BuildContext context,
  List<(String, int)> flat, {
  required bool truncated,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) {
      final cs = Theme.of(bc).colorScheme;
      return SafeArea(
        child: SizedBox(
          key: const ValueKey('mm-frommd-sheet'),
          height: MediaQuery.sizeOf(bc).height * 0.66,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text('解析预览',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              if (truncated)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    key: const ValueKey('mm-md-truncated'),
                    '已截断，超出部分未导入',
                    style: TextStyle(fontSize: 12, color: cs.error),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: flat.length,
                  itemBuilder: (bc, i) {
                    final (title, depth) = flat[i];
                    return Padding(
                      padding: EdgeInsets.only(left: depth * 18.0, top: 4),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                depth == 0 ? FontWeight.w700 : FontWeight.w400),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(bc, false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('mm-frommd-ok'),
                      onPressed: () => Navigator.pop(bc, true),
                      child: const Text('生成导图'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return r ?? false;
}

/// 删除二次确认（F1-11：确认文案列明连带子级数；C1：文案不出现「可撤销」——
/// 撤销栈排批 2，节点删除不进回收站，进回收站的是「删图」第九类）。
Future<bool> mmConfirmDeleteNode(BuildContext context, int total, int children) {
  return lhConfirm(context, '将删除 $total 个节点（含 $children 个子节点）\n此操作不可恢复');
}

/// 文件夹管理弹层（批2 F4-4 · 原型 sheetMm-folders）：文件夹列表＋新建＋
/// 行内改名/删除。删文件夹＝**只置空引用不删图**（DAO 侧已钉；本弹层给
/// 人话确认）。操作即时生效，关弹层后由调用侧刷新列表。
Future<void> showMmFolderSheet(BuildContext context, MindmapDao dao) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _MmFolderSheet(dao: dao),
  );
}

class _MmFolderSheet extends StatefulWidget {
  const _MmFolderSheet({required this.dao});

  final MindmapDao dao;

  @override
  State<_MmFolderSheet> createState() => _MmFolderSheetState();
}

class _MmFolderSheetState extends State<_MmFolderSheet> {
  List<MindmapFolder> _folders = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final v = await widget.dao.listFolders();
    if (!mounted) return;
    setState(() {
      _folders = v;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final r = await showMmNodeSheet(context, headline: '新建文件夹');
    if (r == null) return;
    await widget.dao.createFolder(r.title);
    await _reload();
  }

  Future<void> _rename(MindmapFolder f) async {
    final r = await showMmNodeSheet(context,
        headline: '重命名文件夹', initialTitle: f.title);
    if (r == null) return;
    await widget.dao.renameFolder(f.id!, r.title);
    await _reload();
  }

  Future<void> _delete(MindmapFolder f) async {
    final ok = await lhConfirm(
        context, '删除文件夹「${f.title}」？\n文件夹里的导图会回到「全部」，不会删除');
    if (!ok) return;
    await widget.dao.deleteFolder(f.id!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('mm-folder-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text('文件夹',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : _folders.isEmpty
                      ? Center(
                          child: Text('还没有文件夹，新建一个归类导图',
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant)))
                      : ListView.builder(
                          itemCount: _folders.length,
                          itemBuilder: (bc, i) {
                            final f = _folders[i];
                            return ListTile(
                              key: ValueKey('mm-folder-row-${f.id}'),
                              dense: true,
                              leading: const Icon(Icons.folder_outlined,
                                  size: 20),
                              title: Text(f.title,
                                  style: const TextStyle(fontSize: 13.5)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey(
                                        'mm-folder-rename-${f.id}'),
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    onPressed: () => _rename(f),
                                  ),
                                  IconButton(
                                    key: ValueKey('mm-folder-del-${f.id}'),
                                    icon: const Icon(Icons.delete_outlined,
                                        size: 18),
                                    onPressed: () => _delete(f),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: OutlinedButton(
                key: const ValueKey('mm-folder-create'),
                onPressed: _create,
                child: const Text('新建文件夹'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
