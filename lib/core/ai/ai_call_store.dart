/// AI 使用记录存储（V1.53 · 表 `ai_calls`，DB v26）。
///
/// 口径（需求清单 §六 原则 7）：**每次能力调用落一行**，含成功 / 失败 / 用户取消 /
/// 门控拒绝四种状态；发送的 System+User 与返回正文一并留存，供「AI 使用记录」全屏页
/// 按时间·状态·模块·关键词查删。隐私边界：
/// - API Key 永不入库（也不落日志、不进备份明文）；
/// - 正文可整体停记（配置项 `recordBody`）或单独清除（[AiCallStore.clearBodies]）；
/// - 单条正文超过 [AiCallStore.maxBodyChars] 字按上限截断并置 `cut`；
/// - 超保留天数的记录按最旧整批丢弃（[AiCallStore.prune]，0=不限）。
///
/// 落库点在 [AiService.request] 的成功/失败出口（下沉兜底：任何调用方绕行 UI 层也留痕），
/// 门控拒绝由入口单独记一行（拒绝＝零请求，但用户要能查到为什么没发出去）。
library;

import 'package:sqflite/sqflite.dart';

/// 一行 AI 使用记录。正文三段（sys/usr/out）为空串＝未记录正文。
class AiCallRecord {
  const AiCallRecord({
    this.id,
    required this.ts,
    required this.taskId,
    required this.module,
    required this.name,
    required this.status,
    this.inTok = 0,
    this.outTok = 0,
    this.ms = 0,
    this.sys = '',
    this.usr = '',
    this.out = '',
    this.err = '',
    this.cut = false,
  });

  factory AiCallRecord.fromRow(Map<String, Object?> r) => AiCallRecord(
        id: (r['id'] as num?)?.toInt(),
        ts: (r['ts'] as num?)?.toInt() ?? 0,
        taskId: '${r['task_id'] ?? ''}',
        module: '${r['module'] ?? ''}',
        name: '${r['name'] ?? ''}',
        status: '${r['status'] ?? AiCallStore.statusOk}',
        inTok: (r['in_tok'] as num?)?.toInt() ?? 0,
        outTok: (r['out_tok'] as num?)?.toInt() ?? 0,
        ms: (r['ms'] as num?)?.toInt() ?? 0,
        sys: '${r['sys'] ?? ''}',
        usr: '${r['usr'] ?? ''}',
        out: '${r['out'] ?? ''}',
        err: '${r['err'] ?? ''}',
        cut: (r['cut'] as num?)?.toInt() == 1,
      );

  final int? id;

  /// 调用**发起**时刻（epoch 毫秒）。
  final int ts;
  final String taskId;

  /// 模块名与能力点名取自提示词包（新增能力点零改表）。
  final String module;
  final String name;

  /// ok | fail | cancel | denied。
  final String status;
  final int inTok;
  final int outTok;
  final int ms;
  final String sys;
  final String usr;
  final String out;

  /// 失败/拒绝原因（成功时可为提示文案，空=无）。
  final String err;

  /// 正文是否被上限截断过。
  final bool cut;

  bool get hasBody => sys.isNotEmpty || usr.isNotEmpty || out.isNotEmpty;
  bool get ok => status == AiCallStore.statusOk;
}

/// 列表/删除共用的筛选条件（同一处构造 where，防「查到 A 删掉 B」）。
class AiCallFilter {
  const AiCallFilter({
    this.sinceDays,
    this.status,
    this.module,
    this.keyword,
  });

  /// 只看最近 N 个自然日（null=全部；0＝今日）。
  final int? sinceDays;

  /// 状态精确匹配（null=全部）。
  final String? status;

  /// 模块精确匹配（null=全部）。
  final String? module;

  /// 关键词：跨 能力点名/模块/能力点 id/正文三段/原因 模糊匹配。
  final String? keyword;

  bool get isBlank =>
      sinceDays == null && status == null && module == null && keyword == null;
}

/// 一组记录的合计（页首统计行与入口卡共用）。
class AiCallSum {
  const AiCallSum({this.n = 0, this.inTok = 0, this.outTok = 0, this.bad = 0});
  final int n;
  final int inTok;
  final int outTok;

  /// 未成功数＝失败 + 取消（门控拒绝没发出去，不计入"未成功"以免与"失败"混读）。
  final int bad;
  int get tokens => inTok + outTok;
}

class AiCallStore {
  AiCallStore(this.db);

  final Database db;

  static const String table = 'ai_calls';

  static const String statusOk = 'ok';
  static const String statusFail = 'fail';
  static const String statusCancel = 'cancel';
  static const String statusDenied = 'denied';

  /// 单条正文上限（字数口径＝Dart 字符数，中文按字计）。
  static const int maxBodyChars = 8000;

  Future<int> insert(AiCallRecord r) => db.insert(table, {
        'ts': r.ts,
        'task_id': r.taskId,
        'module': r.module,
        'name': r.name,
        'status': r.status,
        'in_tok': r.inTok,
        'out_tok': r.outTok,
        'ms': r.ms,
        'sys': _clip(r.sys, r),
        'usr': _clip(r.usr, r),
        'out': _clip(r.out, r),
        'err': _clip(r.err, r),
        'cut': (r.cut ? 1 : 0),
      });

