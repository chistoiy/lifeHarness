/// 数据库 schema 定义（sqflite）。
///
/// 建库策略（ADR D6）：V0.1 即定义 待办/日程/日记/笔记 四核心表 + 收集箱，
/// **并预留** 健康/财务/物品 表结构与迁移骨架，避免后期数据迁移。
/// 插件隔离表统一以 `plugin_` 前缀命名（需求 V1.15），宿主不迁移、卸载可清理。
class DbSchema {
  const DbSchema._();

  /// 数据库文件名与版本（版本递增驱动 onUpgrade 迁移）。
  static const String fileName = 'lifeharness.db';
  static const int version = 1;

  // ---- 表名常量 ----
  static const String tTodos = 'todos';
  static const String tEvents = 'events';
  static const String tJournal = 'journal_entries';
  static const String tNotes = 'notes';
  static const String tInbox = 'inbox_items';
  static const String tSettings = 'settings';
  // 预留表（V0.1 建表，业务 M2/M3 填充）
  static const String tHealth = 'health_records';
  static const String tFinance = 'finance_txns';
  static const String tItems = 'items';

  /// 插件表前缀约定：宿主建表/校验/清理时据此识别。
  static const String pluginPrefix = 'plugin_';

  /// v1 全量建表 DDL。时间字段统一存 epoch 毫秒（INTEGER），日界线固定自然日 00:00
  /// （ADR D13），跨天由「开始日归属 + 跨天标记」处理。
  static const List<String> createStatements = [
    // 模块2 待办 + 四象限（quadrant: 1~4；priority 预留）
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
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_events_start ON $tEvents(start_at)',

    // 模块3 日记（mood 1~5；tags 逗号分隔）
    '''
    CREATE TABLE $tJournal (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_date INTEGER NOT NULL,
      mood INTEGER,
      content TEXT NOT NULL,
      tags TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_journal_date ON $tJournal(entry_date)',

    // 模块3 笔记（kind: plain/rich/md；folder 分组；pinned 置顶）
    '''
    CREATE TABLE $tNotes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT,
      content TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'plain',
      folder TEXT,
      pinned INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
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
  ];
}
