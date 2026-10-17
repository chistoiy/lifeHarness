/// V1.54.1 批2 · X-Ray 中心（三段同页：词条 / AI 精化 / 索引与备份，原型 p-xrwords）。
///
/// 段一（词条，默认段＝中心页工单拍板②）：GLOBAL 养成词库全量增删改查：
/// 列表（词/类型/动作/时间）＋改名/改动作/删除
/// ＋新增置顶＋类型筛选；「启用养成词库」开关行（`read.xrUserDict`，默认开；
/// 关＝纯预置视角：面板隐藏我的词条并恢复被屏蔽词、解析不叠加用户层；
/// 已物化状态行不回滚，重开即恢复）。导入导出随批3。
/// 段二（AI 精化）：门控→本次范围→预算五档→开始/查看汇总→明细块**复用**
/// reader_xray_refine 的 [xrRefineLogBlock]（与面板段内卡两地同源，禁再写一份）；
/// 书归属＝阅读器入口带 ?book=（拍板①），不带书时点开始先弹书选择页（枚举选择）。
/// 段三（索引与备份）：全书索引面板（回阅读器）·单书 .xraybak 导出/导入
/// （复用 [showXrBakSheet]）·重置索引·解析范围三档；设置页 xrBak 行改道本页第三段
/// （拍板③：入口合并，弹层不再各挂一份）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_review.dart' show aiGateDenied;
import '../../../core/logging/app_log.dart';

import '../data/xray/xray_dao.dart';
import '../data/xray/xray_refine.dart';
import '../../../core/database/schema/xray.dart' as xs;
import '../domain/book.dart' show Book;
import 'reader/reader_xray_learn_sheets.dart' show xrGuessType, showXrBakSheet;
import 'reader/reader_xray_panel.dart' show kXrTypes;
import 'reader/reader_xray_refine.dart'
    show
        kXrRefineTask,
        kXrRefineBudgets,
        kXrRefineBudgetDefault,
        xrRefineBudgetOf,
        xrRefineTokens,
        xrRefineCaller,
        xrRefineForBook,
        xrRefineLogBlock,
        showXrRefineReview;
import 'read_providers.dart';
import 'read_sheets.dart' show readToast;
import '../../../shared/widgets/ui_kit.dart' show EmptyDashRow;
import '../../../core/theme/app_theme.dart';

// F3-3/F3-6：品牌靛蓝与小字灰收主题令牌（其余 _xrRose/_xrViolet/_typeColor 为
// 词性分类色板＝数据色，保留并登记工单）。
Color _xrMuted(BuildContext c) => c.tokens.text2;
Color _xrAccent(BuildContext c) => c.tokens.accent;
const _xrRose = Color(0xFFF43F5E);
const _xrViolet = Color(0xFF7C3AED);

/// 类型徽着色（与面板 _Badge 六类同表）。
const _typeColor = {
  'per': Color(0xFF6366F1),
  'loc': Color(0xFF059669),
  'org': Color(0xFFB45309),
  'term': Color(0xFF0284C7),
  'abbr': Color(0xFF475569),
  'book': Color(0xFFDB2777),
};

String _typeLabel(String t) =>
    kXrTypes.firstWhere((x) => x.$1 == t, orElse: () => ('', t)).$2;

/// 养成词库开关的统一读口（管理页与面板头共用一个键）。
bool xrUserDictOn(WidgetRef ref) =>
    ref.watch(readKvProvider(('read.xrUserDict', 'true'))).valueOrNull != 'false';

class XrayWordsPage extends ConsumerStatefulWidget {
  const XrayWordsPage({super.key, this.bookId, this.initialSeg});

  /// 拍板①：阅读器 ⋯ 入口带 `?book=<id>`（AI/索引段直接可用当前书）；
  /// 书架/阅读设置入口不带书——点「开始精化」/「重置索引」先弹书选择页。
  final String? bookId;

