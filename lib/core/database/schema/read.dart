// 治理G5 域库：read · 由 schema.dart 外提（原名零改写）·跨域引用带前缀
import 'core.dart' as c;


  
  const String tBooks =  'books';


  const String tBookSessions =  'book_sessions';


  const String tBookQuotes =  'book_quotes';


  
  const String tBookTocNodes =  'book_toc_nodes';


  const String tBookDict =  'book_dict';


  
  const int catReadingId =  22;


  
  const String tBookReviews =  'book_reviews';


  
  const String tBookLists =  'book_lists';


  const String tBookListItems =  'book_list_items';


  
  
  
  const String tDoubanMeta =  'douban_meta';



  
  
  
  
  
  const List<String> doubanMetaSchemaStatements =  [
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



  
  const List<String> bookSchemaStatements =  [
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
      md5 TEXT,
      first_img TEXT,
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
    'CREATE INDEX IF NOT EXISTS idx_books_md5 ON $tBooks(md5) WHERE md5 IS NOT NULL',
    
    
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
      from_chapter TEXT,
      to_chapter TEXT,
      from_pct REAL,
      to_pct REAL,
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



  
  const List<String> bookReviewSchemaStatements =  [
    '''
    CREATE TABLE IF NOT EXISTS $tBookReviews (
      quote_id INTEGER PRIMARY KEY,
      stage INTEGER NOT NULL DEFAULT 0,
      next_at INTEGER
    )
    ''',
  ];



  
  
  
  const List<String> bookListSchemaStatements =  [
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



  
  const List<String> bookTocSchemaStatements =  [
    
    
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

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    
    11: [...bookSchemaStatements],
    
    12: [
      ...bookTocSchemaStatements,
      "INSERT OR IGNORE INTO ${c.tCategories}(id,parent_id,name,color,tag,sort) VALUES"
          "(22,NULL,'阅读','#0EA5E9',NULL,11)",
    ],
    
    
    13: [
      ...bookReviewSchemaStatements,
    ],
    
    14: [
      ...bookListSchemaStatements,
    ],
    
    
    22: [
      ...doubanMetaSchemaStatements,
    ],
    
    
    
    23: [
      'ALTER TABLE $tBooks ADD COLUMN word_count INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $tBooks ADD COLUMN binding TEXT',
      'ALTER TABLE $tBooks ADD COLUMN fee_date TEXT',
    ],
    
    
    
    
    
    
    24: [
      'ALTER TABLE $tBooks ADD COLUMN local INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE $tBooks ADD COLUMN epub TEXT',
      'ALTER TABLE $tBookQuotes ADD COLUMN cf TEXT',
      'ALTER TABLE $tBookQuotes ADD COLUMN rid TEXT',
    ],
    
    
    26: [
      'ALTER TABLE $tBookSessions ADD COLUMN from_chapter TEXT',
      'ALTER TABLE $tBookSessions ADD COLUMN to_chapter TEXT',
      'ALTER TABLE $tBookSessions ADD COLUMN from_pct REAL',
      'ALTER TABLE $tBookSessions ADD COLUMN to_pct REAL',
    ],

    // R14-4（2026-09-30 三档回落）：EPUB 正文首图回落封面的衍生文件路径（A 档用）。
    // 导入/预载时生成；单书清缓存随封面衍生件一并回收（记录本身保留）。
    32: [
      'ALTER TABLE $tBooks ADD COLUMN first_img TEXT',
    ]
};
