// 影音游模块（需求模块 10 · V1.25 并入「记录」第四 tab · 2026-10-07 产品令解禁并开工）
// 表结构唯一出处＝《docs/影音游模块开发计划-20260922.md》§二（四类＝电影/剧集/音乐/游戏；
// 综艺并入剧集、播客 kind 预留不实现）。
//
// 三条口径在字段层就钉死，别在 UI 侧补：
// · `media_items.id` 是 **TEXT**（外部 id 归一后直接当主键，导入去重少一次映射）；
// · 状态列 `state` 一列四义（看完/循环中/通关按 kind 解释），`progress_way` 决定进度怎么算；
// · 会话表与 `book_sessions` 同构（用户 2026-09-22 明确），`txn_id` 指向时间账本块。

const String tMediaItems = 'media_items';
const String tMediaSessions = 'media_sessions';
const String tMediaNotes = 'media_notes';
const String tMediaUnits = 'media_units';
const String tMediaDict = 'media_dict';
const String tMediaLists = 'media_lists';
const String tMediaListItems = 'media_list_items';

/// 本模块全部表名（备份登记、概览在册、守护清单都吃这一份）。
const List<String> mediaTables = [
  tMediaItems,
  tMediaSessions,
  tMediaNotes,
  tMediaUnits,
  tMediaDict,
  tMediaLists,
  tMediaListItems,
];

/// 四类（综艺并入剧集＝§九.5 已定案；播客留 V1.x 不建 kind）。
const List<String> mediaKinds = ['movie', 'series', 'music', 'game'];

/// 外部源去重键（§六 三级去重的第一级）：每个源建一条部分唯一索引，空值不参与唯一约束。
const List<String> mediaExternalSources = [
  'douban', 'imdb', 'tmdb', 'tvdb', 'musicbrainz', 'discogs', 'steam', 'igdb'
];

