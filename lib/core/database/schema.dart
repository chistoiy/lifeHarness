/// 数据库 schema 定义（sqflite）。
///
/// 建库策略（ADR D6）：V0.1 即定义 待办/日程/日记/笔记 四核心表 + 收集箱，
/// **并预留** 健康/财务/物品 表结构与迁移骨架，避免后期数据迁移。
/// 插件隔离表统一以 `plugin_` 前缀命名（需求 V1.15），宿主不迁移、卸载可清理。
class DbSchema {
  const DbSchema._();

  /// 数据库文件名与版本（版本递增驱动 onUpgrade 迁移）。
  static const String fileName = 'lifeharness.db';
  static const int version = 26;

  // ---- 表名常量 ----
  static const String tTodos = 'todos';
  static const String tEvents = 'events';
  static const String tJournal = 'journal_entries';
  // v6：日记真结构分节 + 模板（需求 V1.28）
  static const String tJournalSections = 'journal_sections';
  static const String tDiaryTemplates = 'diary_templates';
  static const String tTemplateSections = 'template_sections';
  static const String tNotes = 'notes';
  // v7：笔记归档/回收站 + 版本快照（M1 批1 · 需求 模块3 纯纯写作风）
  static const String tNoteSnapshots = 'note_snapshots';
  // v8：笔记多层文件夹树（需求 V1.29 · notes.folder 存文件夹名，本表管层级）
  static const String tNoteFolders = 'note_folders';
  static const String tInbox = 'inbox_items';
  static const String tSettings = 'settings';
  // 预留表（V0.1 建表，业务 M2/M3 填充）
  static const String tHealth = 'health_records';
  static const String tFinance = 'finance_txns';
  static const String tItems = 'items';
  // v3：格子时间块标记（需求 V1.4，L4 时间账本数据源）
  static const String tTimeBlocks = 'time_blocks';
  // v4：两级分类表（需求 V1.19.1，全局唯一分类源：速记列/标记/账本/统计共用）
  static const String tCategories = 'categories';
  // v11（M1批2e）：每日天气缓存（Open-Meteo 抓取落库·当天只抓一次）
  static const String tWeatherDaily = 'weather_daily';
  // v12（M1批3·阅读）：书与阅读行为三表（计划 §2.1；影音游后续另建 media_sessions 不共表）
  static const String tBooks = 'books';
  static const String tBookSessions = 'book_sessions';
  static const String tBookQuotes = 'book_quotes';
  // v13（M1批3·批2）：两级目录节点 + 书架资料字典（计划 §2.2）
  static const String tBookTocNodes = 'book_toc_nodes';
  static const String tBookDict = 'book_dict';
  // v13 内置分类种子：阅读（L4 账本计时会话入账分类·计划 §7）
  static const int catReadingId = 22;
  // v14（M1批3·批3）：摘录复习档位（艾宾浩斯 1/3/7/30 天·独立表防直升撞列）
  static const String tBookReviews = 'book_reviews';
  // v15（M1批3·批4）：书单两表（计划 §2.3；年度书单 auto_year 动态成员不落 items）
  static const String tBookLists = 'book_lists';
  static const String tBookListItems = 'book_list_items';
  // v16（M1·习惯批1）：习惯五表（计划 §2.1；按日流水为中心，
  // slips/goal_hist/freezes/pend 四表由批2/批5 顺延版本建表）
  static const String tHabits = 'habits';
  static const String tHabitSubs = 'habit_subs';
  static const String tHabitEntries = 'habit_entries';
  static const String tHabitEntrySubs = 'habit_entry_subs';
  static const String tHabitDict = 'habit_dict';
  static const String tHabitSlips = 'habit_slips';
  static const String tHabitFreezes = 'habit_freezes';
  static const String tHabitGoalHist = 'habit_goal_hist';
  static const String tHabitPend = 'habit_pend';
  // v18（M2·记账批1）：记账全家桶十一表（记账计划 §3 + 九·补1/4/5）。
  static const String tLedgerBooks = 'ledger_books';
  static const String tLedgerTxns = 'ledger_txns';
  static const String tLedgerAccounts = 'ledger_accounts';
  static const String tLedgerCategories = 'ledger_categories';
  static const String tLedgerBudgets = 'ledger_budgets';
  static const String tLedgerFav = 'ledger_fav';
  static const String tLedgerRecur = 'ledger_recur';
  static const String tLedgerWishes = 'ledger_wishes';
  static const String tLedgerDebts = 'ledger_debts';
  static const String tLedgerTagGroups = 'ledger_tag_groups';
  static const String tLedgerTags = 'ledger_tags';
  static const String tLedgerWhos = 'ledger_whos';
  static const String tLedgerMerchants = 'ledger_merchants';
  static const String tLedgerImportBatches = 'ledger_import_batches';
  // v19（M3·呵护批0）：母婴呵护十一表（交接 §3 按宝宝分档：记录/周期/预测存档/
  // 测量/疫苗/里程碑/过敏史 + 档案/记录人/自定义事件/速记顺序）。
  static const String tCareBabies = 'care_babies';
  static const String tCareCarers = 'care_carers';
  static const String tCareLogs = 'care_logs';
  static const String tCareCycleDays = 'care_cycle_days';
  static const String tCareCyclePred = 'care_cycle_pred';
  static const String tCareMeasures = 'care_measures';
  static const String tCareVaccines = 'care_vaccines';
  static const String tCareMilestones = 'care_milestones';
  static const String tCareAllergies = 'care_allergies';
  static const String tCareCustomEvents = 'care_custom_events';
  static const String tCareEventOrder = 'care_event_order';
  // v20（M4·日子批1）：重要日子三表（需求 V1.42 模块11 · 专版 P8 系）。
  // days 用 rep_mode/target_date/lunar_*/month_day 承载四种重复方式；
  // day_preps 准备事项（勾选转待办回写 todo_id）；
  // reminder_items 提醒中心（cert 手动 · sub/warranty 派生，source_key 唯一）。
  static const String tDays = 'days';
  static const String tDayPreps = 'day_preps';
  static const String tReminderItems = 'reminder_items';
  // v21（M4·物品批2）：物品价值三表（需求 V1.42 模块9 · 专版 P7 系六屏）。
  // item_events 审计时间轴仅追加（repo 不暴露改删口）；extra/res 不落列＝
  // 由 events 实算（HG-E1），billing=0 冻结决算；source/source_txn_id 来源徽标。
  static const String tItemProfiles = 'item_profiles';
  static const String tItemEvents = 'item_events';
  static const String tItemUsages = 'item_usages';
  // v22（M4·目标批3）：目标 OKR 五表（需求 V1.42 模块7 · 专版 P10 系四屏）。
  // period TEXT（'2026 Q3' | '年度目标'）；goal_periods 存周期归档态（只读口径）；
  // kr_updates 回填/来源留痕仅追加；goal_reviews 每季一份 KPT。
  static const String tGoals = 'goals';
  static const String tGoalKrs = 'goal_krs';
  static const String tKrUpdates = 'kr_updates';
  static const String tGoalReviews = 'goal_reviews';
  static const String tGoalPeriods = 'goal_periods';
  // v23（豆瓣防封批）：豆瓣书目元数据缓存单表（calibre-douban 的
  // isbn→identifier / identifier→cover 缓存思路落本地）。只存 App 在用的
  // 最小字段集、不存整页快照——防库膨胀并控制云备份体积（2026-09-26 拍板）。
  static const String tDoubanMeta = 'douban_meta';
  // v26（V1.53）：AI 使用记录单表——每次能力调用一行（含门控拒绝与取消），
  // 正文列在「记录正文」关闭时留空；Key 永不入库（需求清单 §六 原则 7）。
  static const String tAiCalls = 'ai_calls';

