/// V1.54.1 批4 · X-Ray「AI 精化」UI 群（预检卡 → 面板内逐批进度 → 汇总审阅）。
///
/// 事实源＝`prototype/index-bookshelf.html` 的 `sheetXrAiPre` / `#xrAiBar` /
/// `sheetXrAiReview`（深链 `?xr=ai|airun|airev`），key 名与原型逐一对齐，
/// 真机 adb 走查与原型断言用同一套语义。
///
/// 三条硬口径：
/// - **未授权零请求**：入口点按先过 [AiService.gate]（三重门控），被拒只 toast 不发请求；
///   逐批请求本身走 `AiService.request`＝`ai_calls` 自动留痕、输出结构校验照旧。
/// - **每请求体量可控**：单请求字符预算 `read.xraiBatchChars`（默认 3000）在预检卡
///   就地五档选，改了立刻重算批次数（联动可见，不是藏在大模型配置里）。
/// - **结果必须确认后才写库**：跑完只出建议清单，写入发生在审阅弹层「确认写入」之后，
///   且默认本书 scope（R7）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ai/ai_review.dart'
    show aiGateDenied, aiRunJsonBatch;
import '../../data/xray/xray_dao.dart' show XrayEntityRow;
import '../../data/xray/xray_refine.dart';
import '../../domain/book.dart' show Book;
import '../read_providers.dart'
    show
        readRepositoryProvider,
        xrRefineHolderProvider,
        xrayDaoProvider,
        xraySchedulerProvider,
        xraySnapProvider;
import '../read_sheets.dart' show readToast;

/// 能力点 id（与 `assets/ai_prompts/prompts.json` 同名）。
const String kXrRefineTask = 'read.xray_refine';

/// 预算档位与默认值（需求 V1.54.1 批4：默认 3000 字≈免费 API 4k 上下文安全线）。
const List<int> kXrRefineBudgets = [1000, 2000, 3000, 5000, 8000];
const int kXrRefineBudgetDefault = 3000;

/// tokens 估算：中文约 1.5 字/token，与预检卡「约 N tokens」同源。
int xrRefineTokens(int chars) => (chars / 1.5).round();

/// 读预算设置（KV 缺省＝[kXrRefineBudgetDefault]）。
int xrRefineBudgetOf(String? raw) =>
    int.tryParse(raw ?? '') ?? kXrRefineBudgetDefault;

/// ⋯菜单右侧状态字（原型 `brMoreXrAi`）：入口常在，状态跟着在跑的任务走。
String xrAiMenuStatus(XrRefineRunner? r) => switch (r) {
      null => 'AI · 未跑',
      final x when x.stage == XrRefineStage.done =>
        'AI · ${x.suggestions.length} 条建议',
      final x when x.stage == XrRefineStage.cancelled => 'AI · 已中止',
      final x => 'AI · ${x.doneBatches}/${x.totalBatches} 批',
    };

/// 生产 caller：一批词条 → 模型 JSON（走 core/ai 的批式出口，R7 同源门控与留痕）。
/// 失败一律上抛，由 runner 计重试/跳过——本闭包不吞异常。
/// [hostRef] 必须是**宿主页面**的 ref（跑批横跨弹层开关，弹层自己的 ref 会先 dispose）。
XrBatchCaller xrRefineCaller(WidgetRef hostRef, String bookTitle) =>
    (batch) => aiRunJsonBatch(hostRef, taskId: kXrRefineTask, vars: {
          'book': bookTitle,
          'batch': batch.map((e) => e.row).join('\n'),
        });