final List<String> mediaSchemaStatements = [
  '''
  CREATE TABLE IF NOT EXISTS $tMediaItems (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    subtitle TEXT,
    creator TEXT NOT NULL DEFAULT '未知',
    creator_role TEXT,
    publisher TEXT,
    publisher_role TEXT,
    release_year INTEGER,
    release_date TEXT,
    country TEXT,
    language TEXT,
    cover_path TEXT,
    color_idx INTEGER NOT NULL DEFAULT 0,
    state TEXT NOT NULL,
    rating REAL NOT NULL DEFAULT 0,
    my_rating REAL NOT NULL DEFAULT 0,
    duration_min INTEGER NOT NULL DEFAULT 0,
    seasons_count INTEGER NOT NULL DEFAULT 0,
    episodes_total INTEGER NOT NULL DEFAULT 0,
    tracks_count INTEGER NOT NULL DEFAULT 0,
    playthroughs INTEGER NOT NULL DEFAULT 0,
    main_pct INTEGER NOT NULL DEFAULT 0,
    side_pct INTEGER NOT NULL DEFAULT 0,
    ach_pct INTEGER NOT NULL DEFAULT 0,
    completed INTEGER NOT NULL DEFAULT 0,
    progress_way TEXT NOT NULL,
    progress_from TEXT,
    progress_to TEXT,
    source TEXT,
    grp TEXT,
    external_ids TEXT,
    tags TEXT,
    started_at INTEGER,
    ended_at INTEGER,
    last_activity_at INTEGER,
    intro TEXT,
    note TEXT,
    final_note TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_mitem_kind ON $tMediaItems(kind)',
  'CREATE INDEX IF NOT EXISTS idx_mitem_state ON $tMediaItems(state)',
  'CREATE INDEX IF NOT EXISTS idx_mitem_creator ON $tMediaItems(creator)',
  'CREATE INDEX IF NOT EXISTS idx_mitem_publisher ON $tMediaItems(publisher)',
  'CREATE INDEX IF NOT EXISTS idx_mitem_source ON $tMediaItems(source)',
  'CREATE INDEX IF NOT EXISTS idx_mitem_grp ON $tMediaItems(grp)',
  'CREATE INDEX IF NOT EXISTS idx_mitem_lastact ON $tMediaItems(last_activity_at)',
  'CREATE INDEX IF NOT EXISTS idx_mitem_deleted ON $tMediaItems(deleted_at)',
  // 外部 id 三级去重第一级：非空才约束（同一部片在豆瓣/IMDb 各有一条记录是常态，互不干扰）。
  for (final s in mediaExternalSources)
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_mitem_ext_$s ON $tMediaItems(json_extract(external_ids, \'\$.${s}_id\')) '
        "WHERE json_extract(external_ids, '\$.${s}_id') IS NOT NULL",
  '''
  CREATE TABLE IF NOT EXISTS $tMediaSessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    ended_at INTEGER,
    minutes INTEGER NOT NULL DEFAULT 0,
    speed REAL,
    from_min INTEGER,
    to_min INTEGER,
    from_pct INTEGER,
    to_pct INTEGER,
    from_unit INTEGER,
    to_unit INTEGER,
    from_text TEXT,
    to_text TEXT,
    source TEXT NOT NULL DEFAULT 'timer',
    txn_id INTEGER
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_msess_item ON $tMediaSessions(item_id)',
  'CREATE INDEX IF NOT EXISTS idx_msess_started ON $tMediaSessions(started_at)',
  'CREATE INDEX IF NOT EXISTS idx_msess_kind ON $tMediaSessions(kind)',
  '''
  CREATE TABLE IF NOT EXISTS $tMediaNotes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    note_type TEXT NOT NULL,
    tag TEXT,
    body TEXT NOT NULL,
    thought TEXT,
    unit_ref INTEGER,
    at_min INTEGER,
    image_paths TEXT,
    starred INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    origin TEXT,
    dedup_hash TEXT,
    tags TEXT
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_mnote_item ON $tMediaNotes(item_id)',
  'CREATE INDEX IF NOT EXISTS idx_mnote_type ON $tMediaNotes(note_type)',
  'CREATE INDEX IF NOT EXISTS idx_mnote_tag ON $tMediaNotes(tag)',
  'CREATE INDEX IF NOT EXISTS idx_mnote_created ON $tMediaNotes(created_at)',
  'CREATE INDEX IF NOT EXISTS idx_mnote_starred ON $tMediaNotes(starred)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_mnote_dedup ON $tMediaNotes(dedup_hash) WHERE dedup_hash IS NOT NULL',
  '''
  CREATE TABLE IF NOT EXISTS $tMediaUnits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id TEXT NOT NULL,
    unit_type TEXT NOT NULL,
    parent_id INTEGER,
    ordinal INTEGER NOT NULL,
    name TEXT,
    duration_min INTEGER,
    extra TEXT,
    state TEXT,
    loops INTEGER NOT NULL DEFAULT 0,
    completed_at INTEGER
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_munit_item ON $tMediaUnits(item_id)',
  'CREATE INDEX IF NOT EXISTS idx_munit_type ON $tMediaUnits(unit_type)',
  'CREATE INDEX IF NOT EXISTS idx_munit_parent ON $tMediaUnits(parent_id)',
  '''
  CREATE TABLE IF NOT EXISTS $tMediaDict (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    role_hint TEXT,
    sort INTEGER NOT NULL DEFAULT 0,
    extra TEXT
  )
  ''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_mdict_kind_name ON $tMediaDict(kind,name)',
  '''
  CREATE TABLE IF NOT EXISTS $tMediaLists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    note TEXT,
    kind_filter TEXT,
    auto_year INTEGER,
    sort INTEGER NOT NULL DEFAULT 0,
    cover_style TEXT NOT NULL DEFAULT 'desk',
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS $tMediaListItems (
    list_id INTEGER NOT NULL,
    item_id TEXT NOT NULL,
    pos INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (list_id, item_id)
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_mlistitem_item ON $tMediaListItems(item_id)',
  // 字典 source 预置（§2.2）：改名/停用走字典，条目侧只存名字。
  "INSERT OR IGNORE INTO $tMediaDict(kind,name,sort) VALUES"
      "('source','豆瓣',1),('source','IMDb',2),('source','TMDB',3),('source','TVMAZE',4),"
      "('source','MusicBrainz',5),('source','RateYourMusic',6),('source','Discogs',7),('source','Steam',8),"
      "('source','IGDB',9),('source','B 站',10),('source','网易云',11),('source','Spotify',12),"
      "('source','Letterboxd',13),('source','自建',14)",
];

/// 批5 · v38→v39 复习三列（工单 §1.2 定案＝零搬数据纯加列）。
///
/// **勿把这三列写进上面的基础 DDL**：基础 DDL 冻结在 v38 形态、由 `mig[37]` 原样重放，
/// 本段由 `mig[38]`（38→39）与 `DbSchema.createStatements` 尾部各吃一次。这样老库从
/// v37 直升 v39 时「[37] 建表 → [38] 加列」相接不撞列；若列进基础 DDL，同一条链上
/// [38] 的 ALTER 必炸 duplicate column（撞列留档教训＝read.dart 的 [32]/[33] 段注）。
final List<String> mediaReviewStatements = [
  'ALTER TABLE $tMediaNotes ADD COLUMN review_stage INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE $tMediaNotes ADD COLUMN reviewed_at INTEGER',
  'ALTER TABLE $tMediaNotes ADD COLUMN next_review_at INTEGER',
  // 到期队列按 next_review_at 升序取（NULL＝未排期/已走完，不进队列）。
  'CREATE INDEX IF NOT EXISTS idx_mnote_due ON $tMediaNotes(next_review_at)',
  // 判重索引改「仅在库行」局部唯一（与阅读侧真机反馈⑤同一条坑，这里在零数据时先纠）：
  // 旧索引让软删行永久占键——删掉一条笔记再记同一句话必撞 2067。先把历史脏行的键位让出，
  // 再按 live 局部重建（在库行本就互斥，重建必成）。
  'UPDATE $tMediaNotes SET dedup_hash = NULL WHERE deleted_at IS NOT NULL',
  'DROP INDEX IF EXISTS idx_mnote_dedup',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_mnote_dedup ON $tMediaNotes(dedup_hash) '
      'WHERE dedup_hash IS NOT NULL AND deleted_at IS NULL',
];

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
  // 37→38（影音游解禁批1）：新模块只建表不搬数据。
  37: [
    ...mediaSchemaStatements,
  ],
  // 38→39（影音游批5 数据层）：media_notes 加复习三列＋到期索引。
  38: [...mediaReviewStatements],
};