  /// 深链段：设置页 xrBak 行带 ?seg=idx 直达第三段（拍板③）；null＝默认词条段（拍板②）。
  final String? initialSeg;

  @override
  ConsumerState<XrayWordsPage> createState() => _XrayWordsPageState();
}

class _XrayWordsPageState extends ConsumerState<XrayWordsPage> {
  List<XrayDictRow> _rows = const [];
  bool _loading = true;
  String _type = 'all';
  String _q = '';
  final _addCtrl = TextEditingController();

  // ---- X-Ray 中心三段面（V1.59 批3 · 中心页工单：三段同页） ----
  late String _seg = switch (widget.initialSeg) {
    'ai' => 'ai',
    'idx' => 'idx',
    _ => 'word',
  };
  Book? _book; // 当前书：词条段不消费；AI/索引段围绕它（入口带书或书选择页选定）。
  String? _md5;
  List<XrRefineCandidate> _cands = const [];
  int _budget = kXrRefineBudgetDefault;
  String? _aiGate; // 非空＝AI 能力未就绪的拒绝原因（门控行显示未启用）。
  bool _aiLoading = false;
  String _idxLbl = '未解析';
  String _scope = 'all'; // 索引段范围三档＝展示态（与原型同口径，只提示不落库）。

  @override
  void initState() {
    super.initState();
    _load();
    _initBook();
  }