/// ⋯菜单「X-Ray 精化」入口：门控→指纹→候选→预检卡（被拒＝toast，零请求）。
Future<void> showXrRefineEntry(
    BuildContext context, WidgetRef ref, Book book) async {
  final denial = await aiGateDenied(ref, kXrRefineTask);
  if (denial != null) {
    if (context.mounted) readToast(context, 'AI 未启用：$denial');
    return;
  }
  final dao = ref.read(xrayDaoProvider);
  var md5 = await dao.bookMd5(book.id);
  if (md5 == null || md5.isEmpty) {
    md5 = await ref.read(xraySchedulerProvider).ensureMd5(book);
  }
  if (md5 == null || md5.isEmpty) {
    if (context.mounted) readToast(context, '这本书还没有可用指纹');
    return;
  }
  final rows = await dao.allEntities(md5);
  final budget = xrRefineBudgetOf(
      await ref.read(readRepositoryProvider).kv('read.xraiBatchChars'));
  if (!context.mounted) return;
  if (rows.isEmpty) {
    readToast(context, '本书还没有已解析词条，先跑一次 X-Ray 解析');
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _XrRefinePreSheet(
        md5: md5!,
        bookTitle: book.title,
        rows: rows,
        budget: budget,
        hostRef: ref),
  );
}

class _XrRefinePreSheet extends ConsumerStatefulWidget {
  const _XrRefinePreSheet({
    required this.md5,
    required this.bookTitle,
    required this.rows,
    required this.budget,
    required this.hostRef,
  });

  final String md5;
  final String bookTitle;
  final List<XrayEntityRow> rows;
  final int budget;

  /// 宿主页面（阅读页）的 ref：跑批比弹层活得久，别用弹层自己的 ref。
  final WidgetRef hostRef;

  @override
  ConsumerState<_XrRefinePreSheet> createState() => _XrRefinePreSheetState();
}

class _XrRefinePreSheetState extends ConsumerState<_XrRefinePreSheet> {
  late int _budget = widget.budget;

  List<XrRefineCandidate> get _cands => [
        for (final XrayEntityRow e in widget.rows)
          XrRefineCandidate(
              name: e.name, type: e.type, n: e.n, chs: e.chs)
      ];

  Future<void> _setBudget(int v) async {
    setState(() => _budget = v);
    await ref.read(readRepositoryProvider).setKv('read.xraiBatchChars', '$v');
  }

