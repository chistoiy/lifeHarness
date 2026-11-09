/// V1.54.1 批4 · X-Ray 词条 AI 精化（纯逻辑面：切批 → 顺序逐批 → 汇总建议）。
///
/// 口径（需求 V1.54.1 拍板⑥ + 治理计划 §6）：
/// - **每请求体量可控**：按 [budgetChars] 字符预算切批，一条候选词长超预算时自成一批
///   （宁可单批超限也不丢数据）；
/// - **顺序逐批**：不并发（免费 API 上下文小、并发只会互相撞挂），批间可 [pause]/[resume]，
///   暂停只挂起「下一批」，已发出的应答照常收；
/// - **单批失败不拖垮全书**：失败重试 [retryLimit] 次，仍失败即记 failed 批次并跳过；
/// - 本文件**零 UI 零网络**：模型调用经 [XrBatchCaller] 注入（生产＝`AiService.request`
///   的薄封装，测试＝假 caller），所以 FakeAsync 里没有真 HTTP 定时器（见记忆坑）。
/// - 结果**不自动写库**：汇总给 [suggestions]，由 UI 侧审阅确认后走
///   [xrApplySuggestions]（R7：未授权零请求、确认后才落库）。
/// - **R3-3 过程可见性**（V1.59 轮3）：每跑完一批落一条内存明细 [batchLogs]
///   （条数 / 前 3 词名 / 删改补计数 / 用时 / tokens 估算 / 失败归类四档），
///   中止与完成后**明细保留**供回看，只有 [reset] 清场；日志按「X-Ray 精化」可追，
///   一条记录＝落盘一行。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/ai/ai_client.dart' show AiException, AiFailKind;
import '../../../../core/ai/ai_service.dart' show AiBadOutput, AiDenied;
import '../../../../core/database/schema/xray.dart' as xs;
import '../../../../core/logging/app_log.dart';
import 'xray_dao.dart';

/// 与预置词表/校验器同族的六种类型；模型给出集合外的值一律丢弃。
const Set<String> kXrRefineTypes = {'per', 'loc', 'org', 'term', 'abbr', 'book'};

/// 建议动作三分类（对应审阅弹层的三个分组）。
enum XrRefineKind { remove, retype, add }

/// 一条待精化词条（来自 `xray_entity` 行）。
class XrRefineCandidate {
  const XrRefineCandidate({
    required this.name,
    required this.type,
    required this.n,
    required this.chs,
  });

  final String name;
  final String type;
  final int n;
  final int chs;

  /// 送进模型的行式（与提示词里「词 | 类型 | 出现次数 | 跨章数」同构，
  /// 校验器也按这个行首取词做防幻觉比对）。
  String get row => '$name | $type | $n | $chs';

  /// 预算按 UTF-16 长度计（中文一字一码元，够用且不引 characters 包）。
  int get cost => row.length;
}

/// 一条精化建议。[word] 已 trim；retype/add 的 [type] 保证落在 [kXrRefineTypes]。
class XrRefineSuggestion {
  const XrRefineSuggestion({
    required this.kind,
    required this.word,
    this.type,
    this.why,
  });

  final XrRefineKind kind;
  final String word;
  final String? type;
  final String? why;
}

/// 一批词条 → 模型 JSON（返回 null 或抛异常＝本批失败）。
typedef XrBatchCaller = Future<Map<String, dynamic>?> Function(
    List<XrRefineCandidate> batch);

/// 按字符预算切批：累计行长度（含换行）超预算即封批。
List<List<XrRefineCandidate>> xrSplitBatches(
    List<XrRefineCandidate> all, int budgetChars) {
  final out = <List<XrRefineCandidate>>[];
  var cur = <XrRefineCandidate>[];
  var len = 0;
  for (final c in all) {
    final add = cur.isEmpty ? c.cost : c.cost + 1; // +1＝换行符
    if (cur.isNotEmpty && len + add > budgetChars) {
      out.add(cur);
      cur = <XrRefineCandidate>[];
      len = 0;
    }
    cur.add(c);
    len += cur.length == 1 ? c.cost : c.cost + 1;
  }
  if (cur.isNotEmpty) out.add(cur);
  return out;
}

