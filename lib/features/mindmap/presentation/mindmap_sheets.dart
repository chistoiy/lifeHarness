import 'package:flutter/material.dart';

import '../../../shared/linkage/mindmap_mounts.dart';
import '../../../shared/widgets/confirm_dialog.dart';

/// 思维导图弹层族（批1 · 原型 `sheetMm-*` 对应物）。
///
/// 复用规则（冻结方案 §5.5）：删除确认走 [lhConfirm]（不新造）、弹层用
/// 系统底部上滑骨架（120~180ms 框架自带）、线性图标、文案不教学。
/// 空标题拦截（B8）与节点上限提示（B9）在弹层内给一行人话，不静默。

/// 添加/编辑节点弹层（原型 sheetMm-node 双分支）：返回 (标题, 备注)。
/// 空标题＝禁用保存钮（B8：禁止保存空标题，根节点同上）。
Future<(String, String)?> showMmNodeSheet(
  BuildContext context, {
  String initialTitle = '',
  String initialNote = '',
  required String headline,
}) {
  final titleCtrl = TextEditingController(text: initialTitle);
  final noteCtrl = TextEditingController(text: initialNote);
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) {
      final cs = Theme.of(bc).colorScheme;
      return StatefulBuilder(
        builder: (bc, setS) {
          final ok = titleCtrl.text.trim().isNotEmpty;
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(bc).bottom),
            child: SafeArea(
              child: Padding(
                key: const ValueKey('mm-node-sheet'),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(headline,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('mm-node-title'),
                      controller: titleCtrl,
                      autofocus: initialTitle.isEmpty,
                      maxLines: 1,
                      onChanged: (_) => setS(() {}),
                      decoration: const InputDecoration(
                        hintText: '节点标题',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('mm-node-note'),
                      controller: noteCtrl,
                      maxLines: 4,
                      minLines: 2,
                      decoration: const InputDecoration(
                        hintText: '备注（画布不显示，编辑时可读回）',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(bc),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('mm-node-save'),
                          onPressed: ok
                              ? () => Navigator.pop(bc, (
                                    titleCtrl.text.trim(),
                                    noteCtrl.text.trim(),
                                  ))
                              : null,
                          style: ok
                              ? null
                              : FilledButton.styleFrom(
                                  disabledForegroundColor:
                                      cs.onSurface.withValues(alpha: .38)),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                    if (!ok)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('节点标题不能为空',
                            key: const ValueKey('mm-node-empty-hint'),
                            style: TextStyle(
                                fontSize: 12, color: cs.error)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

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
