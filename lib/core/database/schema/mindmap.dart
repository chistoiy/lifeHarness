// 思维导图模块（需求模块 18 · V1.62 · 2026-10-12 产品裁定独立模块走宫格第 15 枚）。
//
// 数据层三条口径（冻结方案 §6.2）在字段层钉死，别在 UI 侧补：
// · 扁平表不 JOIN：`(map_id, parent_id, side, sort)` 一张平表存整棵树，
//   拉整图一次 `WHERE map_id=?`，不做邻接表递归查询；
// · 子节点顺序＝`sort` 整数字段，不靠 rowid 隐式序（rowid 在 vacuum/迁移后不稳定）；
// · 拖拽只存相对自动布局基线的偏移 `dx/dy`，不存绝对坐标——换布局类型时
//   基线重算、偏移仍可叠加，「归位到自动布局」＝清零两列。
//
// v44→v45 迁移（mig[44]）与基础 DDL **不同源**（批2 起拆两份，read/media 惯例）：
// v45 口径的建表语句**不带** folder_id——若同源引用 v46 全量口径，老库 44→46
// 直升时先建带列表再跑 mig[46] 的 ALTER ⇒ duplicate column 崩。
// v45→v46（批2 F4-4 图归文件夹）：建 `mindmap_folders` 同级表 ＋
// `mindmaps.folder_id` 可空列（NULL＝未归入；删文件夹只置空引用不删图）。
// `parent_id` 留多层树口（现单层用法恒 NULL，将来扩多级零再迁移）。
// v46→v47（批5 F4-9 节点增强）：`mindmap_nodes` 加 tags/is_task/task_done/image_path
// 四列——**老口径两份（基础 DDL 与 `mindmapMig45Statements`）都不含这四列之外的混改**，
// 批5 四列只进基础 DDL（全量口径）与 mig[46]（ALTER），老库直升才不撞 duplicate column。

const String tMindmaps = 'mindmaps';
const String tMindmapNodes = 'mindmap_nodes';
const String tMindmapFolders = 'mindmap_folders';

/// 本模块全部表名（备份登记、守护清单都吃这一份）。
const List<String> mindmapTables = [tMindmaps, tMindmapNodes, tMindmapFolders];

/// 图行软删（回收站第九类）：`deleted_at` 非空＝在回收站。
/// 节点行**不软删**——恢复＝只清图行标记，节点天然原样回来（先例＝journal→分节：
/// journal purge 才连带清分节行，restore 只清 journal.deleted_at）。
///
/// 基础 DDL＝**v46 全量口径**（onCreate 走这份）：tMindmaps 自带 folder_id。
final List<String> mindmapSchemaStatements = [
  '''
  CREATE TABLE IF NOT EXISTS $tMindmaps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    folder_id INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS $tMindmapNodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    map_id INTEGER NOT NULL,
    parent_id INTEGER,
    note_id INTEGER,
    title TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    side TEXT,
    sort INTEGER NOT NULL DEFAULT 0,
    dx REAL NOT NULL DEFAULT 0,
    dy REAL NOT NULL DEFAULT 0,
    folded INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    tags TEXT,
    is_task INTEGER NOT NULL DEFAULT 0,
    task_done INTEGER NOT NULL DEFAULT 0,
    image_path TEXT
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS $tMindmapFolders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    parent_id INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  // 复合索引（数据层三条之一）：拉整图按 map_id 走一条索引，父查子走前缀即中。
  'CREATE INDEX IF NOT EXISTS idx_mmnode_map_parent ON $tMindmapNodes(map_id, parent_id)',
  'CREATE INDEX IF NOT EXISTS idx_mmnode_map ON $tMindmapNodes(map_id)',
  'CREATE INDEX IF NOT EXISTS idx_mmaps_deleted ON $tMindmaps(deleted_at)',
  'CREATE INDEX IF NOT EXISTS idx_mmaps_folder ON $tMindmaps(folder_id)',
];

/// v44→v45 升级口径（mig[44] 专用·**不带** folder_id，理由见文件头段注）。
final List<String> mindmapMig45Statements = [
  '''
  CREATE TABLE IF NOT EXISTS $tMindmaps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS $tMindmapNodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    map_id INTEGER NOT NULL,
    parent_id INTEGER,
    note_id INTEGER,
    title TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    side TEXT,
    sort INTEGER NOT NULL DEFAULT 0,
    dx REAL NOT NULL DEFAULT 0,
    dy REAL NOT NULL DEFAULT 0,
    folded INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_mmnode_map_parent ON $tMindmapNodes(map_id, parent_id)',
  'CREATE INDEX IF NOT EXISTS idx_mmnode_map ON $tMindmapNodes(map_id)',
  'CREATE INDEX IF NOT EXISTS idx_mmaps_deleted ON $tMindmaps(deleted_at)',
];

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）。
/// 键语义＝仓内循环 `for v=from; v<to; migrations[v]` ⇒ 键 v＝「v→v+1 升级语句」。
/// 44（思维导图批1）：新模块只建表不搬数据（v45 口径）。
/// 45（思维导图批2 F4-4）：建 mindmap_folders ＋ mindmaps 加 folder_id
/// （纯建表加列零搬数据；IF NOT EXISTS 保证重放不撞，ALTER 只在本键出现一次）。
/// 46（思维导图批5 F4-9）：给 mindmap_nodes 加批5 四列（tags/is_task/task_done/
/// image_path）。四列**只在基础 DDL 与本键出现**，老口径（`mindmapMig45Statements`
/// 与 mig[45]）一字不加——否则 44→47 直升会 duplicate column。
final Map<int, List<String>> mig = {
  44: [...mindmapMig45Statements],
  45: [
    '''
    CREATE TABLE IF NOT EXISTS $tMindmapFolders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      parent_id INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'ALTER TABLE $tMindmaps ADD COLUMN folder_id INTEGER',
    'CREATE INDEX IF NOT EXISTS idx_mmaps_folder ON $tMindmaps(folder_id)',
  ],
  46: [
    'ALTER TABLE $tMindmapNodes ADD COLUMN tags TEXT',
    'ALTER TABLE $tMindmapNodes ADD COLUMN is_task INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE $tMindmapNodes ADD COLUMN task_done INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE $tMindmapNodes ADD COLUMN image_path TEXT',
  ],
};
