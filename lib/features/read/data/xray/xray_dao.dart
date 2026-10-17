/// X-Ray 四表唯一出口（需求 V1.54 · 设计书 §6/§7）
///
/// **红线（照 E 批 `todo_trash_guard_test.dart` 先例，由 `test/xray_table_guard_test.dart` 源码级拦死）**：
/// `xray_task / xray_entity / xray_mention / xray_userdict` 与 `books.md5` 只许本文件直碰；
/// 其它地方要用就在这里加方法，不要 copy 一句 SQL 过去。
///
/// 语义要点：
/// - 一切归属键是 `book_md5`（内容指纹），不是 `books.id`——同一本书的多条架位共享同一份索引（§13 路径 A）；
/// - 用户层是**覆盖层**：`status` / `xray_userdict` 永远叠在解析产出之上，重解析不丢用户整理结果（§7）；
/// - 「删除=状态位」不是降分：`status='deleted'` 的行读侧一律过滤掉，阈值再低也不复活（F8②）。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/schema.dart';
import '../../../../core/database/schema/xray.dart' as xs;
import 'xray_engine.dart';
import 'xray_lexicon.dart';

/// 任务态（`xray_task` 一行的视图）。
class XrayTaskRow {
  const XrayTaskRow({
    required this.md5,
    required this.totalCh,
    required this.rangeStart,
    required this.rangeEnd,
    required this.status,
    required this.processedCh,
    required this.scoreMeta,
  });

  final String md5;
  final int totalCh;
  final int rangeStart;
  final int rangeEnd;
  final String status;
  final int processedCh;
  final String? scoreMeta;

  bool get isDone => status == xs.xrayStatusSuccess;
  bool get isRunning => status == xs.xrayStatusRunning;
}

/// 词条行（读侧给面板用；`id` 为库主键）。
class XrayEntityRow {
  const XrayEntityRow({
    required this.id,
    required this.name,
    required this.type,
    required this.n,
    required this.chs,
    required this.score,
    required this.channels,
    required this.status,
    required this.aliases,
    this.aiDesc,
    required this.firstCh,
    required this.firstPara,
    required this.tocFlag,
  });

  final int id;
  final String name;
  final String type;
  final int n;
  final int chs;
  final double score;
  final int channels;
  final String status;
  final List<String> aliases;

  /// 词条简介（批A 面板行/详情的 desc 行；AI 二期回写，一期多为空）。
  final String? aiDesc;
  final int? firstCh;
  final int? firstPara;
  final bool tocFlag;

  /// 批A 面板判定「我的词条」徽：用户加词来源而非解析产出。
  bool get userAdded => status == xs.xrayEntityUserAdded;
}

/// 出场锚点（页码由调用方按当前排版现算，这里只有章+段）。
class XrayAnchorRow {
  const XrayAnchorRow(this.entityId, this.ch, this.para, this.snippet);
  final int entityId;
  final int ch;
  final int para;
  final String? snippet;
}

/// 落库用的词条写入模型（批A：引擎实体跨 isolate 回报后不再可构造，
/// 这里承接「词条 + 全量锚点」的形状；字段与 `xray_entity` 一一对应）。
class XrayWriteEntity {
  const XrayWriteEntity({
    required this.name,
    required this.type,
    required this.n,
    required this.chs,
    required this.score,
    required this.channels,
    required this.tocFlag,
    required this.aliases,
    required this.anchors,
  });

  final String name;
  final String type;
  final int n;
  final int chs;
  final double score;
  final int channels;
  final bool tocFlag;
  final List<String> aliases;
  final List<XrayMention> anchors;

  /// `_IsoXrayWorker` 协议里的平铺 Map（键名见 xray_scheduler 的 `_payload`）。
  static XrayWriteEntity fromMap(Map<String, Object?> m) => XrayWriteEntity(
        name: m['name'] as String,
        type: m['type'] as String,
        n: m['n'] as int,
        chs: m['chs'] as int,
        score: (m['score'] as num).toDouble(),
        channels: m['ch'] as int,
        tocFlag: (m['toc'] as int) != 0,
        aliases: (m['al'] as List).cast<String>(),
        anchors: [
          for (final a in (m['m'] as List))
            XrayMention(
                (a as List)[0] as int, (a)[1] as int, (a)[2] as String?),
        ],
      );
}

/// 面板渲染所需的整包快照（词条已按分值倒序；锚点按实体分组、章段升序）。
class XrayPanelData {
  const XrayPanelData({
    required this.task,
    required this.entities,
    required this.anchors,
  });

  final XrayTaskRow? task;
  final List<XrayEntityRow> entities;
  final Map<int, List<XrayAnchorRow>> anchors;

  static const XrayPanelData empty =
      XrayPanelData(task: null, entities: [], anchors: {});
}

/// GLOBAL 养成词库行（批2 词库管理页数据面；scope 恒为 GLOBAL）。
class XrayDictRow {
  const XrayDictRow({
    required this.word,
    required this.action,
    this.type,
    this.target,
    this.patternHint,
    required this.createTime,
  });

  final String word;
  final String action;
  final String? type;
  final String? target;
  final String? patternHint;
  final int createTime;
}

/// `.xrwords` 包内的单条养成词（批3 导入载荷；与 [XrayDictRow] 同构但 ts 可缺省）。
class XrayDictEntry {
  const XrayDictEntry({
    required this.word,
    required this.action,
    this.type,
    this.target,
    this.patternHint,
    int? createTime,
  }) : createTime = createTime ?? 0;

  final String word;
  final String action;
  final String? type;
  final String? target;
  final String? patternHint;
  final int createTime;
}

