import '../../../core/database/schema/media.dart';
import '../domain/media_note.dart';
import 'media_repository.dart';

/// 影音笔记＋名场面复习（影音游批5 数据层 · 计划 §五批3 · 工单 §1.2/§1.3）。
///
/// 四条硬口径：
/// - **筛选只有一处**：笔记库四视图、条目名场面时间线、复习队列与复习角标全部吃
///   [_noteFilter] 这一份 where（工单 §1.1「四视图吃同一筛选结果，计数必须一致」；
///   刀3 钉的就是「四视图各自重算过滤」这条漂移）；
/// - **在册读取的唯一出口**：每条查询都带 `deleted_at IS NULL`，本扩展不提供
///   「含软删行」的开关（回收站若要做，另批按阅读侧口径立第二出口，不在这里开口子）；
/// - 判重只认在库行：`dedup_hash` 是 partial unique（`deleted_at IS NULL`），
///   所以「删了再记同一句」记得上（v39 迁移段里把这条索引纠过形）；
/// - 复习档位落本行三列（`review_stage`/`reviewed_at`/`next_review_at`），
///   「记住了」＝推档并重排下次到期，「跳过」＝**不落库**（本轮不再出＝内存队列摘除，
///   下次进屏仍按排期出，与原型 `m-review` 同口径）。
extension MediaNoteRepo on MediaRepository {
  static const String _live = MediaRepository.rawLive;

  /// 记一条笔记（唯一录入口）。
  ///
  /// 返回新行 id；**空正文＝null 不落库**（UI 侧就地报错 LH-K32 同口径），
  /// 撞在册判重＝返回既有行 id（连点保存只落一条，第二次的返回即第一次的行）。
  /// 入账即排第一档：`next_review_at = created_at + 1 天`（工单 §1.2 的 1/3/7）。
  Future<int?> addNote(MediaNote note) async {
    final body = note.body.trim();
    if (body.isEmpty) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = note.createdAt == 0 ? now : note.createdAt;
    final hash = MediaNote.dedupKey(
      itemId: note.itemId,
      unitRef: note.unitRef,
      atMin: note.atMin,
      body: body,
    );
    if (hash.isNotEmpty) {
      final hit = await db.query(
        tMediaNotes,
        columns: ['id'],
        where: 'dedup_hash = ? AND $_live',
        whereArgs: [hash],
        limit: 1,
      );
      if (hit.isNotEmpty) return hit.first['id'] as int;
    }
    final row = Map<String, Object?>.from(note.toRow())
      ..['body'] = body
      ..['dedup_hash'] = hash.isEmpty ? null : hash
      ..['created_at'] = created
      ..['updated_at'] = now
      // 未排期＝档位 0、下次到期按建档时刻（不是「现在」）算：补记旧笔记不蹭今天的档。
      ..['review_stage'] = note.reviewStage
      ..['next_review_at'] =
          note.nextReviewAt ?? created + MediaNote.reviewGapsDays.first * _dayMs;
    return await db.insert(tMediaNotes, row);
  }

  /// 全量更新一条笔记（编辑面走这一口；正文变了就重算判重键）。
  /// 返回是否落库（空正文/缺行/软删行/撞在册判重＝false，不动库）。
  Future<bool> updateNote(MediaNote note) async {
    final id = note.id;
    final body = note.body.trim();
    if (id == null || body.isEmpty) return false;
    final cur = await noteById(id);
    if (cur == null) return false;
    final hash = MediaNote.dedupKey(
      itemId: note.itemId,
      unitRef: note.unitRef,
      atMin: note.atMin,
      body: body,
    );
    if (hash.isNotEmpty) {
      final hit = await db.query(
        tMediaNotes,
        columns: ['id'],
        where: 'dedup_hash = ? AND id <> ? AND $_live',
        whereArgs: [hash, id],
        limit: 1,
      );
      if (hit.isNotEmpty) return false;
    }
    final row = Map<String, Object?>.from(note.toRow())
      ..['body'] = body
      ..['dedup_hash'] = hash.isEmpty ? null : hash
      ..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    final n = await db.update(
      tMediaNotes,
      row,
      where: 'id = ? AND $_live',
      whereArgs: [id],
    );
    return n > 0;
  }

