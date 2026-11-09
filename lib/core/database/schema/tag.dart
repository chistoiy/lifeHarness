// 标签体系（日记改版批2b · 2026-10-19 产品四条口径）。
//
// 规格＝`docs/handoff/交棒话术-20261019-日记模块改版批1日期轨道与图墙.md` §4g
// （原型家＝`prototype/index-time.html` 的 `p-sub-tags`，日记侧 `sheetDiaryTag`）。
//
// 三条口径在表结构层钉死，别在 UI 侧补：
// · **标签池全局唯一**（口径①）：`tags` 是唯一真源，日记/笔记/时间页只做**选择**，
//   不各存一份名字副本。关联一律走 `tag_links`（按 id 引用）——这样「改名＝所有模块
//   一起改」是一条 `UPDATE tags SET name=?` 的事，不用扫全仓 JSON。
// · **`scopes` 是多值属性**（口径②）：`diary,note,time` 逗号分隔。新建默认三个全勾。
//   `public` **不是第四个 scope**，而是「三个都含」的派生视图——若落成独立值，
//   就会出现「公共里有、但日记里选不到」的裂缝（判「属于日记」时得同时判两处，漏一处就断）。
// · **删除＝解除关联，内容不删**（口径④）：先 `DELETE tag_links WHERE tag_id=?`
//   再删 `tags` 行。合并＝关联改指目标 + `scopes` 取**并集**（取交集会让合并后
//   日记里选不到该标签），再删源行。
//
// `journal_entries.tags` 列**保留但降级为快照**：真源是 `tag_links`，DAO 读路径
// 以关联表覆盖；列内 JSON 只服务「关联表尚无该篇行」的回落与备份可读性。
// 任何池/关联变更后由 `TagDao.resyncSnapshots` 把受影响篇目重写一遍，
// 保证「删光标签后旧快照不会把标签复活」。

const String tTags = 'tags';
const String tTagLinks = 'tag_links';

/// 本模块全部表名（备份登记、守护清单吃这一份）。
const List<String> tagTables = [tTags, tTagLinks];

/// 三个适用模块（顺序即原型 `TG_SCOPE_KS`：日记 / 笔记 / 时间）。
///
/// 顺序有意义：添加页默认全勾、分区导轨与「公共」判定都按这个序。
/// **别加第四个**——见文件头「public 不是 scope」。
const List<String> kTagScopes = ['diary', 'note', 'time'];

/// 建表语句（onCreate 与 mig[49] 同源引一份：新模块只建表零搬数据，
/// 无 v45/v48 那种「老口径带新列 ⇒ 直升撞列」的历史包袱）。
const List<String> tagSchemaStatements = <String>[
  '''
  CREATE TABLE IF NOT EXISTS $tTags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    scopes TEXT NOT NULL DEFAULT '',
    sort INTEGER NOT NULL DEFAULT 0,
    builtin INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS $tTagLinks (
    tag_id INTEGER NOT NULL,
    module TEXT NOT NULL,
    item_id INTEGER NOT NULL,
    PRIMARY KEY (tag_id, module, item_id)
  )
  ''',
  // 反查方向（按内容取它的标签）走这条；正查（按标签取内容）由主键前缀覆盖。
  'CREATE INDEX IF NOT EXISTS idx_tag_links_item ON $tTagLinks(module, item_id)',
];

/// 本域承接的版本迁移条目（聚合于 `DbSchema.migrations`·键互斥）。
/// 键语义＝仓内循环 `for v=from; v<to; migrations[v]` ⇒ **键 49 ＝「49→50 升级语句」**。
/// 49（批2b）：建 `tags` / `tag_links` 两张表（新模块只建表零搬数据；
/// 历史 `journal_entries.tags` 的名字由 Dart 侧 `TagDao.seedFromJournalTags` 懒导入，
/// 不在 SQL 里解析 JSON——Android 各版本内置 SQLite 的 JSON1 可用性不值得赌）。
final Map<int, List<String>> mig = {
  49: [...tagSchemaStatements],
};
