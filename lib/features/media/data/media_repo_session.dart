import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema/core.dart' as core;
import '../../../core/database/schema/media.dart';
import '../domain/media_item.dart';
import '../domain/media_session.dart';
import 'media_repository.dart';

/// 影音游计时会话仓储（批3 · 计划 §八 L4 口径）。
///
/// 与阅读会话**同构但独立表**（`media_sessions` 不碰 `book_sessions`）：
/// - 全库**单活**：起新计时先结算在跑的那条（回拨/短会话删行不入账，同阅读口径）；
/// - 结束即写 `time_blocks`（分类=娱乐，`cat_id=5`），`txn_id` 回填；
///   明细改动**差量更新同一条块**（txn_id 复用不新建），删除会话连删块；
/// - `minutes` 恒为真实耗时，倍速只存 [MediaSession.speed] 列，折算在读取侧。
extension MediaSessionsRepo on MediaRepository {
  /// settings 表 `media.*` 键读取（计划 §七：不落散落 SharedPreferences）。
  Future<String?> kv(String key) async {
    final rows = await db.query(
      core.tSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setKv(String key, String value) => db.insert(
    core.tSettings,
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  /// 在跑的会话（ended_at IS NULL 的唯一行）；杀进程重开延续靠它。
  Future<MediaSession?> runningSession() async {
    final rows = await db.query(
      tMediaSessions,
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : MediaSession.fromRow(rows.first);
  }

  /// 开始计时：先结算任何在跑会话，再落新行；条目落「在场」分区并补 started_at。
  Future<MediaSession> startSession(String itemId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = await runningSession();
    if (old != null) {
      await _close(old, now);
    }
    final item = await itemById(itemId);
    final id = await db.insert(
      tMediaSessions,
      MediaSession(
        itemId: itemId,
        kind: item?.kind ?? '',
        startedAt: now,
        fromText: item?.progressTo,
      ).toRow(),
    );
    if (item != null) {
      await db.update(
        tMediaItems,
        {
          'started_at': item.startedAt ?? now,
          'state': _ongoingState(item.kind, item.state),
          'last_activity_at': now,
          'updated_at': now,
        },
        where: 'id = ? AND ${MediaRepository.rawLive}',
        whereArgs: [itemId],
      );
    }
    return MediaSession(id: id, itemId: itemId, kind: item?.kind ?? '', startedAt: now);
  }

  /// 结束计时：返回已关闭会话供结算回显；不在跑/不属该条目返回 null。
  Future<MediaSession?> endSession(String itemId) async {
    final old = await runningSession();
    if (old == null || old.itemId != itemId) return null;
    return _close(old, DateTime.now().millisecondsSinceEpoch);
  }

  /// 关闭一条在跑会话：不足 1 分钟删行不入账（同阅读短会话门槛）。
  Future<MediaSession?> _close(MediaSession s, int nowMs) async {
    final mins = ((nowMs - s.startedAt) / 60000).floor();
    if (mins < 1 || nowMs < s.startedAt) {
      await db.delete(tMediaSessions, where: 'id = ?', whereArgs: [s.id]);
      return null;
    }
    final closed = s.copyWith(endedAt: nowMs, minutes: mins);
    await db.update(
      tMediaSessions,
      {'ended_at': nowMs, 'minutes': mins},
      where: 'id = ?',
      whereArgs: [s.id],
    );
    await db.update(
      tMediaItems,
      {'last_activity_at': nowMs, 'updated_at': nowMs},
      where: 'id = ? AND ${MediaRepository.rawLive}',
      whereArgs: [s.itemId],
    );
    final txnId = await _syncTxn(closed);
    return txnId == null ? closed : closed.copyWith(txnId: txnId);
  }

  /// 进度保存（`m-sheet-progress` 唯一写回口 · 刀2 落点）：
  /// **按 kind 分派写回的列组**，不是同一张表单换个标题——
  /// 电影＝pct→main_pct/progress_to、min→progress_to(分钟)；
  /// 剧集＝看到第几集→progress_to；音乐＝不落进度列（循环＝会话派生）；
  /// 游戏＝按档写 main_pct / ach_pct / playthroughs / progress_to。
  /// 完结档同场落 completed 与 ended_at（原型「保存 · 重算预计完成日」的写回面）。
  Future<int> saveProgress({
    required MediaItem item,
    String? state,
    double? myRating,
    String? way,
    int? pct,
    int? atMin,
    int? ep,
    int? sidePct,
    int? achPct,
    int? playthroughs,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final k = way ?? item.progressWay;
    final values = <String, Object?>{'updated_at': now, 'last_activity_at': now};
    final doneStates = {'看完', '追完', '通关'};
    if (state != null && state != item.state) {
      values['state'] = state;
      values['completed'] = doneStates.contains(state) ? 1 : 0;
      if (doneStates.contains(state)) values['ended_at'] = now;
    }
    if (myRating != null) values['my_rating'] = myRating;
    switch (item.kind) {
      case MediaItem.kMovie:
        if (k == MediaItem.kWayPct && pct != null) {
          values['progress_way'] = k;
          values['main_pct'] = pct.clamp(0, 100);
          values['progress_to'] = '${pct.clamp(0, 100)}';
        } else if (k == MediaItem.kWayMin && atMin != null) {
          values['progress_way'] = k;
          values['progress_to'] = '$atMin';
        }
      case MediaItem.kSeries:
        if (ep != null) values['progress_to'] = '$ep';
      case MediaItem.kMusic:
        // 循环次数没有列可写：它是会话条数派生（loopCounts），编数＝假账。
        break;
      case MediaItem.kGame:
        if (playthroughs != null) values['playthroughs'] = playthroughs;
        if (sidePct != null) values['side_pct'] = sidePct.clamp(0, 100);
        // 三档各写各列：成就档独立落 ach_pct（当档是主线时由下面 switch 覆写主线）。
        if (achPct != null && k != MediaItem.kWayMainPct) {
          values['ach_pct'] = achPct.clamp(0, 100);
        }
        switch (k) {
          case MediaItem.kWayMainPct:
            if (pct != null) {
              values['main_pct'] = pct.clamp(0, 100);
              values['progress_to'] = '${pct.clamp(0, 100)}';
            }
          case MediaItem.kWayAchv:
            if (pct != null) {
              values['ach_pct'] = pct.clamp(0, 100);
              values['progress_to'] = '${pct.clamp(0, 100)}';
            }
          case MediaItem.kWayPlaythrough:
            if (playthroughs != null) values['progress_to'] = '$playthroughs';
        }
    }
    return db.update(
      tMediaItems,
      values,
      where: 'id = ? AND ${MediaRepository.rawLive}',
      whereArgs: [item.id],
    );
  }

  /// 手动补记一次（时长 [minutes]，落 [atMs] 那天）：循环次数＝会话条数，
  /// 音乐「记一次」即经此入口，与计时会话同表同 L4。
  Future<int> addManualSession({
    required String itemId,
    required int atMs,
    required int minutes,
    int? toPct,
    int? toUnit,
    String? toText,
  }) async {
    final item = await itemById(itemId);
    final id = await db.insert(
      tMediaSessions,
      MediaSession(
        itemId: itemId,
        kind: item?.kind ?? '',
        startedAt: atMs,
        endedAt: atMs + minutes * 60000,
        minutes: minutes,
        toPct: toPct,
        toUnit: toUnit,
        toText: toText,
        source: MediaSession.kSrcManual,
      ).toRow(),
    );
    await db.update(
      tMediaItems,
      {'last_activity_at': atMs + minutes * 60000, 'updated_at': atMs},
      where: 'id = ? AND ${MediaRepository.rawLive}',
      whereArgs: [itemId],
    );
    await _syncTxn(
      MediaSession(
        id: id,
        itemId: itemId,
        kind: item?.kind ?? '',
        startedAt: atMs,
        endedAt: atMs + minutes * 60000,
        minutes: minutes,
        source: MediaSession.kSrcManual,
      ),
    );
    return id;
  }

  /// 明细屏「补记」写口（批4b A1）：来源＝手动补记，会话行与 L4 娱乐块同场落定，
  /// 返回回填了 `id`/`txnId` 的行对象（差量改口据此沿用同一条块，不新建）。
  /// [minutes] 只落真实耗时，[speed] 单列存值——折算一律读侧 [MediaSession.billedMinutes]。
  Future<MediaSession> addManualDetail({
    required String itemId,
    required String kind,
    required int startedAtMs,
    required int minutes,
    double? speed,
    int? toPct,
    int? toUnit,
    String? toText,
  }) async {
    final endedAt = startedAtMs + minutes * 60000;
    final draft = MediaSession(
      itemId: itemId,
      kind: kind,
      startedAt: startedAtMs,
      endedAt: endedAt,
      minutes: minutes,
      speed: speed,
      toPct: toPct,
      toUnit: toUnit,
      toText: toText,
      source: MediaSession.kSrcManual,
    );
    final id = await db.insert(tMediaSessions, draft.toRow());
    await db.update(
      tMediaItems,
      {'last_activity_at': endedAt, 'updated_at': endedAt},
      where: 'id = ? AND ${MediaRepository.rawLive}',
      whereArgs: [itemId],
    );
    final s = draft.copyWith(id: id);
    final txnId = await _syncTxn(s);
    return txnId == null ? s : s.copyWith(txnId: txnId);
  }

  /// 明细行内改（日期/时长）：重排 ended_at 并**差量回写同一条 L4 块**。
  Future<void> editSession(int id, {int? startedAtMs, int? minutes}) async {
    final rows = await db.query(
      tMediaSessions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final s = MediaSession.fromRow(rows.first);
    final start = startedAtMs ?? s.startedAt;
    final mins = minutes ?? s.minutes;
    await db.update(
      tMediaSessions,
      {'started_at': start, 'minutes': mins, 'ended_at': start + mins * 60000},
      where: 'id = ?',
      whereArgs: [id],
    );
    // 差量回写：txn_id 显式带上——缺块的旧行据此补建，已有块的沿用同一条。
    await _syncTxn(
      s.copyWith(endedAt: start + mins * 60000, minutes: mins),
    );
  }

  /// 明细屏差量写口（批4b A1）：改日期/时长/倍速/结束进度快照，
  /// 已结算会话同场把结束点重排并按 `txn_id` **UPDATE 同一条娱乐块**（绝不新建）；
  /// 未露的入参一律保持原值（copyWith 全字段透传，别把 speed/toText 洗成空）。
  Future<void> updateSessionDetail(
    int id, {
    int? startedAtMs,
    int? minutes,
    double? speed,
    int? toPct,
    int? toUnit,
    String? toText,
  }) async {
    final rows = await db.query(
      tMediaSessions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final s = MediaSession.fromRow(rows.first);
    final patch = <String, Object?>{};
    if (startedAtMs != null) patch['started_at'] = startedAtMs;
    if (minutes != null) patch['minutes'] = minutes;
    if (speed != null) patch['speed'] = speed;
    if (toPct != null) patch['to_pct'] = toPct;
    if (toUnit != null) patch['to_unit'] = toUnit;
    if (toText != null) patch['to_text'] = toText;
    if (patch.isEmpty) return;
    final start = startedAtMs ?? s.startedAt;
    final mins = minutes ?? s.minutes;
    // 结束点只在已结算行上重排；进行中行不替它落 ended_at（单活语义归 endSession）。
    final endedAt = s.endedAt == null ? null : start + mins * 60000;
    if (endedAt != null) patch['ended_at'] = endedAt;
    await db.update(tMediaSessions, patch, where: 'id = ?', whereArgs: [id]);
    await _syncTxn(
      s.copyWith(
        startedAt: start,
        endedAt: endedAt,
        minutes: mins,
        speed: speed,
        toPct: toPct,
        toUnit: toUnit,
        toText: toText,
      ),
    );
  }

  /// 删除一条会话：同场删其 L4 块（计划 §八「删除会话同事务删流水」）。
  Future<void> deleteSession(int id) async {
    final rows = await db.query(
      tMediaSessions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final s = MediaSession.fromRow(rows.first);
    if (s.txnId != null) {
      await db.delete(core.tTimeBlocks, where: 'id = ?', whereArgs: [s.txnId]);
    }
    await db.delete(tMediaSessions, where: 'id = ?', whereArgs: [id]);
  }

  /// 某条目全部会话（倒序＝明细/统计读法；进行中也在内）。
  Future<List<MediaSession>> sessionsOf(String itemId) async =>
      (await db.query(
        tMediaSessions,
        where: 'item_id = ?',
        whereArgs: [itemId],
        orderBy: 'started_at DESC',
      )).map(MediaSession.fromRow).toList();

  /// 某条目已结算会话（ETA 计算的 pace 原料）。
  Future<List<MediaSession>> closedSessionsOf(String itemId) async =>
      (await sessionsOf(itemId)).where((s) => s.endedAt != null).toList();

  /// 某条目累计入账分钟（真实耗时；进行中不含——卡面「累计」只报落定的账）。
  Future<int> minutesOfItem(String itemId) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(minutes), 0) AS n FROM $tMediaSessions '
      'WHERE item_id = ? AND ended_at IS NOT NULL',
      [itemId],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// L4 差量写入：块记在结束日；`txn_id` 已有就 UPDATE 同一条（补记走 manual 同源）。
  /// 返回该会话应对齐的块 id（新建＝新 id；已有＝沿用；未入账＝null）。
  Future<int?> _syncTxn(MediaSession s) async {
    if (s.id == null || s.endedAt == null || s.minutes <= 0) {
      return s.txnId;
    }
    final item = await itemById(s.itemId);
    final start = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    final end = DateTime.fromMillisecondsSinceEpoch(s.endedAt!);
    final day = DateTime(end.year, end.month, end.day);
    final endMin = end.hour * 60 + end.minute;
    final sameDay =
        start.year == end.year && start.month == end.month && start.day == end.day;
    final startMin = sameDay
        ? (start.hour * 60 + start.minute).clamp(0, 1439)
        : 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = <String, Object?>{
      'day': day.millisecondsSinceEpoch,
      'start_min': startMin,
      'end_min': endMin.clamp(startMin + 1, 1440),
      'category': '娱乐',
      'note': item?.title ?? '',
      'source': 'mark',
      'cat_id': _entertainCatId,
      'updated_at': now,
    };
    if (s.txnId == null) {
      final txnId = await db.insert(
        core.tTimeBlocks,
        {...row, 'created_at': now},
      );
      await db.update(
        tMediaSessions,
        {'txn_id': txnId},
        where: 'id = ?',
        whereArgs: [s.id],
      );
      return txnId;
    }
    await db.update(
      core.tTimeBlocks,
      row,
      where: 'id = ?',
      whereArgs: [s.txnId],
    );
    return s.txnId;
  }

  /// 「在场」分区：起计时即进入该 kind 的进行中档（已看完/通关的不回退）。
  static String _ongoingState(String kind, String cur) {
    final done = {'看完', '追完', '通关'};
    if (done.contains(cur)) return cur;
    return switch (kind) {
      'movie' => '在看',
      'series' => '在追',
      'music' => '在听',
      'game' => '在玩',
      _ => cur,
    };
  }
}

/// 时间账本「娱乐」分类种子 id（core schema categorySeed 第 5 行，写死同阅读侧
/// `catReadingId` 手法——种子早于本模块存在，不会漂移）。
const int _entertainCatId = 5;
