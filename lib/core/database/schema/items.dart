// 治理G5 域库：items · 由 schema.dart 外提（原名零改写）·跨域引用带前缀


  const String tItems =  'items';


  
  
  
  const String tItemProfiles =  'item_profiles';


  const String tItemEvents =  'item_events';


  const String tItemUsages =  'item_usages';



  
  
  
  
  const List<String> itemSchemaStatements =  [
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
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_item_profiles_deleted ON $tItemProfiles(deleted_at)
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

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    
    20: [
      ...itemSchemaStatements,
    ],
    // 35→36（V1.61 物品档案删除）：item_profiles 加软删列，子表不加（随父行判在册）。
    // 老库全部行 deleted_at=NULL＝在册，零数据风险；索引同批建（回收站与在册读都吃它）。
    35: [
      'ALTER TABLE $tItemProfiles ADD COLUMN deleted_at INTEGER',
      'CREATE INDEX IF NOT EXISTS idx_item_profiles_deleted ON $tItemProfiles(deleted_at)',
    ]
};
