part of 'note_edit_page.dart';

// 治理G7d③：轮8③ 左右滑动/←→ 切笔记群自 _NoteEditPageState 移入同库扩展（行为零改动）。
// Listener 旁路追踪 + 按当前排序/筛选取上下一篇 + 换笔记载入；字数与统计文案 getter 同群。
extension _NoteSwipe on _NoteEditPageState {
  // ---------- 轮8③ · 左右滑动/←→ 按当前排序+筛选切换笔记 ----------
  // 轮10-2：滑动改为可选能力（lh.note_swipe·记录管理·默认关）；←→ 键仅桌面不受限。

  /// 原型 pwSwipe：dx>70 且 |dx|>2|dy| 才认横向滑动（纵向留给滚动）。
  void _onSwipeDown(PointerDownEvent e) {
    if (!ref.read(settingsControllerProvider).noteSwipe) {
      _swDown = null;
      return;
    }
    _swDown = e.position;
    _swFired = false;
  }

  void _onSwipeMove(PointerMoveEvent e) {
    final down = _swDown;
    if (_swFired || down == null) return;
    final d = e.position - down;
    if (d.dx.abs() > 70 && d.dx.abs() > 2 * d.dy.abs()) {
      _swFired = true;
      _switchNote(d.dx < 0 ? 1 : -1);
    }
  }

  /// 切换前先把当前稿落库（输入即存不丢稿），再按列表序进邻篇。
  Future<void> _switchNote(int dir) async {
    if (_swiping) return;
    _swiping = true;
    try {
      _debounce?.cancel();
      _snapIdle?.cancel();
      if (_mode == NoteEditMode.focus) _flushParas();
      if (_dirty) await _persist();
      if (!mounted) return;
      final f = ref.read(noteFilterProvider);
      final dao = ref.read(noteDaoProvider);
      final list = f.folder == kNoteTrash
          ? await dao.trash()
          : await dao.list(
              folder: f.folder.isEmpty ? null : f.folder,
              sort: f.sort,
              asc: f.asc);
      if (!mounted) return;
      if (list.isEmpty) {
        AppToast.show(context, '当前筛选下暂无笔记');
        return;
      }
      final i = list.indexWhere((n) => n.id == _existing?.id);
      final j = i + dir;
      if (i >= 0 && j < 0) {
        AppToast.show(context, '已是第一篇');
        return;
      }
      if (j >= list.length) {
        AppToast.show(context, '已是最后一篇');
        return;
      }
      final target = list[j < 0 ? 0 : j];
      await _loadNote(target);
      if (!mounted) return;
      final title =
          target.title.trim().isEmpty ? '未命名笔记' : target.title.trim();
      AppToast.show(
          context, '⇄ 已切换 ${j + 1}/${list.length} · $title');
    } finally {
      _swiping = false;
    }
  }

  /// 就地换稿载入（不重开路由）：标题/正文/kind/文件夹/置顶全部跟随。
  Future<void> _loadNote(Note n) async {
    // ignore: invalid_use_of_protected_member
    setState(() {
      _existing = n;
      _titleCtl.text = n.title;
      _bodyCtl.text = n.content;
      _folder = n.folder ?? '';
      _pinned = n.pinned;
      _kind = n.kind;
      _paper = n.paper;
      _dirty = false;
      _saved = true;
      _pwSub = '';
      _mode = NoteEditMode.focus;
      _mdUndo.clear();
      _mdRedo.clear();
      _lastSnapText = '';
      _snapBaseWords = n.wordCount;
      _resetParas(n.content);
      _syncBodyAfterReset();
    });
    if (n.kind == 'rich') _rebuildRich(n.content);
  }

  int get _words {
    final body = _isRich
        ? Note.richToPlain(_bodyCtl.text)
        : Note.stripMdImages(_bodyCtl.text);
    final t = '${_titleCtl.text}$body'.replaceAll(RegExp(r'\s'), '');
    return t.length;
  }

  String get _countText {
    final w = _words;
    if (w == 0) return '开始写吧';
    return '$w 字 · 约 ${math.max(1, (w / 300).round())} 分钟';
  }
}