/// 解析模型 JSON 成建议清单（缺段容忍、类型越界丢弃、同键去重）。
List<XrRefineSuggestion> xrParseRefineJson(Map<String, dynamic> j) {
  final out = <XrRefineSuggestion>[];
  final seen = <String>{};
  void push(XrRefineKind k, String w, String? t, String? why) {
    final key = '${k.name}/$w';
    if (w.isEmpty || !seen.add(key)) return;
    out.add(XrRefineSuggestion(kind: k, word: w, type: t, why: why));
  }

  final rm = j['remove'];
  if (rm is List) {
    for (final e in rm) {
      if (e is String) push(XrRefineKind.remove, e.trim(), null, '非实体词');
    }
  }
  final rt = j['retype'];
  if (rt is List) {
    for (final e in rt) {
      if (e is! Map) continue;
      final w = '${e['word']}'.trim();
      final t = '${e['type']}'.trim();
      if (w.isEmpty || !kXrRefineTypes.contains(t)) continue;
      push(XrRefineKind.retype, w, t, '类型改判');
    }
  }
  final ad = j['add'];
  if (ad is List) {
    for (final e in ad) {
      if (e is! Map) continue;
      final w = '${e['word']}'.trim();
      if (w.isEmpty) continue;
      final raw = '${e['type']}'.trim();
      push(XrRefineKind.add, w, kXrRefineTypes.contains(raw) ? raw : 'term',
          e['why'] is String ? '${e['why']}'.trim() : '漏召补词');
    }
  }
  return out;
}

enum XrRefineStage { idle, running, paused, done, cancelled }

/// tokens 估算（中文约 1.5 字/token）。预检卡「约 N tokens」与逐批明细**同一公式**，
/// 收在数据层一处——两处各写一份 1.5，迟早和预估对不上账。
int xrRefineEstTokens(int chars) => (chars / 1.5).round();

/// 一批的预算字符数（行长度含换行，与切批口径一致）。
int xrRefineBatchChars(List<XrRefineCandidate> batch) =>
    batch.fold<int>(0, (a, e) => a + e.cost + 1);

/// R3-3 过程可见性 · 失败归类四档（需求 V1.59 轮3 钉死的口径，UI 直接取 [label]）。
enum XrRefineFailKind { timeout, noResponse, badOutput, unauthorized }

String xrRefineFailLabel(XrRefineFailKind k) => switch (k) {
      XrRefineFailKind.timeout => '超时',
      XrRefineFailKind.noResponse => '端点无响应',
      XrRefineFailKind.badOutput => '输出不合约定',
      XrRefineFailKind.unauthorized => '未授权',
    };

/// 把一次调用抛出的异常归进四档。
///
/// 只认**类型**不认文案：文案是给日志页看的，归类是给明细行看的，绑在一起改文案就红。
/// 认不出的（真·未知异常）落「端点无响应」——四档是封闭集，不许出现「其他」。
XrRefineFailKind xrRefineFailOf(Object e) {
  if (e is AiDenied) return XrRefineFailKind.unauthorized;
  if (e is AiBadOutput || e is FormatException) return XrRefineFailKind.badOutput;
  if (e is TimeoutException) return XrRefineFailKind.timeout;
  if (e is AiException) {
    return switch (e.kind) {
      AiFailKind.timeout => XrRefineFailKind.timeout,
      AiFailKind.unauthorized || AiFailKind.noKey =>
        XrRefineFailKind.unauthorized,
      AiFailKind.badResponse => XrRefineFailKind.badOutput,
      // 404/400/429·503/断连/地址缺失＝端点侧没给出可用应答。
      _ => XrRefineFailKind.noResponse,
    };
  }
  return XrRefineFailKind.noResponse;
}

/// 一批跑完的明细行（R3-3）。**只在内存累积**：中止/完成后保留供回看，不落库、不跨重启。
class XrRefineBatchLog {
  const XrRefineBatchLog({
    required this.i,
    required this.n,
    required this.cnt,
    required this.prev,
    required this.removed,
    required this.retyped,
    required this.added,
    required this.ms,
    required this.tokens,
    this.fail,
  });

  /// 批序（1 基）与总批数。
  final int i;
  final int n;

  /// 本批送出条数与前 3 词名预览（原型 `（a、b、c）`）。
  final int cnt;
  final List<String> prev;

