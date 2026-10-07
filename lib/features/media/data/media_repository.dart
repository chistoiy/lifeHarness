import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema/media.dart';
import '../domain/media_item.dart';

/// 影音游仓储（批2 · 计划 §2.1 表结构）。
///
/// 两条硬口径：
/// - **在册读取的唯一出口**：所有条目查询都带 `deleted_at IS NULL`，
///   UI/统计侧不许自己拼裸查（刀1 钉的就是这一条）；
/// - 聚合派生不落列：音乐「循环次数」＝该条目在 `media_sessions` 的会话条数，
///   与阅读侧 `sessionAggByBook` 同一口径（表里没有 loops 列，不写死、不编数）。
class MediaRepository {
  MediaRepository(this.db);

  final Database db;

  /// 在册谓词（唯一口径；会话扩展 `media_repo_session.dart` 同吃这一份）。
  static const String rawLive = 'deleted_at IS NULL';

  static const String _live = rawLive;

  /// 排序键白名单（§七 media.sortDefault）：非白名单一律回落 recent，
  /// 排序串全部是本类内常量，不吃外部拼接。
  static const Map<String, String> _orderBy = {
    'recent':
        'COALESCE(last_activity_at, created_at) DESC',
    'rating': 'COALESCE(NULLIF(my_rating, 0), rating) DESC, updated_at DESC',
    'added': 'created_at DESC',
    // 能力边界：本档按标题码位序（SQLite NOCASE 只折叠 ASCII），**不是拼音序**——
    // 拼音比较器目前在阅读模块内部（R1 禁跨 feature import），要推全需先抽进 shared，另批做。
    'name': 'title COLLATE NOCASE ASC',
    'duration': 'duration_min DESC, updated_at DESC',
  };

  static final Random _rnd = Random();

  /// TEXT 主键：毫秒＋4 位随机尾（同毫秒连点新增不撞）。
  String _newId() =>
      'm${DateTime.now().millisecondsSinceEpoch}'
      '${_rnd.nextInt(9000) + 1000}';

