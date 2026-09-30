/// X-Ray 全书索引（需求 V1.54 · 一期轻抽取档）· 治理G5 域库
///
/// 事实源：`docs/X-Ray全书索引开发设计说明书-20260928.md` §6（数据模型）与 §7（用户层语义）。
/// 迁移号口径：设计书写「自 v31 起」，实查 `schema.dart` 当前 v30（V1.58 小工具下架），故本域落在 **v30→v31**。
///
/// 四表分工（全部以 `book_md5`＝书的内容指纹为归属键，见 §13 数据携带性）：
/// - `xray_task`     任务态与断点（F2/F3：逐章落库、断点续跑）
/// - `xray_entity`   实体词条（F4：类型/频次/跨章/置信分/来源通道/状态）
/// - `xray_mention`  出场锚点（F5：章+段，页码现算不落库；context 每实体仅前 N 条带文）
/// - `xray_userdict` 用户覆盖层（F8：加词/永久屏蔽/合并配对 + 全局升级）
///
/// 红线：**四表只允许 `lib/features/read/data/xray_dao.dart` 直碰**（照 E 批
/// `test/todo_trash_guard_test.dart` 的源码级谓词守护先例，由批1 守护用例钉住）。
library;

const String tXrayTask = 'xray_task';
const String tXrayEntity = 'xray_entity';
const String tXrayMention = 'xray_mention';
const String tXrayUserdict = 'xray_userdict';

/// `xray_task.status` 取值（设计书 §6·与 §8 生命周期一致：前台跑·退后台 pause）。
const String xrayStatusPending = 'pending';
const String xrayStatusRunning = 'running';
const String xrayStatusPause = 'pause';
const String xrayStatusSuccess = 'success';
const String xrayStatusFailed = 'failed';
const String xrayStatusCanceled = 'canceled';

/// `xray_entity.type` 六类（F4 标签页·空类隐藏）。
const String xrayTypePer = 'per';
const String xrayTypeLoc = 'loc';
const String xrayTypeOrg = 'org';
const String xrayTypeTerm = 'term';
const String xrayTypeAbbr = 'abbr';
const String xrayTypeBook = 'book';

/// `xray_entity.src_channels` 位标志（设计书 §4 通道号与位序一一对应）。
const int xrayChanRegex = 1 << 0;
const int xrayChanNgram = 1 << 1;
const int xrayChanGazetteer = 1 << 2;
const int xrayChanDialog = 1 << 3;
const int xrayChanToc = 1 << 4;

/// `xray_userdict.action` 三态（F8）。
const String xrayActAdd = 'add';
const String xrayActForbid = 'forbid';
const String xrayActMerge = 'merge_pair';

/// `xray_userdict.scope` 的全局档（黑名单升级·§7「应用到所有书」）。
const String xrayScopeGlobal = 'GLOBAL';

const List<String> xraySchemaStatements = [
  '''
    CREATE TABLE IF NOT EXISTS $tXrayTask (
      book_md5 TEXT PRIMARY KEY,
      total_ch INTEGER NOT NULL DEFAULT 0,
      range_start INTEGER NOT NULL DEFAULT 0,
      range_end INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      processed_ch INTEGER NOT NULL DEFAULT 0,
      score_meta TEXT,
      update_time INTEGER NOT NULL
    )
  ''',
  '''
    CREATE TABLE IF NOT EXISTS $tXrayEntity (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_md5 TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      n INTEGER NOT NULL DEFAULT 0,
      chs INTEGER NOT NULL DEFAULT 0,
      score REAL NOT NULL DEFAULT 0,
      src_channels INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      aliases TEXT,
      ai_desc TEXT,
      relation TEXT,
      first_ch INTEGER,
      first_para INTEGER,
      toc_flag INTEGER NOT NULL DEFAULT 0
    )
  ''',
  // 跨类型仲裁「同名只保留最高分类别」（§4）在库层的表达：同书同名只能有一条实体。
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_xray_entity_name '
      'ON $tXrayEntity(book_md5, name)',
  // 面板主查询：按置信分排序 + 低分折叠（F4）。
  'CREATE INDEX IF NOT EXISTS idx_xray_entity_rank '
      'ON $tXrayEntity(book_md5, type, score)',
  // 选区就地查（F6）：按书名点查实体，命中靠上面的 name 唯一索引。
  '''
    CREATE TABLE IF NOT EXISTS $tXrayMention (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_id INTEGER NOT NULL,
      book_md5 TEXT NOT NULL,
      ch INTEGER NOT NULL,
      para INTEGER NOT NULL,
      snippet TEXT
    )
  ''',
  // 出场列表（F5）按实体取；「已解析 x/y 章」与脉络统计（F11）按章取。
  'CREATE INDEX IF NOT EXISTS idx_xray_mention_ent '
      'ON $tXrayMention(book_md5, entity_id)',
  'CREATE INDEX IF NOT EXISTS idx_xray_mention_ch '
      'ON $tXrayMention(book_md5, ch)',
  '''
    CREATE TABLE IF NOT EXISTS $tXrayUserdict (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      scope TEXT NOT NULL,
      word TEXT NOT NULL,
      type TEXT,
      action TEXT NOT NULL,
      target TEXT,
      pattern_hint TEXT,
      create_time INTEGER NOT NULL
    )
  ''',
  // 同作用域同词同动作只有一条：重复加词/重复屏蔽不积累历史行（§7 写时物化）。
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_xray_userdict_key '
      'ON $tXrayUserdict(scope, word, action)',
];

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）。
///
/// v30→v31：建 X-Ray 四表 + 给 `books` 补 `md5` 列（F9 内容指纹·存量书懒补算）。
/// `books.md5` 的**新装库形态**在 `read.dart` 的 `bookSchemaStatements` 里（基础 DDL 直接带列），
/// 这里的 `ALTER` 只服务存量库升级——与 `word_count`（v23→v24）同一条双写口径。
///
/// 注意：`books` 属 read 域，这是**全库唯一一处跨域加列**；为免迁移键被两个域同时认领
/// （中枢用 `...r.mig` / `...x.mig` 展开·同键后者静默覆盖前者），整条 v31 由本域独占，
/// 键唯一性由 `test/xray_schema_test.dart` 逐域扫源码钉住。
final Map<int, List<String>> mig = {
  30: [
    ...xraySchemaStatements,
    'ALTER TABLE books ADD COLUMN md5 TEXT',
    'CREATE INDEX IF NOT EXISTS idx_books_md5 ON books(md5) WHERE md5 IS NOT NULL',
  ],
};