  /// 本批建议计数（失败批恒为 0）。
  final int removed;
  final int retyped;
  final int added;

  /// 本批墙钟用时（含重试；毫秒）与 tokens 估算（[xrRefineEstTokens]）。
  final int ms;
  final int tokens;

  /// 失败归类；null＝本批成功。原始异常摘要只进日志行（`AppLog`），不塞进 UI。
  final XrRefineFailKind? fail;

  bool get failed => fail != null;
  String get failLabel => fail == null ? '' : xrRefineFailLabel(fail!);

  /// 本批建议总数（失败批＝0）。
  int get sum => removed + retyped + added;

  /// 展示口径与原型逐字符对齐：用时一位小数 + `s`，tokens 破千折成 `x.yk`。
  String get secText => (ms / 1000).toStringAsFixed(1);
  String get tokText =>
      tokens >= 1000 ? '${(tokens / 1000).toStringAsFixed(1)}k' : '$tokens';
}

/// 单批结局（内部）：成功带建议，失败带归类＋摘要——不把「失败」压成 null 交给上层猜。
class _XrOutcome {
  const _XrOutcome.ok(this.suggestions)
      : fail = null,
        detail = null;
  const _XrOutcome.fail(this.fail, this.detail) : suggestions = const [];

  final List<XrRefineSuggestion> suggestions;
  final XrRefineFailKind? fail;
  final String? detail;
}

/// 逐批精化执行器（UI 侧只 watch 它的进度与建议，不碰网络）。
/// R3-5：[bookId] 钉死归属书——进度/汇总/明细只随该书显示，换书不得借用（跨书泄漏）。
/// R3-3：[batchLogs] 逐批明细＋[detailOpen] 展开态同为**状态源**，两处 UI 共用同一渲染函数。
class XrRefineRunner extends ChangeNotifier {
  XrRefineRunner({
    required this.bookId,
    required this.caller,
    this.budgetChars = 3000,
    this.retryLimit = 1,
    this.pace = Duration.zero,
  });

  /// 归属书（R3-5）：holder 全局单槽，靠它判「这条进度是不是当前书的」。
  final String bookId;

  final XrBatchCaller caller;

  /// 单请求字符预算（`read.xraiBatchChars`，默认 3000）。
  final int budgetChars;

  /// 单批失败后的重试次数（重试仍失败＝跳过，不整链中断）。
  final int retryLimit;

  /// 批间隔（生产给 0；测试可注入小间隔验暂停续跑时序）。
  final Duration pace;

  XrRefineStage stage = XrRefineStage.idle;
  int totalBatches = 0;
  int doneBatches = 0;
  int failedBatches = 0;
  int retriedBatches = 0;

  /// 最后一次失败的批次序号（1 基，供进度行显示「第 N 批失败」）。
  int? lastFailedBatch;

  /// R3-3 · 逐批明细（内存累积；中止/完成保留，[reset] 清空）。
  final List<XrRefineBatchLog> batchLogs = <XrRefineBatchLog>[];

  /// R3-3 · 明细展开态。**放在状态源里而不是 widget 里**：面板与中心页两处同构，
  /// 各自 setState 会让同一任务在两地一开一合。
  bool detailOpen = false;

  final List<XrRefineSuggestion> suggestions = <XrRefineSuggestion>[];

  /// 顶部汇总「已出建议 删 x · 改 y · 补 z」：随明细逐批累加（与明细同源）。
  int get tallyRemoved => batchLogs.fold<int>(0, (a, e) => a + e.removed);
  int get tallyRetyped => batchLogs.fold<int>(0, (a, e) => a + e.retyped);
  int get tallyAdded => batchLogs.fold<int>(0, (a, e) => a + e.added);

  void toggleDetail() {
    detailOpen = !detailOpen;
    notifyListeners();
  }

  List<List<XrRefineCandidate>> _batches = <List<XrRefineCandidate>>[];
  bool _running = false;
  bool _cancelRequested = false;
  int _consecFails = 0;
  Completer<void>? _gate;

  bool get active =>
      stage == XrRefineStage.running || stage == XrRefineStage.paused;

  /// 进度 0~1（未开始＝0；跑完＝1）。
  double get progress => totalBatches == 0 ? 0 : doneBatches / totalBatches;

