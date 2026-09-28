part of 'note_edit_page.dart';

// 治理G7d③：模式/快捷栏/纸感群自 _NoteEditPageState 移入同库扩展（行为零改动）。
// 三态切换 / MD 工具条与撤销重做栈 / 标题级与列表级快捷 / 聚焦开关 / 类型切换 / 小工具抽屉。
extension _NoteModeKit on _NoteEditPageState {
  // ---------- 模式 / 快捷栏 / 纸感 ----------

  void _setMode(NoteEditMode m) {
    if (m == _mode) return;
    if (_mode == NoteEditMode.focus) _flushParas();
    // ignore: invalid_use_of_protected_member
    setState(() {
      _mode = m;
      if (m == NoteEditMode.focus) _resetParas(_bodyCtl.text);
    });
    if (m != NoteEditMode.focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mode != NoteEditMode.focus) _bodyFocus.requestFocus();
      });
    }
  }

  void _tool(String k) {
    if (_mode == NoteEditMode.focus) {
      AppToast.show(context, '当前为写作视图 · 切源码后可用 MD 快捷栏');
      return;
    }
    _mdPushUndo();
    final sel = _bodyCtl.selection;
    final r = applyMdShortcut(
        k, _bodyCtl.text, sel.isValid ? sel.start : _bodyCtl.text.length,
        sel.isValid ? sel.end : _bodyCtl.text.length);
    _bodyCtl.value = TextEditingValue(
        text: r.text, selection: TextSelection.collapsed(offset: r.caret));
    _onChanged(r.text);
    _bodyFocus.requestFocus();
    AppToast.show(context, r.label);
  }

  /// 底部 MD 主条路由：h 开二级行，↺↻ 走工具级撤销栈，其余即插语法。
  void _mdBarTap(String k) {
    if (k == 'h') {
      // ignore: invalid_use_of_protected_member
      setState(() => _pwSub = _pwSub == 'h' ? '' : 'h');
      return;
    }
    if (k == 'undo') return _mdUndoStep();
    if (k == 'redo') return _mdRedoStep();
    _tool(k);
  }

  void _mdPushUndo() {
    final s = _bodyCtl.selection;
    _mdUndo.add((
      text: _bodyCtl.text,
      caret: s.isValid ? s.start : _bodyCtl.text.length
    ));
    if (_mdUndo.length > 60) _mdUndo.removeAt(0);
    _mdRedo.clear();
  }

  void _mdApply(({String text, int caret}) r) {
    _bodyCtl.value = TextEditingValue(
        text: r.text, selection: TextSelection.collapsed(offset: r.caret));
    _onChanged(r.text);
    _bodyFocus.requestFocus();
  }

  void _mdUndoStep() {
    if (_mode == NoteEditMode.focus) {
      AppToast.show(context, '当前为写作视图 · 切源码后可用 MD 快捷栏');
      return;
    }
    if (_mdUndo.isEmpty) {
      AppToast.show(context, '已无更早的快捷操作');
      return;
    }
    final s = _bodyCtl.selection;
    _mdRedo.add((
      text: _bodyCtl.text,
      caret: s.isValid ? s.start : _bodyCtl.text.length
    ));
    _mdApply(_mdUndo.removeLast());
  }

  void _mdRedoStep() {
    if (_mode == NoteEditMode.focus) {
      AppToast.show(context, '当前为写作视图 · 切源码后可用 MD 快捷栏');
      return;
    }
    if (_mdRedo.isEmpty) {
      AppToast.show(context, '已无更晚的快捷操作');
      return;
    }
    final s = _bodyCtl.selection;
    _mdUndo.add((
      text: _bodyCtl.text,
      caret: s.isValid ? s.start : _bodyCtl.text.length
    ));
    _mdApply(_mdRedo.removeLast());
  }

  /// 二级行 H1~H6 直选（原型 pwMdHead）：光标行行首 # 数置为 lv。
  void _mdSetHeading(int lv) {
    if (_mode == NoteEditMode.focus) {
      AppToast.show(context, '当前为写作视图 · 切源码后可用 MD 快捷栏');
      return;
    }
    _mdPushUndo();
    final text = _bodyCtl.text;
    final sel = _bodyCtl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final ls = text.lastIndexOf('\n', start - 1) + 1;
    var ne = text.indexOf('\n', ls);
    if (ne == -1) ne = text.length;
    final rest = text.substring(ls, ne).replaceFirst(RegExp(r'^#{1,6}\s?'), '');
    final nl = '${'#' * lv} $rest';
    _mdApply((text: text.substring(0, ls) + nl + text.substring(ne), caret: ls + nl.length));
    AppToast.show(context, '标题级别：h$lv');
  }

  /// 🕘 快照弹层（经 ⋯ 菜单进入）：恢复=按记录管理设置替换正文或新增副本。
  void _openSnap() => showSnapshotSheet(context, ref, _existing, _bg, _fg,
      currentBody: _bodyCtl.text,
      onReplace: (content) {
        if (_isRich) {
          _rebuildRich(content);
          _onChanged(content);
          return;
        }
        // ignore: invalid_use_of_protected_member
        setState(() {
          _resetParas(content);
        });
        _flushParas();
      });

  /// 轮9j补正2：聚焦开关（⋯ 内）·纸面默认开·纯文本/MD/富文本通用不再限模式。
  void _toggleFocus() {
    // ignore: invalid_use_of_protected_member
    setState(() => _focusOn = !_focusOn);
    AppToast.show(context,
        _focusOn ? '聚焦开：当前段高亮，其余淡出' : '聚焦关：全部段落正常显示');
  }

  /// 轮9j：类型经 ⋯ 三 chip 直选（原型 pwSetType·替代旧三态循环钮）。
  void _setKind(String next) {
    if (next == _kind) return;
    final old = _kind;
    var text = _bodyCtl.text;
    if (old == 'rich') {
      text = Note.richToPlain(text);
    }
    // ignore: invalid_use_of_protected_member
    setState(() {
      _kind = next;
      _dirty = true;
      _pwSub = '';
      // 模式行=MD 专属：切离 MD 回专注段落形态。
      if (next != 'md') _mode = NoteEditMode.focus;
    });
    if (next == 'rich') {
      _rebuildRich(text);
    } else {
      if (_bodyCtl.text != text) {
        _bodyCtl.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length));
      }
      _resetParas(text);
      _flushParas();
    }
    _autoSave();
  }

  /// ⋯ 笔记选项弹层（原型 sheetNoteKit · 轮9 汇总：字号/纸色/聚焦/行号/
  /// 文件夹/快照/类型全部收进这里，底部状态条移除）。
  void _openKit() {
    showNoteKitSheet(
      context,
      ref,
      kind: _kind,
      font: _font,
      paper: _paper,
      focusOn: _focusOn,
      folder: _folder,
      countText: _countText,
      onKind: _setKind,
      // ignore: invalid_use_of_protected_member
      onFont: (v) => setState(() => _font = v),
      onPaper: (v) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _paper = v;
          _dirty = true;
        });
        _autoSave();
      },
      onFocus: _toggleFocus,
      onFolder: (v) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _folder = v;
          _dirty = true;
        });
        _autoSave();
      },
      onSnap: _openSnap,
      onShare: () => showNoteShareSheet(
          context,
          _titleCtl.text.trim(),
          _isRich ? Note.richToPlain(_bodyCtl.text) : _bodyCtl.text,
          _bg,
          _fg),
    );
  }
}