  /// 截断只发生在写入前（读回来就是库里真实存的内容，不做二次加工）。
  String _clip(String s, AiCallRecord r) =>
      s.length <= maxBodyChars ? s : s.substring(0, maxBodyChars);

  /// 自然日 00:00 起算的第 N 天窗口下界（0＝今天，7＝最近 7 天含今天）。
  /// 与原型 `r.d < n` 同口径：按「日偏移」而不是「减 n 天」。
  static DateTime _dayCutoff(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return days <= 0 ? today : today.subtract(Duration(days: days - 1));
  }

  /// 条件 SQL（**不含 WHERE 关键字**）+ 参数。
  /// [query]/[sumOf]/[moduleCounts]/[deleteFiltered] 全部走这里，
  /// 保证「筛出来的」与「删掉的」是同一批行。
  (String cond, List<Object?> args) _where(AiCallFilter f) {
    final parts = <String>[];
    final args = <Object?>[];
    if (f.sinceDays != null) {
      parts.add('ts >= ?');
      args.add(_dayCutoff(f.sinceDays!).millisecondsSinceEpoch);
    }
    if (f.status != null) {
      parts.add('status = ?');
      args.add(f.status);
    }
    if (f.module != null) {
      parts.add('module = ?');
      args.add(f.module);
    }
    final kw = f.keyword?.trim() ?? '';
    if (kw.isNotEmpty) {
      final like = '%${kw.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      parts.add('(name LIKE ? OR module LIKE ? OR task_id LIKE ?'
          ' OR sys LIKE ? OR usr LIKE ? OR out LIKE ? OR err LIKE ?)');
      args.addAll([like, like, like, like, like, like, like]);
    }
    return (parts.join(' AND '), args);
  }

  /// rawQuery 侧的条件前缀（条件为空串时不拼 WHERE）。
  static String _sqlWhere(String cond) => cond.isEmpty ? '' : 'WHERE $cond';

  Future<List<AiCallRecord>> query(AiCallFilter f, {int? limit}) async {
    final (cond, args) = _where(f);
    final rows = await db.query(table,
        where: cond.isEmpty ? null : cond,
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'ts DESC, id DESC',
        limit: limit);
    return rows.map(AiCallRecord.fromRow).toList();
  }

  Future<AiCallSum> sumOf(AiCallFilter f) async {
    final (cond, args) = _where(f);
    final rows = await db.rawQuery(
        'SELECT status, in_tok, out_tok FROM $table ${_sqlWhere(cond)}',
        args.isEmpty ? null : args);
    var inT = 0, outT = 0, bad = 0;
    for (final r in rows) {
      inT += (r['in_tok'] as num?)?.toInt() ?? 0;
      outT += (r['out_tok'] as num?)?.toInt() ?? 0;
      final st = '${r['status']}';
      if (st == statusFail || st == statusCancel) bad++;
    }
    return AiCallSum(n: rows.length, inTok: inT, outTok: outT, bad: bad);
  }

  /// 模块分布（筛选胶囊里「模块 · 名称 条数」的候选集）。
  Future<List<(String module, int n)>> moduleCounts(int? sinceDays) async {
    final f = AiCallFilter(sinceDays: sinceDays);
    final (cond, args) = _where(f);
    final rows = await db.rawQuery(
        'SELECT module, COUNT(*) AS n FROM $table ${_sqlWhere(cond)} GROUP BY module ORDER BY module',
        args.isEmpty ? null : args);
    return rows
        .map((r) => ('${r['module']}', (r['n'] as num?)?.toInt() ?? 0))
        .toList();
  }

  Future<int> deleteOne(int id) =>
      db.delete(table, where: 'id = ?', whereArgs: [id]);

  Future<int> deleteFiltered(AiCallFilter f) async {
    final (cond, args) = _where(f);
    if (cond.isEmpty) return clearAll();
    return db.delete(table, where: cond, whereArgs: args.isEmpty ? null : args);
  }

  Future<int> clearAll() => db.delete(table);

  /// 只清正文，用量与状态行保留（「记录设置 → 清除已存正文」）。
  Future<int> clearBodies() =>
      db.update(table, {'sys': '', 'usr': '', 'out': '', 'cut': 0});

  /// 丢弃超过 [keepDays] 天的记录（0/null=不限）。返回删除条数。
  /// 窗口口径与筛选同源（自然日偏移），避免「筛到 30 天却删不掉」。
  Future<int> prune(int? keepDays) async {
    if (keepDays == null || keepDays <= 0) return 0;
    return db.delete(table,
        where: 'ts < ?', whereArgs: [_dayCutoff(keepDays).millisecondsSinceEpoch]);
  }

  /// 正文占用字节估算（设置页展示「当前占用 x.x MB」）。
  Future<int> bodyBytes() async {
    final rows = await db
        .rawQuery('SELECT COALESCE(SUM(LENGTH(sys)+LENGTH(usr)+LENGTH(out)'
        '+LENGTH(err)),0) AS b FROM $table');
    return (rows.first['b'] as num?)?.toInt() ?? 0;
  }
}
