// 治理G5 域库：ai · 由 schema.dart 外提（原名零改写）·跨域引用带前缀


  
  
  const String tAiCalls =  'ai_calls';



  
  
  
  
  const List<String> aiCallSchemaStatements =  [
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

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    
    
    25: [
      ...aiCallSchemaStatements,
    ]
};
