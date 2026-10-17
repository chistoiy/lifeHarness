import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../../../shared/widgets/image_attach.dart' show pickAndStoreImage;
import '../domain/mindmap_node_meta.dart';

/// 添加/编辑节点弹层（原型 `sheetMm-node` 五段：标题/备注/**标签**/**任务属性**/
/// **节点图片**，批5 F4-9 补后三段）。返回 [MmNodeDraft]；null＝取消。
///
/// 空标题＝禁用保存钮（B8：禁止保存空标题，根节点同上）。
/// 三段的批5 口径：
/// · **标签**＝一行输入、按 `[,，]` 切、读回时 `', '` 连接（原型同款）；
/// · **任务属性**＝一枚 chip 开关（`设为任务`／`已是任务`），**取消任务即清完成态**
///   （原型 `if(!n.task) n.taskDone=false`）；
/// · **节点图片**＝走 `image_attach` 通路选一张，落盘路径随草稿返回
///   （画布只画占位角标，见工单 §4f.3 口径一）。
///
/// 本件从 `mindmap_sheets.dart` 抽出：批5 要给它加三段 ＋ 改返回值类型，
/// 而画布页已近 `size_budget` 预算线（登记面 1200），塞回原文件会顶破。
class MmNodeDraft {
  const MmNodeDraft({
    required this.title,
    this.note = '',
    this.tags = const <String>[],
    this.isTask = false,
    this.imagePath,
  });

  final String title;
  final String note;

  /// 已按输入分隔符切好、去重保序的标签列表。
  final List<String> tags;

  final bool isTask;

  /// 已选图片的落盘路径（null＝未挂图）。
  final String? imagePath;
}

Future<MmNodeDraft?> showMmNodeSheet(
  BuildContext context, {
  String initialTitle = '',
  String initialNote = '',
  List<String> initialTags = const <String>[],
  bool initialTask = false,
  String? initialImagePath,
  required String headline,
}) {
  final titleCtrl = TextEditingController(text: initialTitle);
  final noteCtrl = TextEditingController(text: initialNote);
  final tagsCtrl =
      TextEditingController(text: mmTagsFormat(initialTags));
  return showModalBottomSheet<MmNodeDraft>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _MmNodeSheet(
      headline: headline,
      titleCtrl: titleCtrl,
      noteCtrl: noteCtrl,
      tagsCtrl: tagsCtrl,
      initialTask: initialTask,
      initialImagePath: initialImagePath,
    ),
  );
}

/// 弹层体（Stateful：任务 chip 与图片按钮要就地改态）。
class _MmNodeSheet extends StatefulWidget {
  const _MmNodeSheet({
    required this.headline,
    required this.titleCtrl,
    required this.noteCtrl,
    required this.tagsCtrl,
    required this.initialTask,
    required this.initialImagePath,
  });

  final String headline;
  final TextEditingController titleCtrl;
  final TextEditingController noteCtrl;
  final TextEditingController tagsCtrl;
  final bool initialTask;
  final String? initialImagePath;

  @override
  State<_MmNodeSheet> createState() => _MmNodeSheetState();
}

class _MmNodeSheetState extends State<_MmNodeSheet> {
  late bool _task;
  String? _image;

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    _image = widget.initialImagePath;
  }

  @override
  void dispose() {
    widget.titleCtrl.dispose();
    widget.noteCtrl.dispose();
    widget.tagsCtrl.dispose();
    super.dispose();
  }

  /// 选图（走共享通路；取消/失败＝原态不动，不报错打断编辑）。
  Future<void> _pickImage() async {
    final cs = Theme.of(context).colorScheme;
    final path = await pickAndStoreImage(context,
        bg: cs.surface, fg: cs.onSurface);
    if (path == null || !mounted) return;
    setState(() => _image = path);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context;
    final cs = Theme.of(bc).colorScheme;
    return StatefulBuilder(
      builder: (bc, setS) {
        final ok = widget.titleCtrl.text.trim().isNotEmpty;
        return SingleChildScrollView(
          child: Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(bc).bottom),
            child: SafeArea(
              child: Padding(
                key: const ValueKey('mm-node-sheet'),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.headline,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('mm-node-title'),
                      controller: widget.titleCtrl,
                      autofocus: widget.titleCtrl.text.isEmpty,
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
                      controller: widget.noteCtrl,
                      maxLines: 4,
                      minLines: 2,
                      decoration: const InputDecoration(
                        hintText: '备注（画布不显示，编辑时可读回）',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Label(
                      text: '标签（逗号分隔）',
                      child: TextField(
                        key: const ValueKey('mm-node-tags'),
                        controller: widget.tagsCtrl,
                        decoration: const InputDecoration(
                          hintText: '留空则无标签，如：方法论, 复盘',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Label(
                      text: '任务属性',
                      child: Row(
                        children: [
                          _Chip(
                            key: const ValueKey('mm-node-task-toggle'),
                            on: _task,
                            label: _task ? '已是任务' : '设为任务',
                            onTap: () => setState(() => _task = !_task),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _task ? '画布节点左侧出勾选框' : '勾选完成会通知待办统计',
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Label(
                      text: '节点图片',
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            key: const ValueKey('mm-node-image-pick'),
                            onPressed: _pickImage,
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: Text(_image == null ? '选择图片' : '换一张'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _imageThumb(_image),
                          ),
                          if (_image != null)
                            IconButton(
                              key: const ValueKey('mm-node-image-clear'),
                              tooltip: '移除图片',
                              onPressed: () => setState(() => _image = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                        ],
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
                              ? () => Navigator.pop(bc, MmNodeDraft(
                                    title: widget.titleCtrl.text.trim(),
                                    note: widget.noteCtrl.text.trim(),
                                    tags: mmTagsParse(widget.tagsCtrl.text),
                                    isTask: _task,
                                    imagePath: _image,
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
                            style:
                                TextStyle(fontSize: 12, color: cs.error)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 已挂图的真实缩略（**只在弹层内单张解码**，画布侧只画占位角标）。
  Widget _imageThumb(String? path) {
    final cs = Theme.of(context).colorScheme;
    if (path == null) {
      return Text('未挂图片',
          key: const ValueKey('mm-node-image-hint'),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant));
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(path),
            key: const ValueKey('mm-node-image-thumb'),
            width: 34,
            height: 34,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Icon(
                Icons.broken_image_outlined, size: 20, color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('已挂图片',
              key: const ValueKey('mm-node-image-hint'),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
      ],
    );
  }
}

/// 段标题（原型 `.field > label` 形态：小字次级色）。
class _Label extends StatelessWidget {
  const _Label({required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// 任务属性开关 chip（原型 `.chip` 形态：选中态描边＋主色）。
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.on, required this.label, required this.onTap});

  final bool on;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: on ? cs.primary.withValues(alpha: .12) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: on ? cs.primary : cs.outlineVariant, width: 1),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: on ? cs.primary : cs.onSurface,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
        ),
      ),
    );
  }
}