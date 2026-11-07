// 治理G5 域库：ledger · 由 schema.dart 外提（原名零改写）·跨域引用带前缀


  const String tFinance =  'finance_txns';


  
  const String tLedgerBooks =  'ledger_books';


  const String tLedgerTxns =  'ledger_txns';


  const String tLedgerAccounts =  'ledger_accounts';


  const String tLedgerCategories =  'ledger_categories';


  const String tLedgerBudgets =  'ledger_budgets';


  const String tLedgerFav =  'ledger_fav';


  const String tLedgerRecur =  'ledger_recur';


  const String tLedgerWishes =  'ledger_wishes';


  const String tLedgerDebts =  'ledger_debts';


  const String tLedgerTagGroups =  'ledger_tag_groups';


  const String tLedgerTags =  'ledger_tags';


  const String tLedgerWhos =  'ledger_whos';


  const String tLedgerMerchants =  'ledger_merchants';


  const String tLedgerImportBatches =  'ledger_import_batches';



  
  const int ledgerCatOtherExpense =  114;

 
  const int ledgerCatOtherIncome =  207;



  
  
  
  
  
  
  
  
  
  
  final List<String> ledgerSchemaStatements =  [
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

/// 治理G5：本域承接的版本迁移条目（聚合于 DbSchema.migrations·键互斥）
final Map<int, List<String>> mig = {
    
    
    17: [
      ...ledgerSchemaStatements,
    ]
};

/// 治理G5：自 DbSchema 整体外提（仅引用本域表名常量·零重写）
List<String> _ledgerSeeds() {
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
