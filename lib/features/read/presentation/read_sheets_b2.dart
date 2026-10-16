part of 'read_sheets.dart';

/// 批2 弹层：书籍表单（含更多资料 · 封面上传 · 字典来源）/
/// 记进度四方式（openProgress）/ 计时明细可改（sheetSess）/
/// 目录粘贴导入（sheetTocImport）。

// ============================ 书籍表单（新增＝编辑同一张 · 原型 sheetNewBook / sheetEditBook 全量字段） ============================

Future<void> showBookFormSheet(
  BuildContext context,
  WidgetRef ref, {
  Book? editing,
  String defaultState = Book.kStateWant,
}) => _sheet<void>(
  context,
  _BookForm(editing: editing, defaultState: defaultState),
);

/// 从作者列表选择（原型 sheetAuthorPick：标题+脚注+「作者名 N 本 ＋」行）。
Future<void> _showAuthorPickSheet(
  BuildContext context,
  void Function(String name) onPick,
) => _sheet<void>(
  context,
  Consumer(
    builder: (bc, ref2, _) {
      final cs = Theme.of(bc).colorScheme;
      final authors =
          ref2.watch(dictProvider(DictEntry.kAuthor)).valueOrNull ??
          const <DictEntry>[];
      final books = ref2.watch(booksProvider).valueOrNull ?? const <Book>[];
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text(
                '从作者列表选择',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '直接输入新名字则保存时自动登记到作者管理',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final e in authors)
              GestureDetector(
                key: ValueKey('bap-${e.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(bc).pop();
                  onPick(e.name);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: .35),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        e.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${books.where((b) => !b.isDeleted && b.author == e.name).length} 本',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        BsIcons.add,
                        size: 14,
                        color: bc.tokens.accent,
                      ),
                    ],
                  ),
                ),
              ),
            if (authors.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  '还没有登记作者 · 在表单里输入名字保存后自动登记',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  ),
);

/// 未命中成因 → 表单状态文案（真机反馈③分档口径；V1.44 整页表单
/// book_form_page 与本 sheet 共用一份，原 _BookForm 内联 switch 提出，行为不变）。
String isbnMissLabel(IsbnMiss miss) => switch (miss) {
  IsbnMiss.network => '网络不通 · 留空待补',
  // V1.46：已配 Cookie 仍受限→点出「登录态可能失效」，引导去设置重登。
  IsbnMiss.blocked => DoubanCookie.value != null
      ? '豆瓣访问受限 · 稍后再试（登录态可能失效）'
      : '豆瓣访问受限 · 稍后再试',
  _ => '豆瓣未收录 · 留空待补',
};


// 治理（高保真批6b·刀1）：书籍表单小件群（_lbl/_pill/_dictChips/_miniBtn）
// 自 _BookFormState 类体落为同库扩展（G7c 族）——行为零改动、直访私有字段。
extension _BookFormBits on _BookFormState {
  Widget _lbl(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
    ),
  );

  Widget _pill(
    ColorScheme cs,
    ThemeTokens tokens,
    String t,
    bool on,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: on
          ? tokens.accent.withValues(alpha: .12)
          : cs.surfaceContainerHighest,
      border: Border.all(color: on ? tokens.accent : tokens.cardBorder),
    ),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: on ? tokens.accent : cs.onSurfaceVariant,
      ),
    ),
  );

  /// 来源/分组下拉（真机验收轮2：点选一个，末项「＋ 新增…」进对应添加页 · 原型 ebPickSel）。
  Widget _dictChips(
    String keyPrefix,
    List<DictEntry> dict,
    String current,
    ValueChanged<String> onPick,
  ) {
    final kind = keyPrefix == 'bkf-src' ? 'source' : 'group';
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: DropdownButton<String>(
        key: ValueKey('$keyPrefix-sel'),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(16),
        value: dict.any((e) => e.name == current) ? current : '',
        items: [
          for (final (label, v) in [
            (
              kind == 'source' ? '未选择来源' : '未选择分组',
              '',
            ),
            for (final e in dict) (e.name, e.name),
            (
              kind == 'source' ? '＋ 新增来源…' : '＋ 新增分组…',
              '__add__',
            ),
          ])
          DropdownMenuItem(value: v, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          if (v == '__add__') {
            GoRouter.of(context).push('/read/mgr?kind=$kind');
            return;
          }
          onPick(v ?? '');
        },
      ),
    );
  }

  Widget _miniBtn(
    BuildContext context,
    String key,
    String label,
    VoidCallback onTap,
  ) => GestureDetector(
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
}

