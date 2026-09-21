import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../domain/note.dart';
import 'journal_providers.dart';

/// 笔记编辑页（原型 p-noteEdit · 纯纯写作纸感 · 批1a 基础形态）：
/// 标题+正文 · 900ms 自动保存（输入即存·状态指示）· 字数与阅读时长 ·
/// 文件夹/置顶/plain·MD；四模式与快捷栏=批1b，渲染层=批1c，快照与导出=批1d。
class NoteEditPage extends ConsumerStatefulWidget {
  const NoteEditPage({super.key, this.noteId});

  final int? noteId;

  @override
  ConsumerState<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends ConsumerState<NoteEditPage> {
  static const _paper = Color(0xFFFBF8F1);
  static const _ink = Color(0xFF403A31);

  final _titleCtl = TextEditingController();
  final _bodyCtl = TextEditingController();
  Note? _existing;
  String _folder = '';
  bool _pinned = false;
  String _kind = 'plain';
  bool _dirty = false;
  bool _saved = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.noteId == null) return;
    final n = await ref.read(noteDaoProvider).byId(widget.noteId!);
    if (n == null || !mounted) return;
    setState(() {
      _existing = n;
      _titleCtl.text = n.title;
      _bodyCtl.text = n.content;
      _folder = n.folder ?? '';
      _pinned = n.pinned;
      _kind = n.kind;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleCtl.dispose();
    _bodyCtl.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    setState(() {
      _dirty = true;
      _saved = false;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _autoSave);
  }

  Future<Note> _persist() async {
    final now = DateTime.now();
    final dao = ref.read(noteDaoProvider);
    final saved = await dao.save(_existing != null
        ? _existing!.copyWith(
            title: _titleCtl.text.trim(),
            content: _bodyCtl.text,
            kind: _kind,
            folder: _folder.isEmpty ? null : _folder,
            pinned: _pinned,
            updatedAt: now)
        : Note(
            title: _titleCtl.text.trim(),
            content: _bodyCtl.text,
            kind: _kind,
            folder: _folder.isEmpty ? null : _folder,
            pinned: _pinned,
            createdAt: now,
            updatedAt: now));
    _existing = saved;
    _dirty = false;
    ref.invalidate(notesProvider);
    ref.invalidate(noteFoldersProvider);
    return saved;
  }

  Future<void> _autoSave() async {
    if (!_dirty || !mounted) return;
    await _persist();
    if (mounted) setState(() => _saved = true);
  }

  Future<void> _saveAndExit() async {
    _debounce?.cancel();
    if (_dirty) await _persist();
    if (mounted) Navigator.of(context).pop();
  }

  int get _words {
    final t = '${_titleCtl.text}${_bodyCtl.text}'.replaceAll(RegExp(r'\s'), '');
    return t.length;
  }

  String get _countText {
    final w = _words;
    if (w == 0) return '开始写吧';
    return '$w 字 · 约 ${math.max(1, (w / 400).ceil())} 分钟';
  }

  Future<void> _pickFolder() async {
    final folders = ref.read(noteFoldersProvider).valueOrNull ?? const [];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in ['（无分类）', ...folders])
              ListTile(
                title: Text(f),
                onTap: () =>
                    Navigator.of(bc).pop(f == '（无分类）' ? '' : f),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _folder = picked;
        _dirty = true;
      });
      _autoSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: _paper,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('note-back'),
                      onPressed: _saveAndExit,
                      icon: const Icon(Icons.keyboard_arrow_left,
                          size: 26, color: _ink),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _titleCtl.text.trim().isEmpty
                                ? '未命名笔记'
                                : _titleCtl.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: _ink),
                          ),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: _saved ? 1 : .55,
                            child: Text(
                              _saved ? '自动保存 ✓ 刚刚 · 输入即存' : '编辑中…',
                              style: const TextStyle(
                                  fontSize: 10, color: _ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '版本快照',
                      onPressed: () =>
                          AppToast.show(context, '暂无快照 · 停输后自动创建（批1d）'),
                      icon: const Text('🕘', style: TextStyle(fontSize: 16)),
                    ),
                    IconButton(
                      tooltip: '导出',
                      onPressed: () => AppToast.show(
                          context, '导出 TXT / Markdown / PDF · 批1d 开放'),
                      icon: const Icon(Icons.more_horiz, color: _ink),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(26, 10, 26, 24),
                  children: [
                    TextField(
                      key: const ValueKey('note-title'),
                      controller: _titleCtl,
                      onChanged: _onChanged,
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                          height: 1.5),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '标题',
                        hintStyle: TextStyle(
                            color: _ink, fontWeight: FontWeight.w300),
                      ),
                    ),
                    const Divider(color: Color(0x1A786E5A), height: 28),
                    TextField(
                      key: const ValueKey('note-body'),
                      controller: _bodyCtl,
                      onChanged: _onChanged,
                      maxLines: null,
                      minLines: 12,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                          fontSize: 15.5,
                          color: _ink,
                          height: 2.0,
                          letterSpacing: 0.3),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '写下第一个字…（自动保存，不怕丢稿）',
                        hintStyle: TextStyle(
                            color: Color(0x66403A31), letterSpacing: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  color: _paper,
                  border: Border(
                      top: BorderSide(color: Color(0x1F786E5A))),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      key: const ValueKey('note-folder'),
                      onTap: _pickFolder,
                      child: Text('📁 ${_folder.isEmpty ? '无分类' : _folder} ▾',
                          style:
                              const TextStyle(fontSize: 11.5, color: _ink)),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      key: const ValueKey('note-pin'),
                      onTap: () {
                        setState(() {
                          _pinned = !_pinned;
                          _dirty = true;
                        });
                        _autoSave();
                      },
                      child: Text(_pinned ? '📌 已置顶' : '📌 置顶',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _pinned ? _ink : const Color(0x80403A31))),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      key: const ValueKey('note-kind'),
                      onTap: () {
                        setState(() {
                          _kind = _kind == 'plain' ? 'md' : 'plain';
                          _dirty = true;
                        });
                        _autoSave();
                      },
                      child: Text(
                          _kind == 'md' ? '⌨️ MD' : '🖊 纯文本',
                          style: const TextStyle(
                              fontSize: 11.5, color: _ink)),
                    ),
                    const Spacer(),
                    Text(_countText,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0x99403A31))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