  void _start() {
    final cands = _cands;
    final host = widget.hostRef;
    final runner = XrRefineRunner(
        budgetChars: _budget,
        caller: xrRefineCaller(host, widget.bookTitle));
    runner.plan(cands);
    host.read(xrRefineHolderProvider.notifier).state = runner;
    Navigator.pop(context);
    // 不 await：进度由面板内 [XrRefineCard] 跟进，跑完就地出「查看汇总」。
    runner.run(cands);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cands = _cands;
    final batches = xrSplitBatches(cands, _budget).length;
    final chars = cands.fold<int>(0, (a, e) => a + e.cost + 1);
    return Padding(
      key: const ValueKey('xrAiPre'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('AI 精化',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(kXrRefineTask,
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('xrAiPreStat'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(14)),
            child: Text.rich(TextSpan(
                style: const TextStyle(fontSize: 11.5, height: 1.6),
                children: [
                  const TextSpan(text: '候选 '),
                  TextSpan(
                      text: '${cands.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' 条 · 预计 '),
                  TextSpan(
                      text: '$batches',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' 批 · 约 '),
                  TextSpan(
                      text: '${xrRefineTokens(chars)}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' tokens'),
                ])),
          ),
          const SizedBox(height: 12),
          Text('单请求字符预算',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in kXrRefineBudgets)
                GestureDetector(
                  key: ValueKey('xrAiB-$v'),
                  onTap: () => _setBudget(v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: v == _budget
                          ? cs.primary.withValues(alpha: .14)
                          : Colors.transparent,
                      border: Border.all(
                          color: v == _budget ? cs.primary : cs.outlineVariant),
                    ),
                    child: Text('$v 字',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: v == _budget
                                ? cs.primary
                                : cs.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            key: const ValueKey('xrAiPreGo'),
            onTap: _start,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: cs.primary, borderRadius: BorderRadius.circular(14)),
              child: Text('开始精化 · $batches 批',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimary)),
            ),
          ),
          GestureDetector(
            key: const ValueKey('xrAiPreCancel'),
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('取消',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ),
          Text('确认后按预算逐批顺序请求 · 未配 Key 或离线不出现本入口',
              style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 面板段内的逐批进度卡（原型 `#xrAiBar`）：跑动/暂停/失败提示/查看汇总。
class XrRefineCard extends ConsumerWidget {
  const XrRefineCard({required this.runner, required this.md5, super.key});

  final XrRefineRunner runner;
  final String md5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: runner,
      builder: (context, _) {
        final showRev = (runner.stage == XrRefineStage.done ||
                runner.stage == XrRefineStage.cancelled) &&
            runner.suggestions.isNotEmpty;
        final revLead = runner.stage == XrRefineStage.cancelled
            ? '已中止 · 失败 ${runner.failedBatches} 批'
            : '${runner.totalBatches} 批跑完';
        return Container(
          key: const ValueKey('xrAiBar'),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: .6))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'AI 精化 · 第 ${runner.doneBatches}/${runner.totalBatches} 批',
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                  if (runner.stage == XrRefineStage.paused)
                    GestureDetector(
                      key: const ValueKey('xrAiResume'),
                      onTap: runner.resume,
                      child: _xrChip(context, '继续', filled: true),
                    )
                  else if (runner.stage == XrRefineStage.running)
                    GestureDetector(
                      key: const ValueKey('xrAiPause'),
                      onTap: runner.pause,
                      child: _xrChip(context, '暂停', filled: false),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  key: const ValueKey('xrAiProg'),
                  value: runner.progress,
                  minHeight: 5,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              if (runner.lastFailedBatch case final fb?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('第 $fb 批失败 · 已重试后跳过，后续批次继续',
                      key: const ValueKey('xrAiErr'),
                      style: TextStyle(fontSize: 9, color: cs.error)),
                ),
              // 中止且一条建议都没攒到：给个收场位，别把进度卡永久钉在面板上。
              if (runner.stage == XrRefineStage.cancelled &&
                  runner.suggestions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Text('已中止 · 失败 ${runner.failedBatches} 批',
                          key: const ValueKey('xrAiAborted'),
                          style: TextStyle(
                              fontSize: 9, color: cs.onSurfaceVariant)),
                      const Spacer(),
                      GestureDetector(
                        key: const ValueKey('xrAiClear'),
                        onTap: () => ref
                            .read(xrRefineHolderProvider.notifier)
                            .state = null,
                        child: Text('清除',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: cs.primary)),
                      ),
                    ],
                  ),
                ),
              if (showRev)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Text('$revLead · 建议 ${runner.suggestions.length} 条',
                          style: TextStyle(
                              fontSize: 9, color: cs.onSurfaceVariant)),
                      const Spacer(),
                      GestureDetector(
                        key: const ValueKey('xrAiShowRev'),
                        onTap: () => showXrRefineReview(context, ref, md5: md5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('查看汇总',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onPrimary)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Widget _xrChip(BuildContext context, String text, {required bool filled}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: filled ? cs.primary.withValues(alpha: .14) : Colors.transparent,
        border:
            Border.all(color: filled ? cs.primary : cs.outlineVariant)),
    child: Text(text,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: filled ? cs.primary : cs.onSurfaceVariant)),
  );
}

/// 汇总审阅弹层（原型 `sheetXrAiReview`）：三段分组 + 勾选 + 写入范围 + 确认写入。
Future<void> showXrRefineReview(BuildContext context, WidgetRef ref,
    {required String md5}) async {
  final runner = ref.read(xrRefineHolderProvider);
  if (runner == null || runner.suggestions.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _XrRefineReviewSheet(runner: runner, md5: md5),
  );
}

class _XrRefineReviewSheet extends ConsumerStatefulWidget {
  const _XrRefineReviewSheet({required this.runner, required this.md5});

  final XrRefineRunner runner;
  final String md5;

  @override
  ConsumerState<_XrRefineReviewSheet> createState() =>
      _XrRefineReviewSheetState();
}

class _XrRefineReviewSheetState extends ConsumerState<_XrRefineReviewSheet> {
  static const Map<XrRefineKind, String> _groups = {
    XrRefineKind.remove: '建议删除',
    XrRefineKind.retype: '建议改类',
    XrRefineKind.add: '建议补词',
  };

  late final List<XrRefineSuggestion> _all = widget.runner.suggestions.toList();
  late final Map<String, bool> _sel = {for (final s in _all) _key(s): true};
  bool _global = false;
  bool _busy = false;

  String _key(XrRefineSuggestion s) => '${s.kind.name}/${s.word}';

  List<XrRefineSuggestion> get _picked =>
      _all.where((s) => _sel[_key(s)] ?? false).toList();

  Future<void> _apply() async {
    if (_busy) return;
    final picked = _picked;
    if (picked.isEmpty) {
      readToast(context, '先勾选要写入的建议');
      return;
    }
    setState(() => _busy = true);
    final dao = ref.read(xrayDaoProvider);
    final c = await xrApplySuggestions(dao, widget.md5, picked,
        toGlobal: _global);
    if (!mounted) return;
    ref.read(xrRefineHolderProvider.notifier).state = null;
    ref.invalidate(xraySnapProvider(widget.md5));
    Navigator.pop(context);
    readToast(context,
        '已写入 ${c.total} 条 · 跳过 ${c.skipped} · ${_global ? '升级为全局，随词库导出带走' : '仅本书，可在词库管理升级'}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final picked = _picked.length;
    final del = _all.where((s) => s.kind == XrRefineKind.remove).length;
    final cls = _all.where((s) => s.kind == XrRefineKind.retype).length;
    final add = _all.where((s) => s.kind == XrRefineKind.add).length;
    return Padding(
      key: const ValueKey('xrAiRev'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('精化结果',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('建议删 $del · 改类 $cls · 补 $add',
                  key: const ValueKey('xrAiRevSum'),
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView(
              key: const ValueKey('xrAiRevBody'),
              shrinkWrap: true,
              children: [
                for (final g in _groups.entries)
                  if (_all.any((s) => s.kind == g.key))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${g.value} · ${_all.where((s) => s.kind == g.key).length}',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          for (final s in _all.where((s) => s.kind == g.key))
                            GestureDetector(
                              key: ValueKey('xrAiR-${_key(s)}'),
                              onTap: () =>
                                  setState(() => _sel[_key(s)] = !(_sel[_key(s)] ?? false)),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                        child: Text(s.word,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700))),
                                    if (s.type != null)
                                      Text('→ ${s.type}',
                                          style: TextStyle(
                                              fontSize: 9.5,
                                              color: cs.onSurfaceVariant)),
                                    const SizedBox(width: 8),
                                    Icon(
                                        _sel[_key(s)] ?? false
                                            ? Icons.check_circle_outline
                                            : Icons.circle_outlined,
                                        size: 16,
                                        color: _sel[_key(s)] ?? false
                                            ? cs.primary
                                            : cs.outlineVariant),
                                  ],
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
          Row(
            children: [
              GestureDetector(
                key: const ValueKey('xrAiSc-book'),
                onTap: () => setState(() => _global = false),
                child: _xrChip(context, '仅本书', filled: !_global),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                key: const ValueKey('xrAiSc-global'),
                onTap: () => setState(() => _global = true),
                child: _xrChip(context, '升级为全局', filled: _global),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            key: const ValueKey('xrAiApplyGo'),
            onTap: _busy ? null : _apply,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: picked == 0 ? .35 : 1),
                  borderRadius: BorderRadius.circular(14)),
              child: Text('确认写入 $picked 条',
                  textAlign: TextAlign.center,
                  key: const ValueKey('xrAiApplyN'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimary)),
            ),
          ),
          GestureDetector(
            key: const ValueKey('xrAiRevCancel'),
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('先不写',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}
