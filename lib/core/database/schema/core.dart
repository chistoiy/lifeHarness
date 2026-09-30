// 治理G5 域库：core · 由 schema.dart 外提（原名零改写）·跨域引用带前缀



  
  const String tTodos =  'todos';


  const String tEvents =  'events';


  const String tJournal =  'journal_entries';


  
  const String tJournalSections =  'journal_sections';


  const String tDiaryTemplates =  'diary_templates';


  const String tTemplateSections =  'template_sections';


  const String tNotes =  'notes';


  
  const String tNoteSnapshots =  'note_snapshots';


  
  const String tNoteFolders =  'note_folders';


  const String tInbox =  'inbox_items';


  const String tSettings =  'settings';


  
  const String tHealth =  'health_records';


  
  const String tTimeBlocks =  'time_blocks';


  
  const String tCategories =  'categories';


  
  const String tWeatherDaily =  'weather_daily';



  
  const List<String> categorySeed =  [
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
    
    "INSERT OR IGNORE INTO $tCategories(id,parent_id,name,color,tag,sort) VALUES"
        "(22,NULL,'阅读','#0EA5E9',NULL,11)",
  ];

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    // V1.57 E 批 · v29：待办垃圾箱软删列（NULL=在册）。只加列，不动任何既有行数据。
    28: ['ALTER TABLE $tTodos ADD COLUMN deleted_at INTEGER'],
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
    
    8: ["ALTER TABLE $tNotes ADD COLUMN paper TEXT NOT NULL DEFAULT ''"],
    
    9: ["ALTER TABLE $tJournal ADD COLUMN kind TEXT NOT NULL DEFAULT ''"],
    
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
    ]
};
