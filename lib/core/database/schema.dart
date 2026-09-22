/// 数据库 schema 定义（sqflite）。
///
/// 建库策略（ADR D6）：V0.1 即定义 待办/日程/日记/笔记 四核心表 + 收集箱，
/// **并预留** 健康/财务/物品 表结构与迁移骨架，避免后期数据迁移。
/// 插件隔离表统一以 `plugin_` 前缀命名（需求 V1.15），宿主不迁移、卸载可清理。
class DbSchema {
  const DbSchema._();

  /// 数据库文件名与版本（版本递增驱动 onUpgrade 迁移）。
  static const String fileName = 'lifeharness.db';
  static const int version = 14;

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

  /// 插件表前缀约定：宿主建表/校验/清理时据此识别。
  static const String pluginPrefix = 'plugin_';

  /// v1 全量建表 DDL。时间字段统一存 epoch 毫秒（INTEGER），日界线固定自然日 00:00
  /// （ADR D13），跨天由「开始日归属 + 跨天标记」处理。
  static const List<String> createStatements = [
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
  static const Map<int, List<String>> migrations = {
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
  };

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
}