/// X-Ray 数据访问。
class XrayDao {
  const XrayDao(this._db);

  final Database _db;

  // ---------------------------------------------------------------- books.md5

  /// 书架条目的内容指纹（未补算过＝null，走懒补算）。
  Future<String?> bookMd5(String bookId) async {
    final r = await _db.query(DbSchema.tBooks,
        columns: ['md5'], where: 'id = ?', whereArgs: [bookId], limit: 1);
    if (r.isEmpty) return null;
    return r.first['md5'] as String?;
  }

  /// 回填内容指纹。同 MD5 已出现在别的架位时**不覆盖**（复用判定交给上层，F9）。
  Future<void> setBookMd5(String bookId, String md5) =>
      _db.update(DbSchema.tBooks, {'md5': md5}, where: 'id = ?', whereArgs: [bookId]);

  /// 按 MD5 找已有索引的架位条目（F9 复用提示用；返回空＝没有可复用的）。
  Future<List<String>> bookIdsWithMd5(String md5, {String? exceptBookId}) async {
    final where = 'md5 = ?';
    final args = <Object?>[md5];
    final rows = exceptBookId == null
        ? await _db.query(DbSchema.tBooks, columns: ['id'], where: where, whereArgs: args)
        : await _db.query(DbSchema.tBooks,
            columns: ['id'],
            where: '$where AND id <> ?',
            whereArgs: [...args, exceptBookId]);
    return rows.map((r) => r['id'] as String).toList();
  }

  // ---------------------------------------------------------------- xray_task

  Future<XrayTaskRow?> task(String md5) async {
    final r = await _db.query(DbSchema.tXrayTask, where: 'book_md5 = ?', whereArgs: [md5], limit: 1);
    if (r.isEmpty) return null;
    final m = r.first;
    return XrayTaskRow(
      md5: md5,
      totalCh: m['total_ch'] as int? ?? 0,
      rangeStart: m['range_start'] as int? ?? 0,
      rangeEnd: m['range_end'] as int? ?? 0,
      status: m['status'] as String? ?? xs.xrayStatusPending,
      processedCh: m['processed_ch'] as int? ?? 0,
      scoreMeta: m['score_meta'] as String?,
    );
  }

