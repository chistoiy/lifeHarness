part of 'note_edit_page.dart';

// 治理G7d③：保存群自 _NoteEditPageState 移入同库扩展（行为零改动）。
// 变更标脏 / 版本快照（停输 30s·每 +500 字）/ 落库 / 防抖自动保存 / 保存并退出。
extension _NoteSave on _NoteEditPageState {
  // ---------- 保存 ----------

  void _onChanged(String _) {
    // ignore: invalid_use_of_protected_member
    setState(() {
      _dirty = true;
      _saved = false;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _autoSave);
    _snapIdle?.cancel();
    _snapIdle = Timer(const Duration(seconds: 30), () => _maybeSnap(idle: true));
  }

  /// 停输 30s 或每 +500 字 → 自动留存快照（恢复为副本，不动当前稿）。
  Future<void> _maybeSnap({required bool idle}) async {
    final text = _bodyCtl.text;
    final words = text.replaceAll(RegExp(r'\s'), '').length;
    if (text.trim().isEmpty || text == _lastSnapText) return;
    if (!idle && words - _snapBaseWords < 500) return;
    if (_existing == null && _dirty) await _persist();
    final id = _existing?.id;
    if (id == null) return;
    await ref.read(noteDaoProvider).snapshot(id, text);
    _lastSnapText = text;
    _snapBaseWords = words;
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
            paper: _paper,
            updatedAt: now)
        : Note(
            title: _titleCtl.text.trim(),
            content: _bodyCtl.text,
            kind: _kind,
            folder: _folder.isEmpty ? null : _folder,
            pinned: _pinned,
            paper: _paper,
            createdAt: now,
            updatedAt: now));
    _existing = saved;
    _dirty = false;
    // V1.64 批1（工单 §4 拍板 G）：open_with 条目保存＝回写手机里的原始文件；
    // 原文件不在/授权失效按人话降级（改动仅存应用内），非在场来源不打扰。
    final wb = await noteWriteBackGuard(
        source: saved.source,
        originUri: saved.originUri,
        content: saved.content);
    if (wb != null && wb != 'ok' && mounted) {
      AppToast.show(context, wb == 'missing'
          ? '原文件已不在 · 改动仅存应用内'
          : '原文件授权失效 · 改动仅存应用内');
    }
    ref.invalidate(notesProvider);
    ref.invalidate(noteFoldersProvider);
    return saved;
  }

  Future<void> _autoSave() async {
    if (!_dirty || !mounted) return;
    await _persist();
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() => _saved = true);
    await _maybeSnap(idle: false); // 每 +500 字里程碑留存
  }

  Future<void> _saveAndExit() async {
    _debounce?.cancel();
    _snapIdle?.cancel();
    if (_mode == NoteEditMode.focus) _flushParas();
    if (_dirty) await _persist();
    final n = await _syncTodoLines();
    if (!mounted) return;
    if (n > 0) AppToast.show(context, '已保存 ✓ · ☑ 待办已同步（$n 条）');
    Navigator.of(context).pop();
  }
}