  /// 红线 7（V1.41·T16）：母婴呵护十一表成组清单（上方 v19 注释归组）。
  /// `care.syncExcluded` 置位时由 SnapshotService 整组作 excludeTables 传入
  /// 备份导出——同步快照剔除全部 care_* 表；本机直接备份不受影响（设计稿 §3）。
  static const List<String> careTables = [
    tCareBabies,
    tCareCarers,
    tCareLogs,
    tCareCycleDays,
    tCareCyclePred,
    tCareMeasures,
    tCareVaccines,
    tCareMilestones,
    tCareAllergies,
    tCareCustomEvents,
    tCareEventOrder,
  ];

  /// 记账兜底分类固定 id（删除大类时流水迁移目标 · 计划 §4「兜底分类不可删」）。
  static const int ledgerCatOtherExpense = 114; // 其他（支出树）
  static const int ledgerCatOtherIncome = 207; // 其他（收入树）

  /// 插件表前缀约定：宿主建表/校验/清理时据此识别。
  static const String pluginPrefix = 'plugin_';

  /// v1 全量建表 DDL。时间字段统一存 epoch 毫秒（INTEGER），日界线固定自然日 00:00
  /// （ADR D13），跨天由「开始日归属 + 跨天标记」处理。
  /// （v18 起含运行时构建的 ledger 种子，故本表 non-const。）
  static final List<String> createStatements = [
    // 模块2 待办 + 四象限（quadrant: 1~4；priority 预留；tag 标签，v2 起）
    '''
    CREATE TABLE $tTodos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      note TEXT,
      quadrant INTEGER NOT NULL DEFAULT 4,
      due_at INTEGER,
      remind_at INTEGER,
      done INTEGER NOT NULL DEFAULT 0,
      priority INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      tag TEXT,
      time_mode TEXT,
      start_min INTEGER,
      end_min INTEGER,
      pomo_mode TEXT,
      pomo_min INTEGER,
      dropped INTEGER NOT NULL DEFAULT 0,
      color INTEGER,
      grp TEXT,
      habit_id INTEGER,
      link_cat INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_todos_done ON $tTodos(done)',
    'CREATE INDEX idx_todos_due ON $tTodos(due_at)',

    // 模块1 日程 + 时间块（status: 0=计划 1=进行中 2=已完成）
    '''
    CREATE TABLE $tEvents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      start_at INTEGER NOT NULL,
      end_at INTEGER,
      all_day INTEGER NOT NULL DEFAULT 0,
      color_tag TEXT,
      status INTEGER NOT NULL DEFAULT 0,
      cross_day INTEGER NOT NULL DEFAULT 0,
      duration_min INTEGER,
      cat_id INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_events_start ON $tEvents(start_at)',

    // 模块3 日记（mood 1~7 对应原型 7 表情；tags 逗号分隔；v5 起 INS 回望字段）
    '''
    CREATE TABLE $tJournal (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_date INTEGER NOT NULL,
      mood INTEGER,
      content TEXT NOT NULL,
      tags TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      starred INTEGER NOT NULL DEFAULT 0,
      liked INTEGER NOT NULL DEFAULT 0,
      view_count INTEGER NOT NULL DEFAULT 0,
      template_id INTEGER,
      kind TEXT NOT NULL DEFAULT '',
      weather_code INTEGER,
      temp_max REAL,
      temp_min REAL,
      weather_manual INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_journal_date ON $tJournal(entry_date)',

    // v6（需求 V1.28）：日记一天多篇 · 每篇各带心情 · 真结构分节与模板。
    // journal_sections：结构化日记的正文分节（自由书写篇无行）。
    '''
    CREATE TABLE IF NOT EXISTS $tJournalSections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id INTEGER NOT NULL,
      idx INTEGER NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_jsections_entry ON $tJournalSections(entry_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tDiaryTemplates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      builtin INTEGER NOT NULL DEFAULT 0,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tTemplateSections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      template_id INTEGER NOT NULL,
      idx INTEGER NOT NULL,
      title TEXT NOT NULL,
      placeholder TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_tsections_tpl ON $tTemplateSections(template_id)',
    // 内置模板种子（与原型 DI_TPLS 同构；id 固定 1/2）
    "INSERT OR IGNORE INTO $tDiaryTemplates(id,name,builtin,sort) VALUES(1,'感恩三件事',1,1)",
    "INSERT OR IGNORE INTO $tDiaryTemplates(id,name,builtin,sort) VALUES(2,'KPT 复盘',1,2)",
    "INSERT OR IGNORE INTO $tTemplateSections(template_id,idx,title,placeholder) VALUES(1,0,'感恩 ①','小事也可以'),(1,1,'感恩 ②',NULL),(1,2,'感恩 ③',NULL)",
    "INSERT OR IGNORE INTO $tTemplateSections(template_id,idx,title,placeholder) VALUES(2,0,'Keep · 做对了什么',NULL),(2,1,'Problem · 哪里不顺',NULL),(2,2,'Try · 下一步怎么改',NULL)",

    // 模块3 笔记（kind: plain/rich/md；folder 分组；pinned 置顶；v7 archived/deleted_at；
    // v9 paper 纸色 hex·''=默认米纸·仅卡片视图条目底色跟随）
    '''
    CREATE TABLE $tNotes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT,
      content TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'plain',
      folder TEXT,
      pinned INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      deleted_at INTEGER,
      paper TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tNoteSnapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_snap_note ON $tNoteSnapshots(note_id)',
    // v8（V1.29）：笔记多层文件夹树；parent_id NULL=顶层；sort 同级排序
    '''
    CREATE TABLE IF NOT EXISTS $tNoteFolders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_id INTEGER,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',

    // 模块5 收集箱（routed_to: null=未分流, todo/event/note/journal；routed_ref 目标行 id）
    '''
    CREATE TABLE $tInbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      raw_text TEXT NOT NULL,
      kind TEXT,
      routed_to TEXT,
      routed_ref INTEGER,
      created_at INTEGER NOT NULL
    )
    ''',

    // 设置表（键值；替代骨架阶段 shared_preferences 的正式落点，ADR D11）
    '''
    CREATE TABLE $tSettings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''',

    // ---- 预留表（V0.1 建表占位，字段随里程碑细化）----
    '''
    CREATE TABLE $tHealth (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      value REAL,
      unit TEXT,
      occurred_at INTEGER NOT NULL,
      meta TEXT
    )
    ''',
    '''
    CREATE TABLE $tFinance (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      amount REAL NOT NULL,
      direction TEXT NOT NULL,
      category TEXT,
      occurred_at INTEGER NOT NULL,
      source TEXT,
      note TEXT
    )
    ''',
    '''
    CREATE TABLE $tItems (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      price REAL,
      bought_at INTEGER,
      method TEXT,
      salvage_value REAL,
      status TEXT,
      meta TEXT
    )
    ''',

    // v3 格子时间块标记（day=当日 00:00 epoch ms；start/end=分钟 0-1440；
    // source: mark=手动标记 event=日程回填；L4 时间账本数据源）
    '''
    CREATE TABLE $tTimeBlocks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      day INTEGER NOT NULL,
      start_min INTEGER NOT NULL,
      end_min INTEGER NOT NULL,
      category TEXT NOT NULL DEFAULT '其他',
      note TEXT,
      source TEXT NOT NULL DEFAULT 'mark',
      event_id INTEGER,
      cat_id INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_blocks_day ON $tTimeBlocks(day)',

    // v4 两级分类表：parent_id NULL=一级；color 十六进制（次级留空=继承父级）；
    // tag 默认标签（如 #开会）；sort 同级排序（拖拽换组/排序写回）
    '''
    CREATE TABLE $tCategories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_id INTEGER,
      name TEXT NOT NULL,
      color TEXT,
      tag TEXT,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    // v11（M1批2e）：每日天气缓存（day=YYYY-MM-DD · 城市变更后旧缓存自然失效重抓）
    '''
    CREATE TABLE IF NOT EXISTS $tWeatherDaily (
      day TEXT PRIMARY KEY,
      city TEXT NOT NULL,
      code INTEGER NOT NULL,
      tmax REAL,
      tmin REAL,
      fetched_at INTEGER NOT NULL
    )
    ''',
    ...categorySeed,
    ...bookSchemaStatements,
    ...bookTocSchemaStatements,
    ...bookReviewSchemaStatements,
    ...bookListSchemaStatements,
    ...habitSchemaStatements,
    ...habitAuxSchemaStatements,
    ...ledgerSchemaStatements,
    ...careSchemaStatements,
    ...daysSchemaStatements,
    ...itemSchemaStatements,
    ...goalSchemaStatements,
    ...doubanMetaSchemaStatements,
    ...aiCallSchemaStatements,
  ];

  /// 内置分类种子（id 固定；一级 1-10 + 22 阅读，次级 11-21）。
  static const List<String> categorySeed = [
    "INSERT OR IGNORE INTO $tCategories(id,parent_id,name,color,tag,sort) VALUES"
        "(1,NULL,'工作','#6366F1',NULL,1),"
        "(2,NULL,'学习','#8B5CF6',NULL,2),"
        "(3,NULL,'运动','#F59E0B',NULL,3),"
        "(4,NULL,'吃饭','#F97316',NULL,4),"
        "(5,NULL,'娱乐','#F472B6',NULL,5),"
        "(6,NULL,'睡眠','#3730A3',NULL,6),"
        "(7,NULL,'清洁','#34D399',NULL,7),"
        "(8,NULL,'休息','#B45309',NULL,8),"
        "(9,NULL,'路上','#64748B',NULL,9),"
        "(10,NULL,'其他','#94A3B8',NULL,10)",
    "INSERT OR IGNORE INTO $tCategories(id,parent_id,name,color,tag,sort) VALUES"
        "(11,1,'开会',NULL,'#开会',1),"
        "(12,1,'不在工位',NULL,'#加班',2),"
        "(13,8,'午休',NULL,NULL,1),"
        "(14,8,'睡觉',NULL,'#睡觉',2),"
        "(15,9,'上班',NULL,'#工作',1),"
        "(16,9,'下班',NULL,'#工作',2),"
        "(17,9,'出行',NULL,NULL,3),"
        "(18,5,'摸鱼',NULL,'#摸鱼',1),"
        "(19,5,'躺平',NULL,NULL,2),"
        "(20,5,'旅行',NULL,NULL,3),"
        "(21,5,'逛街',NULL,NULL,4)",
    // v13（M1批3·批2）：一级分类「阅读」（读书计时入 L4 账本用·计划 §7）
    "INSERT OR IGNORE INTO $tCategories(id,parent_id,name,color,tag,sort) VALUES"
        "(22,NULL,'阅读','#0EA5E9',NULL,11)",
  ];

  /// 逐级迁移：key = 升级前版本（from）。v2：todos 增 tag 标签列（保真对齐包）；
  /// v3：新增 time_blocks 格子标记表（业务②b）；
  /// v4：categories 两级分类表+种子；events/time_blocks 加 cat_id；
  ///     todos 扩 10 列（时间三态/番茄/放弃/颜色/分组/习惯绑定/关联计时分类，V1.19~V1.25）。
  /// v5：journal_entries 加 INS 回望三列（starred/liked/view_count，业务③）。
  /// （ledger 种子为运行时构建，故本表 non-const。）
  static final Map<int, List<String>> migrations = {
    1: ['ALTER TABLE $tTodos ADD COLUMN tag TEXT'],
    2: [
      '''
      CREATE TABLE IF NOT EXISTS $tTimeBlocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day INTEGER NOT NULL,
        start_min INTEGER NOT NULL,
        end_min INTEGER NOT NULL,
        category TEXT NOT NULL DEFAULT '其他',
        note TEXT,
        source TEXT NOT NULL DEFAULT 'mark',
        event_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_blocks_day ON $tTimeBlocks(day)',
    ],
    3: [
      '''
      CREATE TABLE IF NOT EXISTS $tCategories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name TEXT NOT NULL,
        color TEXT,
        tag TEXT,
        sort INTEGER NOT NULL DEFAULT 0
      )
      ''',
      ...categorySeed,
      'ALTER TABLE $tEvents ADD COLUMN cat_id INTEGER',
      'ALTER TABLE $tTimeBlocks ADD COLUMN cat_id INTEGER',
      'ALTER TABLE $tTodos ADD COLUMN time_mode TEXT',
      'ALTER TABLE $tTodos ADD COLUMN start_min INTEGER',
      'ALTER TABLE $tTodos ADD COLUMN end_min INTEGER',
      'ALTER TABLE $tTodos ADD COLUMN pomo_mode TEXT',
      'ALTER TABLE $tTodos ADD COLUMN pomo_min INTEGER',
      'ALTER TABLE $tTodos ADD COLUMN dropped INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $tTodos ADD COLUMN color INTEGER',
      'ALTER TABLE $tTodos ADD COLUMN grp TEXT',
      'ALTER TABLE $tTodos ADD COLUMN habit_id INTEGER',
      'ALTER TABLE $tTodos ADD COLUMN link_cat INTEGER',
    ],
    4: [
      'ALTER TABLE $tJournal ADD COLUMN starred INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $tJournal ADD COLUMN liked INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $tJournal ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0',
    ],
    // v6（V1.28）：一天多篇（无按日唯一约束，仅改应用层）+ 真结构分节 + 模板。
    5: [
      'ALTER TABLE $tJournal ADD COLUMN template_id INTEGER',
      '''
      CREATE TABLE IF NOT EXISTS $tJournalSections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL,
        idx INTEGER NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_jsections_entry ON $tJournalSections(entry_id)',
      '''
      CREATE TABLE IF NOT EXISTS $tDiaryTemplates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        builtin INTEGER NOT NULL DEFAULT 0,
        sort INTEGER NOT NULL DEFAULT 0
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS $tTemplateSections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_id INTEGER NOT NULL,
        idx INTEGER NOT NULL,
        title TEXT NOT NULL,
        placeholder TEXT
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_tsections_tpl ON $tTemplateSections(template_id)',
      "INSERT OR IGNORE INTO $tDiaryTemplates(id,name,builtin,sort) VALUES(1,'感恩三件事',1,1)",
      "INSERT OR IGNORE INTO $tDiaryTemplates(id,name,builtin,sort) VALUES(2,'KPT 复盘',1,2)",
      "INSERT OR IGNORE INTO $tTemplateSections(template_id,idx,title,placeholder) VALUES(1,0,'感恩 ①','小事也可以'),(1,1,'感恩 ②',NULL),(1,2,'感恩 ③',NULL)",
      "INSERT OR IGNORE INTO $tTemplateSections(template_id,idx,title,placeholder) VALUES(2,0,'Keep · 做对了什么',NULL),(2,1,'Problem · 哪里不顺',NULL),(2,2,'Try · 下一步怎么改',NULL)",
    ],
    // v7（M1 批1）：笔记管理列 + 版本快照表
    6: [
      'ALTER TABLE $tNotes ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $tNotes ADD COLUMN deleted_at INTEGER',
      '''
      CREATE TABLE IF NOT EXISTS $tNoteSnapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_snap_note ON $tNoteSnapshots(note_id)',
    ],
    // v8（V1.29）：笔记多层文件夹树表
    7: [
      '''
      CREATE TABLE IF NOT EXISTS $tNoteFolders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name TEXT NOT NULL,
        sort INTEGER NOT NULL DEFAULT 0
      )
      ''',
    ],
    // v9（V1.29轮9n）：笔记纸色按篇独立（hex·''=默认米纸·仅卡片视图条目底色跟随）
    8: ["ALTER TABLE $tNotes ADD COLUMN paper TEXT NOT NULL DEFAULT ''"],
    // v10（M1批2a）：日记自由书写富文本 kind（''=纯文本 · rich=Quill Delta JSON）
    9: ["ALTER TABLE $tJournal ADD COLUMN kind TEXT NOT NULL DEFAULT ''"],
    // v11（M1批2e）：日记天气快照（写当天抓一次落条目·历史天气不查）+ 每日缓存表
    10: [
      'ALTER TABLE $tJournal ADD COLUMN weather_code INTEGER',
      'ALTER TABLE $tJournal ADD COLUMN temp_max REAL',
      'ALTER TABLE $tJournal ADD COLUMN temp_min REAL',
      'ALTER TABLE $tJournal ADD COLUMN weather_manual INTEGER NOT NULL DEFAULT 0',
      '''
      CREATE TABLE IF NOT EXISTS $tWeatherDaily (
        day TEXT PRIMARY KEY,
        city TEXT NOT NULL,
        code INTEGER NOT NULL,
        tmax REAL,
        tmin REAL,
        fetched_at INTEGER NOT NULL
      )
      ''',
    ],
    // v12（M1批3·阅读）：books / book_sessions / book_quotes 三表（与 v1 全量段同文·幂等）。
    11: [...bookSchemaStatements],
    // v13（M1批3·批2）：目录两级节点 + 书架资料字典；补「阅读」分类种子。
    12: [
      ...bookTocSchemaStatements,
      "INSERT OR IGNORE INTO $tCategories(id,parent_id,name,color,tag,sort) VALUES"
          "(22,NULL,'阅读','#0EA5E9',NULL,11)",
    ],
    // v14（M1批3·批3）：摘录复习档位表（艾宾浩斯 1/3/7 天·计划 §4 批3）。
    // 用独立表而非 ALTER book_quotes：v11→v14 直升时「建库同文段+迁移段」会撞重复列。
    13: [
      ...bookReviewSchemaStatements,
    ],
    // v15（M1批3·批4）：书单两表（计划 §2.3 原编号 v14，被复习表占位顺延）。
    14: [
      ...bookListSchemaStatements,
    ],
    // v16（M1·习惯批1）：习惯五表（计划 §2.1 相对序号 v16；按日流水为中心，
    // streak/best 为写入时重算的缓存列，派生统计不建物化表）。
    15: [
      ...habitSchemaStatements,
    ],
    // v17（M1·习惯批2）：九表补齐——触发/宽限/目标历史/待确认队列四张辅表。
    // 一次建齐避免批4/批5 再抬版本；goal_hist 与 pend 批4/批5 才写入。
    16: [
      ...habitAuxSchemaStatements,
    ],
    // v18（M2·记账批1）：记账全家桶十一表 + 分类/账本/账户/角色/标签种子。
    // 一次建齐（含批2/批3 的 recur/wishes/debts/import_batches），避免逐批抬版本。
    17: [
      ...ledgerSchemaStatements,
    ],
    // v19（M3·呵护批0）：母婴呵护十一表 + 记录人/速记顺序种子。
    // 一次建齐（周期/宝宝两侧全部批次共用），避免逐批抬版本。
    18: [
      ...careSchemaStatements,
    ],
    // v20（M4·日子批1）：重要日子三表（需求 V1.42 模块11 全量能力）。
    19: [
      ...daysSchemaStatements,
    ],
    // v21（M4·物品批2）：物品价值三表（需求 V1.42 模块9 全量能力）。
    20: [
      ...itemSchemaStatements,
    ],
    // v22（M4·目标批3）：目标 OKR 五表（需求 V1.42 模块7 全量能力）。
    21: [
      ...goalSchemaStatements,
    ],
    // v23（豆瓣防封批）：豆瓣书目元数据缓存表（需求 2026-09-26：二次查询命中
    // 本地缓存先提醒、由用户选「用缓存/仍联网」；支持手动清理）。
    22: [
      ...doubanMetaSchemaStatements,
    ],
    // v24（V1.44 先搜后加）：books 增「字数/装帧/购入日期」三列。需求清单原口径只列
    // word_count，但整页表单「装帧」「购入日期」行必须落库（丛书复用 series、
    // 作者简介复用 author_note、豆瓣评分存 douban_meta.rating 不加列），故同迁移带上。
    23: [
      'ALTER TABLE $tBooks ADD COLUMN word_count INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $tBooks ADD COLUMN binding TEXT',
      'ALTER TABLE $tBooks ADD COLUMN fee_date TEXT',
    ],
    // v25（V1.50 阅读器并入书架专版·批1）：本地 EPUB 阅读能力四列一次建齐——
    // books.local＝1 标记本地导入书（封面角标 + 点封面直达阅读器的分流依据）；
    // books.epub＝JSON {fmt,size,path}（EPUB 版本/源文件字节数/应用私有目录路径）；
    // book_quotes.cf＝划线书摘的 CFI 出处 JSON {c,p0,p1}（章序+段落区间，批3 划词用）；
    // book_quotes.rid＝阅读器高亮稳定标识（批3 双向映射与 brSync 暂存回灌用）。
    // 阅读位置/逐书外观走 settings 表 KV（reader.* 键，无新表；不新建批注表口径）。
    24: [
      'ALTER TABLE $tBooks ADD COLUMN local INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $tBooks ADD COLUMN epub TEXT',
      'ALTER TABLE $tBookQuotes ADD COLUMN cf TEXT',
      'ALTER TABLE $tBookQuotes ADD COLUMN rid TEXT',
    ],
    // v25（V1.53）：AI 使用记录表 ai_calls（每次能力调用一行，含门控拒绝与取消；
    // 正文可整体停记或单独清除；Key 永不入库）。
    25: [
      ...aiCallSchemaStatements,
    ],
  };

