// 思维导图模块（需求模块 18 · V1.62 · 2026-10-12 产品裁定独立模块走宫格第 15 枚）。
//
// 数据层三条口径（冻结方案 §6.2）在字段层钉死，别在 UI 侧补：
// · 扁平表不 JOIN：`(map_id, parent_id, side, sort)` 一张平表存整棵树，
//   拉整图一次 `WHERE map_id=?`，不做邻接表递归查询；
// · 子节点顺序＝`sort` 整数字段，不靠 rowid 隐式序（rowid 在 vacuum/迁移后不稳定）；
// · 拖拽只存相对自动布局基线的偏移 `dx/dy`，不存绝对坐标——换布局类型时
//   基线重算、偏移仍可叠加，「归位到自动布局」＝清零两列。
//
// v44→v45 迁移（mig[44]）与基础 DDL 同源：本模块是纯新建表（零搬数据），
// 两处引用同一份 [mindmapSchemaStatements]（`IF NOT EXISTS` 保证重放不撞），
// 与 read.dart/media.dart 的「冻结段拆两份」不同——那两处是给既有表加列才有撞列问题。

const String tMindmaps = 'mindmaps';
const String tMindmapNodes = 'mindmap_nodes';

/// 本模块全部表名（备份登记、守护清单都吃这一份）。
const List<String> mindmapTables = [tMindmaps, tMindmapNodes];

/// 图行软删（回收站第九类）：`deleted_at` 非空＝在回收站。
/// 节点行**不软删**——恢复＝只清图行标记，节点天然原样回来（先例＝journal→分节：
/// journal purge 才连带清分节行，restore 只清 journal.deleted_at）。
final List<String> mindmapSchemaStatements = [
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
  // 复合索引（数据层三条之一）：拉整图按 map_id 走一条索引，父查子走前缀即中。
  'CREATE INDEX IF NOT EXISTS idx_mmnode_map_parent ON $tMindmapNodes(map_id, parent_id)',
  'CREATE INDEX IF NOT EXISTS idx_mmnode_map ON $tMindmapNodes(map_id)',
  'CREATE INDEX IF NOT EXISTS idx_mmaps_deleted ON $tMindmaps(deleted_at)',
];

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）。
/// 44→45（思维导图批1）：新模块只建表不搬数据。
final Map<int, List<String>> mig = {
  44: [...mindmapSchemaStatements],
};