  /// 把候选按预算切批并回报批数（预检卡用，不发请求）。
  int plan(List<XrRefineCandidate> all) {
    _batches = xrSplitBatches(all, budgetChars);
    totalBatches = _batches.length;
    return totalBatches;
  }

  /// 逐批跑（[all] 已按 [plan] 同序给出；重复调用＝从当前游标续跑）。
  Future<void> run(List<XrRefineCandidate> all) async {
    if (_running) return;
    if (_batches.isEmpty || _batches.length != totalBatches) plan(all);
    _running = true;
    _cancelRequested = false;
    _consecFails = 0;
    stage = XrRefineStage.running;
    notifyListeners();
    for (var i = doneBatches; i < _batches.length; i++) {
      await _waitGate();
      if (_cancelRequested) break;
      final watch = Stopwatch()..start();
      final got = await _tryBatch(_batches[i], i + 1);
      watch.stop();
      _recordLog(i + 1, _batches[i], got, watch.elapsedMilliseconds);
      if (got.fail case final XrRefineFailKind fk) {
        failedBatches++;
        _consecFails++;
        lastFailedBatch = i + 1;
        AppLog.add(
            'X-Ray 精化第 ${i + 1}/${_batches.length} 批失败已跳过（归类 ${xrRefineFailLabel(fk)}：${got.detail}）'
            '· 已重试 $retriedBatches 次 · 建议 删 $tallyRemoved 改 $tallyRetyped 补 $tallyAdded',
            level: LhLevel.warn);
        // 连续两批都失败＝端点/配额/Key 出问题了：再发下去只烧 token 不出结果，停。
        if (_consecFails >= 2) {
          _cancelRequested = true;
          AppLog.add('X-Ray 精化连续 $_consecFails 批失败，自动中止（保护额度）',
              level: LhLevel.warn);
          break;
        }
      } else {
        _consecFails = 0;
        suggestions.addAll(got.suggestions);
      }
      doneBatches = i + 1;
      notifyListeners();
      if (pace > Duration.zero) await Future<void>.delayed(pace);
    }
    _running = false;
    stage = _cancelRequested ? XrRefineStage.cancelled : XrRefineStage.done;
    AppLog.add(
        'X-Ray 精化收束：$stage · 批 $doneBatches/${_batches.length} · 失败 $failedBatches · 建议 ${suggestions.length} 条'
        '· 明细 ${batchLogs.length} 行');
    notifyListeners();
  }

  /// 明细落表：同一批号重发（游标停在失败批后续跑）＝覆盖那行，不出重复行。
  void _recordLog(int no, List<XrRefineCandidate> batch, _XrOutcome got, int ms) {
    final s = got.suggestions;
    final log = XrRefineBatchLog(
      i: no,
      n: _batches.length,
      cnt: batch.length,
      prev: [for (final c in batch.take(3)) c.name],
      removed: s.where((e) => e.kind == XrRefineKind.remove).length,
      retyped: s.where((e) => e.kind == XrRefineKind.retype).length,
      added: s.where((e) => e.kind == XrRefineKind.add).length,
      ms: ms,
      tokens: xrRefineEstTokens(xrRefineBatchChars(batch)),
      fail: got.fail,
    );
    if (batchLogs.isNotEmpty && batchLogs.last.i == no) {
      batchLogs[batchLogs.length - 1] = log;
    } else {
      batchLogs.add(log);
    }
  }