  /// 任务态落库（存在则更新）。`update_time` 一律现算，别让调用方忘记传。
  Future<void> upsertTask({
    required String md5,
    required int totalCh,
    required int rangeStart,
    required int rangeEnd,
    required String status,
    int processedCh = 0,
    String? scoreMeta,
  }) =>
      _db.insert(DbSchema.tXrayTask, {
        'book_md5': md5,
        'total_ch': totalCh,
        'range_start': rangeStart,
        'range_end': rangeEnd,
        'status': status,
        'processed_ch': processedCh,
        'score_meta': scoreMeta,
        'update_time': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// 断点推进（只动 processed_ch/status，其余保持不变）。
  Future<void> patchTaskProgress(
          {required String md5, required int processedCh, String? status}) =>
      _db.update(
          DbSchema.tXrayTask,
          {
            'processed_ch': processedCh,
            'status': ?status,
            'update_time': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'book_md5 = ?',
          whereArgs: [md5]);

  /// 冷启动收尸：App 单进程 ⇒ 库里残留的 `running` 只可能是上个进程被杀/崩溃
  /// 留下的死任务。不收则面板走 `else` 分支谎报「已解析 x/x 章」（真机 15:43 见
  /// 已解析 34/34 而词条 0），书架角标谎报「解析中」，且没有任何恢复入口。
  /// 一律转 `pause`：断点语义成立，面板头给「继续生成」。
  Future<int> reapStaleRunning() => _db.update(
        DbSchema.tXrayTask,
        {
          'status': xs.xrayStatusPause,
          'update_time': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'status = ?',
        whereArgs: [xs.xrayStatusRunning],
      );

  // -------------------------------------------------------------- xray_entity

  /// 引擎产出整批写入（**同事务**：词条与锚点必须一起成，否则面板会点到空锚点）。
  ///
  /// 幂等与「用户结果不丢」两件事同时成立（§7）：
  /// - 按 `(md5,name)` upsert：重解析不产生第二条；
  /// - 计数/跨章/分值/通道**每次刷新**（否则重跑后分数是旧的）；
  /// - `status` 只在解析产出上写 `active`，**已经是用户状态**（user_added/deleted/merged_into）的行保留原状态；
  /// - 锚点整批替换（先删后插），避免重跑叠加出双倍出场。
  Future<void> writeChapterResult({
    required String md5,
    required List<XrayEntity> entities,
    required Map<String, List<XrayMention>> anchorsByName,
  }) =>
      writeRunResult(
        md5: md5,
        rows: [
          for (final e in entities)
            XrayWriteEntity(
              name: e.name,
              type: e.type.code,
              n: e.n,
              chs: e.chs,
              score: e.score,
              channels: e.channels,
              tocFlag: e.tocFlag,
              aliases: e.aliases,
              anchors: anchorsByName[e.name] ?? e.mentions,
            ),
        ],
      );

  /// 调度器（跨 isolate 回报的平铺结果）落库的同一出口。
  /// R3-9：旧实现＝整本书单事务 + 逐枚 await（真机 774 枚×几十锚＝上万次串行往返，
  /// 锁库约一分钟，期间一切读排队 → 阅读器白屏 + logcat「database has been locked」刷屏）。
  /// 现改为**分小块事务（64 枚/块）+ Batch 合并提交 + 块间让帧**；语义不变：
  /// 新行 active、已有行保留用户状态、锚点删旧重建（段级去重、优先带 snippet）。
  /// 前提＝同一次结果内 name 唯一（引擎按名字典聚合产出，天然成立）。
  Future<void> writeRunResult({
    required String md5,
    required List<XrayWriteEntity> rows,
  }) async {
    const chunkSize = 64;
    for (var off = 0; off < rows.length; off += chunkSize) {
      final chunk =
          rows.sublist(off, off + chunkSize > rows.length ? rows.length : off + chunkSize);
      await _db.transaction((txn) async {
        final ph = List.generate(chunk.length, (_) => '?').join(',');
        final names = [for (final e in chunk) e.name];
        // 一趟取回本块已有行（状态保留 + id），替代逐枚 SELECT。
        final old = await txn.query(DbSchema.tXrayEntity,
            columns: ['id', 'status', 'name'],
            where: 'book_md5 = ? AND name IN ($ph)',
            whereArgs: [md5, ...names]);
        final byName = {for (final r in old) r['name'] as String: r};
        final b1 = txn.batch();
        for (final e in chunk) {
          final first = e.anchors.isEmpty ? null : e.anchors.first;
          final values = <String, Object?>{
            'book_md5': md5,
            'name': e.name,
            'type': e.type,
            'n': e.n,
            'chs': e.chs,
            'score': e.score,
            'src_channels': e.channels,
            'aliases': jsonEncode(e.aliases),
            'first_ch': first?.ch,
            'first_para': first?.para,
            'toc_flag': e.tocFlag ? 1 : 0,
          };
          final ex = byName[e.name];
          if (ex == null) {
            b1.insert(DbSchema.tXrayEntity,
                {...values, 'status': xs.xrayEntityActive});
          } else {
            final id = ex['id'] as int;
            // 用户状态优先：解析无权把「用户屏蔽」洗回在册，也无权改走「用户加词」的来源标记。
            final keep = ex['status'] as String;
            b1.update(
                DbSchema.tXrayEntity,
                {
                  ...values,
                  'status':
                      keep == xs.xrayEntityActive ? xs.xrayEntityActive : keep,
                },
                where: 'id = ?',
                whereArgs: [id]);
            b1.delete(DbSchema.tXrayMention,
                where: 'book_md5 = ? AND entity_id = ?', whereArgs: [md5, id]);
          }
        }
        await b1.commit(noResult: true);
        // 二趟取回本块 id（新插入行此刻可见）→ 锚点批量插入。
        final idRows = await txn.query(DbSchema.tXrayEntity,
            columns: ['id', 'name'],
            where: 'book_md5 = ? AND name IN ($ph)',
            whereArgs: [md5, ...names]);
        final ids = {for (final r in idRows) r['name'] as String: r['id'] as int};
        final b2 = txn.batch();
        for (final e in chunk) {
          final id = ids[e.name];
          if (id == null) continue;
          for (final m in _dedupeAnchors(e.anchors)) {
            b2.insert(DbSchema.tXrayMention, {
              'entity_id': id,
              'book_md5': md5,
              'ch': m.ch,
              'para': m.para,
              'snippet': m.snippet,
            });
          }
        }
        await b2.commit(noResult: true);
      });
      // 块间让帧：给面板/kv/计时等排队读插队窗口，白屏不再复现。
      // 只在「还有下一块」时延时——尾块后挂真定时器会把链尾拖出微任务域，
      // 假通道测试（xray_panel 全链路微任务口径）会被饿死成假红。
      if (off + chunkSize < rows.length) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }
  }

  /// 单词回填路径的逐条锚点插入（补扫只有一枚实体、量小；批量面走 writeRunResult）。
  Future<void> _insertAnchors(Transaction txn, String md5, int entityId,
      List<XrayMention> anchors) async {
    for (final m in _dedupeAnchors(anchors)) {
      await txn.insert(DbSchema.tXrayMention, {
        'entity_id': entityId,
        'book_md5': md5,
        'ch': m.ch,
        'para': m.para,
        'snippet': m.snippet,
      });
    }
  }

  /// **段级去重**：引擎侧 `hit`/`anchorOnly` 每次出现都记一条，多通道合并
  /// （`win.mentions.addAll`）还会带来非相邻重复；真机表现＝F5 出场列表整行
  /// 重复、迷你分布条同位叠点（2026-10-01 人类简史「几乎」第一章段 42 连列两次）。
  /// 提及数 `n` 仍按出现次数计，这里只保证锚点一格一条（优先保留带 snippet 的那条）。
  static List<XrayMention> _dedupeAnchors(List<XrayMention> anchors) {
    final byPos = <String, XrayMention>{};
    for (final m in anchors) {
      final k = '${m.ch}:${m.para}';
      final old = byPos[k];
      if (old == null) {
        byPos[k] = m;
      } else if (old.snippet == null && m.snippet != null) {
        byPos[k] = XrayMention(m.ch, m.para, m.snippet);
      }
    }
    return byPos.values.toList();
  }

  /// 面板主查询：某类型按置信分倒序；读侧口径＝**在册两条状态**（active/user_added），
  /// `deleted` 与 `merged_into:*` 一律不出现（F8② 的读侧口径）。
  Future<List<XrayEntityRow>> entitiesOfType(String md5, String type,
      {int? minScore, int limit = 400}) async {
    final rows = await _db.query(DbSchema.tXrayEntity,
        where: 'book_md5 = ? AND type = ? AND status IN (?, ?)'
            '${minScore != null ? ' AND score >= ?' : ''}',
        whereArgs: [md5, type, xs.xrayEntityActive, xs.xrayEntityUserAdded, ?minScore],
        orderBy: 'score DESC',
        limit: limit);
    return rows.map(_row).toList();
  }

  /// 类内搜索（F4 顶部搜索框）。
  Future<List<XrayEntityRow>> searchEntities(String md5, String q,
      {String? type}) async {
    final rows = await _db.query(DbSchema.tXrayEntity,
        where: 'book_md5 = ? AND status IN (?, ?) AND name LIKE ?'
            '${type != null ? ' AND type = ?' : ''}',
        whereArgs: [
          md5, xs.xrayEntityActive, xs.xrayEntityUserAdded, '$q%', ?type,
        ],
        orderBy: 'score DESC',
        limit: 200);
    return rows.map(_row).toList();
  }

  /// 出场列表（F5 跳转用）：按章段排序，snippet 只在前若干条有值。
  Future<List<XrayAnchorRow>> anchorsOf(String md5, int entityId) async {
    final rows = await _db.query(DbSchema.tXrayMention,
        columns: ['ch', 'para', 'snippet'],
        where: 'book_md5 = ? AND entity_id = ?',
        whereArgs: [md5, entityId],
        orderBy: 'ch ASC, para ASC');
    return rows
        .map((r) => XrayAnchorRow(entityId, r['ch'] as int, r['para'] as int,
            r['snippet'] as String?))
        .toList();
  }

  /// 已解析章数（面板顶部「已解析 x/y 章」同源，避免 UI 自己数锚点）。
  Future<int> parsedChapterCount(String md5) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(DISTINCT ch) AS c FROM ${DbSchema.tXrayMention} WHERE book_md5 = ?', [md5]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<int> entityCount(String md5, {String? type}) async {
    final r = type == null
        ? await _db.rawQuery(
            'SELECT COUNT(*) AS c FROM ${DbSchema.tXrayEntity} '
            'WHERE book_md5 = ? AND status IN (?, ?)',
            [md5, xs.xrayEntityActive, xs.xrayEntityUserAdded])
        : await _db.rawQuery(
            'SELECT COUNT(*) AS c FROM ${DbSchema.tXrayEntity} '
            'WHERE book_md5 = ? AND type = ? AND status IN (?, ?)',
            [md5, type, xs.xrayEntityActive, xs.xrayEntityUserAdded]);
    return (r.first['c'] as int?) ?? 0;
  }

  /// 面板主查询的「全部」段（批A F4）：一次取回六类在册词条，UI 侧分桶。
  /// 上限 2000＝预研单书实体 500~2000 画像的宽余量（大书极端时截尾，
  /// 排序分值低的自然落在尾部，与「低置信折叠」消化路径同侧）。
  /// [presetView]（批2 开关关＝纯预置视角）：只看引擎原始产出——`user_added`
  /// 不算预置产物要隐掉，`deleted` 是「被用户屏蔽的原始行」要恢复；merged 死行两态都不出现。
  Future<List<XrayEntityRow>> allEntities(String md5,
      {int limit = 2000, bool presetView = false}) async {
    final rows = await _db.query(DbSchema.tXrayEntity,
        where: presetView
            ? 'book_md5 = ? AND (status = ? OR status = ?)'
            : 'book_md5 = ? AND status IN (?, ?)',
        whereArgs: presetView
            ? [md5, xs.xrayEntityActive, xs.xrayEntityDeleted]
            : [md5, xs.xrayEntityActive, xs.xrayEntityUserAdded],
        orderBy: 'score DESC',
        limit: limit);
    return rows.map(_row).toList();
  }

  /// 单条词条点查（选区迷你卡/详情刷新用）。
  Future<XrayEntityRow?> entityById(String md5, int id) async {
    final rows = await _db.query(DbSchema.tXrayEntity,
        where: 'book_md5 = ? AND id = ? AND status IN (?, ?)',
        whereArgs: [md5, id, xs.xrayEntityActive, xs.xrayEntityUserAdded],
        limit: 1);
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// 行内迷你分布条数据源（批A）：整书锚点一把取回按实体分组。
  /// 体积口径见 §6：单书 0.1~1MB，面板只在 X-Ray 段激活时查这一发。
  Future<Map<int, List<XrayAnchorRow>>> anchorsByEntity(String md5) async {
    final rows = await _db.query(DbSchema.tXrayMention,
        columns: ['entity_id', 'ch', 'para', 'snippet'],
        where: 'book_md5 = ?',
        whereArgs: [md5],
        orderBy: 'ch ASC, para ASC');
    final out = <int, List<XrayAnchorRow>>{};
    for (final r in rows) {
      final id = r['entity_id'] as int;
      (out[id] ??= <XrayAnchorRow>[]).add(
          XrayAnchorRow(id, r['ch'] as int, r['para'] as int, r['snippet'] as String?));
    }
    return out;
  }

  // ------------------------------------------------- 批C .xraybak（F10）

  /// 导出包（F10）：按 md5 分册打包四表（含 deleted/merged 状态与 GLOBAL 词典——
  /// 用户整理结果是要分享的资产，原样随行）。
  Future<Map<String, Object?>> exportBundle() async {
    final tasks = await _db.query(DbSchema.tXrayTask);
    final ents = await _db.query(DbSchema.tXrayEntity);
    final ments = await _db.query(DbSchema.tXrayMention);
    final dict = await _db.query(DbSchema.tXrayUserdict);
    final md5s = <String>{
      for (final t in tasks) t['book_md5'] as String,
      for (final e in ents) e['book_md5'] as String,
    }..removeWhere((m) => m.isEmpty);
    final titleByMd5 = <String, String>{};
    if (md5s.isNotEmpty) {
      final rows = await _db.query(DbSchema.tBooks,
          columns: ['title', 'md5'],
          where: 'md5 IN (${List.filled(md5s.length, '?').join(',')})',
          whereArgs: md5s.toList());
      for (final r in rows) {
        titleByMd5.putIfAbsent(r['md5'] as String, () => r['title'] as String);
      }
    }
    List<List<Map<String, Object?>>> byMd5(List<Map<String, Object?>> rows,
            {bool keepId = false}) =>
        [
          for (final md5 in md5s)
            [
              for (final r in rows)
                if (r['book_md5'] == md5)
                  keepId ? r : _strip(r, ['id'])
            ],
        ];
    final groupedT = byMd5(tasks);
    // 实体行带 id 出包：导入侧按旧→新 id 重映射 mention.entity_id（跨设备 id 不复用）。
    final groupedE = byMd5(ents, keepId: true);
    final groupedM = byMd5(ments);
    return {
      'v': 1,
      'exported_at': DateTime.now().millisecondsSinceEpoch,
      'indices': [
        for (final (i, md5) in md5s.indexed)
          {
            'md5': md5,
            'title': titleByMd5[md5] ?? '',
            'task': groupedT[i].isEmpty ? null : groupedT[i].first,
            'entities': groupedE[i],
            'mentions': groupedM[i],
          },
      ],
      'userdict': [for (final d in dict) _strip(d, ['id'])],
    };
  }

  static Map<String, Object?> _strip(
          Map<String, Object?> row, List<String> keys) =>
      {for (final e in row.entries) if (!keys.contains(e.key)) e.key: e.value};

  /// 导入包（F10）：逐册 **MD5 一致性校验**（task/entities/mentions 必须同指纹，
  /// 不符整册拒收）；通过后整册替换本机数据（覆盖确认在 UI 侧先行）。
  Future<({int books, int bad, List<String> md5s})> importBundle(
      Map<String, Object?> bundle) async {
    if (bundle['v'] != 1) {
      throw const FormatException('不支持的 .xraybak 版本');
    }
    final list = (bundle['indices'] as List?) ?? const [];
    var books = 0, bad = 0;
    final md5s = <String>[];
    final dict = ((bundle['userdict'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    for (final raw in list) {
      final item = (raw as Map).cast<String, Object?>();
      final md5 = item['md5'] as String? ?? '';
      if (!_md5Shape(md5)) {
        bad++;
        continue;
      }
      final ents =
          ((item['entities'] as List?) ?? const []).cast<Map<String, Object?>>();
      final ments =
          ((item['mentions'] as List?) ?? const []).cast<Map<String, Object?>>();
      final task = item['task'];
      final same = ents.every((e) => e['book_md5'] == md5) &&
          ments.every((m) => m['book_md5'] == md5) &&
          (task == null || (task as Map<String, Object?>)['book_md5'] == md5);
      if (!same) {
        bad++; // 册内指纹不齐＝包被拼改，整册拒收
        continue;
      }
      await _db.transaction((txn) async {
        await txn.delete(DbSchema.tXrayMention,
            where: 'book_md5 = ?', whereArgs: [md5]);
        await txn.delete(DbSchema.tXrayEntity,
            where: 'book_md5 = ?', whereArgs: [md5]);
        await txn.delete(DbSchema.tXrayTask,
            where: 'book_md5 = ?', whereArgs: [md5]);
        final idMap = <Object?, Object?>{};
        for (final e in ents) {
          final old = e['id'];
          final row = _strip(e, ['id']);
          final newId = await txn.insert(DbSchema.tXrayEntity, row);
          if (old != null) idMap[old] = newId;
        }
        for (final m in ments) {
          final mapped = idMap[m['entity_id']];
          if (mapped == null) continue;
          await txn.insert(DbSchema.tXrayMention,
              {...m, 'entity_id': mapped});
        }
        if (task != null) {
          await txn.insert(DbSchema.tXrayTask,
              (task as Map<Object?, Object?>).cast<String, Object?>());
        }
        for (final d in dict) {
          final scope = d['scope'] as String? ?? '';
          if (scope != xs.xrayScopeGlobal && scope != md5) continue;
          await txn.insert(DbSchema.tXrayUserdict, d,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      books++;
      md5s.add(md5);
    }
    return (books: books, bad: bad, md5s: md5s);
  }

  static bool _md5Shape(String m) =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(m);

  /// 设置页备份行摘要：已有索引的本机书数。
  Future<int> indexedBookCount() async {
    final r = await _db.rawQuery(
        'SELECT COUNT(DISTINCT book_md5) AS c FROM ${DbSchema.tXrayEntity}');
    return (r.first['c'] as int?) ?? 0;
  }

  /// 书架角标（F7）：一张联合查询取回**所有**有任务态的架位（md5→books.id 多架位共享）。
  /// 书架每轮刷新只打一发，不在每本封面各查一次。
  Future<Map<String, XrayTaskRow>> taskByBookIds() async {
    final rows = await _db.rawQuery(
      'SELECT b.id AS book_id, t.* FROM ${DbSchema.tBooks} b '
      'JOIN ${DbSchema.tXrayTask} t ON b.md5 = t.book_md5 '
      'WHERE b.md5 IS NOT NULL',
    );
    final out = <String, XrayTaskRow>{};
    for (final m in rows) {
      out[m['book_id'] as String] = XrayTaskRow(
        md5: m['book_md5'] as String,
        totalCh: m['total_ch'] as int? ?? 0,
        rangeStart: m['range_start'] as int? ?? 0,
        rangeEnd: m['range_end'] as int? ?? 0,
        status: m['status'] as String? ?? xs.xrayStatusPending,
        processedCh: m['processed_ch'] as int? ?? 0,
        scoreMeta: m['score_meta'] as String?,
      );
    }
    return out;
  }

  /// 重置索引＝清该书三层数据（F3）。**不动用户词典**：那是用户资产，
  /// 「重置」的语义是重跑解析，不是抹掉用户加词/屏蔽。
  Future<void> resetBook(String md5) => _db.transaction((txn) async {
        await txn.delete(DbSchema.tXrayMention, where: 'book_md5 = ?', whereArgs: [md5]);
        await txn.delete(DbSchema.tXrayEntity, where: 'book_md5 = ?', whereArgs: [md5]);
        await txn.delete(DbSchema.tXrayTask, where: 'book_md5 = ?', whereArgs: [md5]);
      });

  // ------------------------------------------------- 批B 自学习（F8 · 写时物化）

  /// 按 (md5,name) 点查（加词幂等与选区命中判重用）。
  Future<XrayEntityRow?> entityByName(String md5, String name) async {
    final rows = await _db.query(DbSchema.tXrayEntity,
        where: 'book_md5 = ? AND name = ?', whereArgs: [md5, name], limit: 1);
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// 批4 AI 精化「改类」：只改本书实体行的类型（零迁移，`type` 本就是列）。
  /// 用户层的类型登记由调用方另走 [putUserWord]（add 行随批3 `.xrwords` 导出带走）。
  Future<int> setEntityType(String md5, String name, String type) => _db.update(
        DbSchema.tXrayEntity,
        {'type': type},
        where: 'book_md5 = ? AND name = ?',
        whereArgs: [md5, name],
      );

  Future<void> _putUserdict(Transaction txn,
      {required String scope,
      required String word,
      required String action,
      String? type,
      String? target,
      String? patternHint}) =>
      txn.insert(DbSchema.tXrayUserdict, {
        'scope': scope,
        'word': word,
        'action': action,
        'type': type,
        'target': target,
        'pattern_hint': patternHint,
        'create_time': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// 移除（F8②）：**状态位而非降分**——`status=deleted` 读侧永不出现，
  /// 同时写本书屏蔽词（`action=forbid`）让重解析也捞不回来（§7）；
  /// [toGlobal]＝「升级到全局黑名单」，所有书生效。
  Future<void> markDeleted(String md5, List<int> ids, {bool toGlobal = false}) =>
      _db.transaction((txn) async {
        for (final id in ids) {
          final r = await txn.query(DbSchema.tXrayEntity,
              columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
          if (r.isEmpty) continue;
          final name = r.first['name'] as String;
          await txn.update(DbSchema.tXrayEntity, {'status': xs.xrayEntityDeleted},
              where: 'id = ?', whereArgs: [id]);
          await _putUserdict(txn,
              scope: md5, word: name, action: xs.xrayActForbid);
          if (toGlobal) {
            await _putUserdict(txn,
                scope: xs.xrayScopeGlobal, word: name, action: xs.xrayActForbid);
          }
        }
      });

  /// 合并（F8③）：**mention 归属迁移**至规范词条（与账目「改名不迁流水」刻意相反
  /// ——出场属于实体本体）；曾用名进 aliases；计数/跨章/首锚点**当场重算落库**
  /// （写时物化：二次打开面板只查询、不重算，§7 的 <10ms 红线靠这条）。
  Future<void> mergeInto(String md5,
      {required int intoId, required List<int> fromIds}) =>
          _db.transaction((txn) async {
            final intoRows = await txn.query(DbSchema.tXrayEntity,
                where: 'id = ?', whereArgs: [intoId], limit: 1);
            if (intoRows.isEmpty) return;
            final into = intoRows.first;
            final aliases = <String>[
              ..._decodeAliases(into['aliases'] as String?),
            ];
            for (final fid in fromIds) {
              if (fid == intoId) continue;
              final fr = await txn.query(DbSchema.tXrayEntity,
                  columns: ['name', 'aliases', 'status'],
                  where: 'id = ? AND book_md5 = ?',
                  whereArgs: [fid, md5],
                  limit: 1);
              if (fr.isEmpty) continue;
              final f = fr.first;
              if ((f['status'] as String).startsWith(xs.xrayEntityMergedPrefix)) {
                continue; // 已是死行不并第二遍
              }
              final fname = f['name'] as String;
              if (fname != into['name'] && !aliases.contains(fname)) {
                aliases.add(fname);
              }
              for (final al in _decodeAliases(f['aliases'] as String?)) {
                if (al != into['name'] && !aliases.contains(al)) aliases.add(al);
              }
              // 出场整批搬家。
              await txn.update(DbSchema.tXrayMention, {'entity_id': intoId},
                  where: 'book_md5 = ? AND entity_id = ?', whereArgs: [md5, fid]);
              await txn.update(DbSchema.tXrayEntity,
                  {'status': '${xs.xrayEntityMergedPrefix}$intoId'},
                  where: 'id = ?', whereArgs: [fid]);
            }
            // 重算派生值（全从迁移后的 mention 表现算，不信任累加）。
            final agg = await txn.rawQuery(
                'SELECT COUNT(*) AS n, COUNT(DISTINCT ch) AS chs FROM ${DbSchema.tXrayMention} '
                'WHERE book_md5 = ? AND entity_id = ?', [md5, intoId]);
            final firstRow = await txn.rawQuery(
                'SELECT ch, para FROM ${DbSchema.tXrayMention} '
                'WHERE book_md5 = ? AND entity_id = ? ORDER BY ch ASC, para ASC LIMIT 1',
                [md5, intoId]);
            await txn.update(DbSchema.tXrayEntity, {
              'n': (agg.first['n'] as int?) ?? 0,
              'chs': (agg.first['chs'] as int?) ?? 0,
              'aliases': jsonEncode(aliases),
              'first_ch': firstRow.isEmpty ? null : firstRow.first['ch'],
              'first_para': firstRow.isEmpty ? null : firstRow.first['para'],
            }, where: 'id = ?', whereArgs: [intoId]);
          });

  /// 加词（F8①）登记：词条行（`status=user_added`）+ 本书/全局 userdict add。
  /// 出场由 [XrayScheduler] 全书补扫回填（`applyScanResult`）。
  Future<int> registerUserWord(
      {required String md5,
      required String word,
      required String type,
      bool global = false}) => _db.transaction((txn) async {
        final exist = await txn.query(DbSchema.tXrayEntity,
            columns: ['id'],
            where: 'book_md5 = ? AND name = ?',
            whereArgs: [md5, word],
            limit: 1);
        final int id;
        if (exist.isEmpty) {
          id = await txn.insert(DbSchema.tXrayEntity, {
            'book_md5': md5,
            'name': word,
            'type': type,
            'n': 0,
            'chs': 0,
            'score': 1.0,
            'src_channels': 0,
            'status': xs.xrayEntityUserAdded,
            'aliases': '[]',
            'toc_flag': 0,
          });
        } else {
          id = exist.first['id'] as int;
          // 已有行只把来源改标为「我的词条」，不动其出场统计。
          await txn.update(DbSchema.tXrayEntity,
              {'status': xs.xrayEntityUserAdded},
              where: 'id = ?', whereArgs: [id]);
        }
        await _putUserdict(txn,
            scope: md5, word: word, action: xs.xrayActAdd, type: type);
        if (global) {
          await _putUserdict(txn,
              scope: xs.xrayScopeGlobal, word: word, action: xs.xrayActAdd);
        }
        return id;
      });

  /// 全书补扫回填（含 §7 回流建议的 pattern_hint 落库）。
  Future<void> applyScanResult({
    required String md5,
    required String word,
    required int entityId,
    required int n,
    required int chs,
    required List<XrayMention> anchors,
    String? patternHint,
  }) =>
      _db.transaction((txn) async {
        final first = anchors.isEmpty ? null : anchors.first;
        await txn.update(DbSchema.tXrayEntity, {
          'n': n,
          'chs': chs,
          'first_ch': first?.ch,
          'first_para': first?.para,
        }, where: 'id = ?', whereArgs: [entityId]);
        await txn.delete(DbSchema.tXrayMention,
            where: 'book_md5 = ? AND entity_id = ?',
            whereArgs: [md5, entityId]);
        await _insertAnchors(txn, md5, entityId, anchors);
        if (patternHint != null) {
          await txn.update(
              DbSchema.tXrayUserdict,
              {'pattern_hint': patternHint},
              where: 'scope = ? AND word = ? AND action = ?',
              whereArgs: [md5, word, xs.xrayActAdd]);
        }
      });

  /// 全局惯例采纳（建议规则卡「采纳」）：写 GLOBAL add（可带模式注记）。
  Future<void> promoteWordToGlobal(String md5, String word, {String? patternHint}) async {
    final rows = await _db.query(DbSchema.tXrayUserdict,
        columns: ['type'],
        where: 'scope = ? AND word = ? AND action = ?',
        whereArgs: [md5, word, xs.xrayActAdd],
        limit: 1);
    await putUserWord(
        scope: xs.xrayScopeGlobal,
        word: word,
        action: xs.xrayActAdd,
        type: rows.isEmpty ? null : rows.first['type'] as String?,
        patternHint: patternHint);
  }

  // ------------------------------------------------------------ xray_userdict

  /// 三层词库里的后两层：GLOBAL + 本书（§5/§7）。
  Future<XrayUserLayer> userLayer(String md5) async {
    final rows = await _db.query(DbSchema.tXrayUserdict,
        columns: ['scope', 'word', 'action'],
        where: 'scope IN (?, ?)',
        whereArgs: [xs.xrayScopeGlobal, md5]);
    final added = <String>{}, forbidden = <String>{};
    for (final r in rows) {
      final action = r['action'] as String;
      final word = r['word'] as String;
      if (action == xs.xrayActAdd) {
        added.add(word);
      } else if (action == xs.xrayActForbid) {
        forbidden.add(word);
      }
    }
    return XrayUserLayer(added: added, forbidden: forbidden);
  }

  /// 加词 / 屏蔽（重复登记按幂等处理，不积累历史行）。
  Future<void> putUserWord({
    required String scope,
    required String word,
    required String action,
    String? type,
    String? target,
    String? patternHint,
  }) =>
      _db.insert(DbSchema.tXrayUserdict, {
        'scope': scope,
        'word': word,
        'action': action,
        'type': type,
        'target': target,
        'pattern_hint': patternHint,
        'create_time': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// F8②「应用到所有书」：把本书屏蔽升级成 GLOBAL 黑名单。
  Future<void> promoteToGlobal(String md5, String word) => putUserWord(
      scope: xs.xrayScopeGlobal, word: word, action: xs.xrayActForbid);

  // ---------------------------------------------- GLOBAL 养成词库管理（批2 数据面）

  /// GLOBAL 养成词库全量行（管理页列表：最近养入在前）。
  Future<List<XrayDictRow>> listGlobalDict() async {
    final rows = await _db.query(DbSchema.tXrayUserdict,
        where: 'scope = ?',
        whereArgs: [xs.xrayScopeGlobal],
        orderBy: 'create_time DESC, word ASC');
    return [
      for (final r in rows)
        XrayDictRow(
          word: r['word'] as String,
          action: r['action'] as String,
          type: r['type'] as String?,
          target: r['target'] as String?,
          patternHint: r['pattern_hint'] as String?,
          createTime: r['create_time'] as int,
        ),
    ];
  }

  /// 编辑 GLOBAL 行：键 = (word, action) 唯一键。[newWord] 改名、[type] 改类型
  /// （传 null 不动，显式改空不可达——类型列本就允许空）；[toAction] 换动作
  /// ＝旧行删新行写（唯一键含 action，原键位更新会撞键）。
  Future<void> updateGlobalDict({
    required String word,
    required String action,
    String? newWord,
    String? type,
    String? toAction,
  }) =>
      _db.transaction((txn) async {
        final rows = await txn.query(DbSchema.tXrayUserdict,
            where: 'scope = ? AND word = ? AND action = ?',
            whereArgs: [xs.xrayScopeGlobal, word, action],
            limit: 1);
        if (rows.isEmpty) return;
        final row = rows.first;
        final nextAction = toAction ?? action;
        // 唯一键 = (scope, word, action)：任一维度变化都得删旧键行，
        // 否则改名会留下旧词行（实测红灯）。
        if (nextAction != action || (newWord != null && newWord != word)) {
          await txn.delete(DbSchema.tXrayUserdict,
              where: 'scope = ? AND word = ? AND action = ?',
              whereArgs: [xs.xrayScopeGlobal, word, action]);
        }
        await txn.insert(
            DbSchema.tXrayUserdict,
            {
              'scope': xs.xrayScopeGlobal,
              'word': newWord ?? (row['word'] as String),
              'action': nextAction,
              'type': type ?? row['type'] as String?,
              'target': row['target'] as String?,
              'pattern_hint': row['pattern_hint'] as String?,
              'create_time': row['create_time'] as int,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

  /// 删除 GLOBAL 行：[action] 精确删单动作行，null＝该词所有动作行全删。
  Future<int> deleteGlobalDict(String word, {String? action}) =>
      _db.delete(DbSchema.tXrayUserdict,
          where: action == null
              ? 'scope = ? AND word = ?'
              : 'scope = ? AND word = ? AND action = ?',
          whereArgs: action == null
              ? [xs.xrayScopeGlobal, word]
              : [xs.xrayScopeGlobal, word, action]);

  // ------------------------------------------------- 批3 .xrwords 导入导出

  /// 逐条 upsert 进 GLOBAL 层（导入专用，整包一个事务），返回 (新增, 覆盖, 跳过)。
  /// 跳过＝空词或非法动作（`merge_pair` 无 target 语义不收），不中断整包。
  Future<({int added, int updated, int skipped})> importGlobalDict(
      List<XrayDictEntry> entries) async {
    var added = 0, updated = 0, skipped = 0;
    await _db.transaction((txn) async {
      for (final e in entries) {
        final word = e.word.trim();
        if (word.isEmpty ||
            (e.action != xs.xrayActAdd && e.action != xs.xrayActForbid)) {
          skipped++;
          continue;
        }
        final exist = await txn.query(DbSchema.tXrayUserdict,
            columns: ['id'],
            where: 'scope = ? AND word = ? AND action = ?',
            whereArgs: [xs.xrayScopeGlobal, word, e.action],
            limit: 1);
        exist.isEmpty ? added++ : updated++;
        await txn.insert(
            DbSchema.tXrayUserdict,
            {
              'scope': xs.xrayScopeGlobal,
              'word': word,
              'action': e.action,
              'type': e.type,
              'target': e.target,
              'pattern_hint': e.patternHint,
              'create_time': e.createTime,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    return (added: added, updated: updated, skipped: skipped);
  }

  /// 面板一揽子数据（批A）：任务态 + 全部词条 + 锚点分组，一次查齐。
  /// 只在 X-Ray 段激活时调用（autoDispose 跟页面走），逐章进度不重查。
  /// [presetView] 直通 [allEntities]（批2 开关关＝纯预置视角）。
  Future<XrayPanelData> panelData(String md5, {bool presetView = false}) async {
    final task = await this.task(md5);
    final ents = await allEntities(md5, presetView: presetView);
    final anchors = await anchorsByEntity(md5);
    return XrayPanelData(task: task, entities: ents, anchors: anchors);
  }

  XrayEntityRow _row(Map<String, Object?> m) => XrayEntityRow(
        id: m['id'] as int,
        name: m['name'] as String,
        type: m['type'] as String,
        n: m['n'] as int,
        chs: m['chs'] as int,
        score: (m['score'] as num).toDouble(),
        channels: m['src_channels'] as int,
        status: m['status'] as String,
        aliases: _decodeAliases(m['aliases'] as String?),
        aiDesc: m['ai_desc'] as String?,
        firstCh: m['first_ch'] as int?,
        firstPara: m['first_para'] as int?,
        tocFlag: (m['toc_flag'] as int) != 0,
      );

  static List<String> _decodeAliases(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      // catch-ok: 别名是展示性附加信息，脏数据按无别名处理即可；
      // 抛出去会让整个面板打不开，收益不成比例。
      return const [];
    }
  }
}
