part of 'note_edit_page.dart';

// 治理G7d③：V1.29批B 富文本群自 _NoteEditPageState 移入同库扩展（行为零改动）。
// Quill 文档↔Delta JSON / 属性开关（标题·列表·居中·链接·待办·插图·字号弹层）/
// 标题字段·富文本编辑器·底栏图标钮与二级行。
extension _NoteRich on _NoteEditPageState {
  // ---------- V1.29批B · 富文本（原型 pwRichBar · flutter_quill WYSIWYG） ----------

  /// content → Quill 文档：优先按 Delta JSON 解析；非 JSON（旧占位/纯文本
  /// 切过来）容错包成单段纯文本。
  Document _richDocFromContent(String content) {
    if (content.trim().isNotEmpty) {
      try {
        final data = jsonDecode(content);
        if (data is List) return Document.fromJson(data);
      } catch (_) {}
    }
    return Document.fromJson([
      {'insert': content.isEmpty ? '\n' : '$content\n'}
    ]);
  }

  QuillController _newRich(String content) => QuillController(
      document: _richDocFromContent(content),
      selection: const TextSelection.collapsed(offset: 0))
    ..addListener(_onRichChanged);

  /// 换文档（载入/快照恢复/类型切入）：重建控制器并同步 _bodyCtl 单一真源。
  void _rebuildRich(String content) {
    final old = _richCtl;
    old?.removeListener(_onRichChanged);
    final c = _newRich(content);
    _lastRichJson = jsonEncode(c.document.toDelta().toJson());
    if (_bodyCtl.text != content) {
      _bodyCtl.value = TextEditingValue(
          text: content,
          selection: TextSelection.collapsed(offset: content.length));
    }
    // ignore: invalid_use_of_protected_member
    setState(() => _richCtl = c);
    if (old != null) _disposeLater([old]);
  }

  /// Quill 变更 → Delta JSON 写回 _bodyCtl 并走既有自动保存链路。
  /// 控制器选区变化也会 notify，用 JSON 比对过滤，避免空触发。
  void _onRichChanged() {
    if (!mounted) return;
    final c = _richCtl;
    if (c == null) return;
    final json = jsonEncode(c.document.toDelta().toJson());
    if (json == _lastRichJson) return;
    _lastRichJson = json;
    if (_bodyCtl.text != json) {
      _bodyCtl.value = TextEditingValue(
          text: json,
          selection: TextSelection.collapsed(offset: json.length));
    }
    _onChanged(json);
  }

  void _richToggle(Attribute<dynamic> attr) {
    final c = _richCtl;
    if (c == null) return;
    final has = c.getSelectionStyle().attributes.containsKey(attr.key);
    c.formatSelection(has ? Attribute.clone(attr, null) : attr);
  }

  /// tt 二级（原型 pwRichHead）：N 还原正文 / H1~H3 直选标题级。
  void _richSetHeader(int level) {
    final c = _richCtl;
    if (c == null) return;
    if (level == 0) {
      c.formatSelection(Attribute.clone(Attribute.h1, null));
    } else {
      c.formatSelection([Attribute.h1, Attribute.h2, Attribute.h3][level - 1]);
    }
  }

  /// lay 二级（原型 pwRich）：ol/ul/居中 在「已是该型」时还原，其余直切。
  void _richListAs(Attribute target) {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['list'];
    c.formatSelection(cur == target ? Attribute.clone(target, null) : target);
  }

  void _richCenter() {
    final c = _richCtl;
    if (c == null) return;
    const attr = Attribute.centerAlignment;
    final has = c.getSelectionStyle().attributes.containsKey(attr.key);
    c.formatSelection(has ? Attribute.clone(attr, null) : attr);
  }

