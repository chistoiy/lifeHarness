part of 'note_edit_page.dart';

// 治理G7d③：专注模式段落群自 _NoteEditPageState 移入同库扩展（行为零改动·直访私有字段）。
// 段落即编辑（段击聚焦·淡出）/ 全局退格拦截并入上段 / 段落↔_bodyCtl 单一真源同步 /
// MD 图片独占段的缩略卡呈现与删除。群内含 static _splitParas 与 static _imgPara（互引不出群）。
extension _NoteFocusMode on _NoteEditPageState {
  // ---------- 专注模式：段落即编辑（原型 pwBody 段击聚焦 · pw-focus 淡出） ----------

  void _disposeLater(List<Object> disposable) {
    if (disposable.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final d in disposable) {
        if (d is TextEditingController) d.dispose();
        if (d is FocusNode) d.dispose();
        if (d is QuillController) d.dispose();
      }
    });
  }

  FocusNode _newParaNode() {
    late final FocusNode node;
    node = FocusNode()
      ..addListener(() {
        if (!node.hasFocus) return;
        final idx = _paraNodes.indexOf(node);
        // ignore: invalid_use_of_protected_member
        if (idx != -1 && idx != _curPara) setState(() => _curPara = idx);
      });
    return node;
  }

  // V1.29轮1①：专注模式段首退格=并入上一段。EditableText 内部 Shortcuts
  // 会先吞掉冒泡的退格键，故用 HardwareKeyboard 全局前置拦截。
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // 轮8③：桌面 ←/→ 切上/下一篇（有输入焦点时归光标移动，不拦截）。
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_hasTextFocus) return false;
      _switchNote(event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return true;
    }
    if (_isRich) return false; // 富文本段落结构由 Quill 自管
    if (_mode != NoteEditMode.focus || !mounted) return false;
    if (event.logicalKey != LogicalKeyboardKey.backspace) return false;
    final i = _curPara;
    if (i <= 0 || i >= _paras.length) return false;
    final ctl = _paras[i];
    final s = ctl.selection;
    if (!s.isCollapsed || s.start != 0) return false;
    if (!_paraNodes[i].hasFocus) return false;
    final prev = _paras[i - 1];
    final at = prev.text.length;
    prev.value = TextEditingValue(
        text: prev.text + ctl.text,
        selection: TextSelection.collapsed(offset: at));
    final old = <Object>[_paras[i], _paraNodes[i]];
    _paras.removeAt(i);
    _paraNodes.removeAt(i);
    _disposeLater(old);
    // ignore: invalid_use_of_protected_member
    setState(() => _curPara = i - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _paraNodes[_curPara].requestFocus();
    });
    _flushParas();
    return true;
  }

  void _resetParas(String text) {
    final stale = <Object>[..._paras, ..._paraNodes];
    final segs = _splitParas(text);
    // 轮11-3：末段是图片（卡片不可写）时补空文本段，重开纯图片笔记也能直接写正文。
    if (_imgPara.hasMatch(segs.last.trim())) segs.add('');
    _paras
      ..clear()
      ..addAll(segs.map((s) => TextEditingController(text: s)));
    _paraNodes
      ..clear()
      ..addAll(List.generate(_paras.length, (_) => _newParaNode()));
    _curPara = math.min(_curPara, _paras.length - 1);
    _disposeLater(stale);
  }

  /// 轮10-1：段内混入的图片语法行（文字+单换行+![..](..)）载入时拆回独立段，
  /// 否则整段匹配失败→重开显示原始 md 语法（图片卡只在独占段呈现）。
  static List<String> _splitParas(String text) {
    final out = <String>[];
    for (final seg in (text.isEmpty ? [''] : text.split('\n\n'))) {
      final lines = seg.split('\n');
      if (!lines.any((l) => _imgPara.hasMatch(l.trim()))) {
        out.add(seg);
        continue;
      }
      var buf = <String>[];
      for (final l in lines) {
        if (_imgPara.hasMatch(l.trim())) {
          if (buf.isNotEmpty) {
            out.add(buf.join('\n'));
            buf = [];
          }
          out.add(l.trim());
        } else {
          buf.add(l);
        }
      }
      if (buf.isNotEmpty) out.add(buf.join('\n'));
    }
    return out.isEmpty ? [''] : out;
  }

  /// 轮11-3：段落联集——尾部空段只是插图后的光标落点，不落库（防内容被
  /// `\n\n` 尾巴污染、字数统计虚增）。
  String _joinedParas() {
    final parts = _paras.map((c) => c.text).toList();
    while (parts.length > 1 && parts.last.trim().isEmpty) {
      parts.removeLast();
    }
    return parts.join('\n\n');
  }

  /// 轮10-1：载入归一（图片行拆独立段）后同步 _bodyCtl，避免其后 _flushParas
  /// 比对不等而误标脏、打开即重写 updated_at 打乱列表序（轮8③教训）。
  void _syncBodyAfterReset() {
    if (_isRich) return;
    final joined = _joinedParas();
    if (_bodyCtl.text != joined) {
      _bodyCtl.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length));
    }
  }

  /// 段落全文 → _bodyCtl（单一真源·自动保存与持久层都读它）。
  /// 文本无变化时整体跳过：避免打开即切篇等无编辑场景误标脏、
  /// 重写 updated_at 导致列表顺序被悄悄打乱（轮8③）。
  /// 轮10-3a：rich 模式 _paras 是陈旧镜像（正文真源=Quill 文档→_onRichChanged），
  /// 退出时若用其覆盖 _bodyCtl 会把刚插入的图片 embed 等编辑抹掉，直接跳过。
  void _flushParas() {
    if (_isRich) return;
    final joined = _joinedParas();
    if (_bodyCtl.text == joined) return;
    _bodyCtl.value = TextEditingValue(
        text: joined,
        selection: TextSelection.collapsed(offset: joined.length));
    _onChanged(joined);
  }

  void _paraChanged(int i, String v) {
    if (v.contains('\n\n')) {
      final segs = v.split('\n\n');
      final fresh = [
        for (final s in segs)
          (TextEditingController(text: s), _newParaNode())
      ];
      final old = <Object>[_paras[i], _paraNodes[i]];
      _paras.replaceRange(i, i + 1, fresh.map((e) => e.$1));
      _paraNodes.replaceRange(i, i + 1, fresh.map((e) => e.$2));
      _disposeLater(old);
      _curPara = i + segs.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _paraNodes[_curPara].requestFocus();
      });
    }
    _flushParas();
  }

  /// 纯文本图片段：整段=一行 MD 图片语法时以缩略图块呈现（原型 ins-img）。
  static final _imgPara = RegExp(r'^!\[[^\]]*\]\(([^)]*)\)$');

  Widget _paraField(int i, {bool lineNum = false}) {
    final img = _imgPara.firstMatch(_paras[i].text.trim());
    final body = img != null
        ? _paraImage(i, img.group(1)!)
        : _paraInput(i, dimmed: _focusOn && _curPara != i,
            highlight: _curPara == i);
    // 轮9p：行号=段左序号（仅纯文本·开关在 ⋯）。
    if (!lineNum) return body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Text('${i + 1}',
                key: ValueKey('note-ln-$i'),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: _fg.withValues(alpha: .35))),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _paraInput(int i, {required bool dimmed, required bool highlight}) {
    return TextField(
      key: ValueKey('note-para-$i'),
      controller: _paras[i],
      focusNode: _paraNodes[i],
      maxLines: null,
      minLines: 1,
      keyboardType: TextInputType.multiline,
      style: TextStyle(
          fontSize: _font,
          color: _fg.withValues(alpha: dimmed ? .22 : 1),
          height: 2.15,
          letterSpacing: .3),
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        filled: highlight,
        fillColor: _fg.withValues(alpha: .07),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      onChanged: (v) => _paraChanged(i, v),
    );
  }

  /// 图片段呈现=文末正方形缩略卡（原型轮9c 120×120 · 点图看大图 · 右上✕删；
  /// 存储仍是 ![🖼](路径) 独占一段，导出/预览兼容）。
  Widget _paraImage(int i, String path) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              key: ValueKey('note-img-view-$i'),
              onTap: () => _showImageFull(path),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(path),
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 120,
                    height: 120,
                    alignment: Alignment.center,
                    color: _fg.withValues(alpha: .08),
                    child: Text('图片已丢失',
                        style: TextStyle(
                            fontSize: 11, color: _fg.withValues(alpha: .45))),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                key: ValueKey('note-img-del-$i'),
                onTap: () => _removePara(i),
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xDC000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Text('✕',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 轮9c：点缩略图看大图（M1批2a 起走公共链 showImageLightbox）。
  void _showImageFull(String path) => showImageLightbox(context, path);

  void _removePara(int i) {
    if (i < 0 || i >= _paras.length) return;
    if (_paras.length == 1) {
      _paras[i].clear();
      _flushParas();
      return;
    }
    final old = <Object>[_paras[i], _paraNodes[i]];
    _paras.removeAt(i);
    _paraNodes.removeAt(i);
    _disposeLater(old);
    _curPara = i.clamp(0, _paras.length - 1);
    // ignore: invalid_use_of_protected_member
    setState(() {});
    _flushParas();
  }
}
