// 治理G5 域库：goals · 由 schema.dart 外提（原名零改写）·跨域引用带前缀


  
  
  
  const String tGoals =  'goals';


  const String tGoalKrs =  'goal_krs';


  const String tKrUpdates =  'kr_updates';


  const String tGoalReviews =  'goal_reviews';


  const String tGoalPeriods =  'goal_periods';



  
  
  
  const List<String> goalSchemaStatements =  [
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

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    
    21: [
      ...goalSchemaStatements,
    ]
};