  /// 新条目落库，返回实际主键。
  Future<String> addItem(MediaItem item) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = item.id.isEmpty ? _newId() : item.id;
    final map = Map<String, Object?>.from(item.toMap())
      ..['id'] = id
      ..['created_at'] = item.createdAt == 0 ? now : item.createdAt
      ..['updated_at'] = now
      ..['last_activity_at'] = item.lastActivityAt ?? now;
    await db.insert(tMediaItems, map);
    return id;
  }

  Future<int> updateItem(MediaItem item) => db.update(
    tMediaItems,
    Map<String, Object?>.from(item.toMap())
      ..['updated_at'] = DateTime.now().millisecondsSinceEpoch,
    where: 'id = ?',
    whereArgs: [item.id],
  );

  /// 单条在册条目（详情/计时页取数口；软删行返回 null）。
  Future<MediaItem?> itemById(String id) async {
    final rows = await db.query(
      tMediaItems,
      where: 'id = ? AND $_live',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final x = MediaItem.fromMap(rows.first);
    if (x.kind != MediaItem.kMusic) return x;
    final loops = await loopCounts();
    final n = loops[x.id];
    return n == null ? x : x.copyWith(listenLoops: n);
  }

  /// 在册条目（四类 chip × 分区 chip × 关键词，原型 mItems＋mFilter 同口径）。
  ///
  /// [stateGroup] 吃筛选档标签（[MediaItem.stateGroups] 第一元），按 kind 展开成
  /// 该类的真实分区值；单类视图下 [MediaItem.states] 里的分区名可原样传入。
  Future<List<MediaItem>> items({
    String? kind,
    String? stateGroup,
    String? query,
    String sort = 'recent',
  }) async {
    final where = <String>[_live];
    final args = <Object?>[];
    if (kind != null && kind != 'all') {
      where.add('kind = ?');
      args.add(kind);
    }
    final states = _statesForGroup(stateGroup, kind);
    if (states != null && states.isNotEmpty) {
      where.add('state IN (${List.filled(states.length, '?').join(',')})');
      args.addAll(states);
    }
    final kw = (query ?? '').trim();
    if (kw.isNotEmpty) {
      where.add('(title LIKE ? OR subtitle LIKE ? OR creator LIKE ? '
          'OR publisher LIKE ? OR tags LIKE ?)');
      final like = '%$kw%';
      args.addAll([like, like, like, like, like]);
    }
    final rows = await db.query(
      tMediaItems,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: _orderBy[sort] ?? _orderBy['recent']!,
    );
    final loops = await loopCounts();
    final out = <MediaItem>[];
    for (final r in rows) {
      final x = MediaItem.fromMap(r);
      final n = x.kind == MediaItem.kMusic ? loops[x.id] : null;
      out.add(n == null ? x : x.copyWith(listenLoops: n));
    }
    return out;
  }

  /// 影音架顶部分区 chip 展开：筛选档 → 该档在各 kind 下的分区值集合。
  /// 单 kind 视图传进来的就是该类分区名，原样成组。
  List<String>? _statesForGroup(String? group, String? kind) {
    if (group == null || group.isEmpty || group == 'all') return null;
    if (kind != null && kind != 'all') return [group];
    for (final (label, list) in MediaItem.stateGroups) {
      if (label == group) return list;
    }
    return null;
  }

  /// 四类计数（chip 角标同源；音乐按条目数计，听后感流属批3 笔记面）。
  Future<Map<String, int>> kindCounts() async {
    final rows = await db.rawQuery(
      'SELECT kind, COUNT(*) AS n FROM $tMediaItems '
      'WHERE $_live GROUP BY kind',
    );
    final out = {for (final k in MediaItem.kinds) k: 0};
    for (final r in rows) {
      final k = '${r['kind']}';
      if (out.containsKey(k)) out[k] = (r['n'] as num?)?.toInt() ?? 0;
    }
    out['all'] = out.values.fold(0, (a, b) => a + b);
    return out;
  }

  /// 音乐循环次数（会话条数派生，一次查询全表回填）。
  Future<Map<String, int>> loopCounts() async {
    final rows = await db.rawQuery(
      'SELECT item_id, COUNT(*) AS n FROM $tMediaSessions GROUP BY item_id',
    );
    return {
      for (final r in rows) '${r['item_id']}': (r['n'] as num?)?.toInt() ?? 0,
    };
  }

  /// 桌面俯瞰 · 最近四条（四类各取最近活动一条，原型 #mdsHubDesk 同口径）。
  Future<List<MediaItem>> recentPerKind() async {
    final rows = await db.query(
      tMediaItems,
      where: _live,
      orderBy: 'COALESCE(last_activity_at, created_at) DESC',
      limit: 200,
    );
    final picked = <String, MediaItem>{};
    for (final r in rows) {
      final x = MediaItem.fromMap(r);
      if (!picked.containsKey(x.kind)) picked[x.kind] = x;
      if (picked.length == MediaItem.kinds.length) break;
    }
    return [
      for (final k in MediaItem.kinds)
        if (picked[k] != null) picked[k]!,
    ];
  }

  /// 批量改分区（长按管理条动作①）：目标分区必须在该 kind 的取值域内。
  Future<int> bulkSetState(List<String> ids, String state) {
    if (ids.isEmpty) return Future.value(0);
    final ph = List.filled(ids.length, '?').join(',');
    return db.update(
      tMediaItems,
      {'state': state, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id IN ($ph) AND $_live',
      whereArgs: ids,
    );
  }

  /// 单个条目改分区（速览面）：一次一条，`completed` 随完结档同步。
  Future<int> moveState(String id, String kind, String state) =>
      db.update(
        tMediaItems,
        {
          'state': state,
          'completed': _isDone(kind, state) ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND $_live',
        whereArgs: [id],
      );

  /// 批量移动到目标档：[kindFilter] 是具体类型时 [target] 就是该类分区名；
  /// 「全部」视图传进来的是语义档（[MediaItem.stateGroups] 第一元），
  /// 逐条按各自 kind 找对应分区值，**找不到就跳过**——归并标签绝不写进 state 列。
  Future<int> bulkMove(List<String> ids, String target, String kindFilter) async {
    final concrete = MediaItem.states.containsKey(kindFilter);
    if (concrete) return bulkSetState(ids, target);
    List<String>? values;
    for (final (label, list) in MediaItem.stateGroups) {
      if (label == target) {
        values = list;
        break;
      }
    }
    if (values == null || ids.isEmpty) return 0;
    final want = values; // 闭包内不做 null 提升，这里收成非空局部
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      tMediaItems,
      columns: ['id', 'kind'],
      where: 'id IN ($ph) AND $_live',
      whereArgs: ids,
    );
    var n = 0;
    for (final r in rows) {
      final kind = '${r['kind']}';
      final states = MediaItem.states[kind] ?? const [];
      final hit = states.firstWhere(want.contains, orElse: () => '');
      if (hit.isEmpty) continue;
      n += await db.update(
        tMediaItems,
        {
          'state': hit,
          'completed': _isDone(kind, hit) ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    return n;
  }

  static bool _isDone(String kind, String state) =>
      state == '看完' || state == '追完' || state == '通关';

  /// 批量加标签（长按管理条动作②）：逗号分隔追加且去重。
  Future<int> bulkAddTags(List<String> ids, String tag) async {
    final t = tag.trim();
    if (ids.isEmpty || t.isEmpty) return 0;
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      tMediaItems,
      columns: ['id', 'tags'],
      where: 'id IN ($ph) AND $_live',
      whereArgs: ids,
    );
    var n = 0;
    for (final r in rows) {
      final cur = (r['tags'] ?? '')
          .toString()
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (cur.contains(t)) continue;
      cur.add(t);
      n += await db.update(
        tMediaItems,
        {
          'tags': cur.join(','),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    return n;
  }

  /// 批量软删（长按管理条动作③）：只打 deleted_at，进全局回收站的路随批⑦做，
  /// 不在此处硬删（删除可逆口径＝批六 T3）。
  Future<int> softDelete(List<String> ids) {
    if (ids.isEmpty) return Future.value(0);
    final ph = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      tMediaItems,
      {'deleted_at': now, 'updated_at': now},
      where: 'id IN ($ph) AND $_live',
      whereArgs: ids,
    );
  }
}
