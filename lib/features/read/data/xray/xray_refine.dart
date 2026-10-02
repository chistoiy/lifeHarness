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
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

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

/// 逐批精化执行器（UI 侧只 watch 它的进度与建议，不碰网络）。
/// R3-5：[bookId] 钉死归属书——进度/汇总只随该书显示，换书不得借用（跨书泄漏）。
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

  final List<XrRefineSuggestion> suggestions = <XrRefineSuggestion>[];

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
      final got = await _tryBatch(_batches[i], i + 1);
      if (got == null) {
        failedBatches++;
        _consecFails++;
        lastFailedBatch = i + 1;
        AppLog.add('X-Ray 精化第 ${i + 1}/${_batches.length} 批失败已跳过 · 已重试 $retriedBatches 次',
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
        suggestions.addAll(got);
      }
      doneBatches = i + 1;
      notifyListeners();
      if (pace > Duration.zero) await Future<void>.delayed(pace);
    }
    _running = false;
    stage = _cancelRequested ? XrRefineStage.cancelled : XrRefineStage.done;
    AppLog.add(
        'X-Ray 精化收束：$stage · 批 $doneBatches/${_batches.length} · 失败 $failedBatches · 建议 ${suggestions.length} 条');
    notifyListeners();
  }

  Future<List<XrRefineSuggestion>?> _tryBatch(
      List<XrRefineCandidate> batch, int no) async {
    for (var attempt = 0; attempt <= retryLimit; attempt++) {
      try {
        final j = await caller(batch);
        if (j == null) throw const FormatException('空响应');
        return xrParseRefineJson(j);
      } on Object catch (e) {
        if (attempt < retryLimit) {
          retriedBatches++;
          AppLog.add('X-Ray 精化第 $no 批失败重试 ${attempt + 1}/$retryLimit：$e',
              level: LhLevel.warn);
          continue;
        }
        return null;
      }
    }
    return null;
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