  /// 🔗 链接：底部轻输入框 → LinkAttribute 作用于选区。
  Future<void> _richLink() async {
    final c = _richCtl;
    if (c == null) return;
    final urlCtl = TextEditingController();
    final url = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      builder: (bc) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(bc).viewInsets.bottom + 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('note-link-input'),
                controller: urlCtl,
                autofocus: true,
                keyboardType: TextInputType.url,
                style: TextStyle(fontSize: 13.5, color: _fg),
                decoration: InputDecoration(
                  labelText: 'https://…',
                  labelStyle: TextStyle(color: _fg.withValues(alpha: .55)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: _fg.withValues(alpha: .3))),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: _brand)),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('note-link-ok'),
              onPressed: () => Navigator.of(bc).pop(urlCtl.text.trim()),
              child: const Text('确定', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
    urlCtl.dispose();
    if (url == null || url.isEmpty || !mounted) return;
    c.formatSelection(LinkAttribute(url));
    // T13 档③ 清零：提示条不带表情符号（图标位已由 Icons.link 线性图标承担）
    AppToast.show(context, '已添加链接');
  }

  /// Aa 字号：滑杆弹层（与底栏字号滑杆同一状态源）。
  Future<void> _openFontSheet() async {
    // ignore: invalid_use_of_protected_member
    setState(() => _pwSub = '');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      builder: (bc) => SafeArea(
        child: StatefulBuilder(
          builder: (bc, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              children: [
                Text('字号',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _fg)),
                Expanded(
                  child: Slider(
                    key: const ValueKey('note-font-sheet'),
                    value: _font,
                    min: 13,
                    max: 19,
                    divisions: 6,
                    activeColor: _brand,
                    inactiveColor: _fg.withValues(alpha: .2),
                    onChanged: (v) {
                      setSheet(() {});
                      // ignore: invalid_use_of_protected_member
                      setState(() => _font = v);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ☑ 键：无列表→待办(未勾)→已勾→清；其他列表型→待办。
  void _richTask() {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['list'];
    if (cur == null) {
      c.formatSelection(Attribute.unchecked);
    } else if (cur == Attribute.unchecked) {
      c.formatSelection(Attribute.checked);
    } else if (cur == Attribute.checked) {
      c.formatSelection(Attribute.clone(Attribute.checked, null));
    } else {
      c.formatSelection(Attribute.unchecked);
    }
  }

  /// 🖼 插图共享链（M1批2a 起抽至 widgets/image_attach.dart 与日记共用）：
  /// 返回落盘路径（任一步取消/失败=null）。rich 嵌 Delta，plain 插 MD 语法。
  Future<String?> _pickImage() =>
      pickAndStoreImage(context, bg: _bg, fg: _fg);

  /// rich 插图：Delta image 嵌入当前选区处。
  /// 不引 flutter_quill_extensions（其 super_native_extensions 原生链在本机
  /// 网络受限环境构建风险大），渲染由共享 NoteImageEmbedBuilder 承担。
  Future<void> _richImage() async {
    final dest = await _pickImage();
    if (dest == null || !mounted) return;
    final c = _richCtl;
    if (c == null) return;
    final idx = c.selection.baseOffset < 0
        ? c.document.length - 1
        : c.selection.baseOffset;
    c.replaceText(idx, 0, BlockEmbed.image(dest),
        TextSelection.collapsed(offset: idx + 1));
    AppToast.show(context, '已插入图片');
  }

  /// 轮8①：纯文本「＋」附件卡 → 走同一插图链 → 当前段后插**独立图片段**
  /// （以缩略图块呈现，不露出原始 MD 语法文本）。
  Future<void> _plainAttach() async {
    final dest = await _pickImage();
    if (dest == null || !mounted) return;
    final i = _curPara.clamp(0, _paras.length - 1);
    final md = '![图片]($dest)';
    final int imgIdx;
    if (_paras[i].text.trim().isEmpty) {
      // 轮11-3：图片段是卡片不可聚焦——若它落在末尾，补一个空文本段并聚焦，
      // 否则新建笔记一打开先插图就没有写正文的位置（须删图才能写）。
      _paras[i].value = TextEditingValue(
          text: md, selection: TextSelection.collapsed(offset: md.length));
      imgIdx = i;
    } else {
      _paras.insert(i + 1, TextEditingController(text: md));
      _paraNodes.insert(i + 1, _newParaNode());
      imgIdx = i + 1;
    }
    if (imgIdx == _paras.length - 1) {
      _paras.add(TextEditingController(text: ''));
      _paraNodes.add(_newParaNode());
    }
    _curPara = imgIdx + 1;
    // ignore: invalid_use_of_protected_member
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _curPara < _paraNodes.length) {
        _paraNodes[_curPara].requestFocus();
      }
    });
    _flushParas();
    AppToast.show(context, '已插入图片');
  }

  /// 纸感样式：正文/三级标题/列表/引用/占位符随 _fg 与字号滑杆。
  DefaultStyles _richStyles() {
    const hs = HorizontalSpacing(0, 0);
    TextStyle t(double size, {Color? color, FontWeight? w, FontStyle? f}) =>
        TextStyle(
            fontSize: size,
            color: color ?? _fg,
            height: 2.0,
            letterSpacing: .3,
            fontWeight: w,
            fontStyle: f);
    return DefaultStyles(
      color: _fg,
      paragraph:
          DefaultTextBlockStyle(t(_font), hs, const VerticalSpacing(6, 0), const VerticalSpacing(0, 0), null),
      h1: DefaultTextBlockStyle(
          t(_font + 9, w: FontWeight.w900), hs, const VerticalSpacing(10, 2), const VerticalSpacing(0, 0), null),
      h2: DefaultTextBlockStyle(
          t(_font + 6, w: FontWeight.w900), hs, const VerticalSpacing(8, 2), const VerticalSpacing(0, 0), null),
      h3: DefaultTextBlockStyle(
          t(_font + 3, w: FontWeight.w800), hs, const VerticalSpacing(6, 2), const VerticalSpacing(0, 0), null),
      lists: DefaultListBlockStyle(t(_font), hs,
          const VerticalSpacing(6, 0), const VerticalSpacing(0, 0), null, null),
      quote: DefaultTextBlockStyle(
          t(_font, color: _fg.withValues(alpha: .65), f: FontStyle.italic),
          hs,
          const VerticalSpacing(6, 0),
          const VerticalSpacing(0, 0),
          null),
      placeHolder: DefaultTextBlockStyle(
          t(_font, color: _fg.withValues(alpha: .4)),
          hs,
          const VerticalSpacing(6, 0),
          const VerticalSpacing(0, 0),
          null),
    );
  }

  Widget _titleField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TextField(
        key: const ValueKey('note-title'),
        controller: _titleCtl,
        focusNode: _titleFocus,
        onChanged: _onChanged,
        style: TextStyle(
            fontSize: _font + 6,
            fontWeight: FontWeight.w900,
            color: _fg,
            height: 1.5),
        decoration: const InputDecoration(
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _richEditor() {
    return Column(
      children: [
        _titleField(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Divider(color: _fg.withValues(alpha: .1), height: 20),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: QuillEditor(
              key: const ValueKey('note-rich-editor'),
              controller: _richCtl!,
              focusNode: _richFocus,
              scrollController: _richScroll,
              config: QuillEditorConfig(
                padding: EdgeInsets.zero,
                expands: true,
                customStyles: _richStyles(),
                embedBuilders: const [NoteImageEmbedBuilder()],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 底部快捷栏通用按钮（原型 pw-tool 30×28 · 纯符号，中文只进悬停提示）。
  Widget _pwBtn(String key, String glyph, VoidCallback onTap, String tip,
      {FontWeight w = FontWeight.w800,
      FontStyle? f,
      TextDecoration? d,
      String? fontFamily}) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 28,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(glyph,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: w,
                  fontStyle: f,
                  fontFamily: fontFamily,
                  decoration: d,
                  color: _fg.withValues(alpha: .75))),
        ),
      ),
    );
  }

  /// 轮10-3b：工具条 emoji（🖼/）→ 简约线性图标（md/rich 共用·key 不变）。
  Widget _pwIconBtn(String key, IconData icon, VoidCallback onTap, String tip) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 28,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Icon(icon, size: 15, color: _fg.withValues(alpha: .75)),
        ),
      ),
    );
  }

  Widget _pwSep() => Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: _fg.withValues(alpha: .25));

  /// 轮8②⑥：主条+二级行整体贴底（拇指热区）；plain 无条（＋附件卡承担插图）。
  Widget _toolBarArea() {
    final rich = _isRich;
    // 批3③（工单 §2）：按模式收敛——富文本恒显；MD **仅源码视图**显
    //（原型 renderPwBar：`pwType==='rich' || (pwType==='md' && pwMode==='src')`）。
    // 写作/预览视图下不再挂一排点了只弹「当前为写作视图…」的僵尸键。
    final mdSrc = _kind == 'md' && _mode == NoteEditMode.src;
    if (!rich && !mdSrc) return const SizedBox.shrink();
    return Container(
      // 批3③：rich 与 md 条互切时也要播过渡（默认类型相同会被判作同件）。
      key: ValueKey(rich ? 'note-bar-rich' : 'note-bar-md'),
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _fg.withValues(alpha: .12))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pwSub.isNotEmpty) _pwSubRow(rich),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 批3②：尾条左沿与头/体统一到 20（原型 px-5）。
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Row(
              children: rich
                  ? [
                      _pwBtn('note-rich-undo', '↺', () => _richCtl?.undo(), '撤销'),
                      _pwBtn('note-rich-redo', '↻', () => _richCtl?.redo(), '重做'),
                      _pwSep(),
                      _pwBtn('note-rich-tt', 'Tt',
                          // ignore: invalid_use_of_protected_member
                          () => setState(
                              () => _pwSub = _pwSub == 'tt' ? '' : 'tt'),
                          '字号·标题（点开二级）'),
                      _pwBtn('note-rich-lay', '≡',
                          // ignore: invalid_use_of_protected_member
                          () => setState(
                              () => _pwSub = _pwSub == 'lay' ? '' : 'lay'),
                          '排版（点开二级）'),
                      _pwBtn('note-rich-bold', 'B',
                          () => _richToggle(Attribute.bold), '加粗'),
                      _pwBtn('note-rich-ital', 'I',
                          () => _richToggle(Attribute.italic), '斜体',
                          f: FontStyle.italic),
                      _pwBtn('note-rich-under', 'U',
                          () => _richToggle(Attribute.underline), '下划线',
                          d: TextDecoration.underline),
                      _pwBtn('note-rich-strike', 'S',
                          () => _richToggle(Attribute.strikeThrough), '删除线',
                          d: TextDecoration.lineThrough),
                      _pwBtn('note-rich-code', '<>',
                          () => _richToggle(Attribute.inlineCode), '行内代码',
                          fontFamily: 'monospace'),
                      _pwBtn('note-rich-quote', '❝',
                          () => _richToggle(Attribute.blockQuote), '引用'),
                      _pwBtn('note-rich-task', '☑', _richTask, '待办行'),
                      _pwBtn('note-rich-table', '▦',
                          () => AppToast.show(context, '表格 · 富文本版即将开放'),
                          '表格'),
                      _pwIconBtn('note-rich-link', Icons.link, _richLink, '链接'),
                      _pwIconBtn('note-rich-img', Icons.image_outlined,
                          _richImage, '插图'),
                    ]
                  : [
                      for (final (k, glyph, tip) in _mdTools) ...[
                        if (k == 'h') _pwSep(),
                        if (k == 'img')
                          _pwIconBtn('note-md-img', Icons.image_outlined,
                              () => _mdBarTap(k), tip)
                        else if (k == 'link')
                          _pwIconBtn('note-md-link', Icons.link,
                              () => _mdBarTap(k), tip)
                        else
                          _mdToolBtn(k, glyph, tip),
                      ],
                    ],
            ),
          ),
        ],
      ),
    );
  }

  /// 二级行（原型 pwSubRow）：纯符号 pw-tool 同款；滑到尾部自动收起。
  Widget _pwSubRow(bool rich) {
    final items = <Widget>[
      if (_pwSub == 'h' && !rich)
        for (var lv = 1; lv <= 6; lv++)
          _pwBtn('note-h-$lv', 'H$lv', () => _mdSetHeading(lv), 'H$lv'),
      if (_pwSub == 'tt' && rich) ...[
        _pwBtn('note-rich-tt-plain', 'N', () => _richSetHeader(0), '正文'),
        _pwBtn('note-rich-tt-h1', 'H1', () => _richSetHeader(1), 'H1'),
        _pwBtn('note-rich-tt-h2', 'H2', () => _richSetHeader(2), 'H2'),
        _pwBtn('note-rich-tt-h3', 'H3', () => _richSetHeader(3), 'H3'),
        _pwBtn('note-rich-tt-font', 'Aa', _openFontSheet, '字号滑杆',
            f: FontStyle.italic),
      ],
      if (_pwSub == 'lay' && rich) ...[
        _pwBtn('note-rich-lay-ol', '1.', () => _richListAs(Attribute.ol),
            '有序列表'),
        _pwBtn('note-rich-lay-ul', '•', () => _richListAs(Attribute.ul),
            '无序列表'),
        _pwBtn('note-rich-lay-task', '☑', _richTask, '任务行'),
        _pwBtn('note-rich-lay-center', '↔', _richCenter, '居中'),
        _pwBtn('note-rich-lay-indent', '⇥', () => _richCtl?.indentSelection(true),
            '缩进'),
        _pwBtn('note-rich-lay-outdent', '⇤',
            () => _richCtl?.indentSelection(false), '取消缩进'),
      ],
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.horizontal &&
            n.metrics.maxScrollExtent > 0 &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 6) {
          // ignore: invalid_use_of_protected_member
          setState(() => _pwSub = '');
          AppToast.show(context, '已收起二级栏');
        }
        return false;
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // 批3②：二级行与主条/头/体同一条左沿（原型 px-5）。
        padding: const EdgeInsets.fromLTRB(20, 3, 20, 1),
        child: Row(
          children: [
            ...items,
            // ignore: invalid_use_of_protected_member
            _pwBtn('note-sub-close', '✕', () => setState(() => _pwSub = ''),
                '收起'),
          ],
        ),
      ),
    );
  }
}
