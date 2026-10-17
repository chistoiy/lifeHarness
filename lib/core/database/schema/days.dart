// 治理G5 域库：days · 由 schema.dart 外提（原名零改写）·跨域引用带前缀


  
  
  
  
  const String tDays =  'days';


  const String tDayPreps =  'day_preps';


  const String tReminderItems =  'reminder_items';



  
  
  
  const List<String> daysSchemaStatements =  [
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

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    
    19: [
      ...daysSchemaStatements,
    ]
};