// ============================ 记进度（openProgress 四方式） ============================

/// 记进度弹层（原型 sheetProgress 2325-2336 + bsSaveProgress 4517-4540）。
/// [timerMinutes]＝本次计时分钟数（非空即「本次计时…」上下文行；空＝手动补记）。
Future<void> showProgressSheet(
  BuildContext context,
  WidgetRef ref,
  Book b, {
  int? timerMinutes,
}) => _sheet<void>(context, _ProgressForm(b: b, timerMinutes: timerMinutes));

class _ProgressForm extends ConsumerStatefulWidget {
  const _ProgressForm({required this.b, this.timerMinutes});
  final Book b;
  final int? timerMinutes;

  @override
  ConsumerState<_ProgressForm> createState() => _ProgressFormState();
}

class _ProgressFormState extends ConsumerState<_ProgressForm> {
  late String _way = widget.b.progressWay == Book.kWayMin
      ? Book.kWayPage
      : widget.b.progressWay;
  late final TextEditingController _value = TextEditingController(
    text: _initialValue(),
  );
  late final TextEditingController _to = TextEditingController();
  String? _chapter;

  String _initialValue() {
    final b = widget.b;
    return switch (b.progressWay) {
      Book.kWayPos => b.readLoc != null ? '${b.readLoc!.round()}' : '',
      Book.kWayPct => '${b.percent}',
      _ => b.readPages > 0 ? '${b.readPages}' : '',
    };
  }

  // 方式 chips 文案＝页数/位置/百分比/章节（原型 PROG_WAYS 4056，无「按」前缀）。
  static const _labels = {
    Book.kWayPage: '页数',
    Book.kWayPos: '位置',
    Book.kWayPct: '百分比',
    Book.kWayChap: '章节',
  };

