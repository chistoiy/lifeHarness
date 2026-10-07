/// 数据库 schema 定义（sqflite）。
///
/// 建库策略（ADR D6）：V0.1 即定义 待办/日程/日记/笔记 四核心表 + 收集箱，
/// **并预留** 健康/财务/物品 表结构与迁移骨架，避免后期数据迁移。
/// 插件隔离表统一以 `plugin_` 前缀命名（需求 V1.15），宿主不迁移、卸载可清理。
library;
import 'schema/ai.dart' as a;
import 'schema/care.dart' as e;
import 'schema/core.dart' as c;
import 'schema/days.dart' as d;
import 'schema/goals.dart' as g;
import 'schema/health.dart' as hd;
import 'schema/habit.dart' as h;
import 'schema/items.dart' as m;
import 'schema/ledger.dart' as l;
import 'schema/read.dart' as r;
import 'schema/xray.dart' as x;
class DbSchema {
  const DbSchema._();


  
  static const String fileName = 'lifeharness.db';

  // 34：真机取证修正——_runMigrations 循环按「key=起始版本」取段，
  // ⑤ 索引迁移写在 migrations[33]（33→34 段），故目标版本必须到 34 才会在老库执行；
  // 33 只在 v0.2.7-reader2 上停留过（该批真机 user_version 已是 33，索引仍是全量唯一）。
  // 35：轮7 拍板 X-Ray 派生数据生命周期——migrations[34]（34→35）清扫所属书
  // 已彻底删除的历史孤行（mention/entity/task + 该书专属词库，GLOBAL 保留）。
  // 36：V1.61 物品档案删除——migrations[35]（35→36）给 item_profiles 加 deleted_at
  // （回收站第七类；子表 item_events/item_usages 不加列，随父行判在册）。
  // 37：V1.48/V1.48.1 健康管理模块——migrations[36]（36→37）建 health_* 十四表
  // （档案中心＋五类按日记录＋目标/体征/症状/报告/提醒）；新模块只建表不搬数据。
  static const int version = 37;
 

  
  static const String pluginPrefix = 'plugin_';


  
  
  
  static final List<String> createStatements = [
    
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
      tag TEXT,
      time_mode TEXT,
      start_min INTEGER,
      end_min INTEGER,
      pomo_mode TEXT,
      pomo_min INTEGER,
      dropped INTEGER NOT NULL DEFAULT 0,
      color INTEGER,
      grp TEXT,
      habit_id INTEGER,
      link_cat INTEGER,
      deleted_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_todos_done ON $tTodos(done)',
    'CREATE INDEX idx_todos_due ON $tTodos(due_at)',

    
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
      cat_id INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_events_start ON $tEvents(start_at)',

    
    '''
    CREATE TABLE $tJournal (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_date INTEGER NOT NULL,
      mood INTEGER,
      content TEXT NOT NULL,
      tags TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      starred INTEGER NOT NULL DEFAULT 0,
      liked INTEGER NOT NULL DEFAULT 0,
      view_count INTEGER NOT NULL DEFAULT 0,
      template_id INTEGER,
      kind TEXT NOT NULL DEFAULT '',
      weather_code INTEGER,
      temp_max REAL,
      temp_min REAL,
      weather_manual INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_journal_date ON $tJournal(entry_date)',

    
    
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

    
    
    '''
    CREATE TABLE $tNotes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT,
      content TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'plain',
      folder TEXT,
      pinned INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      deleted_at INTEGER,
      paper TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tNoteSnapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_snap_note ON $tNoteSnapshots(note_id)',
    
    '''
    CREATE TABLE IF NOT EXISTS $tNoteFolders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_id INTEGER,
      name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',

    
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

    
    '''
    CREATE TABLE $tSettings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''',

    
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

    
    
    '''
    CREATE TABLE $tTimeBlocks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      day INTEGER NOT NULL,
      start_min INTEGER NOT NULL,
      end_min INTEGER NOT NULL,
      category TEXT NOT NULL DEFAULT '其他',
      note TEXT,
      source TEXT NOT NULL DEFAULT 'mark',
      event_id INTEGER,
      cat_id INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_blocks_day ON $tTimeBlocks(day)',

    
    
    '''
    CREATE TABLE $tCategories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_id INTEGER,
      name TEXT NOT NULL,
      color TEXT,
      tag TEXT,
      sort INTEGER NOT NULL DEFAULT 0
    )
    ''',
    
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
    ...categorySeed,
    ...bookSchemaStatements,
    ...bookTocSchemaStatements,
    ...bookReviewSchemaStatements,
    ...bookListSchemaStatements,
    ...habitSchemaStatements,
    ...habitAuxSchemaStatements,
    ...ledgerSchemaStatements,
    ...careSchemaStatements,
    ...daysSchemaStatements,
    ...itemSchemaStatements,
    ...goalSchemaStatements,
    ...doubanMetaSchemaStatements,
    ...aiCallSchemaStatements,
    ...xraySchemaStatements,
    ...hd.healthSchemaStatements,
  ];
  static const String tTodos = c.tTodos;  // G5: core.dart
  static const String tEvents = c.tEvents;  // G5: core.dart
  static const String tJournal = c.tJournal;  // G5: core.dart
  static const String tJournalSections = c.tJournalSections;  // G5: core.dart
  static const String tDiaryTemplates = c.tDiaryTemplates;  // G5: core.dart
  static const String tTemplateSections = c.tTemplateSections;  // G5: core.dart
  static const String tNotes = c.tNotes;  // G5: core.dart
  static const String tNoteSnapshots = c.tNoteSnapshots;  // G5: core.dart
  static const String tNoteFolders = c.tNoteFolders;  // G5: core.dart
  static const String tInbox = c.tInbox;  // G5: core.dart
  static const String tSettings = c.tSettings;  // G5: core.dart
  static const String tHealth = c.tHealth;  // G5: core.dart
  static const String tFinance = l.tFinance;  // G5: ledger.dart
  static const String tItems = m.tItems;  // G5: items.dart
  static const String tTimeBlocks = c.tTimeBlocks;  // G5: core.dart
  static const String tCategories = c.tCategories;  // G5: core.dart
  static const String tWeatherDaily = c.tWeatherDaily;  // G5: core.dart
  static const String tBooks = r.tBooks;  // G5: read.dart
  static const String tBookSessions = r.tBookSessions;  // G5: read.dart
  static const String tBookQuotes = r.tBookQuotes;  // G5: read.dart
  static const String tBookTocNodes = r.tBookTocNodes;  // G5: read.dart
  static const String tBookDict = r.tBookDict;  // G5: read.dart
  static const int catReadingId = r.catReadingId;  // G5: read.dart
  static const String tBookReviews = r.tBookReviews;  // G5: read.dart
  static const String tBookLists = r.tBookLists;  // G5: read.dart
  static const String tBookListItems = r.tBookListItems;  // G5: read.dart
  static const String tHabits = h.tHabits;  // G5: habit.dart
  static const String tHabitSubs = h.tHabitSubs;  // G5: habit.dart
  static const String tHabitEntries = h.tHabitEntries;  // G5: habit.dart
  static const String tHabitEntrySubs = h.tHabitEntrySubs;  // G5: habit.dart
  static const String tHabitDict = h.tHabitDict;  // G5: habit.dart
  static const String tHabitSlips = h.tHabitSlips;  // G5: habit.dart
  static const String tHabitFreezes = h.tHabitFreezes;  // G5: habit.dart
  static const String tHabitGoalHist = h.tHabitGoalHist;  // G5: habit.dart
  static const String tHabitPend = h.tHabitPend;  // G5: habit.dart
  static const String tLedgerBooks = l.tLedgerBooks;  // G5: ledger.dart
  static const String tLedgerTxns = l.tLedgerTxns;  // G5: ledger.dart
  static const String tLedgerAccounts = l.tLedgerAccounts;  // G5: ledger.dart
  static const String tLedgerCategories = l.tLedgerCategories;  // G5: ledger.dart
  static const String tLedgerBudgets = l.tLedgerBudgets;  // G5: ledger.dart
  static const String tLedgerFav = l.tLedgerFav;  // G5: ledger.dart
  static const String tLedgerRecur = l.tLedgerRecur;  // G5: ledger.dart
  static const String tLedgerWishes = l.tLedgerWishes;  // G5: ledger.dart
  static const String tLedgerDebts = l.tLedgerDebts;  // G5: ledger.dart
  static const String tLedgerTagGroups = l.tLedgerTagGroups;  // G5: ledger.dart
  static const String tLedgerTags = l.tLedgerTags;  // G5: ledger.dart
  static const String tLedgerWhos = l.tLedgerWhos;  // G5: ledger.dart
  static const String tLedgerMerchants = l.tLedgerMerchants;  // G5: ledger.dart
  static const String tLedgerImportBatches = l.tLedgerImportBatches;  // G5: ledger.dart
  static const String tCareBabies = e.tCareBabies;  // G5: care.dart
  static const String tCareCarers = e.tCareCarers;  // G5: care.dart
  static const String tCareLogs = e.tCareLogs;  // G5: care.dart
  static const String tCareCycleDays = e.tCareCycleDays;  // G5: care.dart
  static const String tCareCyclePred = e.tCareCyclePred;  // G5: care.dart
  static const String tCareMeasures = e.tCareMeasures;  // G5: care.dart
  static const String tCareVaccines = e.tCareVaccines;  // G5: care.dart
  static const String tCareMilestones = e.tCareMilestones;  // G5: care.dart
  static const String tCareAllergies = e.tCareAllergies;  // G5: care.dart
  static const String tCareCustomEvents = e.tCareCustomEvents;  // G5: care.dart
  static const String tCareEventOrder = e.tCareEventOrder;  // G5: care.dart
  static const String tDays = d.tDays;  // G5: days.dart
  static const String tDayPreps = d.tDayPreps;  // G5: days.dart
  static const String tReminderItems = d.tReminderItems;  // G5: days.dart
  static const String tItemProfiles = m.tItemProfiles;  // G5: items.dart
  static const String tItemEvents = m.tItemEvents;  // G5: items.dart
  static const String tItemUsages = m.tItemUsages;  // G5: items.dart
  static const String tGoals = g.tGoals;  // G5: goals.dart
  static const String tGoalKrs = g.tGoalKrs;  // G5: goals.dart
  static const String tKrUpdates = g.tKrUpdates;  // G5: goals.dart
  static const String tGoalReviews = g.tGoalReviews;  // G5: goals.dart
  static const String tGoalPeriods = g.tGoalPeriods;  // G5: goals.dart
  static const String tDoubanMeta = r.tDoubanMeta;  // G5: read.dart
  static const String tAiCalls = a.tAiCalls;  // G5: ai.dart
  static const List<String> careTables = e.careTables;  // G5: care.dart
  static const int ledgerCatOtherExpense = l.ledgerCatOtherExpense;  // G5: ledger.dart
  static const int ledgerCatOtherIncome = l.ledgerCatOtherIncome;  // G5: ledger.dart
  static const List<String> categorySeed = c.categorySeed;  // G5: core.dart
  static const List<String> aiCallSchemaStatements = a.aiCallSchemaStatements;  // G5: ai.dart
  static const List<String> doubanMetaSchemaStatements = r.doubanMetaSchemaStatements;  // G5: read.dart
  static const List<String> goalSchemaStatements = g.goalSchemaStatements;  // G5: goals.dart
  static const List<String> itemSchemaStatements = m.itemSchemaStatements;  // G5: items.dart
  static const List<String> daysSchemaStatements = d.daysSchemaStatements;  // G5: days.dart
  static const List<String> habitSchemaStatements = h.habitSchemaStatements;  // G5: habit.dart
  static const List<String> habitAuxSchemaStatements = h.habitAuxSchemaStatements;  // G5: habit.dart
  static const List<String> bookSchemaStatements = r.bookSchemaStatements;  // G5: read.dart
  static const List<String> bookReviewSchemaStatements = r.bookReviewSchemaStatements;  // G5: read.dart
  static const List<String> bookListSchemaStatements = r.bookListSchemaStatements;  // G5: read.dart
  static const List<String> bookTocSchemaStatements = r.bookTocSchemaStatements;  // G5: read.dart
  static final List<String> ledgerSchemaStatements = l.ledgerSchemaStatements;  // G5: ledger.dart
  static const List<String> careSchemaStatements = e.careSchemaStatements;  // G5: care.dart
  static const String tXrayTask = x.tXrayTask;  // G5: xray.dart
  static const String tXrayEntity = x.tXrayEntity;  // G5: xray.dart
  static const String tXrayMention = x.tXrayMention;  // G5: xray.dart
  static const String tXrayUserdict = x.tXrayUserdict;  // G5: xray.dart
  static const List<String> xraySchemaStatements = x.xraySchemaStatements;  // G5: xray.dart
  static final Map<int, List<String>> migrations = {
    // V1.58 小工具整模块下架（产品负责人 2026-09-30 拍板「模块价值太低」）：
    // v29→v30 删除 kit_* 四表。索引随表自动删除，无需单独 DROP；
    // DROP IF EXISTS 保证「新装库从未建过这四表」也走得通（onCreate 已不再建）。
    // 偏好键 lh.kit 由 SettingsRepository.load() 一次性清除（照 care.rm.lock 先例）。
    29: [
      'DROP TABLE IF EXISTS kit_usage',
      'DROP TABLE IF EXISTS kit_layout',
      'DROP TABLE IF EXISTS kit_tool_data',
      'DROP TABLE IF EXISTS kit_plugin',
    ],
    ...a.mig,
    ...e.mig,
    ...c.mig,
    ...d.mig,
    ...g.mig,
    ...h.mig,
    ...m.mig,
    ...l.mig,
    ...r.mig,
    ...x.mig,
    ...hd.mig,
  };
}
