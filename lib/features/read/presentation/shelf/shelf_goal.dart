part of 'shelf_page.dart';

// 治理G7d1b：目标卡群自 _ShelfPageState 移入同库扩展（行为零改动·直访私有字段）。
// 卡片装饰 / 年度完成与 ETA 计算 / 目标卡与年度迷你视图 / 年度清单弹层。
extension _ShelfGoal on _ShelfPageState {
  BoxDecoration _cardDeco(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
    );
  }

  // ---------------- 目标卡（原型 821-834 + renderYearBox 批F） ----------------

  /// 当年读完（原型 bsReadInYear：已读 + ended 当年，按 yearSort 排）。
  List<Book> _yearDone(List<Book> all) {
    final y = DateTime.now().year;
    final desc =
        (ref.watch(readKvProvider(('read.yearSort', '升序'))).valueOrNull ??
            '升序') ==
        '降序';
    final out = all
        .where(
          (b) =>
              b.state == Book.kStateDone &&
              b.endedAt != null &&
              DateTime.fromMillisecondsSinceEpoch(b.endedAt!).year == y,
        )
        .toList()
      ..sort(
        (a, b) => desc
            ? b.endedAt!.compareTo(a.endedAt!)
            : a.endedAt!.compareTo(b.endedAt!),
      );
    return out;
  }

  /// 预计达成日（原型 bsYearETA 4582 口径：剩本数 × 单本均分钟 ÷ 近 30 天日均分钟）。
  String _yearEta(WorkbenchData? w, int done, int goal) {
    final need = max(0, goal - done);
    if (need == 0) return '';
    final books = w?.books ?? const <Book>[];
    final agg = w?.agg ?? const <String, ({int minutes, int times})>{};
    final per = books
        .where(
          (b) =>
              !b.isDeleted &&
              b.state == Book.kStateDone &&
              (agg[b.id]?.minutes ?? 0) > 0,
        )
        .map((b) => (agg[b.id]?.minutes ?? 0).toDouble())
        .toList();
    final avg = per.isEmpty
        ? 300.0
        : per.reduce((a, b) => a + b) / per.length; // 原型兜底 300 分钟/本
    final recent = (ref.watch(shelfDaily30Provider).valueOrNull ?? 0);
    final daily = recent <= 0 ? 20.0 : recent; // 原型 recent||20
    final d = (need * avg / daily).ceil();
    final t = DateTime.now().add(Duration(days: d));
    return '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Widget _goalCard(WorkbenchData? w, dynamic tokens, List<Book> all) {
    final year = DateTime.now().year;
    final done = _yearDone(all).length;
    final goal = w?.goalBooks ?? 50;
    final ui = ref.watch(shelfUiProvider);
    final need = max(0, goal - done);
    final pct = goal == 0 ? 0 : (done / goal * 100).round();
    final today = DateTime.now();
    final daysLeft =
        DateTime(year, 12, 31).difference(DateTime(today.year, today.month, today.day)).inDays +
        1;
    final eta = _yearEta(w, done, goal);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: tokens.gradient as Gradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (tokens.accent as Color).withValues(alpha: .2),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: CustomPaint(
                  painter: _GoalRingPainter(
                    frac: goal == 0 ? 0 : (done / goal).clamp(0.0, 1.0),
                    color: Colors.white,
                  ),
                  child: Center(
                    child: Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$year 年度阅读目标',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      need > 0
                          ? '读完 $done / $goal 本 · 剩 $daysLeft 天 · 节奏刚好（预计 $eta 达成）'
                          : '读完 $done / $goal 本 · 剩 $daysLeft 天 · 目标已达成',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: .88),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 白色进度条（原型 830：bg-white/25 + bg-white）
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        key: const ValueKey('sh-goal-bar'),
                        value: pct / 100,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: .25),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _pillBtn('sh-goal-adjust', '调整', () => showGoalSheet(context, ref)),
            ],
          ),
          _yearMini(ui, done, goal, need),
        ],
      ),
    );
  }

  /// 「今年读完」折叠块（原型批F renderYearBox 5412-5421：编号格阵 + 年度书单 + 调整目标）。
  Widget _yearMini(ShelfUI ui, int done, int goal, int need) {
    final rd = _yearDone(
      (ref.watch(booksProvider).valueOrNull ?? const <Book>[]).where(
        (b) => !b.isDeleted,
      ).toList(),
    );
    final cells = min(goal, 40);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Text(
                '$done',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ $goal 本',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: .85),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  need > 0 ? '· 还差 $need 本' : '· 目标已达成',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: .75),
                  ),
                ),
              ),
              _pillBtn(
                'sh-yearbox-toggle',
                ui.yearBoxOpen ? '收起' : '今年读完',
                () => ref.read(shelfUiProvider.notifier).state =
                    ui.copyWith(yearBoxOpen: !ui.yearBoxOpen),
              ),
            ],
          ),
        ),
        if (ui.yearBoxOpen) ...[
          const SizedBox(height: 8),
          GridView.count(
            key: const ValueKey('sh-yeargrid'),
            crossAxisCount: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            children: [
              for (var i = 0; i < cells; i++)
                GestureDetector(
                  key: ValueKey('sh-yencell-$i'),
                  onTap: i < rd.length
                      ? () => context.push('/read/book/${rd[i].id}')
                      : null,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i < rd.length
                          ? Colors.white.withValues(alpha: .85)
                          : Colors.white.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: i < rd.length
                            ? const Color(0xFF1E293B)
                            : Colors.white.withValues(alpha: .55),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _pillBtn('sh-year-list', '年度书单', () => _openYearList()),
              const SizedBox(width: 8),
              _pillBtn(
                'sh-goal-adjust-full',
                '调整目标',
                () => showGoalSheet(context, ref),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 年度书单：无则按 autoYear 生成后进入（原型 blDetailYear 5598：blCreate(true)+blSave+blDetail）。
  Future<void> _openYearList() async {
    final repo = ref.read(readRepositoryProvider);
    final y = DateTime.now().year;
    var l = await repo.findAutoYear(y);
    if (l == null) {
      final nm = '$y 年度书单';
      l = await repo.addList(
        BookList(
          name: nm,
          note: '以 $y 年处于「已读」的书为底稿，之后新增已读会自动进来',
          createdAt: 0,
          updatedAt: 0,
        ),
        autoYear: y,
      );
      ref.read(readTickProvider.notifier).state++;
      if (mounted) readToast(context, '书单「$nm」已保存');
    }
    if (mounted) context.push('/read/list/${l.id}');
  }

  Widget _pillBtn(String key, String label, VoidCallback onTap) =>
      GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Colors.white.withValues(alpha: .2),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
}