  /// 单条在册笔记（软删行＝null）。
  Future<MediaNote?> noteById(int id) async {
    final rows = await db.query(
      tMediaNotes,
      where: 'id = ? AND $_live',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : MediaNote.fromMap(rows.first);
  }

  /// 行内标星（笔记库/复习卡共用；就地切，不整表重写）。
  Future<void> setNoteStarred(int id, bool starred) async {
    await db.update(
      tMediaNotes,
      {
        'starred': starred ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND $_live',
      whereArgs: [id],
    );
  }

  /// 软删（LH-S31 确认式之后走这里）：笔记库与该条目名场面时间线同帧不见
  /// ＝两侧都只读在册行，不在这里做二次清理。
  Future<int> deleteNote(int id) => db.update(
    tMediaNotes,
    {
      'deleted_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ? AND $_live',
    whereArgs: [id],
  );

  /// 六路筛选的唯一出口（类型／kind／条目／标星／标签／关键词，＋复习到期档）。
  ///
  /// 排序：带 [dueBefore]（复习队列）＝按下次到期升序；否则按创建时间倒序。
  /// [limit] 只给复习队列取一条时用（UI 侧不许为四视图各写一条查询）。
  Future<List<MediaNote>> notes({
    String? kind,
    String? itemId,
    String? noteType,
    String? tag,
    String? query,
    bool starredOnly = false,
    int? dueBefore,
    int? limit,
  }) async {
    final (where, args) = _noteFilter(
      kind: kind,
      itemId: itemId,
      noteType: noteType,
      tag: tag,
      query: query,
      starredOnly: starredOnly,
      dueBefore: dueBefore,
    );
    final rows = await db.query(
      tMediaNotes,
      where: where,
      whereArgs: args,
      orderBy: dueBefore == null
          ? 'created_at DESC, id DESC'
          : 'next_review_at ASC, created_at ASC',
      limit: limit,
    );
    return rows.map(MediaNote.fromMap).toList();
  }

  /// 在册笔记总数（空态分档用：零笔记 vs 当前筛选零命中，工单 §1.1 两种话术）。
  Future<int> noteCount() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $tMediaNotes WHERE $_live',
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// 标签 chips 来源（筛选行⑤：在册行 `tag` 列去重，按名码位序）。
  Future<List<String>> noteTags() async {
    final rows = await db.rawQuery(
      "SELECT DISTINCT tag AS t FROM $tMediaNotes "
      "WHERE $_live AND tag IS NOT NULL AND tag <> '' ORDER BY t ASC",
    );
    return rows.map((r) => '${r['t']}').toList();
  }

  /// 条目 chips 来源（筛选行③：只列出有笔记的条目，按各条目笔记数倒序）。
  /// 与 [notes] 同一份 where，只是**不吃 itemId 自身**（否则选中一个条目后其余条目消失）。
  Future<List<({String itemId, int count})>> noteItemFacet({
    String? kind,
    String? noteType,
    String? tag,
    String? query,
    bool starredOnly = false,
  }) async {
    final (where, args) = _noteFilter(
      kind: kind,
      noteType: noteType,
      tag: tag,
      query: query,
      starredOnly: starredOnly,
    );
    final rows = await db.rawQuery(
      'SELECT item_id AS i, COUNT(*) AS n FROM $tMediaNotes '
      'WHERE $where GROUP BY item_id ORDER BY n DESC, i ASC',
      args,
    );
    return rows
        .map((r) => (itemId: '${r['i']}', count: (r['n'] as num).toInt()))
        .toList();
  }

  /// 某条目的在册笔记（详情页名场面时间线；时间点升序，无时间点的按创建倒序垫后）。
  Future<List<MediaNote>> notesOfItem(String itemId) async {
    final rows = await db.query(
      tMediaNotes,
      where: 'item_id = ? AND $_live',
      whereArgs: [itemId],
      orderBy: 'at_min IS NULL, at_min ASC, created_at DESC',
    );
    return rows.map(MediaNote.fromMap).toList();
  }

  /// 到期复习队列（工单 §1.2：队列来源＝筛过的笔记）。
  Future<List<MediaNote>> dueReviewNotes({
    int? now,
    String? kind,
    String? itemId,
    String? noteType,
    String? tag,
    String? query,
    bool starredOnly = false,
  }) => notes(
    kind: kind,
    itemId: itemId,
    noteType: noteType,
    tag: tag,
    query: query,
    starredOnly: starredOnly,
    dueBefore: now ?? DateTime.now().millisecondsSinceEpoch,
  );

  /// 复习角标读数（＝队列长度，与 [dueReviewNotes] 同一份 where，不另算）。
  Future<int> dueReviewCount({
    int? now,
    String? kind,
    String? itemId,
    String? noteType,
    String? tag,
    String? query,
    bool starredOnly = false,
  }) async {
    final (where, args) = _noteFilter(
      kind: kind,
      itemId: itemId,
      noteType: noteType,
      tag: tag,
      query: query,
      starredOnly: starredOnly,
      dueBefore: now ?? DateTime.now().millisecondsSinceEpoch,
    );
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $tMediaNotes WHERE $where',
      args,
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// 「记住了」：推一档＋记打卡时刻＋按新档取下次到期（走完＝`next_review_at` 落 NULL）。
  /// 返回推档后的行（缺行/软删行＝null，不动库）。
  Future<MediaNote?> markRemembered(int id, {int? now}) async {
    final cur = await noteById(id);
    if (cur == null) return null;
    final next = cur.remembered(now ?? DateTime.now().millisecondsSinceEpoch);
    await db.update(
      tMediaNotes,
      {
        'review_stage': next.reviewStage,
        'reviewed_at': next.reviewedAt,
        'next_review_at': next.nextReviewAt,
        'updated_at': next.reviewedAt,
      },
      where: 'id = ? AND $_live',
      whereArgs: [id],
    );
    return next;
  }

  static const int _dayMs = 24 * 60 * 60 * 1000;

  /// 筛选 where 的唯一出处（`$_live` 恒在首位＝在册口径不可绕）。
  (String, List<Object?>) _noteFilter({
    String? kind,
    String? itemId,
    String? noteType,
    String? tag,
    String? query,
    bool starredOnly = false,
    int? dueBefore,
  }) {
    final parts = <String>[_live];
    final args = <Object?>[];
    void eq(String col, Object? v) {
      if (v == null) return;
      parts.add('$col = ?');
      args.add(v);
    }

    eq('kind', kind);
    eq('item_id', itemId);
    eq('note_type', noteType);
    eq('tag', tag);
    if (starredOnly) parts.add('starred = 1');
    if (query != null && query.trim().isNotEmpty) {
      // 关键词＝正文＋批注＋条目名（工单 §1.1⑥；条目名走在册条目子查询，
      // 软删条目的名字不参与匹配，与「在册读取唯一出口」同口径）。
      final q = '%${query.trim()}%';
      parts.add(
        '(body LIKE ? OR thought LIKE ? OR item_id IN '
        '(SELECT id FROM $tMediaItems WHERE $_live AND title LIKE ?))',
      );
      args.addAll([q, q, q]);
    }
    if (dueBefore != null) {
      parts.add('next_review_at IS NOT NULL');
      parts.add('next_review_at <= ?');
      args.add(dueBefore);
    }
    return (parts.join(' AND '), args);
  }
}
