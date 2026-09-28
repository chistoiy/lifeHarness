// 治理G5 域库：habit · 由 schema.dart 外提（原名零改写）·跨域引用带前缀


  
  
  const String tHabits =  'habits';


  const String tHabitSubs =  'habit_subs';


  const String tHabitEntries =  'habit_entries';


  const String tHabitEntrySubs =  'habit_entry_subs';


  const String tHabitDict =  'habit_dict';


  const String tHabitSlips =  'habit_slips';


  const String tHabitFreezes =  'habit_freezes';


  const String tHabitGoalHist =  'habit_goal_hist';


  const String tHabitPend =  'habit_pend';



  
  
  
  const List<String> habitSchemaStatements =  [
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
    
    '''
    CREATE TABLE IF NOT EXISTS $tHabitDict (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_hdict_kind_name ON $tHabitDict(kind, name)',
    
    "INSERT OR IGNORE INTO $tHabitDict(kind,name,sort) VALUES"
        "('cat','健康',1),('cat','学习',2),('cat','工作',3),('cat','生活',4),('cat','成长',5)",
    "INSERT OR IGNORE INTO $tHabitDict(kind,name,sort) VALUES"
        "('unit','分钟',1),('unit','个',2),('unit','次',3),('unit','杯',4),('unit','页',5),"
        "('unit','词',6),('unit','字',7),('unit','公里',8),('unit','组',9),('unit','篇',10),('unit','题',11)",
  ];



  
  const List<String> habitAuxSchemaStatements =  [
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

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    
    
    15: [
      ...habitSchemaStatements,
    ],
    
    
    16: [
      ...habitAuxSchemaStatements,
    ]
};
