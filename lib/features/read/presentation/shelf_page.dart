import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/book.dart';
import '../domain/book_dict.dart';
import '../domain/book_list.dart';
import '../domain/book_quote.dart';
import '../domain/book_session.dart';
import '../domain/shelf_query.dart';
import 'read_actions.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'widgets/bs_cover.dart';

/// 书架视图循环 5 态（原型 shCycleView 4545 顺序：墙3 → 墙4 → 列表 → 书脊 → 时间线）。
const kShelfViews = ['wall', 'wall4', 'rows', 'spine', 'time'];
const kShelfViewLabels = {
  'wall': '封面墙',
  'wall4': '封面墙·4列',
  'rows': '列表',
  'spine': '书脊',
  'time': '时间线',
};

/// 排序 / 维度键（与原型 SH_SORTS / SH_DIMS 对齐）。
const kShelfSorts = [
  ('recent', '最近阅读'),
  ('prog', '按进度'),
  ('rate', '按评分'),
  ('added', '入架顺序'),
  ('name', '书名（拼音）'),
  ('pages', '总页数'),
];
const kShelfDims = [
  ('none', '默认'),
  ('st', '状态'),
  ('tag', '标签'),
  ('rate', '评分'),
  ('author', '作者'),
  ('pub', '出版社'),
  ('src', '来源'),
  ('grp', '分组'),
];

/// 维度 → 书架资料字典 kind（/read/mgr?kind= 用）。
const kShelfDimDict = {
  'tag': DictEntry.kTag,
  'src': DictEntry.kSource,
  'grp': DictEntry.kGroup,
  'author': DictEntry.kAuthor,
  'pub': DictEntry.kPublisher,
};

String kShelfDimLabel(String dim) =>
    kShelfDims.firstWhere((e) => e.$1 == dim, orElse: () => ('none', '默认')).$2;

/// 摘录命中集（原型 4549 搜索范围含该书摘录原文）。
final shelfQuoteIdsProvider = FutureProvider.family<Set<String>, String>((
  ref,
  kw,
) {
  ref.watch(readTickProvider);
  if (kw.trim().isEmpty) return const {};
  return ref.watch(readRepositoryProvider).quoteBookIdsMatching(kw);
});

/// 时间线计时事件源（原型 bsSessions 逐书取最近 6 次会话）。
final shelfSessionsProvider = FutureProvider<List<BookSession>>((ref) {
  ref.watch(readTickProvider);
  return ref.watch(readRepositoryProvider).allSessions();
});

typedef _TlEv = (DateTime, IconData, String, Book);

/// 近 30 天日均入账分钟（原型 bsYearETA 的 recent 口径：BS_LOG 近 30 天 / 30）。
final shelfDaily30Provider = FutureProvider<double>((ref) async {
  ref.watch(readTickProvider);
  final sessions = await ref.watch(readRepositoryProvider).allSessions();
  final from =
      DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
  final total = sessions
      .where((s) => s.endedAt != null && s.endedAt! >= from)
      .fold<int>(0, (t, s) => t + s.billedMinutes);
  return total / 30;
});

class ShelfUI {
  const ShelfUI({
    this.view = 'wall',
    this.st,
    this.kw = '',
    this.dim = 'none',
    this.dimVal = '',
    this.sort = 'recent',
    this.batch = false,
    this.sel = const {},
    this.yearBoxOpen = false,
  });

  final String view;
  final String? st;
  final String kw;
  final String dim;
  final String dimVal;
  final String sort;
  final bool batch;
  final Set<String> sel;
  final bool yearBoxOpen;

  ShelfUI copyWith({
    String? view,
    String? Function()? st,
    String? kw,
    String? dim,
    String? dimVal,
    String? sort,
    bool? batch,
    Set<String>? sel,
    bool? yearBoxOpen,
  }) => ShelfUI(
    view: view ?? this.view,
    st: st != null ? st() : this.st,
    kw: kw ?? this.kw,
    dim: dim ?? this.dim,
    dimVal: dimVal ?? this.dimVal,
    sort: sort ?? this.sort,
    batch: batch ?? this.batch,
    sel: sel ?? this.sel,
    yearBoxOpen: yearBoxOpen ?? this.yearBoxOpen,
  );

  /// 清空筛选（原型 shResetFilter 4547：分区 / kw / 维度 / 排序回默认）。
  ShelfUI get cleared => copyWith(
    st: () => null,
    kw: '',
    dim: 'none',
    dimVal: '',
    sort: 'recent',
  );

