// 治理G5 域库：care · 由 schema.dart 外提（原名零改写）·跨域引用带前缀


  
  
  const String tCareBabies =  'care_babies';


  const String tCareCarers =  'care_carers';


  const String tCareLogs =  'care_logs';


  const String tCareCycleDays =  'care_cycle_days';


  const String tCareCyclePred =  'care_cycle_pred';


  const String tCareMeasures =  'care_measures';


  const String tCareVaccines =  'care_vaccines';


  const String tCareMilestones =  'care_milestones';


  const String tCareAllergies =  'care_allergies';


  const String tCareCustomEvents =  'care_custom_events';


  const String tCareEventOrder =  'care_event_order';



  
  
  
  const List<String> careTables =  [
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



  
  
  
  
  
  
  
  
  
  
  
  
  
  const List<String> careSchemaStatements =  [
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
    
    "INSERT OR IGNORE INTO $tCareEventOrder(key,sort) VALUES"
        "('nurse',1),('bmilk',2),('formula',3),('diaper',4),('sleep',5),('bath',6),"
        "('play',7),('supp',8),('swim',9),('water',10),('solids',11),('pump',12),('custom',13)",
  ];

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    
    
    18: [
      ...careSchemaStatements,
    ]
};
