part of 'book_form_page.dart';

// 治理（高保真批6b·刀2）：书籍表单 UI 积木群（_sec/_card/_row/_in/_dateTap/
// _openDateWheel/_chips/_mini/_dictDropdown/_fold/_starRow/_tagsBlock/_coverBlock）
// 与日期滚轮弹层 _DateWheelSheet 自 book_form_page 拆出——积木群落同库扩展
// （G7c 族·行为零改动·直访私有字段），弹层整组迁入（G7d5 族口径·私有类不放宽）。
// 主文件回默认 1200 面，size_budget 登记项按口径删除。

extension _BookFormForm on _BookFormPageState {
  // ---- UI 积木（行式＝左标签右输入 · 字号色值对照现有 sheet）----

  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _card(List<Widget> rows) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: .5,
                color: context.tokens.cardBorder,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _row(String label, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    ),
  );

  Widget _in(
    TextEditingController c,
    String keyName, {
    String? hint,
    TextInputType? kb,
    bool bold = false,
    ValueChanged<String>? onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      key: ValueKey(keyName),
      controller: c,
      textAlign: TextAlign.right,
      keyboardType: kb,
      style: TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w700 : null,
      ),
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        border: InputBorder.none,
      ),
    );
  }

  /// F1-3 日期行（原型 bfTap + bfDateOpen）：点击开滚轮弹层，非文本输入。
  /// [fmt]＝'ym'（出版日期 · 年-月）/ 'ymd'（购入日期 · 年-月-日）。
  /// 值实时写回 [c]（DateWheel 弹层的确定/清空回调），文案照原型 hint。
  Widget _dateTap(
    TextEditingController c,
    String keyName, {
    required String label,
    required String fmt,
  }) {
    final cs = Theme.of(context).colorScheme;
    final cur = c.text.trim();
    return GestureDetector(
      key: ValueKey(keyName),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDateWheel(c, label: label, fmt: fmt),
      child: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cur.isEmpty
                  ? (fmt == 'ym' ? '点击选择年月' : '点击选择年月日')
                  : cur,
              style: TextStyle(
                fontSize: 13,
                color: cur.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                fontWeight: cur.isEmpty ? null : FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// 打开日期滚轮弹层（原型 sheetBfDate）：年月/年月日两形态，与既有滚轮同原语。
  Future<void> _openDateWheel(
    TextEditingController c, {
    required String label,
    required String fmt,
  }) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true, // F3-10 弹层骨架
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DateWheelSheet(
        title: label,
        fmt: fmt,
        initial: c.text.trim(),
      ),
    );
    // 原型 bfDateOk/bfDateClear：确定写值、清空置空、点遮罩/返回＝不改动（null）。
    if (r == null || !mounted) return;
    // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
    setState(() => c.text = r);
    if (r.isEmpty) {
      readToast(context, '已清空$label');
    } else {
      readToast(context, '已录入$label：$r');
    }
  }

  /// 单选 chips（阅读状态/书籍类型）。[selected] 为单元素集，命中即高亮。
  Widget _chips(
    List<String> items,
    Set<String> selected,
    String keyPrefix,
    ValueChanged<String> onPick,
  ) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final v in items)
        GestureDetector(
          key: ValueKey('$keyPrefix-$v'),
          onTap: () => onPick(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected.contains(v)
                  ? context.tokens.accent.withValues(alpha: .12)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: selected.contains(v)
                    ? context.tokens.accent
                    : context.tokens.cardBorder,
              ),
            ),
            child: Text(
              v,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected.contains(v)
                    ? context.tokens.accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _mini(String key, String label, VoidCallback onTap) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
    ),
  );

  /// 来源/分组下拉（复用 sheet _dictChips 的资料库选择交互：点选一个，
  /// 末项「＋ 新增…」进对应资料管理页）。
  Widget _dictDropdown(String kind, String keyName, TextEditingController c) {
    final cs = Theme.of(context).colorScheme;
    final dict =
        ref.watch(dictProvider(kind)).valueOrNull ?? const <DictEntry>[];
    final isSrc = kind == DictEntry.kSource;
    final cur = c.text.trim();
    // 现值不在字典（如豆瓣带入的「豆瓣」）也要显示，不静默清空。
    final entries = <(String, String)>[
      (cur.isEmpty ? (isSrc ? '未选择来源' : '未选择分组') : cur, cur),
      for (final e in dict)
        if (e.name != cur) (e.name, e.name),
      (isSrc ? '＋ 新增来源…' : '＋ 新增分组…', '__add__'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      ),
      child: DropdownButton<String>(
        key: ValueKey(keyName),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(16),
        style: TextStyle(fontSize: 12.5, color: cs.onSurface),
        value: cur,
        items: [
          for (final (label, v) in entries)
            DropdownMenuItem(
              value: v,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v == '__add__') {
            final kindSeg = isSrc ? 'source' : 'group';
            final router = GoRouter.maybeOf(context);
            if (router != null) {
              router.push('/read/mgr?kind=$kindSeg');
            } else {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => BookMgrPage(kind: kindSeg)));
            }
            return;
          }
          // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
          setState(() => c.text = v ?? '');
        },
      ),
    );
  }

  /// 可折叠多行框（简介信息 · 原型 details；有内容默认展开）。
  Widget _fold({
    required String label,
    required String keyName,
    required TextEditingController c,
    required String hint,
    required bool open,
    required ValueChanged<bool> onToggle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: ValueKey('$keyName-fold'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onToggle(!open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              key: ValueKey(keyName),
              controller: c,
              maxLines: 6,
              minLines: 3,
              style: const TextStyle(fontSize: 12, height: 1.6),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: .5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _starRow() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            key: ValueKey('bf-rate-$i'),
            // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
            onTap: () => setState(() => _rate = i),
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(
                Icons.star_rounded,
                size: 18,
                color: i <= _rate
                    ? const Color(0xFFF5A623)
                    : cs.outlineVariant,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            _rate == 0 ? '未评分' : '$_rate',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  /// 标签行（V1.46⑧）：① 选项来自标签字典（多选 toggle，现状保持）；
  /// ② 行尾「＋ 添加标签」chip 就地展开输入行（禁两段式弹层），确认后
  /// dictAdd 落字典并立即选中、readTick 刷新 chips；③ 编辑态回填走 [_tags]（不变）。
  Widget _tagsBlock(List<DictEntry> tagDict) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        key: const ValueKey('bf-tags'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '标签',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in tagDict)
                GestureDetector(
                  key: ValueKey('bf-tag-${e.name}'),
                  // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
                  onTap: () => setState(
                    () => _tags.contains(e.name)
                        ? _tags.remove(e.name)
                        : _tags.add(e.name),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _tags.contains(e.name)
                          ? context.tokens.accent.withValues(alpha: .12)
                          : cs.surfaceContainerHighest,
                      border: Border.all(
                        color: _tags.contains(e.name)
                            ? context.tokens.accent
                            : context.tokens.cardBorder,
                      ),
                    ),
                    child: Text(
                      '#${e.name}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _tags.contains(e.name)
                            ? context.tokens.accent
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              // 行尾「＋ 添加标签」chip：点开就地展开输入行。
              GestureDetector(
                key: const ValueKey('bf-tag-add'),
                // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
                onTap: () => setState(() => _tagAddOpen = !_tagAddOpen),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: _tagAddOpen
                        ? context.tokens.accent.withValues(alpha: .12)
                        : cs.surfaceContainerHighest,
                    border: Border.all(
                      color: _tagAddOpen
                          ? context.tokens.accent
                          : context.tokens.cardBorder,
                    ),
                  ),
                  child: Text(
                    '＋ 添加标签',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _tagAddOpen
                          ? context.tokens.accent
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (tagDict.isEmpty)
                Text(
                  '还没有标签 · 点「＋ 添加标签」就地新建',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
            ],
          ),
          // 就地展开的输入行（同页内嵌，非弹层）。
          if (_tagAddOpen)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('bf-tag-name'),
                      controller: _newTag,
                      autofocus: true,
                      style: const TextStyle(fontSize: 12.5),
                      onSubmitted: (_) => _addTag(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '输入标签名',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(
                          alpha: .5,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _mini('bf-tag-add-ok', '确认', () => _addTag()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _coverBlock() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                key: const ValueKey('bf-cover'),
                borderRadius: BorderRadius.circular(8),
                child: _cover != null && _cover!.isNotEmpty
                    ? Image.file(File(_cover!), width: 64, height: 90, fit: BoxFit.cover)
                    : BsCover(
                        book: Book(
                          id: '',
                          title: _title.text,
                          colorIdx: _colorIdx,
                          createdAt: 0,
                          updatedAt: 0,
                        ),
                        width: 64,
                        height: 90,
                        radius: 8,
                        showAuthor: false,
                        showBadge: false,
                      ),
              ),
              if (_cover != null && _cover!.isNotEmpty)
                Positioned(
                  right: -4,
                  top: -4,
                  child: GestureDetector(
                    key: const ValueKey('bf-cov-clear'),
                    onTap: () {
                      // ignore: invalid_use_of_protected_member // 同库扩展里调 State.setState（note_edit_* 先例）
                      setState(() => _cover = null);
                      readToast(context, '已改回书脊色封面');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _mini('bf-cov-file', '上传', () => _pickCover()),
              const SizedBox(width: 6),
              _mini('bf-cov-cam', '拍照', () => _pickCover(camera: true)),
              const SizedBox(width: 6),
              _mini('bf-cov-isbn', 'ISBN 取图', _isbnCover),
            ],
          ),
          Text(
            '设置封面',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// F1-3 日期滚轮弹层（原型 sheetBfDate · bfDateOpen）：
/// 年 / 月 / 日三柱，[fmt]＝'ym' 藏日柱、'ymd' 全显；标题右侧实时回显当前值；
/// 清空/确定回写；点遮罩/返回＝pop(null) 不改动。年池 1900~2100、月 01~12、日 01~31。
class _DateWheelSheet extends StatefulWidget {
  const _DateWheelSheet({
    required this.title,
    required this.fmt,
    required this.initial,
  });

  final String title;
  final String fmt;
  final String initial;

  @override
  State<_DateWheelSheet> createState() => _DateWheelSheetState();
}

class _DateWheelSheetState extends State<_DateWheelSheet> {
  static final List<String> _years = [
    for (var y = 1900; y <= 2100; y++) '$y',
  ];
  static final List<String> _mons = [
    for (var m = 1; m <= 12; m++) m.toString().padLeft(2, '0'),
  ];
  static final List<String> _days = [
    for (var d = 1; d <= 31; d++) d.toString().padLeft(2, '0'),
  ];

  late int _yi;
  late int _mi;
  late int _di;

  @override
  void initState() {
    super.initState();
    // 解析现值（原型 bfDateOpen 正则）：YYYY-M(-D) 或 M-D。
    final s = widget.initial;
    final dm = RegExp(r'^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?').firstMatch(s);
    final md = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(s);
    final now = DateTime.now();
    var y = now.year, mo = now.month, d = now.day;
    if (dm != null) {
      y = int.parse(dm.group(1)!);
      mo = int.parse(dm.group(2)!);
      d = dm.group(3) != null ? int.parse(dm.group(3)!) : 1;
    } else if (md != null) {
      mo = int.parse(md.group(1)!);
      d = int.parse(md.group(2)!);
    }
    _yi = (_years.indexOf('$y')).clamp(0, _years.length - 1);
    _mi = (mo - 1).clamp(0, 11);
    _di = (d - 1).clamp(0, 30);
  }

  String get _value {
    if (widget.fmt == 'ym') return '${_years[_yi]}-${_mons[_mi]}';
    return '${_years[_yi]}-${_mons[_mi]}-${_days[_di]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showD = widget.fmt != 'ym';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _value,
                  key: const ValueKey('bf-date-echo'),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 72,
                  child: LHWheel(
                    keyPrefix: 'bf-date-y',
                    labels: _years,
                    initialIndex: _yi,
                    onSelect: (i) => setState(() => _yi = i),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: LHWheel(
                    keyPrefix: 'bf-date-m',
                    labels: _mons,
                    initialIndex: _mi,
                    onSelect: (i) => setState(() => _mi = i),
                  ),
                ),
                if (showD)
                  SizedBox(
                    width: 56,
                    child: LHWheel(
                      keyPrefix: 'bf-date-d',
                      labels: _days,
                      initialIndex: _di,
                      onSelect: (i) => setState(() => _di = i),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.fmt == 'ym' ? '年 · 月' : '年 · 月 · 日',
              style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('bf-date-clear'),
                    onPressed: () => Navigator.of(context).pop(''),
                    child: const Text('清空'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('bf-date-ok'),
                    onPressed: () => Navigator.of(context).pop(_value),
                    child: const Text('确定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