  ShelfQuery toQuery({Set<String> quoteIds = const {}}) => ShelfQuery(
    state: st,
    kw: kw,
    dim: dim,
    dimVal: dimVal,
    sort: sort,
    quoteIds: quoteIds,
  );
}

final shelfUiProvider = StateProvider<ShelfUI>((ref) => const ShelfUI());

/// 书架页（原型 p-bookshelf · §3.1 信息架构：目标卡→搜索行→分区chips→封面墙）。
class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key});

  @override
  ConsumerState<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends ConsumerState<ShelfPage> {
  final _kwCtl = TextEditingController();
  bool _tabBooted = false;

  @override
  void dispose() {
    _kwCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(shelfUiProvider);
    // read.openTab（§6 外观与启动）：进书架默认落到的分区；原型 BS_SET 默认「在读」，未设过同样生效。
    if (!_tabBooted) {
      _tabBooted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final t = await ref.read(readRepositoryProvider).kv('read.openTab') ??
            '在读';
        if (mounted &&
            ref.read(shelfUiProvider).st == null &&
            Book.states.contains(t)) {
          ref.read(shelfUiProvider.notifier).state =
              ref.read(shelfUiProvider).copyWith(st: () => t);
        }
      });
    }
    final tokens = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final all = (ref.watch(booksProvider).valueOrNull ?? const <Book>[])
        .where((b) => !b.isDeleted)
        .toList();
    final w = ref.watch(workbenchProvider).valueOrNull;
    final running = ref.watch(runningSessionProvider).valueOrNull;
    final quoteIds = ui.kw.trim().isEmpty
        ? const <String>{}
        : (ref.watch(shelfQuoteIdsProvider(ui.kw)).valueOrNull ??
              const <String>{});
    final list = ui.toQuery(quoteIds: quoteIds).apply(all);
    final dimVals = ui.dim == 'none'
        ? const <String>[]
        : ShelfQuery.dimValues(ui.dim, all);
    final dimCounts = ui.dim == 'none'
        ? const <String, int>{}
        : ShelfQuery.dimValueCounts(ui.dim, all);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('书架')),
      floatingActionButton: ui.batch
          ? null
          : GradShelfFab(onTap: () => showAddBookSheet(context, ref)),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
            children: [
              _goalCard(w, tokens, all),
              const SizedBox(height: 10),
              // 搜索行：输入 + 视图循环 + ⇅ 面板 + 管理（原型 836-841）
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        key: const ValueKey('sh-kw'),
                        controller: _kwCtl,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: '搜索书名 / 作者 / 标签 / 摘录',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                          prefixIcon: const Icon(BsIcons.search, size: 17),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: cs.surfaceContainerHigh,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) =>
                            ref.read(shelfUiProvider.notifier).state = ref
                                .read(shelfUiProvider)
                                .copyWith(kw: v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _roundBtn(
                    'sh-view',
                    BsIcons.view,
                    kShelfViewLabels[ui.view]!,
                    () {
                      final next =
                          kShelfViews[(kShelfViews.indexOf(ui.view) + 1) %
                              kShelfViews.length];
                      ref.read(shelfUiProvider.notifier).state = ref
                          .read(shelfUiProvider)
                          .copyWith(view: next);
                      readToast(context, '书架视图：${kShelfViewLabels[next]}');
                    },
                  ),
                  const SizedBox(width: 8),
                  _roundBtn(
                    'sh-panel',
                    BsIcons.swap,
                    '排序与分组',
                    () => _openPanel(context, ui),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    key: const ValueKey('sh-manage'),
                    onTap: () =>
                        ref.read(shelfUiProvider.notifier).state = ui.copyWith(
                          batch: !ui.batch,
                          sel: const {},
                        ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: ui.batch ? tokens.gradient : null,
                        color: ui.batch ? null : cs.surfaceContainerHigh,
                      ),
                      child: Text(
                        ui.batch ? '完成' : '管理',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: ui.batch
                              ? Colors.white
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 分区 chips（原型 bsChipRow 无计数·常驻一行）
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in ['全部', ...Book.states])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          key: ValueKey('sh-chip-$s'),
                          onTap: () =>
                              ref.read(shelfUiProvider.notifier).state = ref
                                  .read(shelfUiProvider)
                                  .copyWith(st: () => s == '全部' ? null : s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color:
                                  (s == '全部' && ui.st == null) || ui.st == s
                                  ? tokens.accent.withValues(alpha: .12)
                                  : cs.surfaceContainerHigh,
                              border: Border.all(
                                color:
                                    (s == '全部' && ui.st == null) || ui.st == s
                                    ? tokens.accent
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              s,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color:
                                    (s == '全部' && ui.st == null) || ui.st == s
                                    ? tokens.accent
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 维度值行（原型 bsBindBtns 5389-5396：值 chips 带「N 本」+ 管理入口）
              if (ui.dim != 'none') ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final v in dimVals)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            key: ValueKey('sh-dim-$v'),
                            onTap: () =>
                                ref.read(shelfUiProvider.notifier).state = ref
                                    .read(shelfUiProvider)
                                    .copyWith(dimVal: ui.dimVal == v ? '' : v),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: ui.dimVal == v
                                    ? tokens.gradient
                                    : null,
                                color: ui.dimVal == v
                                    ? null
                                    : cs.surfaceContainerHigh,
                              ),
                              child: Text(
                                '$v ${dimCounts[v] ?? 0} 本',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: ui.dimVal == v
                                      ? Colors.white
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // 管理标签 / 来源 / 分组 / 作者 / 出版社 → 书架资料页
                      if (kShelfDimDict.containsKey(ui.dim))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            key: ValueKey('sh-dim-mgr-${ui.dim}'),
                            onTap: () => context.push(
                              '/read/mgr?kind=${kShelfDimDict[ui.dim]}',
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: tokens.accent.withValues(alpha: .5),
                                ),
                              ),
                              child: Text(
                                '管理${kShelfDimLabel(ui.dim)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: tokens.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (list.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  decoration: _cardDeco(context),
                  child: Center(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                        children: [
                          const TextSpan(text: '没有符合条件的书 · '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              key: const ValueKey('sh-reset'),
                              onTap: () {
                                _kwCtl.clear();
                                ref.read(shelfUiProvider.notifier).state = ref
                                    .read(shelfUiProvider)
                                    .copyWith(
                                      st: () => null,
                                      kw: '',
                                      dim: 'none',
                                      dimVal: '',
                                      sort: 'recent',
                                    );
                              },
                              child: Text(
                                '清空筛选',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: tokens.accent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (ui.dim != 'none' && ui.dimVal.isEmpty)
                ..._dimGroups(ui, list, running, cs, tokens)
              else
                _body(ui, list, running, cs, tokens),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  // 原型 4595：N 本 · 分区 · #标签 · 维度：值
                  '${list.length} 本 · ${ui.st ?? '全部'}'
                  '${ui.dimVal.isEmpty ? '' : ui.dim == 'tag' ? ' · #${ui.dimVal}' : ' · ${kShelfDimLabel(ui.dim)}：${ui.dimVal}'}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          // 批量管理浮动条（原型 shSelBar 849-855：已选 N 本 + 四钮）
          if (ui.batch && ui.sel.isNotEmpty) _batchBar(ui, cs, tokens),
        ],
      ),
    );
  }

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

  // ---------------- 排序与筛选面板 ----------------

  void _openPanel(BuildContext context, ShelfUI ui) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // ConstrainedBox 包 builder 会破坏 sheet 布局（按钮 hit-test 被 barrier 吸收）；限高走 constraints。
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            24,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // 轮3：键盘弹出时面板上移且限高，「清空筛选/完成」双钮不再被输入法遮挡。
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
        child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: Consumer(
                    builder: (_, ref2, _) {
                      // watch 当前 UI 态：面板内即时刷新选中态（不重开也对）
                      final ui = ref2.watch(shelfUiProvider);
                      void setUi(ShelfUI Function(ShelfUI) f) =>
                          ref2.read(shelfUiProvider.notifier).state = f(
                            ref2.read(shelfUiProvider),
                          );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '书架排序与筛选',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(sheetCtx).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 原型 2341：排序＝6 行竖排全宽按钮，选中显 ✓
                    for (final (k, t) in kShelfSorts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GestureDetector(
                          key: ValueKey('panel-sort-$k'),
                          onTap: () {
                            setUi((u) => u.copyWith(sort: k));
                            Navigator.of(sheetCtx).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: ui.sort == k
                                  ? context.tokens.accent.withValues(
                                      alpha: .12,
                                    )
                                  : Theme.of(
                                      sheetCtx,
                                    ).colorScheme.surfaceContainerHighest
                                      .withValues(alpha: .5),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: ui.sort == k
                                          ? context.tokens.accent
                                          : Theme.of(
                                              sheetCtx,
                                            ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (ui.sort == k)
                                  Icon(
                                    BsIcons.check,
                                    size: 14,
                                    color: context.tokens.accent,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      '分组方式',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (k, t) in kShelfDims)
                          _panelChip(
                            sheetCtx,
                            'panel-dim-$k',
                            t,
                            ui.dim == k,
                            () => setUi((u) => u.copyWith(dim: k, dimVal: '')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // 原型 2344：清空筛选 / 完成 双钮
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('panel-reset'),
                            onTap: () {
                              _kwCtl.clear();
                              setUi((u) => u.cleared);
                              readToast(context, '筛选与维度已清空');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              alignment: Alignment.center,
                              decoration: _cardDeco(context),
                              child: Text(
                                '清空筛选',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      Theme.of(
                                        sheetCtx,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('panel-done'),
                            onTap: () => Navigator.of(sheetCtx).pop(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: context.tokens.gradient,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text(
                                '完成',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _panelChip(
    BuildContext context,
    String key,
    String label,
    bool on,
    VoidCallback onTap,
  ) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: on
            ? context.tokens.accent.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: on ? context.tokens.accent : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: on ? context.tokens.accent : null,
        ),
      ),
    ),
  );

  // ---------------- 主体五视图 ----------------

  Widget _roundBtn(String key, IconData ic, String tip, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(ic, size: 17, color: cs.onSurface),
        ),
      ),
    );
  }

  /// 维度分组渲染（值 → 该组内容）。
  List<Widget> _dimGroups(
    ShelfUI ui,
    List<Book> list,
    BookSession? running,
    ColorScheme cs,
    dynamic tokens,
  ) {
    final q = ui.toQuery();
    final groups = <String, List<Book>>{};
    for (final b in list) {
      for (final v in q.dimValuesOf(b)) {
        (groups[v] ??= []).add(b);
      }
    }
    return [
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(
            '${g.key} · ${g.value.length} 本',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        _body(ui, g.value, running, cs, tokens, pfx: '${g.key}-'),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _body(
    ShelfUI ui,
    List<Book> list,
    BookSession? running,
    ColorScheme cs,
    dynamic tokens, {
    String pfx = '',
  }) {
    // read.wallCols（§6 外观与启动）：封面墙列数随设置 3/4/5；wall4 为固定 4 列紧凑态。
    final wallKv =
        int.tryParse(
              ref.watch(readKvProvider(('read.wallCols', '3'))).valueOrNull ??
              '3',
            ) ??
            3;
    final wallCols = ui.view == 'wall4' ? 4 : wallKv;
    return switch (ui.view) {
      'spine' => _spineView(list, pfx),
      'time' => _timelineView(list, cs),
      'rows' => Column(
        children: [
          for (final b in list)
            _rowItem(ui, b, running, cs, tokens, pfx: pfx),
        ],
      ),
      _ => GridView.count(
        key: ValueKey('sh-grid-$wallCols-$pfx'),
        crossAxisCount: wallCols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: .62,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: [
          for (final b in list) _wallCard(ui, b, cs, tokens, pfx: pfx),
        ],
      ),
    };
  }

  Widget _tapWrap(
    ShelfUI ui,
    Book b, {
    required Widget child,
    String pfx = '',
  }) => GestureDetector(
    key: ValueKey('sh-item-$pfx${b.id}'),
    // V1.50 分流：本地书点封面＝直接进阅读器（原型 shOpen 包装器同语义），
    // 非本地书行为不变；多选态优先。
    onTap: () => ui.batch
        ? _selTap(ui, b)
        : context.push(b.local ? '/read/reader/${b.id}' : '/read/book/${b.id}'),
    onLongPress: ui.batch ? null : () => showLongPressSheet(context, ref, b),
    child: child,
  );

  void _selTap(ShelfUI ui, Book b) {
    final sel = {...ui.sel};
    sel.contains(b.id) ? sel.remove(b.id) : sel.add(b.id);
    ref.read(shelfUiProvider.notifier).state = ui.copyWith(sel: sel);
  }

  Widget _wallCard(
    ShelfUI ui,
    Book b,
    ColorScheme cs,
    dynamic tokens, {
    String pfx = '',
  }) => _tapWrap(
    ui,
    b,
    pfx: pfx,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: BsCover(
                  book: b,
                  width: double.infinity,
                  height: double.infinity,
                  onBadgeTap: ui.batch
                      ? null
                      : () => cycleBookState(context, ref, b),
                ),
              ),
              if (ui.batch)
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ui.sel.contains(b.id)
                          ? tokens.accent as Color
                          : Colors.white70,
                    ),
                    child: ui.sel.contains(b.id)
                        ? const Icon(
                            BsIcons.check,
                            size: 12,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5, bottom: 4),
          child: Text(
            b.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 4),
        BkPctBar(book: b),
      ],
    ),
  );

  String _md(int? ms) {
    if (ms == null) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Widget _rowItem(
    ShelfUI ui,
    Book b,
    BookSession? running,
    ColorScheme cs,
    dynamic tokens, {
    String pfx = '',
  }) {
    final qn = (ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[])
        .where((q) => q.bookId == b.id)
        .length;
    // 原型 shListRows 4571：元信息补「读完 MM-DD / 开始 MM-DD」
    final dateSeg = b.startedAt == null
        ? ''
        : ' · ${b.state == Book.kStateDone ? '读完 ${_md(b.endedAt)}' : '开始 ${_md(b.startedAt)}'}';
    final showTimer = b.state == Book.kStateReading && !ui.batch;
    return _tapWrap(
      ui,
      b,
      pfx: pfx,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: _cardDeco(context),
        child: Row(
          children: [
            BsCover(
              book: b,
              width: 36,
              height: 52,
              radius: 7,
              showAuthor: false,
              badgeSize: 7,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // 原型 brRowBadge：列表行标题后「本地」小胶囊。
                      if (b.local) ...[
                        const SizedBox(width: 6),
                        const BrLocalInlineBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${b.author} · ${b.pages} 页 · $qn 条笔记$dateSeg',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  if (b.state == Book.kStateReading) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: b.percent / 100,
                        minHeight: 4,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 在读行「开始/结束」计时 mini 钮（原型 4573）
            if (showTimer) ...[
              const SizedBox(width: 8),
              GestureDetector(
                key: ValueKey('sh-row-timer-$pfx${b.id}'),
                onTap: () => readTimerTap(ref, context, target: b),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: cs.surfaceContainerHighest,
                  ),
                  child: Text(
                    running?.bookId == b.id ? '结束' : '开始',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: bsStateColor(b.state).withValues(alpha: .12),
              ),
              child: Text(
                b.state,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: bsStateColor(b.state),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spineView(List<Book> list, String pfx) {
    double h(Book b) => switch (b.state) {
      '在读' => 112,
      '已读' => 132,
      '弃读' => 78,
      _ => 96,
    };
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: _cardDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 150,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final b in list)
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: _tapWrap(
                        ref.watch(shelfUiProvider),
                        b,
                        pfx: pfx,
                        child: GestureDetector(
                          child: Container(
                            width: 30,
                            height: h(b),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              image: _hasCover(b)
                                  ? DecorationImage(
                                      image: FileImage(File(b.coverPath!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              gradient: _hasCover(b)
                                  ? null
                                  : LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        kBsCov[b.paletteIdx].$3,
                                        kBsCov[b.paletteIdx].$3.withValues(
                                          alpha: .8,
                                        ),
                                      ],
                                    ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: Text(
                                      b.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 4,
                                  child: Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: b.state == Book.kStateReading
                                          ? Colors.white
                                          : Colors.white38,
                                    ),
                                  ),
                                ),
                                // 原型 shSpine 本地书右下白圆点（u 元素 5px）。
                                if (b.local)
                                  Positioned(
                                    right: 2,
                                    bottom: 2,
                                    child: Container(
                                      key: ValueKey('sh-spine-local-${b.id}'),
                                      width: 5,
                                      height: 5,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 原型 4569 说明行（照抄）
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '书脊高度＝总页数 · 白点＝在读 · 点书脊看详情，长按进多选',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasCover(Book b) =>
      (b.coverPath?.isNotEmpty ?? false) && File(b.coverPath!).existsSync();

  /// 时间线（原型 bsEvents 4614-4622 + shTimeline 4623-4631 全量口径：
  /// 开始 / 读完（+页数+购书 ¥）/ 评分 / 摘录（划线「」·感想前缀·原文 46 字）/ 会话（最近 6 次）
  /// 五类事件；日头「M月D日 · N 条」；每卡 图标 + 事件行 + 书名·作者副行、点卡进详情；
  /// 尾行「共 N 条 · 显示最近 M 天 · 范围可在阅读设置里调」；空态「这段时间没有阅读事件」）。
  Widget _timelineView(List<Book> list, ColorScheme cs) {
    final quotes =
        ref.watch(allQuotesProvider).valueOrNull ?? const <BookQuote>[];
    final sessions =
        ref.watch(shelfSessionsProvider).valueOrNull ??
        const <BookSession>[];
    final byId = {for (final b in list) b.id: b};
    final range =
        ref.watch(readKvProvider(('read.tlRange', '近半年'))).valueOrNull ??
        '近半年';
    final tlDays =
        int.tryParse(
              ref.watch(readKvProvider(('read.tlDays', '14'))).valueOrNull ??
              '14',
            ) ??
            14;
    // read.tlRange 窗口过滤 → 按日分组倒序 → 取最近 tlDays 天（原型 DS slice 口径）。
    final winDays = switch (range) {
      '本月' => 31,
      '近半年' => 183,
      _ => 366,
    };
    final fromT = DateTime.now().subtract(Duration(days: winDays));
    final events = <_TlEv>[];
    void add(int? ms, IconData ic, String t, Book b) {
      if (ms == null) return;
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (d.isBefore(fromT)) return;
      events.add((d, ic, t, b));
    }
    for (final b in list) {
      add(b.startedAt, Icons.auto_stories_outlined, '开始读《${b.title}》', b);
      if (b.state == Book.kStateDone) {
        final fee = b.fee > 0
            ? ' · 购书 ¥${b.fee % 1 == 0 ? b.fee.toInt() : b.fee}'
            : '';
        add(
          b.endedAt,
          Icons.check_circle_outline,
          '读完《${b.title}》· ${b.pages} 页$fee',
          b,
        );
      }
      if (b.rating > 0) {
        final fin = (b.finalNote ?? '').trim().isNotEmpty
            ? b.finalNote!.trim()
            : (b.authorNote ?? '');
        add(
          b.endedAt ?? b.startedAt ?? b.lastReadAt,
          Icons.star_border,
          '评了 ${b.rating % 1 == 0 ? b.rating.toInt() : b.rating} 分：$fin',
          b,
        );
      }
      for (final q in quotes.where((q) => byId.containsKey(q.bookId))) {
        final t = q.body.length > 46 ? q.body.substring(0, 46) : q.body;
        add(
          q.createdAt,
          Icons.format_quote_outlined,
          q.kind == BookQuote.kKindMark ? '「$t」' : '想法：$t',
          byId[q.bookId]!,
        );
      }
      final closed = sessions
          .where((s) => s.bookId == b.id && s.endedAt != null)
          .toList();
      for (final s in (closed.length > 6
          ? closed.sublist(closed.length - 6)
          : closed)) {
        final pp = s.fromPage != null && s.toPage != null
            ? ' · P${s.fromPage}→${s.toPage}'
            : '';
        add(
          s.endedAt,
          Icons.timer_outlined,
          '读了 ${s.billedMinutes} 分钟$pp',
          b,
        );
      }
    }
    events.sort((a, b) => b.$1.compareTo(a.$1));
    final days = <String, List<_TlEv>>{};
    for (final e in events) {
      final d = e.$1;
      final k =
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      (days[k] ??= []).add(e);
    }
    final shown = days.entries.take(tlDays < 1 ? 14 : tlDays).toList();
    if (shown.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: _cardDeco(context),
        child: Text(
          '这段时间没有阅读事件',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (gi, g) in shown.indexed)
          Padding(
            padding: EdgeInsets.only(top: gi == 0 ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 日头行（原型：M月D日 · N 条 + 分隔线）
                Row(
                  key: ValueKey('sh-tl-day-${g.key}'),
                  children: [
                    Text(
                      '${int.parse(g.key.substring(0, 2))}月${int.parse(g.key.substring(3))}日',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${g.value.length} 条',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        margin: const EdgeInsets.only(left: 8),
                        color: cs.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                  ],
                ),
                for (final (ei, e) in g.value.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GestureDetector(
                      key: ValueKey('sh-tl-ev-${g.key}-$ei'),
                      onTap: () => context.push('/read/book/${e.$4.id}'),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: _cardDeco(context),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                e.$2,
                                size: 13,
                                color: cs.primary,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.$3,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${e.$4.title} · ${e.$4.author}',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              '共 ${events.length} 条 · 显示最近 ${shown.length} 天 · 范围可在阅读设置里调',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- 批量管理浮动条（原型 849-855 / 4619-4628） ----------------

  Widget _batchBar(ShelfUI ui, ColorScheme cs, dynamic tokens) {
    final ids = ui.sel.toList();
    return Positioned(
      left: 16,
      right: 16,
      bottom: 22,
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const ValueKey('bat-bar'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
            boxShadow: tokens.cardShadow as List<BoxShadow>,
          ),
          child: Row(
            children: [
              Text(
                '已选 ${ids.length} 本',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              _batBtn('bat-move', '移入分区', cs, () => _batMove(ids)),
              const SizedBox(width: 6),
              _batBtn('bat-tag', '加标签', cs, () => _batTag(ids)),
              const SizedBox(width: 6),
              _batBtn(
                'bat-del',
                '删除',
                cs,
                () => _batDel(ids),
                danger: true,
              ),
              const Spacer(),
              _batBtn(
                'bat-cancel',
                '取消',
                cs,
                () => ref.read(shelfUiProvider.notifier).state =
                    ui.copyWith(batch: false, sel: const {}),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _batBtn(
    String key,
    String label,
    ColorScheme cs,
    VoidCallback onTap, {
    bool danger = false,
  }) => GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: danger
            ? const Color(0xFFFDBA74).withValues(alpha: .15)
            : cs.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: danger ? const Color(0xFFF43F5E) : cs.onSurfaceVariant,
        ),
      ),
    ),
  );

  void _exitBatch() => ref.read(shelfUiProvider.notifier).state = ref
      .read(shelfUiProvider)
      .copyWith(batch: false, sel: const {});

  /// 移入分区：以首本当前分区循环到下一分区（原型 shBatchMove 4619）。
  Future<void> _batMove(List<String> ids) async {
    final all = await ref.read(readRepositoryProvider).allBooks();
    final cur = all.firstWhere((b) => b.id == ids.first, orElse: () => all.first);
    final nx = Book.states[(Book.states.indexOf(cur.state) + 1) % 4];
    await ref.read(readRepositoryProvider).bulkSetState(ids, nx);
    ref.read(readTickProvider.notifier).state++;
    _exitBatch();
    if (mounted) readToast(context, '已将 ${ids.length} 本移入「$nx」');
  }

  /// 删除：软删（原型 shBatchDel 4627 的 30 天承诺＝softDeleteBooks）。
  Future<void> _batDel(List<String> ids) async {
    await ref.read(readRepositoryProvider).softDeleteBooks(ids);
    ref.read(readTickProvider.notifier).state++;
    _exitBatch();
    if (mounted) {
      readToast(context, '已移出书架 ${ids.length} 本（笔记与时长保留 30 天可恢复）');
    }
  }

  /// 加标签：选一个标签批量并集写入（原型 shBatchTag 4625 ＝ 真落库）。
  Future<void> _batTag(List<String> ids) async {
    final repo = ref.read(readRepositoryProvider);
    final tags = <String>{
      ...await repo.quoteTags(),
      ...[
        for (final b in ref.read(booksProvider).valueOrNull ?? const <Book>[])
          ...b.tags,
      ],
    }.where((t) => t.isNotEmpty).toList();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BatchTagSheet(count: ids.length, tags: tags),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final exist = await repo.dictOf(DictEntry.kTag);
    if (!exist.any((e) => e.name == picked)) {
      await repo.dictAdd(DictEntry.kTag, picked);
    }
    await repo.bulkAddTags(ids, [picked]);
    ref.read(readTickProvider.notifier).state++;
    _exitBatch();
    if (mounted) readToast(context, '已为 ${ids.length} 本加上 #$picked');
  }
}

/// 批量加标签弹层（自持 controller，避免 pop 动画期间用到已 dispose 的控制器）。
class _BatchTagSheet extends StatefulWidget {
  const _BatchTagSheet({required this.count, required this.tags});
  final int count;
  final List<String> tags;

  @override
  State<_BatchTagSheet> createState() => _BatchTagSheetState();
}

class _BatchTagSheetState extends State<_BatchTagSheet> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _pick(String t) => Navigator.of(context).pop(t);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '为 ${widget.count} 本加标签',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in widget.tags)
                    GestureDetector(
                      key: ValueKey('bat-tag-pick-$t'),
                      onTap: () => _pick(t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: cs.surfaceContainerHighest,
                        ),
                        child: Text(
                          '#$t',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('bat-tag-new'),
                controller: _ctl,
                onSubmitted: (v) => _pick(v.trim()),
                decoration: InputDecoration(
                  labelText: '新标签',
                  labelStyle: const TextStyle(fontSize: 12),
                  isDense: true,
                  suffixIcon: IconButton(
                    key: const ValueKey('bat-tag-ok'),
                    icon: const Icon(BsIcons.add, size: 18),
                    onPressed: () => _pick(_ctl.text.trim()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 书架 FAB（＋ 新书）。
class GradShelfFab extends StatelessWidget {
  const GradShelfFab({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      key: const ValueKey('sh-add'),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: tokens.gradient,
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: .35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}

/// 长按书籍菜单：项与顺序来自设置（read.longPress · §6 · sheetLongPress 弹层自带
/// 「调整长按菜单」入口）。可选全集＝LP_ALL，未勾选项不渲染；尾行「查看书籍详情」（原型 5059）。
const kLpAll = ['计时', '记摘录', '改分区', '移书单', '标记读完', '多选', '删除'];
const kLpDefault = '计时,记摘录,改分区,移书单,删除';

Future<void> showLongPressSheet(BuildContext context, WidgetRef ref, Book b) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Consumer(
          builder: (_, ref2, _) {
            final raw =
                ref2
                    .watch(readKvProvider(('read.longPress', kLpDefault)))
                    .valueOrNull ??
                kLpDefault;
            final items = raw.split(',').where(kLpAll.contains).toList();
            Widget row(String key, String label, VoidCallback onTap) =>
                ListTile(
                  key: ValueKey(key),
                  dense: true,
                  title: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: onTap,
                );
            Widget rowFor(String name) => switch (name) {
              '计时' => row('lp-timer', '计时', () {
                Navigator.of(sheetCtx).pop();
                readTimerTap(ref2, context, target: b);
              }),
              '记摘录' => row('lp-quote', '记摘录', () {
                Navigator.of(sheetCtx).pop();
                showQuoteSheet(context, ref2, bookId: b.id);
              }),
              '改分区' => row('lp-state', '改分区 · ${b.state}', () {
                Navigator.of(sheetCtx).pop();
                cycleBookState(context, ref2, b);
              }),
              '移书单' => row('lp-list', '移书单', () {
                Navigator.of(sheetCtx).pop();
                showMoveToListSheet(context, ref2, b);
              }),
              '标记读完' => row('lp-done', '标记读完', () async {
                await ref2.read(readRepositoryProvider).bulkSetState(
                  [b.id],
                  Book.kStateDone,
                );
                ref2.read(readTickProvider.notifier).state++;
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (context.mounted) {
                  readToast(context, '《${b.title}》已标记读完 · 自动进年度书单');
                }
              }),
              '多选' => row('lp-multi', '多选', () {
                ref2.read(shelfUiProvider.notifier).state =
                    ref2.read(shelfUiProvider).copyWith(
                      batch: true,
                      sel: {b.id},
                    );
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              }),
              _ => row('lp-del', '删除', () async {
                await ref2.read(readRepositoryProvider).softDeleteBooks([
                  b.id,
                ]);
                ref2.read(readTickProvider.notifier).state++;
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (context.mounted) readToast(context, '已移除《${b.title}》');
              }),
            };
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '《${b.title}》',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 原型 shLongMenu 包装器：本地书置顶「开始阅读 · 本地 EPUB」渐变钮。
                  if (b.local) ...[
                    GestureDetector(
                      key: const ValueKey('lp-read'),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        if (context.mounted) {
                          context.push('/read/reader/${b.id}');
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: context.tokens.gradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '开始阅读 · 本地 EPUB',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  for (final n in items) rowFor(n),
                  // 原型 5059 尾行灰钮：查看书籍详情
                  TextButton(
                    key: const ValueKey('lp-detail'),
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      if (context.mounted) context.push('/read/book/${b.id}');
                    },
                    child: Text(
                      '查看书籍详情',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('lp-edit-menu'),
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      // 设置页就地内嵌长按编辑：直达「内容显示与排序」组（sec=1）。
                      if (context.mounted) {
                        context.push('/read/settings?sec=1');
                      }
                    },
                    child: Text(
                      '调整长按菜单',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _GoalRingPainter extends CustomPainter {
  _GoalRingPainter({required this.frac, required this.color});
  final double frac;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color.withValues(alpha: .26),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5708,
      6.2832 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) => old.frac != frac;
}