  Future<void> _initBook() async {
    final id = widget.bookId;
    if (id == null) return;
    final b = await ref.read(readRepositoryProvider).bookById(id);
    if (!mounted || b == null) return;
    setState(() => _book = b);
    await _prepSeg();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await ref.read(xrayDaoProvider).listGlobalDict();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _flipUserDict() async {
    // 回调内只能 read（watch 仅限 build）；键值即取即翻。
    final onNow =
        ref.read(readKvProvider(('read.xrUserDict', 'true'))).valueOrNull !=
            'false';
    final next = onNow ? 'false' : 'true';
    await ref.read(readRepositoryProvider).setKv('read.xrUserDict', next);
    ref.read(readTickProvider.notifier).state++;
    if (mounted) {
      readToast(
        context,
        next == 'true'
            ? '养词库已开启 · 我的词条与屏蔽恢复生效'
            : '已切纯预置视角 · 已整理状态不回滚，重开即恢复',
      );
    }
  }

  Future<void> _add() async {
    final w = _addCtrl.text.trim();
    if (w.isEmpty) {
      readToast(context, '先输入词');
      return;
    }
    if (_rows.any((r) => r.word == w)) {
      readToast(context, '该词已在词库');
      return;
    }
    await ref.read(xrayDaoProvider).putUserWord(
          scope: xs.xrayScopeGlobal,
          word: w,
          action: xs.xrayActAdd,
          type: xrGuessType(w),
        );
    _addCtrl.clear();
    await _load();
    if (mounted) readToast(context, '已养入「$w」· 重解析与补扫时生效');
  }

  Future<void> _rename(XrayDictRow r) async {
    final ctrl = TextEditingController(text: r.word);
    final nn = await showDialog<String>(
      context: context,
      builder: (sc) => AlertDialog(
        title: const Text('改名', style: TextStyle(fontSize: 15)),
        content: TextField(
          key: const ValueKey('xrwRenameIn'),
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(sc), child: const Text('取消')),
          TextButton(
              key: const ValueKey('xrwRenameGo'),
              onPressed: () => Navigator.pop(sc, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (nn == null || nn.isEmpty || nn == r.word) return;
    await ref.read(xrayDaoProvider)
        .updateGlobalDict(word: r.word, action: r.action, newWord: nn);
    await _load();
    if (mounted) readToast(context, '已改名「$nn」');
  }

  Future<void> _flipAction(XrayDictRow r) async {
    await ref.read(xrayDaoProvider).updateGlobalDict(
          word: r.word,
          action: r.action,
          toAction:
              r.action == xs.xrayActAdd ? xs.xrayActForbid : xs.xrayActAdd,
        );
    await _load();
    if (mounted) readToast(context, '已更新动作');
  }

  Future<void> _del(XrayDictRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (sc) => AlertDialog(
        title: const Text('删除养成词', style: TextStyle(fontSize: 15)),
        content: Text('「${r.word}」将从全局词库移除（各书已索引不受影响）。',
            style: const TextStyle(fontSize: 12.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(sc, false),
              child: const Text('取消')),
          TextButton(
            key: const ValueKey('xrwDelGo'),
            onPressed: () => Navigator.pop(sc, true),
            child: const Text('删除', style: TextStyle(color: _xrRose)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(xrayDaoProvider).deleteGlobalDict(r.word, action: r.action);
    await _load();
    if (mounted) readToast(context, '已删除「${r.word}」');
  }

  // ---------------------------------------------- 批3 · .xrwords 导入导出

  Future<void> _export() async {
    final saved = await ref.read(xrayWordsIoProvider).exportWords();
    if (!mounted) return;
    readToast(context,
        saved == null ? '已取消导出' : '已导出 ${_rows.length} 条 · $saved');
  }

  Future<void> _import() async {
    Map<String, Object?>? bundle;
    try {
      bundle = await ref.read(xrayWordsIoProvider).readPick();
    } on FormatException catch (e) {
      AppLog.add('xrwords 导入拒收：${e.message}', level: LhLevel.warn);
      if (!mounted) return;
      readToast(context, e.message);
      return;
    } catch (e) {
      AppLog.add('xrwords 导入读取失败：$e', level: LhLevel.warn);
      if (!mounted) return;
      readToast(context, '读取失败：$e');
      return;
    }
    if (bundle == null) {
      if (!mounted) return;
      readToast(context, '已取消导入');
      return;
    }
    if (!mounted) return;
    final (entries, parseSkipped) =
        ref.read(xrayWordsIoProvider).parseEntries(bundle);
    // 预检计数：对照当前 GLOBAL 行算新增/覆盖，确认后才落库。
    final keys = _rows.map((r) => '${r.word}|${r.action}').toSet();
    var add = 0, upd = 0;
    for (final e in entries) {
      keys.contains('${e.word}|${e.action}') ? upd++ : add++;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (sc) => AlertDialog(
        title: const Text('导入养成词', style: TextStyle(fontSize: 15)),
        content: Text(
          '包内 ${entries.length + parseSkipped} 条 · 新增 $add · 覆盖 $upd'
          '${parseSkipped > 0 ? ' · 跳过 $parseSkipped' : ''}\n'
          '合并进全局词库（同名同动作覆盖），不影响按书词条。',
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(sc, false),
              child: const Text('取消')),
          TextButton(
            key: const ValueKey('xrwImpGo'),
            onPressed: () => Navigator.pop(sc, true),
            child: Text('导入', style: TextStyle(color: _xrAccent(context))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ref.read(xrayDaoProvider).importGlobalDict(entries);
    await _load();
    if (mounted) {
      readToast(context,
          '导入完成 · 新增 ${r.added} · 覆盖 ${r.updated} · 跳过 ${r.skipped + parseSkipped}');
    }
  }

  List<XrayDictRow> get _filtered {
    final q = _q.trim();
    return _rows.where((r) {
      if (_type != 'all' && r.type != _type) return false;
      return q.isEmpty || r.word.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = xrUserDictOn(ref);
    final rows = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('X-Ray 中心')),
      body: Column(
        children: [
          _segTabs(cs),
          Expanded(
            child: switch (_seg) {
              'ai' => _aiSeg(cs),
              'idx' => _idxSeg(cs),
              _ => _wordSeg(cs, on, rows),
            },
          ),
        ],
      ),
    );
  }

  /// 三 chips 段签（原型 `#xrcTabs`）：词条／AI 精化／索引与备份；默认词条（拍板②）。
  Widget _segTabs(ColorScheme cs) => Padding(
        key: const ValueKey('xrcTabs'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            for (final (k, l) in const [
              ('word', '词条'),
              ('ai', 'AI 精化'),
              ('idx', '索引与备份'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  key: ValueKey('xrc-t-$k'),
                  onTap: () => _setSeg(k),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: _seg == k ? _xrAccent(context) : const Color(0x2994A3B8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: _seg == k ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  void _setSeg(String k) {
    setState(() => _seg = k);
    _prepSeg();
  }

  /// 段数据预取（原型 xrcTab 注释同口径：状态由各自数据源维护，切段即刷新一次）。
  Future<void> _prepSeg() async {
    if (_seg == 'ai') {
      setState(() => _aiLoading = true);
      final repo = ref.read(readRepositoryProvider);
      _budget = xrRefineBudgetOf(await repo.kv('read.xraiBatchChars'));
      _aiGate = await aiGateDenied(ref, kXrRefineTask);
      await _prepDoc();
    } else if (_seg == 'idx') {
      await _prepDoc();
      await _prepIdx();
    }
  }

  /// 书→指纹→候选（与 showXrRefineEntry 的取数链同序同源）。
  Future<void> _prepDoc() async {
    final b = _book;
    if (b == null) {
      if (mounted) setState(() { _md5 = null; _cands = const []; _aiLoading = false; });
      return;
    }
    final dao = ref.read(xrayDaoProvider);
    var md5 = await dao.bookMd5(b.id);
    if (md5 == null || md5.isEmpty) {
      md5 = await ref.read(xraySchedulerProvider).ensureMd5(b);
    }
    final rows = md5 == null || md5.isEmpty
        ? const <XrayEntityRow>[]
        : await dao.allEntities(md5);
    if (!mounted) return;
    setState(() {
      _md5 = (md5 == null || md5.isEmpty) ? null : md5;
      _cands = [
        for (final e in rows) XrRefineCandidate(name: e.name, type: e.type, n: e.n, chs: e.chs),
      ];
      _aiLoading = false;
    });
  }

  /// 索引段读数（面板头部同一数据源：任务行 processed/total 章）。
  Future<void> _prepIdx() async {
    final b = _book;
    final md5 = _md5;
    if (!mounted) return;
    if (b == null || md5 == null) {
      setState(() => _idxLbl = b == null ? '未选书' : '未解析');
      return;
    }
    final task = await ref.read(xrayDaoProvider).task(md5);
    if (!mounted) return;
    setState(() {
      _idxLbl = task == null
          ? '未解析'
          : '已解析 ${task.processedCh}/${task.totalCh} 章 · 随阅读推进';
    });
  }

  // ---------------------------------------------------------- 段二 · AI 精化

  Future<void> _setBudget(int v) async {
    setState(() => _budget = v);
    await ref.read(readRepositoryProvider).setKv('read.xraiBatchChars', '$v');
  }

  Future<Book?> _pickBook({String title = '选择书籍'}) async {
    final books = (await ref.read(readRepositoryProvider).allBooks())
        .where((b) => b.local && b.epub != null)
        .toList();
    if (!mounted) return null;
    return showModalBottomSheet<Book>(
      context: context,
      showDragHandle: true,
      builder: (sc) => SafeArea(
        top: false,
        child: Column(
          key: const ValueKey('xrcBookSheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            if (books.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                // F2-7 空态定式（LH-L04）：虚线补录行，不再自绘 Text。
                child: EmptyDashRow(text: '书架里还没有导入的本地书'),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in books)
                    ListTile(
                      key: ValueKey('xrcBook-${b.id}'),
                      dense: true,
                      title: Text(b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      subtitle: Text(b.author,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 10.5)),
                      onTap: () => Navigator.pop(sc, b),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _ensureBookPicked() async {
    if (_book != null) return;
    final b = await _pickBook();
    if (b == null || !mounted) return;
    setState(() => _book = b);
    await _prepSeg();
  }

  void _startRefine() {
    () async {
      if (_book == null) {
        await _ensureBookPicked();
        return;
      }
      // 门控在点按时刻再验一次（配置可能已变）；被拒＝toast，零请求（R7 口径）。
      final denial = await aiGateDenied(ref, kXrRefineTask);
      if (denial != null) {
        if (mounted) readToast(context, 'AI 未启用：$denial');
        setState(() => _aiGate = denial);
        return;
      }
      final md5 = _md5;
      if (md5 == null) {
        if (mounted) readToast(context, '这本书还没有可用指纹');
        return;
      }
      if (_cands.isEmpty) {
        if (mounted) readToast(context, '本书还没有已解析词条，先跑一次 X-Ray 解析');
        return;
      }
      final holder = ref.read(xrRefineHolderProvider.notifier);
      // R3-5：单槽——开跑新书前先中止在跑的旧任务，别留孤儿 runner 吃额度。
      if (holder.state case final prev?
          when prev.stage == XrRefineStage.running ||
              prev.stage == XrRefineStage.paused) {
        prev.cancel();
      }
      final runner = XrRefineRunner(
        bookId: _book!.id,
        budgetChars: _budget,
        caller: xrRefineCaller(ref, _book!.title),
      );
      runner.plan(_cands);
      holder.state = runner;
      unawaited(runner.run(_cands));
    }();
  }

  void _openReview(XrRefineRunner? runner) {
    if (runner == null || runner.suggestions.isEmpty) {
      readToast(context, '还没有可确认的精化结果');
      return;
    }
    final md5 = _md5;
    if (md5 == null) return;
    showXrRefineReview(context, ref, runner: runner, md5: md5);
  }

  Widget _aiSeg(ColorScheme cs) {
    final runner = xrRefineForBook(ref.watch(xrRefineHolderProvider), _book?.id);
    final est = runner == null ? xrSplitBatches(_cands, _budget).length : 0;
    final tok = xrRefineTokens(xrRefineBatchChars(_cands));
    final stat = _book == null
        ? '未选书 · 点开始精化先选一本'
        : _aiLoading
            ? '取数中…'
            : '候选 ${_cands.length} 条 · 预计 $est 批 · 约 $tok tokens · 预算 $_budget 字';
    return ListView(
      key: const ValueKey('xrcAiScroll'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _card(cs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                      child: Text('AI 能力',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800))),
                  Text(
                    _aiGate == null
                        ? '已启用 · 可开始精化'
                        : '未启用 · 点按即提示，不发请求',
                    key: const ValueKey('xrcGateLbl'),
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                key: const ValueKey('xrcAiBookRow'),
                behavior: HitTestBehavior.opaque,
                // 不带书入口的换书面板＝同弹书选择页（枚举选择，禁循环切）。
                onTap: () async {
                  final b = await _pickBook();
                  if (b == null || !mounted) return;
                  setState(() => _book = b);
                  await _prepSeg();
                },
                child: Row(
                  children: [
                    const Expanded(
                        child: Text('本次范围',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800))),
                    Flexible(
                      child: Text(
                        _book == null
                            ? stat
                            : '${_book!.title} · ${_cands.length} 条',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 12, 2, 4),
          child: Text('单请求字符预算',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
        ),
        Wrap(
          key: const ValueKey('xrcAiBchips'),
          spacing: 6,
          children: [
            for (final v in kXrRefineBudgets)
              GestureDetector(
                key: ValueKey('xrcB-$v'),
                onTap: () => _setBudget(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: _budget == v ? _xrAccent(context) : const Color(0x2994A3B8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$v 字',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _budget == v ? Colors.white : const Color(0xFF64748B),
                      )),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                key: const ValueKey('xrcAiGo'),
                onTap: _startRefine,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                      color: _xrAccent(context), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    runner != null &&
                            (runner.stage == XrRefineStage.running ||
                                runner.stage == XrRefineStage.paused)
                        ? '进行中 ${runner.doneBatches}/${runner.totalBatches} 批'
                        : '开始精化 · $est 批',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              key: const ValueKey('xrcAiRev'),
              onTap: () => _openReview(runner),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: const Text('查看汇总',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        // 明细行文本只允许来自 xrRefineLogBlock（两地同源）——本文件出现模板即红（交付判据④）。
        if (runner != null)
          AnimatedBuilder(
            animation: runner,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
                  child: Text(stat,
                      key: const ValueKey('xrcAiStat'),
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant)),
                ),
                xrRefineLogBlock(context, runner),
              ],
            ),
          )
        else
          Container(
            key: const ValueKey('xrcAiLast'),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12)),
            child: Text(
              _aiGate == null
                  ? stat
                  : '未跑 · 逐批顺序请求，批间可暂停续跑（AI 未启用时点按只提示）',
              style: TextStyle(
                  fontSize: 10, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------ 段三 · 索引与备份

  Widget _idxSeg(ColorScheme cs) => ListView(
        key: const ValueKey('xrcIdxScroll'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(cs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _idxRow(cs, 'xrcIdxOpen', '全书索引面板', _idxLbl, () async {
                  await _ensureBookPicked();
                  if (_book == null || !mounted) return;
                  context.push('/read/reader/${_book!.id}');
                }),
                _idxRow(cs, 'xrcBak', '导出 / 导入单书备份（.xraybak）', '含出场锚点与整理结果',
                    () => showXrBakSheet(context, ref)),
                _idxRow(cs, 'xrcReset', '重置索引', '清本书全部词条与锚点',
                    _confirmReset,
                    danger: true),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 12, 2, 4),
            child: Text('解析范围',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
          Row(
            key: const ValueKey('xrcRange'),
            children: [
              for (final (k, l) in const [
                ('page', '当前页'),
                ('chapter', '本章'),
                ('book', '全书'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    key: ValueKey('xrcR-$k'),
                    onTap: () {
                      setState(() => _scope = k);
                      readToast(context, '解析范围 · $l');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: _scope == k ? _xrAccent(context) : const Color(0x2994A3B8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(l,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color:
                                _scope == k ? Colors.white : const Color(0xFF64748B),
                          )),
                    ),
                  ),
                ),
            ],
          ),
          Container(
            key: const ValueKey('xrcIdxFoot'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12)),
            child: Text(
              '养成词库与预置词表随备份包同行 · 恢复时指纹一致即一键还原',
              style: TextStyle(
                  fontSize: 10, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );

  Widget _idxRow(ColorScheme cs, String key, String title, String sub,
      VoidCallback onTap,
      {bool danger = false}) =>
      GestureDetector(
        key: ValueKey(key),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: danger ? _xrRose : null)),
              ),
              Flexible(
                child: Text(sub,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      );

  /// 重置索引（与面板同一条 sched.reset 链，用户词典不动）。
  void _confirmReset() {
    () async {
      await _ensureBookPicked();
      final b = _book;
      final md5 = _md5;
      if (b == null || !mounted) return;
      if (md5 == null) {
        readToast(context, '这本书还没有可用指纹');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (sc) => AlertDialog(
          title: const Text('重置全书索引'),
          content: const Text(
              '将清除该书的实体、出场与任务态（你加过/屏蔽过的词保留）。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(sc, false),
                child: const Text('取消')),
            TextButton(
              key: const ValueKey('xrcResetGo'),
              onPressed: () => Navigator.pop(sc, true),
              child: const Text('重置', style: TextStyle(color: _xrRose)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await ref.read(xraySchedulerProvider).reset(b.id, md5);
      if (!mounted) return;
      readToast(context, '已重置 · 实体/出场/任务态已清空');
      await _prepIdx();
    }();
  }

  Widget _wordSeg(ColorScheme cs, bool on, List<XrayDictRow> rows) => ListView(
        key: const ValueKey('xrwScroll'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            key: const ValueKey('xrwToggleCard'),
            padding: const EdgeInsets.all(14),
            decoration: _card(cs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('启用养成词库',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '关＝纯预置视角：隐藏我的词条并恢复被屏蔽词 · 已整理状态不回滚，重开即恢复',
                        style:
                            TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const ValueKey('xrwToggle'),
                  value: on,
                  onChanged: (_) => _flipUserDict(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('xrwIoCard'),
            padding: const EdgeInsets.all(14),
            decoration: _card(cs),
            child: Column(
              children: [
                GestureDetector(
                  key: const ValueKey('xrwExp'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _export,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Text('导出养成词库（.xrwords）',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${_rows.length} 条 · 预置指纹随包',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  key: const ValueKey('xrwImp'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _import,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Text('从文件导入',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('合并进全局词库 · 覆盖需确认',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(cs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_rows.length} 个养成词 · ${on ? '养词库生效中' : '纯预置视角（开关已关）'}',
                    key: const ValueKey('xrwSum'),
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('xrwSearchIn'),
                  onChanged: (v) => setState(() => _q = v),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '搜索养入的词…',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final t in [('all', '全部'), ...kXrTypes])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            key: ValueKey('xrw-tp-${t.$1}'),
                            onTap: () => setState(() => _type = t.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 5),
                              decoration: BoxDecoration(
                                color: _type == t.$1
                                    ? _xrAccent(context)
                                    : const Color(0x2994A3B8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${t.$2} · ${t.$1 == 'all' ? _rows.length : _rows.where((r) => r.type == t.$1).length}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: _type == t.$1
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('xrwAddInp'),
                        controller: _addCtrl,
                        onSubmitted: (_) => _add(),
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '新增养入词…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const ValueKey('xrwAddGo'),
                      onPressed: _add,
                      child: const Text('添加',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                _rows.isEmpty ? '还没有养成词 · 阅读中长按选词即可养入' : '该筛选没有养成词',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: _xrMuted(context)),
              ),
            )
          else
            for (final (i, r) in rows.indexed)
              Container(
                key: ValueKey('xrw-row-$i-${r.word}-${r.action}'),
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: _card(cs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(r.word,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 6),
                        _badge(
                          r.type == null ? '词' : _typeLabel(r.type!),
                          color:
                              _typeColor[r.type] ?? _xrAccent(context),
                        ),
                        const SizedBox(width: 4),
                        _badge(
                          r.action == xs.xrayActAdd ? '加词' : '屏蔽',
                          color: r.action == xs.xrayActAdd
                              ? _xrViolet
                              : _xrRose,
                        ),
                        const Spacer(),
                        Text(_fmtTime(r.createTime),
                            style: TextStyle(
                                fontSize: 9, color: cs.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          key: ValueKey('xrw-rn-$i'),
                          onPressed: () => _rename(r),
                          child:
                              const Text('改名', style: TextStyle(fontSize: 11)),
                        ),
                        TextButton(
                          key: ValueKey('xrw-fl-$i'),
                          onPressed: () => _flipAction(r),
                          child: Text(
                            r.action == xs.xrayActAdd ? '改屏蔽' : '改加词',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          key: ValueKey('xrw-del-$i'),
                          onPressed: () => _del(r),
                          child: const Text('删除',
                              style:
                                  TextStyle(fontSize: 11, color: _xrRose)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      );

  static String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static BoxDecoration _card(ColorScheme cs) => BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      );

  static Widget _badge(String text, {required Color color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 8.5, fontWeight: FontWeight.w900, color: color)),
      );
}