  /// v26 AI 使用记录（V1.53）DDL：建库与迁移共用（幂等）。
  /// status：ok|fail|cancel|denied（denied=三重门控拒绝，同样入账，用户要能看到"没发出去"的原因）；
  /// sys/usr/out 为发送与返回正文，超 8000 字上限截断并置 cut=1；
  /// recordBody 关掉时三段留空，用量列照记。module 取能力点自带模块，新增能力零改表。
  static const List<String> aiCallSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tAiCalls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts INTEGER NOT NULL,
      task_id TEXT NOT NULL,
      module TEXT NOT NULL,
      name TEXT NOT NULL,
      status TEXT NOT NULL,
      in_tok INTEGER NOT NULL DEFAULT 0,
      out_tok INTEGER NOT NULL DEFAULT 0,
      ms INTEGER NOT NULL DEFAULT 0,
      sys TEXT,
      usr TEXT,
      out TEXT,
      err TEXT,
      cut INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_ai_calls_ts ON $tAiCalls(ts)',
    'CREATE INDEX IF NOT EXISTS idx_ai_calls_module ON $tAiCalls(module)',
  ];

  /// v23 豆瓣元数据缓存 DDL（建库与迁移共用·幂等）。
  /// code＝查询码原样（ISBN 13 位或豆瓣 subject_id）；subject 存命中的
  /// subject_id（ISBN 重定向后的真身，二次直抓免重定向）；cover_path 为
  /// 已落本地的封面文件路径（换机备份随私有目录走，清了缓存不删封面文件，
  /// 由「清除缓存」按钮只管本表行）。
  static const List<String> doubanMetaSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tDoubanMeta (
      code TEXT PRIMARY KEY,
      subject TEXT,
      title TEXT NOT NULL,
      author TEXT,
      publisher TEXT,
      pub_date TEXT,
      pages INTEGER,
      rating REAL,
      cover_url TEXT,
      cover_path TEXT,
      via_suggest INTEGER NOT NULL DEFAULT 0,
      fetched_at INTEGER NOT NULL
    )
    ''',
  ];

  /// v22 目标 OKR 五表 DDL（建库与迁移共用·幂等）。
  /// period：'2026 Q1'..'2026 Q4' 或 '年度目标'；归档只读口径落 goal_periods；
  /// goal_krs.src：manual|todo|read|journal|habit|ledger（自动汇聚在载入时实算）。
  static const List<String> goalSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tGoals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      period TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tGoalKrs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      goal_id INTEGER NOT NULL,
      label TEXT NOT NULL,
      target REAL NOT NULL,
      unit TEXT NOT NULL DEFAULT '项',
      src TEXT NOT NULL DEFAULT 'manual',
      cur REAL NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_goal_krs_goal ON $tGoalKrs(goal_id)
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tKrUpdates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kr_id INTEGER NOT NULL,
      cur REAL NOT NULL,
      kind TEXT NOT NULL,
      note TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tGoalReviews (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      period TEXT NOT NULL UNIQUE,
      keep TEXT NOT NULL DEFAULT '',
      problem TEXT NOT NULL DEFAULT '',
      trial TEXT NOT NULL DEFAULT '',
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tGoalPeriods (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      period TEXT NOT NULL UNIQUE,
      archived INTEGER NOT NULL DEFAULT 0,
      archived_at INTEGER
    )
    ''',
  ];

  /// v21 物品价值三表 DDL（建库与迁移共用·幂等）。
  /// status：使用中|闲置|已回收(抵扣留用)|已回收(转出)|已报废；
  /// mode：day 直线|times 按次|stop 止损（止损叠加直线基线）；
  /// 自然日一律 TEXT 'YYYY-MM-DD'；name/warranty 列名与 days 侧派生同步器对齐。
  static const List<String> itemSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tItemProfiles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      icon TEXT NOT NULL DEFAULT 'box',
      category TEXT NOT NULL DEFAULT '数码',
      buy_date TEXT NOT NULL,
      price REAL NOT NULL,
      expected_years INTEGER,
      warranty TEXT,
      status TEXT NOT NULL DEFAULT '使用中',
      billing INTEGER NOT NULL DEFAULT 1,
      mode TEXT NOT NULL DEFAULT 'day',
      plan_units REAL,
      unit TEXT,
      stop_pct INTEGER DEFAULT 30,
      photo TEXT,
      source TEXT NOT NULL DEFAULT 'manual',
      source_txn_id INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tItemEvents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL,
      kind TEXT NOT NULL,
      label TEXT NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      note TEXT,
      event_date TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_item_events_item ON $tItemEvents(item_id)
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tItemUsages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL,
      day TEXT NOT NULL,
      qty REAL NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_item_usages_item ON $tItemUsages(item_id)
    ''',
  ];

  /// v20 重要日子三表 DDL（建库与迁移共用·幂等）。
  /// rep_mode：once|solar-year|lunar|monthly；自然日一律 TEXT 'YYYY-MM-DD'；
  /// reminder_items.source_key 局部唯一索引＝派生条目（sub/warranty）随源刷新的锚。
  static const List<String> daysSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tDays (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      icon TEXT NOT NULL DEFAULT 'cake',
      color TEXT NOT NULL DEFAULT 'rose',
      category TEXT NOT NULL DEFAULT '倒数',
      rep_mode TEXT NOT NULL DEFAULT 'solar-year',
      target_date TEXT,
      lunar_month INTEGER,
      lunar_day INTEGER,
      month_day INTEGER,
      rem_offsets TEXT NOT NULL DEFAULT '[7,0]',
      note TEXT,
      pinned INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      link_diary INTEGER NOT NULL DEFAULT 1,
      prep_to_todo INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tDayPreps (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      day_id INTEGER NOT NULL,
      label TEXT NOT NULL,
      done INTEGER NOT NULL DEFAULT 0,
      todo_id INTEGER
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_day_preps_day ON $tDayPreps(day_id)
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tReminderItems (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      icon TEXT NOT NULL DEFAULT 'id',
      due_date TEXT NOT NULL,
      tip TEXT,
      meta TEXT,
      source_key TEXT,
      handled INTEGER NOT NULL DEFAULT 0,
      handled_at INTEGER,
      snooze_date TEXT,
      snooze_hour INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_remind_source
      ON $tReminderItems(source_key) WHERE source_key IS NOT NULL
    ''',
  ];

  /// v16 习惯五表 DDL（建库与迁移共用，保两处永远同文·幂等 · 习惯计划 §2.1）。
  /// 自然日一律 TEXT 'YYYY-MM-DD'（D13 日界线 00:00）；
  /// habit_entries UNIQUE(habit_id,day)＝同日二次写为改值不新增（时钟篡改防护）。
  static const List<String> habitSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tHabits (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      icon TEXT NOT NULL,
      type TEXT NOT NULL,
      cat TEXT,
      cycle TEXT NOT NULL,
      week_days TEXT,
      month_target INTEGER,
      neg_limit INTEGER NOT NULL DEFAULT 0,
      unit TEXT,
      goal REAL,
      group_rule TEXT,
      source_kinds TEXT,
      remind_at TEXT,
      todo_id TEXT,
      todo_form TEXT,
      start_date TEXT NOT NULL,
      streak INTEGER NOT NULL DEFAULT 0,
      best INTEGER NOT NULL DEFAULT 0,
      archived_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_habits_cat ON $tHabits(cat)',
    'CREATE INDEX IF NOT EXISTS idx_habits_type ON $tHabits(type)',
    'CREATE INDEX IF NOT EXISTS idx_habits_arch ON $tHabits(archived_at)',
    'CREATE INDEX IF NOT EXISTS idx_habits_todo ON $tHabits(todo_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tHabitSubs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      habit_id TEXT NOT NULL,
      name TEXT NOT NULL,
      unit TEXT,
      goal REAL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_hsubs_habit ON $tHabitSubs(habit_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tHabitEntries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      habit_id TEXT NOT NULL,
      day TEXT NOT NULL,
      checked INTEGER NOT NULL DEFAULT 1,
      value REAL,
      origin TEXT NOT NULL,
      check_at TEXT,
      backfilled INTEGER NOT NULL DEFAULT 0,
      frozen INTEGER NOT NULL DEFAULT 0,
      note TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE(habit_id, day)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_hent_habit ON $tHabitEntries(habit_id)',
    'CREATE INDEX IF NOT EXISTS idx_hent_day ON $tHabitEntries(day)',
    'CREATE INDEX IF NOT EXISTS idx_hent_bf ON $tHabitEntries(backfilled)',
    '''
    CREATE TABLE IF NOT EXISTS $tHabitEntrySubs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id INTEGER NOT NULL,
      sub_id INTEGER NOT NULL,
      value REAL,
      UNIQUE(entry_id, sub_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_hes_ent ON $tHabitEntrySubs(entry_id)',
    // 分类/单位共用字典（kind ∈ cat|unit）：改名走事务迁移、删除前引用守卫（批2）。
    '''
    CREATE TABLE IF NOT EXISTS $tHabitDict (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_hdict_kind_name ON $tHabitDict(kind, name)',
    // 默认字典种子（原型 HB_CATS / HB_UNITS 同序；用户可增删改）
    "INSERT OR IGNORE INTO $tHabitDict(kind,name,sort) VALUES"
        "('cat','健康',1),('cat','学习',2),('cat','工作',3),('cat','生活',4),('cat','成长',5)",
    "INSERT OR IGNORE INTO $tHabitDict(kind,name,sort) VALUES"
        "('unit','分钟',1),('unit','个',2),('unit','次',3),('unit','杯',4),('unit','页',5),"
        "('unit','词',6),('unit','字',7),('unit','公里',8),('unit','组',9),('unit','篇',10),('unit','题',11)",
  ];

  /// v17 习惯辅四表 DDL（建库与迁移共用同文·幂等 · 习惯计划 §2.1 九表补齐）。
  static const List<String> habitAuxSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tHabitSlips (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      habit_id TEXT NOT NULL,
      day TEXT NOT NULL,
      check_at TEXT,
      amount REAL,
      amount_text TEXT,
      reasons TEXT,
      note TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_hslip_habit ON $tHabitSlips(habit_id)',
    'CREATE INDEX IF NOT EXISTS idx_hslip_day ON $tHabitSlips(day)',
    '''
    CREATE TABLE IF NOT EXISTS $tHabitFreezes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      habit_id TEXT NOT NULL,
      day TEXT NOT NULL,
      used_at INTEGER,
      source TEXT NOT NULL DEFAULT 'grace'
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_hfrz_habit ON $tHabitFreezes(habit_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tHabitGoalHist (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      habit_id TEXT NOT NULL,
      goal REAL,
      unit TEXT,
      sub_goal TEXT,
      effective_from TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_hgh_habit ON $tHabitGoalHist(habit_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tHabitPend (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      habit_id TEXT NOT NULL,
      day TEXT NOT NULL,
      src TEXT,
      value REAL,
      sub_values TEXT,
      created_at INTEGER,
      state TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_hpend_habit ON $tHabitPend(habit_id)',
    'CREATE INDEX IF NOT EXISTS idx_hpend_state ON $tHabitPend(state)',
  ];

  /// v12 阅读三表 DDL（建库与迁移共用，保两处永远同文）。
  static const List<String> bookSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tBooks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL DEFAULT '佚名',
      translator TEXT,
      publisher TEXT,
      pub_date TEXT,
      series TEXT,
      isbn TEXT,
      cover_path TEXT,
      color_idx INTEGER NOT NULL DEFAULT 0,
      state TEXT NOT NULL DEFAULT '想读',
      format TEXT NOT NULL DEFAULT '纸质',
      progress_way TEXT NOT NULL DEFAULT 'page',
      pages INTEGER NOT NULL DEFAULT 0,
      read_pages INTEGER NOT NULL DEFAULT 0,
      total_loc REAL,
      read_loc REAL,
      chapter TEXT,
      rating REAL NOT NULL DEFAULT 0,
      fee REAL NOT NULL DEFAULT 0,
      fee_txn_id INTEGER,
      source TEXT,
      grp TEXT,
      tags TEXT NOT NULL DEFAULT '',
      started_at INTEGER,
      ended_at INTEGER,
      last_read_at INTEGER,
      intro TEXT,
      author_note TEXT,
      note TEXT,
      final_note TEXT,
      sum_quote TEXT,
      sum_view TEXT,
      sum_gain TEXT,
      word_count INTEGER NOT NULL DEFAULT 0,
      binding TEXT,
      fee_date TEXT,
      local INTEGER NOT NULL DEFAULT 0,
      epub TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_books_state ON $tBooks(state)',
    'CREATE INDEX IF NOT EXISTS idx_books_author ON $tBooks(author)',
    'CREATE INDEX IF NOT EXISTS idx_books_source ON $tBooks(source)',
    'CREATE INDEX IF NOT EXISTS idx_books_grp ON $tBooks(grp)',
    'CREATE INDEX IF NOT EXISTS idx_books_last ON $tBooks(last_read_at)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_books_isbn ON $tBooks(isbn) WHERE isbn IS NOT NULL AND isbn != \'\'',
    '''
    CREATE TABLE IF NOT EXISTS $tBookSessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      ended_at INTEGER,
      minutes INTEGER NOT NULL DEFAULT 0,
      speed REAL,
      from_page INTEGER,
      to_page INTEGER,
      from_loc REAL,
      to_loc REAL,
      source TEXT NOT NULL DEFAULT 'timer',
      txn_id INTEGER
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_bsess_book ON $tBookSessions(book_id)',
    'CREATE INDEX IF NOT EXISTS idx_bsess_start ON $tBookSessions(started_at)',
    '''
    CREATE TABLE IF NOT EXISTS $tBookQuotes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      tag TEXT NOT NULL,
      tags TEXT NOT NULL DEFAULT '',
      body TEXT NOT NULL,
      thought TEXT,
      chapter TEXT,
      page INTEGER,
      loc REAL,
      image_paths TEXT,
      starred INTEGER NOT NULL DEFAULT 0,
      origin TEXT,
      dedup_hash TEXT,
      cf TEXT,
      rid TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_bq_book ON $tBookQuotes(book_id)',
    'CREATE INDEX IF NOT EXISTS idx_bq_tag ON $tBookQuotes(tag)',
    'CREATE INDEX IF NOT EXISTS idx_bq_created ON $tBookQuotes(created_at)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_bq_dedup ON $tBookQuotes(dedup_hash)',
  ];

  /// v14 复习档位表 DDL（建库与迁移共用·幂等）。
  static const List<String> bookReviewSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tBookReviews (
      quote_id INTEGER PRIMARY KEY,
      stage INTEGER NOT NULL DEFAULT 0,
      next_at INTEGER
    )
    ''',
  ];

  /// v15 书单两表 DDL（建库与迁移共用·幂等 · 计划 §2.3）。
  /// auto_year 非空＝年度书单：成员由 state='已读' AND ended_at∈该年 动态求得，
  /// items 不写库（原型 blIds 口径）。
  static const List<String> bookListSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tBookLists (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      note TEXT,
      auto_year INTEGER,
      sort INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tBookListItems (
      list_id INTEGER NOT NULL,
      book_id TEXT NOT NULL,
      pos INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (list_id, book_id)
    )
    ''',
  ];

  /// v13 目录与字典 DDL（建库与迁移共用，保两处永远同文）。
  static const List<String> bookTocSchemaStatements = [
    // 两级目录：parent_id NULL=部分；idx 同级序；state done|reading|NULL；
    // 人工增删改后置 confirmed=1（计划 §2.2 / §3.3 目录可手动微调）。
    '''
    CREATE TABLE IF NOT EXISTS $tBookTocNodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id TEXT NOT NULL,
      parent_id INTEGER,
      level INTEGER NOT NULL DEFAULT 1,
      idx INTEGER NOT NULL DEFAULT 0,
      title TEXT NOT NULL,
      start_page INTEGER,
      start_loc REAL,
      state TEXT,
      ai_generated INTEGER NOT NULL DEFAULT 0,
      confirmed INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_btoc_book ON $tBookTocNodes(book_id)',
    // 书架资料字典：kind ∈ source|group|tag|author|publisher；
    // 改名在事务内回写 books（计划 §3.4 资料管理器行）。
    '''
    CREATE TABLE IF NOT EXISTS $tBookDict (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0,
      extra TEXT
    )
    ''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_bdict_kind_name ON $tBookDict(kind, name)',
  ];

  /// v18 记账全家桶 DDL + 种子（建库与迁移共用同文·幂等 · 记账计划 §3 + 九·补1/4/5）。
  ///
  /// 口径：
  /// - 流水/预算/周期/心愿/借贷带 `bk` 按账本隔离；**账户全局共用**（余额=base+Σeff 跨账本合并，
  ///   `balance_cache` 为写路径同事务重算的物化列，供仪表盘快读）；
  /// - `unpaid`=未付款（计收支不动余额）、`nb`=不计入（mStat/catStat/预算四出口同时剔除）；
  /// - 两级分类：大类 parent_id NULL；子分类行 parent_id=大类 id。流水引用口径为
  ///   `cat_id`(大类) + `sub`(子分类名字符串，原型口径)；子分类改名事务内同步流水；
  /// - `bill_hash` UNIQUE 兜底去重（交易单号优先，缺失时「时间|金额|对方」组合键，
  ///   同 read 模块 dedup_hash 先例）；导入批次表支持整批撤销。
  static final List<String> ledgerSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerBooks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerAccounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      base REAL NOT NULL DEFAULT 0,
      credit_limit REAL,
      bill_day INTEGER,
      repay_day INTEGER,
      icon TEXT NOT NULL DEFAULT 'wallet',
      color TEXT NOT NULL DEFAULT '#0ea5e9',
      archived INTEGER NOT NULL DEFAULT 0,
      balance_cache REAL NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerTxns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      amt REAL NOT NULL,
      cat_id INTEGER,
      sub TEXT,
      account_id INTEGER NOT NULL,
      to_account_id INTEGER,
      date TEXT NOT NULL,
      time TEXT,
      note TEXT,
      tags TEXT NOT NULL DEFAULT '[]',
      source TEXT NOT NULL DEFAULT 'manual',
      link_id TEXT,
      refund_of INTEGER,
      recurring_id INTEGER,
      wish_id INTEGER,
      debt_id INTEGER,
      bill_hash TEXT,
      imp_batch INTEGER,
      bk INTEGER NOT NULL,
      unpaid INTEGER NOT NULL DEFAULT 0,
      nb INTEGER NOT NULL DEFAULT 0,
      merchant TEXT,
      who TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_ltx_bk_date ON $tLedgerTxns(bk, date)',
    'CREATE INDEX IF NOT EXISTS idx_ltx_cat ON $tLedgerTxns(cat_id)',
    'CREATE INDEX IF NOT EXISTS idx_ltx_acct ON $tLedgerTxns(account_id)',
    'CREATE INDEX IF NOT EXISTS idx_ltx_refund ON $tLedgerTxns(refund_of)',
    'CREATE INDEX IF NOT EXISTS idx_ltx_batch ON $tLedgerTxns(imp_batch)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_ltx_billhash ON $tLedgerTxns(bill_hash) WHERE bill_hash IS NOT NULL AND bill_hash != \'\'',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerCategories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      parent_id INTEGER,
      name TEXT NOT NULL,
      icon TEXT NOT NULL DEFAULT 'dots',
      color TEXT NOT NULL DEFAULT '#94a3b8',
      hidden INTEGER NOT NULL DEFAULT 0,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_lcat_parent ON $tLedgerCategories(parent_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerBudgets (
      bk INTEGER NOT NULL,
      month TEXT NOT NULL,
      cat_id INTEGER NOT NULL DEFAULT 0,
      amt REAL NOT NULL DEFAULT 0,
      carry INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (bk, month, cat_id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerFav (
      cat_id INTEGER NOT NULL,
      sub TEXT NOT NULL DEFAULT '',
      PRIMARY KEY (cat_id, sub)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerRecur (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bk INTEGER NOT NULL,
      name TEXT NOT NULL,
      amt REAL NOT NULL,
      cat_id INTEGER,
      sub TEXT,
      account_id INTEGER NOT NULL,
      freq TEXT NOT NULL,
      next_date TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1,
      note TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerWishes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bk INTEGER NOT NULL,
      name TEXT NOT NULL,
      target REAL NOT NULL,
      saved REAL NOT NULL DEFAULT 0,
      done INTEGER NOT NULL DEFAULT 0,
      done_date TEXT,
      done_txn INTEGER
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerDebts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bk INTEGER NOT NULL,
      side TEXT NOT NULL,
      person TEXT NOT NULL,
      total REAL NOT NULL,
      paid REAL NOT NULL DEFAULT 0,
      note TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerTagGroups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerTags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_ltag_group ON $tLedgerTags(group_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerWhos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      is_default INTEGER NOT NULL DEFAULT 0,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerMerchants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tLedgerImportBatches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bk INTEGER NOT NULL,
      platform TEXT NOT NULL,
      file_name TEXT,
      written INTEGER NOT NULL DEFAULT 0,
      new_account_ids TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    ..._ledgerSeeds(),
  ];

  /// v19 母婴呵护十一表 DDL + 种子（建库与迁移共用同文·幂等 · 交接 §3/§4）。
  ///
  /// 口径：
  /// - 所有宝宝维度数据带 `baby_id` 分档（记录/曲线测量/疫苗/里程碑/过敏史），
  ///   删除档案在仓储事务内级联清理（替代原型 shiftDict 字典重排）；
  /// - care_logs 一行一事件（补剂多条=多行），字段与原型记录对象同构
  ///   {k,s,e,dur,ml,tmp,seg,dia,color,tex,vol,name,unit,amt,note,rec,at}；
  ///   展示文本/图标由数据在应用层生成，不落库（红线 6）；
  /// - 周期日状态存 care_cycle_days（state ''|s|p1|p），经期区间与预测由
  ///   p1 起点 + 平均周期在应用层推导；每次重算预测把旧预测行置 superseded
  ///   并新增一行（「保留旧预测存档」红线）；
  /// - 自定义事件键 `cus:名`，改名走事务键迁移 + care_logs.k 回写（红线 8）；
  /// - care.* 设置 KV 走 settings 表（先例 habit.*/ledger.*）。
  static const List<String> careSchemaStatements = [
    '''
    CREATE TABLE IF NOT EXISTS $tCareBabies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      sex TEXT NOT NULL DEFAULT '女',
      birth TEXT NOT NULL,
      color TEXT NOT NULL DEFAULT 'sky',
      avatar TEXT NOT NULL DEFAULT '🧸',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tCareCarers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_care_carer_name ON $tCareCarers(name)',
    "INSERT OR IGNORE INTO $tCareCarers(name,sort) VALUES('妈妈',1),('爸爸',2),('奶奶',3),('月嫂',4)",
    '''
    CREATE TABLE IF NOT EXISTS $tCareLogs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      baby_id INTEGER NOT NULL,
      day TEXT NOT NULL,
      k TEXT NOT NULL,
      s TEXT NOT NULL,
      e TEXT,
      dur INTEGER,
      ml REAL,
      tmp REAL,
      seg TEXT,
      dia TEXT,
      color TEXT,
      tex TEXT,
      vol TEXT,
      name TEXT,
      unit TEXT,
      amt TEXT,
      note TEXT,
      rec TEXT,
      at TEXT,
      ala TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_carelog_baby_day ON $tCareLogs(baby_id, day)',
    'CREATE INDEX IF NOT EXISTS idx_carelog_k ON $tCareLogs(k)',
    '''
    CREATE TABLE IF NOT EXISTS $tCareCycleDays (
      day TEXT PRIMARY KEY,
      state TEXT NOT NULL DEFAULT '',
      flow TEXT,
      temp REAL,
      ovu TEXT,
      syms TEXT,
      note TEXT,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tCareCyclePred (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      next_start TEXT NOT NULL,
      ov_day TEXT,
      made_at INTEGER NOT NULL,
      superseded INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tCareMeasures (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      baby_id INTEGER NOT NULL,
      day TEXT NOT NULL,
      w REAL NOT NULL,
      h REAL NOT NULL,
      head REAL NOT NULL,
      rec TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_caremsr_baby ON $tCareMeasures(baby_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tCareVaccines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      baby_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      dose TEXT NOT NULL DEFAULT '第1剂',
      due TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT '免规',
      lead INTEGER NOT NULL DEFAULT 7,
      done_day TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_carevax_baby ON $tCareVaccines(baby_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tCareMilestones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      baby_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      cat TEXT NOT NULL DEFAULT '大运动',
      day TEXT,
      done INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_caremile_baby ON $tCareMilestones(baby_id)',
    '''
    CREATE TABLE IF NOT EXISTS $tCareAllergies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      baby_id INTEGER NOT NULL,
      food TEXT NOT NULL,
      reaction TEXT,
      created_at INTEGER NOT NULL,
      UNIQUE(baby_id, food)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tCareCustomEvents (
      key TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      icon TEXT NOT NULL DEFAULT '✨',
      unit TEXT NOT NULL DEFAULT 'ml'
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $tCareEventOrder (
      key TEXT PRIMARY KEY,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    // 速记区初始顺序种子（原型 EV_BASE 同序；用户排序后写回覆盖）。
    "INSERT OR IGNORE INTO $tCareEventOrder(key,sort) VALUES"
        "('nurse',1),('bmilk',2),('formula',3),('diaper',4),('sleep',5),('bath',6),"
        "('play',7),('supp',8),('swim',9),('water',10),('solids',11),('pump',12),('custom',13)",
  ];

  /// 记账种子：默认账本 + 现金账户 + 两级分类树（原型 LCATS 同序同色）+
  /// 角色/标签分组（原型 L.whos / L.tagGroups）；全部 INSERT OR IGNORE 幂等。
  static List<String> _ledgerSeeds() {
    final now = 0; // 种子行哨兵时间（用户数据一律写真实 epoch ms）
    final out = <String>[
      "INSERT OR IGNORE INTO $tLedgerBooks(id,name,sort,created_at) VALUES(1,'日常账本',1,$now)",
      "INSERT OR IGNORE INTO $tLedgerAccounts(id,type,name,base,icon,color) "
          "VALUES(1,'cash','现金',0,'wallet','#f59e0b')",
    ];
    // 大类 id 101~114（支出）/201~207（收入）；子分类 id=大类*10+序。
    const expenseCats = [
      (101, '餐饮', 'food', '#f97316', ['早餐', '午餐', '晚餐', '饮品', '外卖', '零食']),
      (102, '交通', 'car', '#0ea5e9', ['地铁', '打车', '加油', '单车', '停车']),
      (103, '购物', 'bag', '#fb7185', ['日用', '数码', '服饰', '美妆']),
      (104, '居住', 'home', '#6366f1', ['房租', '水电', '物业', '宽带']),
      (105, '娱乐', 'film', '#a855f7', ['电影', '游戏', '聚会', '演出']),
      (106, '运动', 'run', '#22c55e', ['健身', '装备']),
      (107, '学习', 'book', '#8b5cf6', ['书籍', '课程']),
      (108, '医疗健康', 'heart', '#ef4444', ['门诊', '药品', '体检']),
      (109, '旅行', 'plane', '#06b6d4', ['交通', '住宿', '门票']),
      (110, '人情', 'gift', '#f59e0b', ['红包', '礼物', 'AA']),
      (111, '通讯', 'phone', '#64748b', ['话费', '流量']),
      (112, '宠物', 'paw', '#d946ef', ['主粮', '医疗', '用品']),
      (113, '订阅', 'repeat', '#14b8a6', ['会员', '软件', '自动续费']),
      (ledgerCatOtherExpense, '其他', 'dots', '#94a3b8', <String>[]),
    ];
    const incomeCats = [
      (201, '工资', 'wallet', '#22c55e', ['月薪', '津补贴']),
      (202, '奖金', 'star', '#f59e0b', ['绩效', '年终奖']),
      (203, '兼职', 'laptop', '#0ea5e9', ['外包', '私活']),
      (204, '理财', 'chart', '#14b8a6', ['利息', '分红', '赎回']),
      (205, '报销', 'receipt', '#8b5cf6', <String>[]),
      (206, '红包', 'redpack', '#fb7185', <String>[]),
      (ledgerCatOtherIncome, '其他', 'dots', '#94a3b8', <String>[]),
    ];
    for (final (kind, cats) in [('expense', expenseCats), ('income', incomeCats)]) {
      var sort = 0;
      for (final (id, name, icon, color, subs) in cats) {
        out.add("INSERT OR IGNORE INTO $tLedgerCategories"
            '(id,kind,parent_id,name,icon,color,sort) VALUES'
            "($id,'$kind',NULL,'$name','$icon','$color',${++sort})");
        var subSort = 0;
        for (final s in subs) {
          out.add("INSERT OR IGNORE INTO $tLedgerCategories"
              '(id,kind,parent_id,name,icon,color,sort) VALUES'
              "(${id * 10 + subSort + 1},'$kind',$id,'$s','$icon','$color',${++subSort})");
        }
      }
    }
    out.add("INSERT OR IGNORE INTO $tLedgerWhos(id,name,is_default,sort) VALUES"
        "(1,'自己',1,1),(2,'家人',0,2),(3,'伴侣',0,3),(4,'同事',0,4),(5,'朋友',0,5),(6,'代付',0,6)");
    out.add("INSERT OR IGNORE INTO $tLedgerTagGroups(id,name,sort) VALUES(1,'消费性质',1),(2,'场景',2)");
    out.add("INSERT OR IGNORE INTO $tLedgerTags(id,group_id,name,sort) VALUES"
        "(1,1,'必要',1),(2,1,'冲动',2),(3,1,'性价比',3),"
        "(4,2,'报销',1),(5,2,'出差',2),(6,2,'AA',3),(7,2,'爱好',4),(8,2,'家庭',5)");
    return out;
  }
}
