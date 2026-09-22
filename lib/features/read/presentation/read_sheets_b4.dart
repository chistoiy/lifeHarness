part of 'read_sheets.dart';

/// 批4 弹层：阅读目标五路（L7 · 就地滚轮）/ 书单表单（手动·年度自动 + 勾选书）/
/// 移入书单（书籍操作弹层入口）。

// ============================ 阅读目标（L7 五路 · 计划 §4 批4） ============================

Future<void> showGoalSheetV2(BuildContext context, WidgetRef ref) {
  final repo = ref.read(readRepositoryProvider);
  return _sheet<void>(
    context,
    Consumer(
      builder: (sheetCtx, ref, _) => FutureBuilder(
        key: const ValueKey('goal-form'),
        future: Future.wait([
          repo.kvInt('read.goalBooks', 50),
          repo.kvInt('read.goalDayMin', 30),
          repo.kvInt('read.goalWeekMin', 210),
          repo.kvInt('read.goalWeekDays', 5),
          repo.kvInt('read.goalMonthQuotes', 20),
        ]),
        builder: (_, snap) {
          if (!snap.hasData) return const SizedBox(height: 160);
          final v = snap.data!;
          final vals = [v[0], v[1], v[2], v[3], v[4]];
          const labels = [
            '全年读完（本）',
            '每日分钟',
            '每周分钟',
            '每周读书天数',
            '每月摘录数',
          ];
          const maxes = [200, 180, 1260, 70, 100];
          const keys = [
            'read.goalBooks',
            'read.goalDayMin',
            'read.goalWeekMin',
            'read.goalWeekDays',
            'read.goalMonthQuotes',
          ];
          final cs = Theme.of(sheetCtx).colorScheme;
          return StatefulBuilder(
            builder: (_, setSt) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetTitle(
                  '阅读目标 · 五路（L7）',
                  onSave: () async {
                    for (var i = 0; i < keys.length; i++) {
                      await repo.setKv(keys[i], '${vals[i]}');
                    }
                    ref.read(readTickProvider.notifier).state++;
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    if (context.mounted) readToast(context, '目标已更新');
                  },
                ),
                for (var i = 0; i < labels.length; i++)
                  Row(
                    children: [
                      SizedBox(
                        width: 108,
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SizedBox(
                          height: 92,
                          child: _NumWheel(
                            keyName: 'goal-w-$i',
                            value: vals[i],
                            max: maxes[i],
                            onChanged: (nv) => setSt(() => vals[i] = nv),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    ),
  );
}

// ============================ 书单表单（创建 / 选书编辑） ============================

/// [autoYear] 非空＝生成年度书单（勾选停用，成员动态）；
/// [editing] 非空＝编辑既有单（标题「编辑选书 · 名」，保存写 setListBooks）。
Future<void> showBooklistFormSheet(
  BuildContext context,
  WidgetRef ref, {
  int? autoYear,
  BookList? editing,
  List<String> initialIds = const [],
}) => _sheet<void>(
  context,
  _BooklistForm(autoYear: autoYear, editing: editing, initialIds: initialIds),
);

class _BooklistForm extends ConsumerStatefulWidget {
  const _BooklistForm({this.autoYear, this.editing, this.initialIds = const []});
  final int? autoYear;
  final BookList? editing;
  final List<String> initialIds;

  @override
  ConsumerState<_BooklistForm> createState() => _BooklistFormState();
}

class _BooklistFormState extends ConsumerState<_BooklistForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ??
        (widget.autoYear != null ? '${widget.autoYear} 年度书单' : ''),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.editing?.note ??
        (widget.autoYear != null
            ? '以 ${widget.autoYear} 年处于「已读」的书为底稿，之后新增已读会自动进来'
            : ''),
  );
  late final List<String> _sel = [...widget.initialIds];
  final _q = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nm = _name.text.trim();
    if (nm.isEmpty) {
      readToast(context, '给书单起个名字');
      return;
    }
    final repo = ref.read(readRepositoryProvider);
    if (widget.autoYear != null) {
      final exist = await repo.findAutoYear(widget.autoYear!);
      if (exist != null) {
        if (mounted) {
          Navigator.of(context).pop();
          readToast(context, '${widget.autoYear} 年度书单已存在 · 已读的书会自动进来');
        }
        return;
      }
      await repo.addList(BookList(name: nm, note: _note.text.trim().isEmpty ? null : _note.text.trim(), createdAt: 0, updatedAt: 0), autoYear: widget.autoYear);
    } else if (widget.editing != null) {
      await repo.updateList(widget.editing!.copyWith(name: nm, note: _note.text.trim()));
      await repo.setListBooks(widget.editing!.id!, _sel);
    } else {
      await repo.addList(
        BookList(name: nm, note: _note.text.trim().isEmpty ? null : _note.text.trim(), createdAt: 0, updatedAt: 0),
        bookIds: _sel,
      );
    }
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    Navigator.of(context).pop();
    readToast(context, '书单「$nm」已保存');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auto = widget.autoYear != null;
    final books =
        (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
            .where((b) => !b.isDeleted)
            .toList();
    final kw = _q.text.trim().toLowerCase();
    final shown = kw.isEmpty
        ? books
        : books
              .where(
                (b) =>
                    b.title.toLowerCase().contains(kw) ||
                    b.author.toLowerCase().contains(kw),
              )
              .toList();
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle(
            widget.editing != null
                ? '编辑选书 · ${widget.editing!.name}'
                : auto
                ? '生成年度书单'
                : '手动创建书单',
            onSave: _save,
          ),
          _field(_name, '书单名', keyName: 'blf-name'),
          const SizedBox(height: 10),
          _field(_note, '一句话说明（可选）', keyName: 'blf-note'),
          const SizedBox(height: 10),
          Text(
            auto
                ? '自动底稿：当年读完后会自动进来，无需勾选'
                : '勾选要收进来的书，之后可随时增删',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (!auto)
            SizedBox(
              height: 300,
              child: Column(
                children: [
                  _field(_q, '搜索书名 / 作者', keyName: 'blf-kw'),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final b in shown)
                          CheckboxListTile(
                            key: ValueKey('blf-pick-${b.id}'),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            activeColor: context.tokens.accent,
                            value: _sel.contains(b.id),
                            onChanged: (on) => setState(
                              () => on == true
                                  ? _sel.add(b.id)
                                  : _sel.remove(b.id),
                            ),
                            title: Text(
                              b.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${b.author} · ${b.state}',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ============================ 移入书单（书籍操作弹层入口） ============================

Future<void> showMoveToListSheet(
  BuildContext context,
  WidgetRef ref,
  Book b,
) => _sheet<void>(
  context,
  Consumer(
    builder: (sheetCtx, ref, _) {
      final cs = Theme.of(sheetCtx).colorScheme;
      final lists =
          (ref.watch(bookListsProvider).valueOrNull ?? const <BookList>[])
              .where((l) => !l.isAuto)
              .toList();
      final inList = {
        for (final l in lists)
          l.id!: ref.watch(listMembersProvider(l.id!)).valueOrNull
                    ?.any((x) => x.id == b.id) ??
                false,
      };
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle('移书单 · 《${b.title}》'),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                '还没有手动书单 · 先去书单页创建',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          for (final l in lists)
            CheckboxListTile(
              key: ValueKey('mtl-${l.id}'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: context.tokens.accent,
              value: inList[l.id] ?? false,
              onChanged: (on) async {
                final repo = ref.read(readRepositoryProvider);
                if (on == true) {
                  await repo.addBookToList(l.id!, b.id);
                } else {
                  await repo.removeBookFromList(l.id!, b.id);
                }
                ref.read(readTickProvider.notifier).state++;
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (context.mounted) {
                  readToast(context, on == true ? '已加入「${l.name}」' : '已移出「${l.name}」（书本身保留）');
                }
              },
              title: Text(
                l.name,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      );
    },
  ),
);