  Future<void> _save() async {
    final repo = ref.read(readRepositoryProvider);
    final b = widget.b;
    if (_way == Book.kWayChap) {
      final toc = await repo.tocOf(b.id);
      final secs = toc.where((n) => !n.isPart).toList();
      final pick =
          _chapter ??
          (b.chapter != null && secs.any((s) => s.title == b.chapter)
              ? b.chapter
              : secs.isNotEmpty
              ? secs.first.title
              : null);
      if (pick == null) {
        if (mounted) readToast(context, '还没有目录 · 请先导入');
        return;
      }
      final node = secs.firstWhere((s) => s.title == pick);
      await repo.saveProgress(
        b.id,
        _way,
        null,
        chapterTitle: pick,
        chapterStartPage: node.startPage,
      );
    } else {
      final v1 = double.tryParse(_value.text.trim());
      final v2 = _to.text.trim().isEmpty
          ? null
          : double.tryParse(_to.text.trim());
      // 原型 bsSaveProgress 4519：从/到都空 → 先填进度
      if (v1 == null && v2 == null) {
        if (mounted) readToast(context, '请先填写进度');
        return;
      }
      // 「到」抬高总页数/总位置（原型 v2 → max(pg/tot)），再落「从」。
      if (v2 != null) {
        if (_way == Book.kWayPage && v2.round() > b.pages) {
          await repo.updateBook(b.copyWith(pages: v2.round()));
        } else if (_way == Book.kWayPos && v2 > (b.totalLoc ?? 0)) {
          await repo.updateBook(b.copyWith(totalLoc: v2));
        }
      }
      await repo.saveProgress(b.id, _way, v1 ?? v2);
    }
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    // pop 前取回最新书行并组富文案（pop 动画后 State 销毁，toast 走根 messenger）
    final nb = await repo.bookById(widget.b.id);
    String toastMsg = '';
    if (nb != null) {
      // 原型 bsSaveProgress 4538 条件省略：均速段＝ mins>0 且有 startedAt 可折算；
      // 预计剩段＝ p<100 且非弃读且均速可得；p≥100 → 恭喜读完。
      final mins = widget.timerMinutes ?? 0;
      final fc = ProgressForecast.of(nb);
      final computable = nb.startedAt != null &&
          nb.state != Book.kStateDropped &&
          fc.pagesPerDay > 0;
      toastMsg =
          '已记录《${nb.title}》${nb.readPages}/${nb.pages} 页（${nb.percent}%）'
          '· 本次 $mins 分钟'
          '${mins > 0 && computable ? ' · 均速 ${fc.pagesPerDay.toStringAsFixed(1)} 页/天' : ''}'
          '${nb.percent >= 100 ? ' · 恭喜读完' : computable ? ' · 预计剩 ${fc.etaDays ?? '—'} 天' : ''}'
          ' · 已入时间账本 L4';
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (nb != null) readToast(context, toastMsg);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final b = widget.b;
    final toc = ref.watch(tocProvider(b.id)).valueOrNull ?? const <TocNode>[];
    final secs = toc.where((n) => !n.isPart).toList();
    final fc = ProgressForecast.of(b);
    final mins = widget.timerMinutes;
    final totalMin =
        ref.watch(workbenchProvider).valueOrNull?.agg[b.id]?.minutes ?? 0;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题（原型 progTitle 2328）＋上下文行（progTimerLine 4060）
          _SheetTitle('记录阅读进度'),
          Text(
            mins != null
                ? '本次计时 $mins 分钟 · 《${b.title}》'
                : '本次未计时 · 手动补记 · 《${b.title}》',
            key: const ValueKey('pgf-line'),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          _Chips(
            items: _labels.values.toList(),
            selected: {_labels[_way]!},
            keys: const ['pgw-page', 'pgw-pos', 'pgw-pct', 'pgw-chap'],
            onPick: (v) => setState(() {
              _way = _labels.entries.firstWhere((e) => e.value == v).key;
            }),
          ),
          const SizedBox(height: 12),
          if (_way == Book.kWayPage || _way == Book.kWayPos)
            // 从→到双输入（原型 progWayRender 4064/4066）
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _field(
                    _value,
                    _way == Book.kWayPos
                        ? '从位置（共 ${b.totalLoc ?? 0}）'
                        : '从页数（共 ${b.pages} 页）',
                    keyName: 'pgf-value',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 14, left: 6, right: 6),
                  child: Text('→', style: TextStyle(fontSize: 13)),
                ),
                Expanded(
                  child: _field(
                    _to,
                    _way == Book.kWayPos ? '到位置（可选）' : '到页数（可选）',
                    keyName: 'pgf-to',
                  ),
                ),
              ],
            )
          else if (_way == Book.kWayPct)
            _field(_value, '百分比（0~100）', keyName: 'pgf-value')
          else if (secs.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: Text(
                '还没有目录 · 可在书籍详情页导入',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in secs)
                      GestureDetector(
                        key: ValueKey('pgc-${s.id}'),
                        onTap: () => setState(() => _chapter = s.title),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: (_chapter ?? b.chapter) == s.title
                                ? tokens.accent.withValues(alpha: .12)
                                : cs.surfaceContainerHighest,
                          ),
                          child: Text(
                            s.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: (_chapter ?? b.chapter) == s.title
                                  ? tokens.accent
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: BkPctBar(book: b)),
              const SizedBox(width: 8),
              Text(
                '${b.percent}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '均速 ${fc.pagesPerDay <= 0 ? '—' : fc.pagesPerDay.toStringAsFixed(1)} 页/天 · '
            '剩 ${fc.remainPages} 页 · ${forecastLabel(fc)}',
            key: const ValueKey('pgf-calc'),
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          // 保存钮（原型 2333：保存记录 · 累计总耗时）
          FilledButton(
            key: const ValueKey('pgf-save'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: _save,
            child: Text('保存记录 · 累计总耗时 ${bsFmt(totalMin)}'),
          ),
          const SizedBox(height: 8),
          Text(
            '保存后：写入时间账本（L4）· 更新目标进度（L7）· 重算预计读完时间',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              height: 1.6,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// 计时明细弹层（sheetSess）已删：真机验收轮1e 改全屏阅读记录页 /read/log/:id（read_log_page.dart）。

// ============================ 目录粘贴导入（sheetTocImport） ============================

/// 目录导入弹层：粘贴文本实时解析 → 预览 → 确认替换。
/// 批4-C「AI 补全」复用本弹层：传 [aiParts] 即预填解析结果，
/// 仍走同一预览＋确认替换路径（绝不静默覆盖目录）。
Future<void> showTocImportSheet(
  BuildContext context,
  WidgetRef ref,
  String bookId, {
  String? bookTitle,
  List<ParsedTocPart>? aiParts,
}) => _sheet<void>(
  context,
  _TocImport(bookId: bookId, bookTitle: bookTitle, aiParts: aiParts),
);

class _TocImport extends ConsumerStatefulWidget {
  const _TocImport({required this.bookId, this.bookTitle, this.aiParts});
  final String bookId;
  final String? bookTitle;
  final List<ParsedTocPart>? aiParts;

  @override
  ConsumerState<_TocImport> createState() => _TocImportState();
}

class _TocImportState extends ConsumerState<_TocImport> {
  final _ctl = TextEditingController();
  List<ParsedTocPart> _parsed = const [];

  int get _secCount => _parsed.fold(0, (t, p) => t + p.sections.length);

  @override
  void initState() {
    super.initState();
    final ai = widget.aiParts;
    if (ai != null && ai.isNotEmpty) {
      // AI 结果直接进预览态：文本框回填可编辑文本，结构保持 AI 解析结果，
      // 用户编辑文本则实时改按文本重解析（既有 onChanged 路径）。
      _parsed = ai;
      _ctl.text = tocPartsToText(ai);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aiMode = widget.aiParts != null && widget.aiParts!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle(
          aiMode
              ? 'AI 目录补全${widget.bookTitle != null ? ' · 《${widget.bookTitle}》' : ''}'
              : '导入目录${widget.bookTitle != null ? ' · 《${widget.bookTitle}》' : ''}',
        ),
        TextField(
          key: const ValueKey('toe-text'),
          controller: _ctl,
          maxLines: 7,
          style: const TextStyle(fontSize: 12, height: 1.6),
          decoration: InputDecoration(
            hintText: '粘贴目录文本：第X部/篇/卷、Part、罗马数字行＝部分；其余行＝小节',
            hintStyle: const TextStyle(fontSize: 11.5),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          onChanged: (v) => setState(() => _parsed = parseTocText(v)),
        ),
        const SizedBox(height: 8),
        Text(
          _ctl.text.trim().isEmpty
              ? '等待粘贴'
              : '${_parsed.length} 个部分 · $_secCount 节',
          key: const ValueKey('toe-preview'),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: const ValueKey('toe-ok'),
          onPressed: _parsed.isEmpty
              ? null
              : () async {
                  final repo = ref.read(readRepositoryProvider);
                  await repo.replaceToc(widget.bookId, _parsed);
                  await repo.tocPrune(widget.bookId);
                  if (!mounted) return;
                  ref.read(readTickProvider.notifier).state++;
                  Navigator.of(this.context).pop();
                  readToast(
                    this.context,
                    '目录已导入 · ${_parsed.length} 部分/$_secCount 节',
                  );
                },
          child: const Text('确认替换'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 编辑目录就地改行（详情页目录卡编辑态用）。
class TocEditRow extends StatefulWidget {
  const TocEditRow({
    super.key,
    required this.node,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    this.onAddSection,
  });
  final TocNode node;
  final ValueChanged<String> onRename;
  final ValueChanged<int> onMove; // -1/+1
  final VoidCallback onDelete;
  final VoidCallback? onAddSection;

  @override
  State<TocEditRow> createState() => _TocEditRowState();
}

class _TocEditRowState extends State<TocEditRow> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.node.title,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget ic(String key, IconData i, VoidCallback? cb) => IconButton(
      key: ValueKey(key),
      visualDensity: VisualDensity.compact,
      onPressed: cb,
      icon: Icon(i, size: 15, color: cs.onSurfaceVariant),
    );
    return Padding(
      padding: EdgeInsets.only(left: widget.node.isPart ? 0 : 18, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('tce-${widget.node.id}'),
              controller: _ctl,
              style: TextStyle(
                fontSize: widget.node.isPart ? 12 : 11.5,
                fontWeight: widget.node.isPart
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) widget.onRename(v.trim());
              },
            ),
          ),
          ic(
            'tcup-${widget.node.id}',
            Icons.arrow_upward_rounded,
            () => widget.onMove(-1),
          ),
          ic(
            'tcdown-${widget.node.id}',
            Icons.arrow_downward_rounded,
            () => widget.onMove(1),
          ),
          if (widget.onAddSection != null)
            ic(
              'tcadd-${widget.node.id}',
              Icons.add_rounded,
              widget.onAddSection,
            ),
          ic(
            'tcdel-${widget.node.id}',
            Icons.remove_circle_outline_rounded,
            widget.onDelete,
          ),
        ],
      ),
    );
  }
}
