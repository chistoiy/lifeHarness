// 旧版库「归真」补丁（存量红消化批1 · 2026-11-08）。
//
// 三份 S7「真升级」用例原本只建一张占位表就钉 `user_version`，等价于「一台只装了日记表的
// 畸形机」。真实老库必然带着当期各模块的表，而后续迁移会**裸 ALTER 老表**
// （`migrations[50]` 给 `item_events` 加 `txn_id`、`migrations[51]` 给 `item_profiles`
// 加 brand/serial/note），畸形 fixture 就崩在 50／51 段的 `no such table`。
//
// 这里补上这两张表在 v44~v50 的**历史形态**（列比现基础 DDL 少「当年新加的那几列」），
// 让 fixture 与真机同形。**生产迁移代码一行不改**——真机上这两张表自 v21 起必然存在，
// 给迁移加「表不存在就跳过」的守卫只会弱化迁移、掩盖真的 schema 缺口。
//
// 用法：搭完占位表后 `await seedLegacyModuleTables(db);` 再钉 `PRAGMA user_version`。
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v21~v50 形态的 `item_events`（无 `txn_id`，该列由 `migrations[50]` 加）。
const legacyItemEventsDdl = '''
CREATE TABLE IF NOT EXISTS item_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  label TEXT NOT NULL,
  amount REAL NOT NULL DEFAULT 0,
  note TEXT,
  event_date TEXT NOT NULL,
  created_at INTEGER NOT NULL
)''';

/// v36~v51 形态的 `item_profiles`（有 `deleted_at`，无 brand/serial/note）。
const legacyItemProfilesDdl = '''
CREATE TABLE IF NOT EXISTS item_profiles (
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
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
)''';

/// 给手工搭的旧版库补齐「后续迁移会裸 ALTER 的历史表」。
///
/// 只补这两张：v44 之后的迁移链里，只有 `migrations[50]`／`[51]` 对**既有表**做裸 ALTER，
/// 其余段都是 `CREATE … IF NOT EXISTS` 或对本用例手搭的表做 ALTER。
Future<void> seedLegacyModuleTables(Database db) async {
  await db.execute(legacyItemEventsDdl);
  await db.execute(legacyItemProfilesDdl);
}
