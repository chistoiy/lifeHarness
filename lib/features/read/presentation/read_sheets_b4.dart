part of 'read_sheets.dart';

/// 批4 弹层：阅读目标（原型 sheetGoal 2436-2485 全套 · 批D 重做）/
/// 书单表单（手动·年度自动 + 勾选书）/ 移入书单（书籍操作弹层入口）。

// ============================ 阅读目标（原型 sheetGoal + shGoal* 4792-4837） ============================

Future<void> showGoalSheetV2(BuildContext context, WidgetRef ref) =>
    _sheet<void>(context, const _GoalForm());

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm();

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  static const _minOpts = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

  // 五路既有 kv 不变；monthBooks/remindMin 为弹层信息位补充键（dailyQ 复用既有开关键）。
  int _books = 50;
  int _dayMin = 30;
  int _weekMin = 210;
  int _monthBooks = 4;
  int _weekDays = 5;
  int _monthQuotes = 20;
  bool _remind = true;
  int _remindMin = 21 * 60 + 30;
  bool _loaded = false;

  /// 实时预览数据源（今天/本周/本月分钟 · 读完本数）。
  int _today = 0, _week = 0, _monthMin = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = ref.read(readRepositoryProvider);
    final now = DateTime.now();
    final ylog = await repo.dayLogYear(now.year);
    final books = await repo.kvInt('read.goalBooks', 50);
    final dayMin = await repo.kvInt('read.goalDayMin', 30);
    final weekMin = await repo.kvInt('read.goalWeekMin', 210);
    final weekDays = await repo.kvInt('read.goalWeekDays', 5);
    final monthQuotes = await repo.kvInt('read.goalMonthQuotes', 20);
    final monthBooks = await repo.kvInt('read.goalMonthBooks', 4);
    final dailyQ = await repo.kv('read.dailyQ');
    final remindMin = await repo.kvInt('read.goalRemindMin', 21 * 60 + 30);
    final today = await repo.minutesOnDay(now);
    final week = await repo.minutesThisWeek();
    if (!mounted) return;
    setState(() {
      _books = books;
      _dayMin = dayMin;
      _weekMin = weekMin;
      _weekDays = weekDays;
      _monthQuotes = monthQuotes;
      _monthBooks = monthBooks;
      _remind = (dailyQ ?? 'true') == 'true';
      _remindMin = remindMin;
      _today = today;
      _week = week;
      final m0 = DateTime(now.year, now.month).millisecondsSinceEpoch;
      final m1 = DateTime(now.year, now.month + 1).millisecondsSinceEpoch;
      _monthMin = ylog
          .where((d) =>
              d.day.millisecondsSinceEpoch >= m0 &&
              d.day.millisecondsSinceEpoch < m1)
          .fold<int>(0, (t, d) => t + d.minutes);
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final repo = ref.read(readRepositoryProvider);
    await Future.wait([
      repo.setKv('read.goalBooks', '$_books'),
      repo.setKv('read.goalDayMin', '$_dayMin'),
      repo.setKv('read.goalWeekMin', '$_weekMin'),
      repo.setKv('read.goalWeekDays', '$_weekDays'),
      repo.setKv('read.goalMonthQuotes', '$_monthQuotes'),
      repo.setKv('read.goalMonthBooks', '$_monthBooks'),
      repo.setKv('read.goalRemindMin', '$_remindMin'),
      repo.setKv('read.dailyQ', _remind ? 'true' : 'false'),
    ]);
    ref.read(readTickProvider.notifier).state++;
    if (!mounted) return;
    Navigator.of(context).pop();
    readToast(
      context,
      '目标已保存 · 每日 $_dayMin 分钟 · 每周 ${(_weekMin / 60).round()} 小时 · '
      '全年 $_books 本',
    );
  }

  Widget _wheelCard({
    required String label,
    required String caption,
    required List<Widget> wheels,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: wheels,
            ),
          ),
          Text(
            caption,
            style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _line(String nm, double cur, double tgt, String unit) {
    final cs = Theme.of(context).colorScheme;
    final hit = cur >= tgt && tgt > 0;
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            nm,
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: tgt == 0 ? 0 : min(1, cur / tgt),
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ),
        SizedBox(
          width: 92,
          child: Text(
            '${cur % 1 == 0 ? cur.toInt() : cur.toStringAsFixed(1)}$unit / '
            '${tgt % 1 == 0 ? tgt.toInt() : tgt.toStringAsFixed(1)}$unit '
            '${tgt == 0 ? 0 : (cur / tgt * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: hit ? FontWeight.w800 : FontWeight.w500,
              color: hit ? const Color(0xFF0D9488) : cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 200);
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final year = now.year;
    final books =
        (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
            .where((b) => !b.isDeleted)
            .toList();
    double h(int m) => (m / 60 * 10).round() / 10;
    final done = books
        .where(
          (b) =>
              b.state == Book.kStateDone &&
              b.endedAt != null &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == year,
        )
        .length;
    final mbDone = books
        .where(
          (b) =>
              b.state == Book.kStateDone &&
              b.endedAt != null &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == year &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).month ==
                  now.month,
        )
        .length;
    final w = ref.watch(workbenchProvider).valueOrNull;
    final daysRead = w?.weekDays ?? 0;
    // 原型 4819-4833（DAYS＝今年已过天数 · 真实现场计算）。
    final days = max(1, now.difference(DateTime(year)).inDays);
    final left = max(1, 365 - days);
    final need = _books - done;
    final rate = done / days * 365;
    final rateTxt = rate.toStringAsFixed(1);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行（原型 2439）。
          Row(
            children: [
              Expanded(
                child: Text(
                  '阅读目标 · $year',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '联动 L7 目标 / L4 时间账本',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 年度读完本数：滑杆 6~120（step2）+ 快捷 chips（原型 2441-2445）。
          Row(
            children: [
              Expanded(
                child: Text(
                  '年度读完本数',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '$_books 本',
                key: const ValueKey('goal-val'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Slider(
            key: const ValueKey('goal-slider'),
            value: _books.toDouble().clamp(6, 120),
            min: 6,
            max: 120,
            divisions: 57,
            label: '$_books 本',
            onChanged: (v) => setState(() => _books = v.round()),
          ),
          _Chips(
            items: const ['20 本', '30 本', '50 本', '80 本', '120 本'],
            selected: {
              for (final v in const [20, 30, 50, 80, 120])
                if (_books == v) '$v 本',
            },
            keys: const [
              'goal-q-20',
              'goal-q-30',
              'goal-q-50',
              'goal-q-80',
              'goal-q-120',
            ],
            onPick: (t) =>
                setState(() => _books = int.parse(t.split(' ').first)),
          ),
          const SizedBox(height: 14),
          // 时·分双滚轮 ×2 ＋ 每月读完 ＋ 每周读几天（原型 2447-2468 · 就地滚轮）。
          SizedBox(
            height: 148,
            child: Row(
              children: [
                Expanded(
                  child: _wheelCard(
                    label: '每日时长',
                    caption: '时 · 分',
                    wheels: [
                      SizedBox(
                        width: 56,
                        child: _ColWheel(
                          keyName: 'goal-dh',
                          items: const ['0时', '1时', '2时', '3时', '4时'],
                          initialIndex: (_dayMin ~/ 60).clamp(0, 4),
                          onChanged: (i) => setState(
                            () => _dayMin = i * 60 + _dayMin % 60,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 56,
                        child: _ColWheel(
                          keyName: 'goal-dm',
                          items: const [
                            '0分', '5分', '10分', '15分', '20分', '25分',
                            '30分', '35分', '40分', '45分', '50分', '55分',
                          ],
                          initialIndex: (_dayMin % 60 ~/ 5).clamp(0, 11),
                          onChanged: (i) => setState(
                            () => _dayMin = _dayMin ~/ 60 * 60 + _minOpts[i],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _wheelCard(
                    label: '每周时长',
                    caption: '时 · 分',
                    wheels: [
                      SizedBox(
                        width: 56,
                        child: _ColWheel(
                          keyName: 'goal-wh',
                          items: [for (var i = 0; i <= 24; i++) '$i时'],
                          initialIndex: (_weekMin ~/ 60).clamp(0, 24),
                          onChanged: (i) => setState(
                            () => _weekMin = i * 60 + _weekMin % 60,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 56,
                        child: _ColWheel(
                          keyName: 'goal-wm',
                          items: const [
                            '0分', '5分', '10分', '15分', '20分', '25分',
                            '30分', '35分', '40分', '45分', '50分', '55分',
                          ],
                          initialIndex: (_weekMin % 60 ~/ 5).clamp(0, 11),
                          onChanged: (i) => setState(
                            () => _weekMin = _weekMin ~/ 60 * 60 + _minOpts[i],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 148,
            child: Row(
              children: [
                Expanded(
                  child: _wheelCard(
                    label: '每月读完',
                    caption: '本',
                    wheels: [
                      SizedBox(
                        width: 56,
                        child: _ColWheel(
                          keyName: 'goal-mb',
                          items: [for (var i = 0; i <= 12; i++) '$i本'],
                          initialIndex: _monthBooks.clamp(0, 12),
                          onChanged: (i) => setState(() => _monthBooks = i),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _wheelCard(
                    label: '每周读几天',
                    caption: '天',
                    wheels: [
                      SizedBox(
                        width: 56,
                        child: _ColWheel(
                          keyName: 'goal-wd',
                          items: [for (var i = 0; i <= 7; i++) '$i天'],
                          initialIndex: _weekDays.clamp(0, 7),
                          onChanged: (i) => setState(() => _weekDays = i),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 每月新增摘录 chips（原型 4803）。
          Text(
            '每月新增摘录',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          _Chips(
            items: const ['20 条 · 轻', '40 条 · 标准', '80 条 · 勤', '0 条 · 不设'],
            selected: {
              for (final e in const {20: '轻', 40: '标准', 80: '勤', 0: '不设'}.entries)
                if (_monthQuotes == e.key) '${e.key} 条 · ${e.value}',
            },
            keys: const [
              'goal-mq-20',
              'goal-mq-40',
              'goal-mq-80',
              'goal-mq-0',
            ],
            onPick: (t) =>
                setState(() => _monthQuotes = int.parse(t.split(' ').first)),
          ),
          const SizedBox(height: 12),
          // 未读提醒开关 + 时/分滚轮（原型 2474-2480 · 通知实际走 dailyQ 21:30 链路）。
          Row(
            children: [
              Expanded(
                child: Text(
                  '未读提醒',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Switch(
                key: const ValueKey('goal-remind'),
                value: _remind,
                onChanged: (v) => setState(() => _remind = v),
              ),
            ],
          ),
          Opacity(
            opacity: _remind ? 1 : .35,
            child: IgnorePointer(
              ignoring: !_remind,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 64,
                        child: _ColWheel(
                          keyName: 'goal-rh',
                          items: [for (var i = 0; i < 24; i++) '$i时'],
                          initialIndex: (_remindMin ~/ 60).clamp(0, 23),
                          onChanged: (i) => setState(
                            () => _remindMin =
                                i * 60 + _minOpts[_remindMin % 60 ~/ 5],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 64,
                        child: _ColWheel(
                          keyName: 'goal-rm',
                          items: [for (final m in _minOpts) '$m分'],
                          initialIndex: _remindMin % 60 ~/ 5,
                          onChanged: (i) => setState(
                            () =>
                                _remindMin = _remindMin ~/ 60 * 60 + _minOpts[i],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '当天未达每日目标时提醒 · 走系统通知（免打扰时段除外）',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 实时预览卡（原型 shGoalPreview 4815-4834 逐字）。
          Container(
            key: const ValueKey('goal-prev'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _line('今天', _today.toDouble(), _dayMin.toDouble(), '′'),
                _line('本周', h(_week), h(_weekMin), 'h'),
                _line('本月', h(_monthMin), h(_dayMin * 30), 'h'),
                _line('本月读完', mbDone.toDouble(), _monthBooks.toDouble(), '本'),
                _line('每周读书', daysRead.toDouble(), _weekDays.toDouble(), '天'),
                const SizedBox(height: 10),
                Text(
                  '年度 $_books 本：已读 $done 本 · 全年折算 $rateTxt 本 → '
                  '${rate >= _books
                      ? '可达，约 ${need <= 0 ? 1 : (need / (done / days)).ceil()} 天后完成'
                      : '差 ${(_books - rate).toStringAsFixed(1)} 本，'
                            '剩余 $left 天需每周 ${(need / left * 7).toStringAsFixed(1)} 本'
                            '（当前 ${(done / days * 7).toStringAsFixed(1)}）'}',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.8,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  _remind
                      ? '每天 ${_remindMin ~/ 60}:'
                            '${(_remindMin % 60).toString().padLeft(2, '0')} '
                            '检查：当日不足 $_dayMin 分钟则提醒（免打扰时段除外）'
                      : '未达目标不提醒 · 只在周报里体现',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.8,
                    color: cs.onSurface,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '目标变更会同步：仪表盘阅读卡、时间账本「阅读」分类（L4）、'
                    '目标 OKR 进度（L7）、热力图色阶阈值。',
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.6,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('goal-save'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _save,
            child: const Text('保存目标'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
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

  /// 年度自动底稿成员（原型 bsReadInYear 5305：当年「已读」全集）。
  List<Book> _readInYear(List<Book> books) {
    final y = widget.autoYear;
    if (y == null) return const [];
    return books
        .where(
          (b) =>
              b.state == Book.kStateDone &&
              b.endedAt != null &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == y,
        )
        .toList();
  }

  Future<void> _save() async {
    final nm = _name.text.trim();
    if (nm.isEmpty) {
      readToast(context, '给书单起个名字');
      return;
    }
    final repo = ref.read(readRepositoryProvider);
    final all = (ref.read(booksProvider).valueOrNull ?? const <Book>[])
        .where((b) => !b.isDeleted)
        .toList();
    var n = _sel.length;
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
      n = _readInYear(all).length;
    } else if (widget.editing != null) {
      await repo.updateList(widget.editing!.copyWith(name: nm, note: _note.text.trim()));
      await repo.setListBooks(widget.editing!.id!, _sel);
      n = _sel.length;
    } else {
      await repo.addList(
        BookList(name: nm, note: _note.text.trim().isEmpty ? null : _note.text.trim(), createdAt: 0, updatedAt: 0),
        bookIds: _sel,
      );
    }
    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    Navigator.of(context).pop();
    // 原型 blSave 5336 逐字。
    readToast(context, '书单「$nm」已创建 · $n 本，可生成分享图');
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
    final autoDone = _readInYear(books).length;
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
          ),
          _field(_name, '书单名', keyName: 'blf-name'),
          const SizedBox(height: 10),
          _field(_note, '一句话说明（会出现在分享图与导出文本里）', keyName: 'blf-note'),
          const SizedBox(height: 10),
          Text(
            // 原型 blCreate 5325 逐字（auto 提示含当年读完 N 本）。
            auto
                ? '自动底稿：当年读完 $autoDone 本，无需勾选（勾选框已停用）'
                : widget.editing != null
                ? '勾选＝加进书单，取消＝移出'
                : '勾选要收进来的书，之后可随时增删',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 300,
            child: Column(
              children: [
                _field(_q, '搜索书名 / 作者', keyName: 'blf-kw'),
                const SizedBox(height: 6),
                Expanded(
                  child: Opacity(
                    // 原型 5328：auto 时勾选框停用但列表仍在。
                    opacity: auto ? .55 : 1,
                    child: ListView(
                      children: [
                        for (final b in shown)
                          CheckboxListTile(
                            key: ValueKey('blf-pick-${b.id}'),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            activeColor: context.tokens.accent,
                            // 真机验收轮1：选书行显示封面（原型 blRenderPick w-7 h-10）。
                            secondary: SizedBox(
                              width: 28,
                              height: 40,
                              child: BsCover(
                                book: b,
                                width: 28,
                                height: 40,
                                radius: 5,
                                showAuthor: false,
                                showBadge: false,
                              ),
                            ),
                            value: auto
                                ? _readInYear(books).any((x) => x.id == b.id)
                                : _sel.contains(b.id),
                            onChanged: auto
                                ? null
                                : (on) => setState(
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
                              '${b.author} · ${b.state}'
                              '${bsRateLabel(b.rating).isEmpty ? '' : ' · ${bsRateLabel(b.rating)}'}',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 原型 1009：底部整宽主按钮（创建书单 / 生成年度书单 / 保存选书）。
          FilledButton(
            key: const ValueKey('blf-save'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _save,
            child: Text(
              widget.editing != null
                  ? '保存选书'
                  : auto
                  ? '生成年度书单'
                  : '创建书单',
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
) async {
  // 原型 blQuickPick 5090：无手动书单＝toast 提示且不开层（不进空态弹层）。
  final pre = await ref.read(readRepositoryProvider).allLists();
  if (!context.mounted) return;
  if (pre.where((l) => !l.isAuto).isEmpty) {
    readToast(context, '还没有手动书单 · 先去书单管理创建');
    return;
  }
  return _sheet<void>(
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
                '还没有手动书单 · 先去书单管理创建',
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
}
