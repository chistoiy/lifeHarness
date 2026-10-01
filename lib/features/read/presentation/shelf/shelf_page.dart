import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/book.dart';
import '../../domain/book_dict.dart';
import '../../domain/book_list.dart';
import '../../domain/book_quote.dart';
import '../../domain/book_session.dart';
import '../../domain/shelf_query.dart';
import '../open_with.dart' show locateBookProvider;
import '../read_actions.dart';
import '../reader/epub_state_ui.dart';
import '../read_providers.dart';
import '../read_sheets.dart';
import '../widgets/bs_cover.dart';

part 'shelf_batch_tag.dart';
part 'shelf_fab.dart';
part 'shelf_locate.dart';
part 'shelf_long_press.dart';
part 'shelf_goal_ring.dart';
part 'shelf_goal.dart';
part 'shelf_panel.dart';
part 'shelf_spine_time.dart';
part 'shelf_batch_ops.dart';
part 'shelf_views.dart';

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

  // V1.53.4⑥ 定位高亮：请求序号（新请求作废旧轮询）与描边闪烁浮层。
  int _locateSeq = 0;
  OverlayEntry? _locateFlashEntry;

  @override
  void initState() {
    super.initState();
    // 真机修⑥：进书架即后台预热就绪本地书（isolate 解析入文档缓存），
    // 点封面秒进；重启后缓存清空也靠这里回温。
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmLocalBooks());
    // V1.53.4⑥：建页前已置位的定位请求（open_with 先 go 后消费）首帧补触发。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = ref.read(locateBookProvider);
      if (id != null) unawaited(_locateBook(id));
    });
  }

  Future<void> _warmLocalBooks() async {
    try {
      final books = await ref.read(booksProvider.future);
      final svc = ref.read(epubPreloadProvider);
      for (final b in ShelfSort.byLastRead(
        books
            .where((b) => !b.isDeleted && b.local && b.epub?.state == 'rdy')
            .toList(),
      ).take(2)) {
        unawaited(svc.warm(b));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _locateFlashEntry?.remove();
    _locateFlashEntry = null;
    _kwCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // V1.53.4⑥：在书架页内时新定位请求即时消费（建页前的首值见 initState）。
    ref.listen<String?>(
      locateBookProvider,
      (_, next) {
        if (next != null) unawaited(_locateBook(next));
      },
    );
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

}