  Future<_XrOutcome> _tryBatch(
      List<XrRefineCandidate> batch, int no) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retryLimit; attempt++) {
      try {
        final j = await caller(batch);
        if (j == null) {
          // 应答为 null＝端点没给出可用内容（真链路里 core/ai 会抛 badResponse，
          // 这条分支服务注入缝）：归「端点无响应」，不与「输出不合约定」混。
          return _XrOutcome.fail(XrRefineFailKind.noResponse, '空应答');
        }
        return _XrOutcome.ok(xrParseRefineJson(j));
      } on Object catch (e) {
        lastError = e;
        if (attempt < retryLimit) {
          retriedBatches++;
          AppLog.add('X-Ray 精化第 $no 批失败重试 ${attempt + 1}/$retryLimit：$e',
              level: LhLevel.warn);
          continue;
        }
      }
    }
    // 重试用尽＝本批放弃：明细必须带归类，否则用户只看到「少了些词」。
    return _XrOutcome.fail(
        xrRefineFailOf(lastError ?? const FormatException('未知失败')),
        '$lastError'.replaceAll('\n', ' ').trim());
  }

  Future<void> _waitGate() async {
    final g = _gate;
    if (g != null) await g.future;
  }

  /// 暂停：只挂起「下一批」，已发出的应答照常收。
  void pause() {
    if (stage != XrRefineStage.running) return;
    _gate = Completer<void>();
    stage = XrRefineStage.paused;
    AppLog.add('X-Ray 精化已暂停 · 断点在第 $doneBatches 批');
    notifyListeners();
  }

  void resume() {
    if (stage != XrRefineStage.paused) return;
    stage = XrRefineStage.running;
    final g = _gate;
    _gate = null;
    if (g != null && !g.isCompleted) g.complete();
    notifyListeners();
  }

  /// 中止：放行闸门让循环退出，已完成批次的建议保留（不丢已花掉的 token）。
  void cancel() {
    _cancelRequested = true;
    final g = _gate;
    _gate = null;
    if (g != null && !g.isCompleted) g.complete();
    notifyListeners();
  }

  /// 清场重跑用。
  void reset() {
    _batches = <List<XrRefineCandidate>>[];
    totalBatches = 0;
    doneBatches = 0;
    failedBatches = 0;
    retriedBatches = 0;
    lastFailedBatch = null;
    suggestions.clear();
    batchLogs.clear();
    detailOpen = false;
    stage = XrRefineStage.idle;
    notifyListeners();
  }
}

/// 写入结果计数（审阅确认后回报用户）。
class XrAppliedCounts {
  const XrAppliedCounts({
    this.removed = 0,
    this.retyped = 0,
    this.added = 0,
    this.skipped = 0,
  });

  final int removed;
  final int retyped;
  final int added;
  final int skipped;

  int get total => removed + retyped + added;
}

/// 把选中的建议写进词库/实体表。
///
/// 三类动作各走各的既有通道，**零迁移**：
/// - remove → [XrayDao.markDeleted]（实体状态位 + 本书 forbid；[toGlobal] 同时进 GLOBAL 黑名单）；
/// - retype → [XrayDao.setEntityType] 改本书实体类型 + 登记 add 词（随批3 `.xrwords` 导出）；
/// - add → [XrayDao.registerUserWord]（[toGlobal] 直接登记成全局养成词）。
///
/// 实体不存在的 remove/retype 计 [XrAppliedCounts.skipped]——AI 说了但库里没有的词，
/// 不凭空造行（宁少勿造）。
Future<XrAppliedCounts> xrApplySuggestions(
  XrayDao dao,
  String md5,
  List<XrRefineSuggestion> selected, {
  bool toGlobal = false,
}) async {
  var removed = 0, retyped = 0, added = 0, skipped = 0;
  for (final s in selected) {
    switch (s.kind) {
      case XrRefineKind.remove:
        final row = await dao.entityByName(md5, s.word);
        if (row == null) {
          skipped++;
          continue;
        }
        await dao.markDeleted(md5, [row.id], toGlobal: toGlobal);
        removed++;
      case XrRefineKind.retype:
        final t = s.type;
        if (t == null || !kXrRefineTypes.contains(t)) {
          skipped++;
          continue;
        }
        final row = await dao.entityByName(md5, s.word);
        if (row == null) {
          skipped++;
          continue;
        }
        await dao.setEntityType(md5, s.word, t);
        // 类型判词的归属跟「写入范围」走：本书＝只影响本书重解析；升级全局＝跨书复用。
        await dao.putUserWord(
            scope: toGlobal ? xs.xrayScopeGlobal : md5,
            word: s.word,
            action: xs.xrayActAdd,
            type: t);
        retyped++;
      case XrRefineKind.add:
        await dao.registerUserWord(
            md5: md5,
            word: s.word,
            type: s.type ?? 'term',
            global: toGlobal);
        added++;
    }
  }
  AppLog.add(
      'X-Ray 精化写入：删 $removed · 改类 $retyped · 补 $added · 跳过 $skipped（范围=${toGlobal ? '全局' : '本书'}）');
  return XrAppliedCounts(
      removed: removed, retyped: retyped, added: added, skipped: skipped);
}
