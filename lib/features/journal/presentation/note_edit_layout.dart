part of 'note_edit_page.dart';

// 治理G7d③：布局群自 _NoteEditPageState 移入同库扩展（行为零改动）。
// MD 工具钮 / 源码编辑器 / 预览 / 待办勾选与联动 / 三态主体区。build() 仍留类内。
extension _NoteLayout on _NoteEditPageState {
  // ---------- 布局 ----------

  /// 顶行模式图标钮（原型 pw-mode-btn · 轮9h/9o）：源码/预览两态·再点当前项回落写作。
  Widget _modeBtn(String keyName, IconData icon, String tip, bool on,
      VoidCallback onTap) {
    return IconButton(
      key: ValueKey(keyName),
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Icon(icon,
          size: 20,
          color: on ? _brand : _fg.withValues(alpha: .55)),
    );
  }

  Widget _mdToolBtn(String k, String glyph, String tip) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: ValueKey('note-md-$k'),
        onTap: () => _mdBarTap(k),
        child: Container(
          width: 30,
          height: 28,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(glyph,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  fontStyle: k == 'ital' || k == 'math' || k == 'mathb'
                      ? FontStyle.italic
                      : FontStyle.normal,
                  decoration: k == 'strike' ? TextDecoration.lineThrough : null,
                  color: _fg.withValues(alpha: .75),
                  fontFamily: k == 'math' || k == 'mathb' ? 'Georgia' : null)),
        ),
      ),
    );
  }

  Widget _srcEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: TextField(
        key: const ValueKey('note-body'),
        controller: _bodyCtl,
        focusNode: _bodyFocus,
        onChanged: _onChanged,
        maxLines: null,
        minLines: 14,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
            fontSize: 12.5,
            height: 1.9,
            letterSpacing: .2,
            fontFamily: 'monospace',
            color: _fg),
        decoration: const InputDecoration(
          border: InputBorder.none,
        ),
      ),
    );
  }

  /// 渲染预览（批1c · MdView：GFM + flutter_math_fork 公式；
  /// 轮9k：LaTeX 渲染由记录管理开关门控·默认关=公式按原文显示）。
  Widget _preview({double fontSize = 14}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MdView(
            key: const ValueKey('md-view'),
            source: _bodyCtl.text,
            fg: _fg,
            fontSize: fontSize,
            onToggleTask: _toggleTask,
            enableLatex: ref.watch(settingsControllerProvider).noteLatex,
          ),
        ],
      ),
    );
  }

  /// ☑ 勾选回写源码第 idx 个任务行；勾上即联动 L3 完成同名待办。
  void _toggleTask(int idx, bool check) {
    final text = _bodyCtl.text;
    var i = -1;
    final out = text.replaceAllMapped(
        RegExp(r'^(\s*[-*]\s+)\[( |x|X)\]', multiLine: true), (m) {
      i++;
      return i == idx ? '${m[1]!}[${check ? 'x' : ' '}]' : m[0]!;
    });
    if (i < idx) return;
    _bodyCtl.value = TextEditingValue(
        text: out, selection: TextSelection.collapsed(offset: out.length));
    _onChanged(out);
    if (check) {
      final title = RegExp(r'^\s*[-*]\s+\[[xX]\]\s+(.+)$', multiLine: true)
          .allMatches(out)
          .map((m) => m[1]!.trim())
          .elementAtOrNull(idx);
      _completeTodo(title);
    } else {
      AppToast.show(context, '已取消勾选 ☐');
    }
  }

  /// L3 联动：勾选的待办行 → 完成同名未完成待办（与日记 ☐ 同构）。
  Future<void> _completeTodo(String? title) async {
    if (title == null || title.isEmpty) return;
    final repo = ref.read(todoRepositoryProvider);
    final match = (await repo.list())
        .where((t) => t.title == title && !t.done)
        .firstOrNull;
    if (!mounted) return;
    if (match == null) {
      AppToast.show(context, '已勾选 ☑ · 保存后同步至待办');
      return;
    }
    await repo.toggleDone(match);
    ref.invalidate(todosProvider);
    if (mounted) {
      AppToast.show(context, '已勾选 ☑ · 待办「$title」已完成');
    }
  }

  /// L3：源码中未勾选的 - [ ] 行 → 新待办（按标题去重，默认「重要不紧急」）。
  Future<int> _syncTodoLines() async {
    final titles = RegExp(r'^\s*[-*]\s+\[ \]\s+(.+)$', multiLine: true)
        .allMatches(_bodyCtl.text)
        .map((m) => m[1]!.trim())
        .toSet();
    if (titles.isEmpty) return 0;
    final repo = ref.read(todoRepositoryProvider);
    final existing = (await repo.list()).map((t) => t.title).toSet();
    var created = 0;
    for (final t in titles) {
      if (existing.contains(t)) continue;
      await repo.add(Todo(title: t, quadrant: Quadrant.q2, tag: '笔记'));
      created++;
    }
    if (created > 0) ref.invalidate(todosProvider);
    return created;
  }

  Widget _bodyArea() {
    // 批3⑤（工单 §2）：各视图带独立 key ⇒ AnimatedSwitcher 才认作「换件」并播过渡。
    if (_isRich) {
      return KeyedSubtree(
          key: const ValueKey('body-rich'), child: _richEditor());
    }    // 模式行=MD 文档专属；纯文本恒为专注段落形态（原型 pwModes 仅 md 渲染）。
    final m = _kind == 'md' ? _mode : NoteEditMode.focus;
    // 轮9p：行号仅纯文本 + 设置位开启时呈现段左序号。
    final showLn = _kind == 'plain' &&
        ref.watch(settingsControllerProvider).notePlainLineNum;
    switch (m) {
      case NoteEditMode.focus:
        // 批1 顺滑：专注段懒构建（原 `ListView(children: [标题, 分隔, …段, 附件卡])`
        // 一次性建满 N 个输入框，长笔记进屏／切视图／切篇都整屏重建）。
        // 零视觉：padding 与各件顺序一字不改；段的 controller/focusNode 由
        // `_paras`/`_paraNodes` 持有，懒构建不丢输入态与焦点。
        {
          final attach = _kind == 'plain';
          final paraCount = _paras.length;
          return KeyedSubtree(
            key: const ValueKey('body-focus'),
            child: ListView.builder(
              key: const ValueKey('note-focus-list'),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              itemCount: 2 + paraCount + (attach ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return TextField(
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
                  );
                }
                if (i == 1) {
                  return Divider(
                      color: _fg.withValues(alpha: .1), height: 28);
                }
                if (i < 2 + paraCount) {
                  return _paraField(i - 2, lineNum: showLn);
                }
                // 轮8①（原型 pwAttach）：纯文本正文尾部「＋」附件卡 → 插独立图片段。
                return Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    key: const ValueKey('note-attach'),
                    onTap: _plainAttach,
                    child: Container(
                      width: 96,
                      height: 96,
                      margin: const EdgeInsets.only(top: 16),
                      decoration: BoxDecoration(
                        color: _fg.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text('＋',
                          style: TextStyle(
                              fontSize: 26,
                              color: _fg.withValues(alpha: .6))),
                    ),
                  ),
                );
              },
            ),
          );
        }
      case NoteEditMode.src:
        return KeyedSubtree(
            key: const ValueKey('body-src'),
            child: SingleChildScrollView(child: _srcEditor()));
      case NoteEditMode.view:
        return KeyedSubtree(
            key: const ValueKey('body-view'),
            child: _preview(fontSize: _font));
    }
  }
}
